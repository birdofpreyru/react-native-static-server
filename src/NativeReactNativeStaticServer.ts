import {
  type CodegenTypes,
  type TurboModule,
  TurboModuleRegistry,
} from "react-native";

type ServerEventT = {
  details: string;
  event: string;
  serverId: number;
};

export interface Spec extends TurboModule {
  getConstants(): {
    CRASHED: string;
    IS_MAC_CATALYST: boolean;
    LAUNCHED: string;
    TERMINATED: string;
  };

  addListener(eventName: string): void;

  getActiveServerId(): Promise<number | null>;

  // TODO: We should create separate callbacks for different events
  // we now send through the same event emitter - that will be better
  // type safety (the current implementation made sense with legacy
  // RN versions, not anymore).
  readonly onServerEvent: CodegenTypes.EventEmitter<ServerEventT>;

  removeListeners(count: number): void;

  start(id: number, configPath: string, errlogPath: string): Promise<string>;

  // TODO: Instead of implementing these methods in native code ourselves,
  // we probably can use `@react-native-community/netinfo` library to retrieve
  // local IP address and a random open port (thus a bit less native code
  // to maintain ourselves in this library).
  getLocalIpAddress(): Promise<string>;

  getOpenPort(address: string): Promise<number>;
  stop(): Promise<string>;
}

export default TurboModuleRegistry.getEnforcing<Spec>(
  "ReactNativeStaticServer",
);
