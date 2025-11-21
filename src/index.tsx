import {
  AppState,
  type AppStateStatus,
  NativeEventEmitter,
  type NativeEventSubscription,
  Platform,
} from "react-native";

import {
  copyFileAssets,
  DocumentDirectoryPath,
  mkdir,
  readDirAssets,
  unlink,
} from "@dr.pogodin/react-native-fs";

import { Emitter, SEC_MS, Semaphore } from "@dr.pogodin/js-utils";

import {
  ERROR_LOG_FILE,
  newStandardConfigFile,
  type ErrorLogOptions,
} from "./config";

import { SIGNALS, STATES } from "./constants";
import ReactNativeStaticServer from "./NativeReactNativeStaticServer";
import { resolveAssetsPath } from "./utils";

export { ERROR_LOG_FILE, UPLOADS_DIR, WORK_DIR } from "./config";

export { STATES, resolveAssetsPath };

// ID-to-StaticServer map for all potentially active server instances,
// used to route native events back to JS server objects.
const servers: { [id: string]: Set<StaticServer> } = {};

const nativeEventEmitter = new NativeEventEmitter(ReactNativeStaticServer);

const LOOPBACK_ADDRESS = "127.0.0.1";

export type StateListener = (
  newState: STATES,
  details: string,
  error?: Error,
) => void;

export type StaticServerParams = {
  extraConfig?: string;
  errorLog?: boolean | ErrorLogOptions;
  fileDir: string;
  hostname?: string;
  id?: number;

  /* DEPRECATED */ nonLocal?: boolean;

  port?: number;
  state?: STATES;
  stopInBackground?: boolean | number;

  /* DEPRECATED */ webdav?: string[];
};

nativeEventEmitter.addListener(
  "RNStaticServer",
  ({ serverId, event, details }) => {
    const group = servers[serverId];
    if (group) {
      switch (event) {
        case SIGNALS.CRASHED:
          // TODO: We probably can, and should, capture the native stack trace
          // and pass it along with the error.
          const error = Error(details);

          group.forEach((item) =>
            item._setState(STATES.CRASHED, details, error),
          );

          // TODO: Should we do here the following?
          // delete servers[this._id];
          break;
        default:
          throw Error(`Unexpected signal ${event}`);
      }
    }
  },
);

// TODO: The idea for later implementation is to allow users to provide their
// own lighttpd config files with completely custom configuration. To do so,
// we'll probably split StaticServer class in two: the BaseServer will run
// server with given config path, and it will contain the logic like server
// state watching, stopInBackground, etc. The StaticServer class will extend it,
// allowing the current interface (starting the server with default config,
// and providing the most important config options via arguments), it will
// hold the props for accesing those options, selected hostname and port, etc.
// (as BaseServer will run the server on whatever port is given in provided
// config, but it won't be able to tell user what address / port it was, etc.).
class StaticServer {
  // NOTE: could be a private method, and we tried it, but it turns out that
  // Babel's @babel/plugin-proposal-private-methods causes many troubles in RN.
  // See: https://github.com/birdofpreyru/react-native-static-server/issues/6
  // and: https://github.com/birdofpreyru/react-native-static-server/issues/9
  _appStateSub?: NativeEventSubscription;
  _configPath?: string;
  _errorLog?: ErrorLogOptions;
  _extraConfig: string;
  _fileDir: string;
  _hostname = "";

  /* DEPRECATED */ _nonLocal: boolean;

  _origin: string = "";
  _stopInBackground: boolean | number;
  _stopTimeoutId?: number;
  _port: number;

  _state: STATES;
  _stateChangeEmitter = new Emitter<[STATES, string, Error | undefined]>();

  // TODO: It will be better to use UUID, but I believe "uuid" library
  // I would use won't work in RN without additional workarounds applied
  // to RN setup to get around some issues with randombytes support in
  // RN JS engine. Anyway, it should be double-checked later, but using
  // timestamps as ID will do for now.
  _id: number;

  // It is used to serialize state change requests, thus ensuring that parallel
  // requests to start / stop the server won't result in a corrupt state.
  _sem = new Semaphore(true);

  _webdav: string[] | undefined;

