package com.drpogodin.reactnativestaticserver

import android.util.Log
import com.drpogodin.reactnativestaticserver.InetAddressUtils.isIPv4Address
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.module.annotations.ReactModule
import com.lighttpd.Server
import java.net.InetAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.util.concurrent.Semaphore

@ReactModule(name = ReactNativeStaticServerModule.NAME)
class ReactNativeStaticServerModule(reactContext: ReactApplicationContext) :
  NativeReactNativeStaticServerSpec(reactContext), LifecycleEventListener {
    // The currently active server instance. We assume only single server instance
    // can be active at any time, thus a simple field should be enough for now.
    // If we arrive to having possibility of multiple servers running in
    // parallel, then this will become a hash map [ID <-> Server], and we will
    // use it for communication from JS to this module to the target Server
    // instance.
    private var server: Server? = null
    private var pendingPromise: Promise? = null

    override fun getTypedExportedConstants(): Map<String, Any> {
        val constants: MutableMap<String, Any> = HashMap()
        constants["CRASHED"] = Server.CRASHED
        constants["IS_MAC_CATALYST"] = false
        constants["LAUNCHED"] = Server.LAUNCHED
        constants["TERMINATED"] = Server.TERMINATED
        return constants
    }

    @ReactMethod
    override fun getActiveServerId(promise: Promise) {
      promise.resolve(server?.id)
    }

    @ReactMethod
    override fun getLocalIpAddress(promise: Promise) {
        try {
            val en = NetworkInterface.getNetworkInterfaces()
            while (en.hasMoreElements()) {
                val `interface` = en.nextElement()
                val enumIpAddress = `interface`.inetAddresses
                while (enumIpAddress.hasMoreElements()) {
                    val inetAddress = enumIpAddress.nextElement()
                    if (!inetAddress.isLoopbackAddress) {
                        val ip = inetAddress.hostAddress
                        if (ip != null && isIPv4Address(ip)) {
                            promise.resolve(ip)
                            return
                        }
                    }
                }
            }
            promise.resolve("127.0.0.1")
        } catch (e: Exception) {
            Errors.failGetLocalIpAddress().reject(promise)
        }
    }

    @ReactMethod
    override fun start(
            id: Double,  // Server ID for backward communication with JS layer.
            configPath: String,
            errlogPath: String,
            promise: Promise
    ) {
        Log.i(LOG_TAG, "Starting...")
        try {
            sem.acquire()
        } catch (e: Exception) {
            Errors.internalError(id).log(e)
                    .reject(promise, "Failed to acquire a semaphore")
            return
        }

        val activeServerId = server?.id
        if (activeServerId != null) {
            Errors.anotherInstanceIsActive(activeServerId, id).log().reject(promise)
            sem.release()
            return
        }
        if (pendingPromise != null) {
            Errors.internalError(id).log().reject(promise, "Unexpected pending promise")
            sem.release()
            return
        }
        pendingPromise = promise

        server = Server(id, configPath, errlogPath) { signal, details ->
            if (signal !== Server.LAUNCHED) server = null
            if (pendingPromise == null) {
                val event = Arguments.createMap().apply {
                    putDouble("serverId", id)
                    putString("event", signal)
                    putString("details", details)
                }
                emitOnServerEvent(event)
            } else {
                if (signal === Server.CRASHED) {
                    Errors.serverCrashed(id).reject(pendingPromise, details)
                } else pendingPromise!!.resolve(details)
                pendingPromise = null
                sem.release()
            }
        }
        server!!.start()
    }

    @ReactMethod
    override fun getOpenPort(address: String, promise: Promise) {
        try {
            val socket = ServerSocket(
                    0, 0, InetAddress.getByName(address))
            val port = socket.localPort
            socket.close()
            promise.resolve(port)
        } catch (e: Exception) {
            Errors.failGetOpenPort().log(e).reject(promise)
        }
    }

    @ReactMethod
    override fun stop(promise: Promise?) {
        Log.i(LOG_TAG, "stop() triggered")
        try {
            sem.acquire()
        } catch (e: Exception) {
            Errors.internalError(server!!.id).log(e)
                    .reject(promise, "Failed to acquire a semaphore")
            return
        }
        if (pendingPromise != null) {
            Errors.internalError(server!!.id)
                    .reject(pendingPromise, "Unexpected pending promise")
            sem.release()
            return
        }
        pendingPromise = promise
        server!!.interrupt()
    }

    @ReactMethod
    override fun addListener(eventName: String?) {
        // NOOP
    }

    @ReactMethod
    override fun removeListeners(count: Double) {
        // NOOP
    }

    // NOTE: Pause/resume operations, if opted, are managed in JS layer.
    override fun onHostResume() {}
    override fun onHostPause() {}
    override fun onHostDestroy() {
        stop(null)
    }

    companion object {
        // This semaphore is used to atomize server start-up and shut-down operations.
        // It is acquired in the very beginning of start() and stop() methods; and it
        // is normally released on the first subsequent signal from the server, at
        // the same moment the pendingPromise for those start() and stop() is resolved.
        // In edge cases, when start() or stop() is aborted due to failed runtime
        // invariant checks, this semaphore is released at those abort points, which
        // are in all cases prior to assigning the pendingPromise value.
        private val sem = Semaphore(1, true)
        const val NAME = NativeReactNativeStaticServerSpec.NAME
        const val LOG_TAG = Errors.LOG_TAG + " (Module)"
    }
}