  get errorLog(): false | ErrorLogOptions {
    return this._errorLog || false;
  }

  get fileDir() {
    return this._fileDir;
  }

  get hostname() {
    return this._hostname;
  }

  get id() {
    return this._id;
  }

  /** @deprecated */
  get nonLocal() {
    return this._nonLocal;
  }

  get origin() {
    return this._origin;
  }

  get stopInBackground() {
    return this._stopInBackground;
  }

  get port() {
    return this._port;
  }

  get state() {
    return this._state;
  }

  _setState(neu: STATES, details: string = "", error?: Error) {
    this._state = neu;
    this._stateChangeEmitter.emit(neu, details, error);
  }

  /**
   * Creates a new Server instance.
   */
  constructor({
    errorLog = false,
    extraConfig = "",
    fileDir,
    hostname,

    // NOTE: For some reasons RN-Windows corrupts large numbers sent
    // as event arguments across JS / Native boundary.
    // Everything smaller than 65535 seems to work fine, so let's just
    // truncate these IDs for now.
    // See: https://github.com/microsoft/react-native-windows/issues/11322
    id = Date.now() % 65535,

    /* DEPRECATED */ nonLocal = false,

    port = 0,
    state = STATES.INACTIVE,
    stopInBackground = false,

    /* DEPRECATED */ webdav,
  }: StaticServerParams) {
    if (errorLog) this._errorLog = errorLog === true ? {} : errorLog;

    this._extraConfig = extraConfig;
    this._id = id;

    this._nonLocal = nonLocal;
    this._hostname = hostname || (nonLocal ? "" : LOOPBACK_ADDRESS);

    this._port = port;
    this._stopInBackground = stopInBackground;

    this._state = state;

    // NOTE: Normally, a server instance is connected to events from the native
    // side inside its .start() call, and it is disconnected from them inside
    // its .stop() call (or crash clean-up sequence). However, if the server is
    // created with a claim that it is already active, we should connect it to
    // the events rigth away here.
    switch (state) {
      case STATES.ACTIVE:
      case STATES.STARTING: {
        this._registerSelf();
        break;
      }
      default:
    }

    if (!fileDir) throw Error("`fileDir` MUST BE a non-empty string");
    this._fileDir = resolveAssetsPath(fileDir);

    this._webdav = webdav;
  }

  addStateListener(listener: StateListener) {
    return this._stateChangeEmitter.addListener(listener);
  }

  /**
   * If a delayed server stop is scheduled (by the "stop in background" feature),
   * it aborts it, and returns "true"; otherwise it does nothing, and returns "false".
   */
  _abortScheduledStop(): boolean {
    if (this._stopTimeoutId === undefined) return false;

    clearTimeout(this._stopTimeoutId);
    delete this._stopTimeoutId;
    return true;
  }

  /**
   * If the "stop in background" feature is active for this server instance
   * (i.e. if this server has been started with `stopInBackground` param set),
   * this function cleans up after this feature (deactivates it) by removing
   * the corresponding application state listener, and clearing up the pending
   * stop timer (if any).
   *
   * Otherwise, it does nothing.
   */
  _cleanUpBackgroundStop() {
    if (this._appStateSub) {
      this._appStateSub.remove();
      delete this._appStateSub;
      this._abortScheduledStop();
    }
  }

  _configureAppStateHandling() {
    if (
      this._stopInBackground ||
      // NOTE: Mind, 0 is falsy, but I guess we want it to enable auto-stop with
      // a zero timeout.
      typeof this._stopInBackground === "number"
    ) {
      if (!this._appStateSub) {
        this._appStateSub = AppState.addEventListener(
          "change",
          this._handleAppStateChange.bind(this),
        );
      }
    } else this._cleanUpBackgroundStop();
  }

  async _removeConfigFile() {
    if (this._configPath) {
      const p = this._configPath;

      // Resetting the field prior to the async unlink attempt is safer,
      // in case the caller does not await for this method to complete.
      this._configPath = undefined;

      try {
        await unlink(p);
      } catch {
        // IGNORE
      }
    }
  }

  _registerSelf() {
    let group = servers[this._id];
    if (group) group.add(this);
    else {
      group = new Set([this]);
      servers[this._id] = group;
    }
  }

  /**
   * This method throws if server is not in a "stable" state, i.e. not in one
   * of these: ACTIVE, CRASHED, INACTIVE.
   */
  _stableStateGuard() {
    switch (this._state) {
      case STATES.ACTIVE:
      case STATES.CRASHED:
      case STATES.INACTIVE:
        return;
      default:
        throw Error(`Server is in unstable state ${this._state}`);
    }
  }

  /**
   * Removes all state listeners connected to this server instance.
   */
  removeAllStateListeners() {
    this._stateChangeEmitter.removeAllListeners();
  }

  /**
   * Removes given state listener, if it is connected to this server instance;
   * or does nothing if the listener is not connected to it.
   * @param listener
   */
  removeStateListener(listener: StateListener) {
    this._stateChangeEmitter.removeListener(listener);
  }

  /**
   * @param {string} [details] Optional. If provided, it will be added
   * to the STARTING message emitted to the server state change listeners.
   * @returns {Promise<string>}
   */
  async start(details?: string): Promise<string> {
    try {
      await this._sem.seize();
      this._stableStateGuard();
      if (this._state === STATES.ACTIVE) return this._origin!;

      this._registerSelf();
      this._setState(STATES.STARTING, details);
      this._configureAppStateHandling();

      // NOTE: This is done at the first start only, to avoid hostname changes
      // when server is paused for background and automatically reactivated
      // later. Same for automatic port selection.
      if (!this._hostname) {
        this._hostname = await ReactNativeStaticServer.getLocalIpAddress();
      }
      if (!this._port) {
        this._port = await ReactNativeStaticServer.getOpenPort(this._hostname);
      }
      this._origin = `http://${this._hostname}:${this._port}`;

      await this._removeConfigFile();
      this._configPath = await newStandardConfigFile({
        errorLog: this._errorLog,
        extraConfig: this._extraConfig,
        fileDir: this._fileDir,
        hostname: this._hostname,
        port: this._port,
        webdav: this._webdav,
      });

      // Native implementations of .start() method must resolve only once
      // the server has been launched (ready to handle incoming requests).
      await ReactNativeStaticServer.start(
        this._id,
        this._configPath,
        this._errorLog ? ERROR_LOG_FILE : "",
      );

      this._setState(STATES.ACTIVE);
      this._removeConfigFile();
      return this._origin;
    } catch (e: any) {
      const error = e instanceof Error ? e : Error(e.message, { cause: e });
      this._setState(STATES.CRASHED, error.message, error);
      throw error;
    } finally {
      this._sem.setReady(true);
    }
  }

  /**
   * Soft-stop the server: if automatic pause for background is enabled,
   * it will be automatically reactivated when the app goes into foreground
   * again. End users are expected to use public .stop() method below, which
   * additionally cleans-up that automatic re-activation.
   * @param {string} [details] Optional. If provided, it will be added
   *  to the STOPPING message emitted to the server state change listeners.
   * @returns {Promise<>}
   */
  async _stop(details?: string) {
    try {
      await this._sem.seize();
      this._stableStateGuard();
      if (this._state !== STATES.ACTIVE) return;
      this._setState(STATES.STOPPING, details);

      // Native implementations of .stop() method must resolve only once
      // the server has been completely shut down (released the port it listens).
      await ReactNativeStaticServer.stop();
      this._setState(STATES.INACTIVE);
    } catch (e: any) {
      const error = e instanceof Error ? e : Error(e.message, { cause: e });
      this._setState(STATES.CRASHED, error.message, error);
      throw error;
    } finally {
      const set = servers[this._id];
      set?.delete(this);
      if (!set?.size) delete servers[this._id];
      this._sem.setReady(true);
    }
  }

  /**
   * Stops or pauses the server, if it is running, depending on whether it was
   * started with keepAlive option or not (note, keepAlive means that server is
   * not paused / restarted when the app goes into background). Pausing the
   * server means it will
   * automatically start again the next time the app transitions from background
   * to foreground. To ensure the server is stopped for good, pass in `kill`
   * flag. In that case only explicit call to .start() will start the server
   * again.
   * @param {string} [details] Optional. If provided, it will be added
   *  to the STOPPING message emitted to the server state change listeners.
   * @returns {Promise<>}
   */
  async stop(details?: string) {
    this._cleanUpBackgroundStop();
    await this._stop(details);
  }

  async _handleAppStateChange(appState: AppStateStatus) {
    const starting = appState === "active" || appState === "inactive";
    try {
      if (starting) {
        // If a delayed server stop has been scheduled, but not yet executed,
        // we just abort it; otherwise, we start the server.
        if (!this._abortScheduledStop()) {
          await this.start("App entered foreground");
        }
      } else {
        if (typeof this._stopInBackground === "number") {
          const delay = this._stopInBackground;
          this._stopTimeoutId ??= setTimeout(() => {
            delete this._stopTimeoutId;
            this._stop(`App entered background ${delay / SEC_MS} sec ago`);
          }, delay);
        } else await this._stop("App entered background");
      }
    } catch {
      // If anything goes wrong within .start() or ._stop() calls, those methods
      // will move the server into the "CRASHED" state, and they'll notify all
      // server state listeners (see .addStateListener()) about the error, with
      // all related details.
      //
      // Thus, if any state listener is connected to the server, we assume it
      // handles possible errors, and we just silently ignore the error here
      // (otherwise some instrumentation, like e.g. Sentry, may catch and report
      // it as unhandled, which is confusing when the error has been handled
      // within the listener).
      //
      // However, if no listeners are connected, we throw an error to allow
      // the instrumentation, if any, to detect and report it as unhandled.
      //
      // In either case this very function is used internally, thus no way for
      // the library consumer to directly handle its possible rejections.
      if (!this._stateChangeEmitter.hasListeners) {
        throw Error(
          starting
            ? `Server (#${this._id}) auto-start on the app going into foreground failed`
            : `Server (#${this._id}) auto-stop on the app going into background failed`,
        );
      }
    }
  }
}

export default StaticServer;

/**
 * Extracts bundled assets into the specified regular directory,
 * preserving asset folder structure, and overwriting any conflicting files
 * in the destination.
 *
 * This is an Android-specific function; it does nothing if called on iOS.
 *
 * @param {string} [into=''] Optional. The destination folder for extracted
 *  assets. By default assets are extracted into the app's document folder.
 * @param {string} [from=''] Optional. Relative path of the root asset folder,
 *  starting from which all assets contained in that folder and its subfolders
 *  will be extracted into the destination folder, preserving asset folder
 *  structure. By default all bundled assets will be extracted.
 * @return {Promise} Resolves once unpacking is completed.
 */
export async function extractBundledAssets(
  into = DocumentDirectoryPath,
  from = "",
) {
  console.warn(
    "extractBundledAssets() is deprecated! See: https://github.com/birdofpreyru/react-native-static-server?tab=readme-ov-file#extractbundledassets",
  );

  if (Platform.OS !== "android") return;

  await mkdir(into);
  const assets = await readDirAssets(from);
  for (let i = 0; i < assets.length; ++i) {
    const asset = assets[i]!;
    const target = `${into}/${asset.name}`;
    if (asset.isDirectory()) await extractBundledAssets(target, asset.path);
    else await copyFileAssets(asset.path, target);
  }
}

/**
 * Returns a set of server instance currently being in ACTIVE, STARTING,
 * or STOPPING state, if such server instances exists.
 * @return {Set<StaticServer>|undefined}
 */
export function getActiveServerSet(): Set<StaticServer> | undefined {
  return Object.values(servers).find((group) => {
    const server = group.values().next().value;
    const state = server?.state;
    return state !== STATES.INACTIVE && state !== STATES.CRASHED;
  });
}

/**
 * Returns a server instance currently being in ACTIVE, STARTING,
 * or STOPPING state, if such server instance exists.
 * @return {StaticServer|undefined}
 */
export function getActiveServer(): StaticServer | undefined {
  const set = getActiveServerSet();
  return set && set.values().next().value;
}

export const getActiveServerId = ReactNativeStaticServer.getActiveServerId;
