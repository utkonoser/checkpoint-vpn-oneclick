package com.checkpoint.vpn.oneclick.vpn

object NativeEngine {
    val loaded: Boolean = try {
        System.loadLibrary("checkpoint_engine")
        true
    } catch (_: UnsatisfiedLinkError) {
        false
    }

    external fun nativeHello(): String

    external fun nativeSetTunFd(fd: Int)

    external fun nativeConnect(
        server: String,
        username: String,
        password: String,
        mfaCode: String,
        loginType: String,
        ignoreServerCert: Boolean,
        routesCsv: String,
    ): String

    external fun nativeDisconnect()

    external fun nativeStatus(): String

    fun helloOrStub(): String =
        if (loaded) nativeHello() else "stub: native library not loaded"

    fun connectOrError(
        server: String,
        username: String,
        password: String,
        mfaCode: String,
        loginType: String,
        ignoreServerCert: Boolean,
        routesCsv: String,
    ): String {
        if (!loaded) return "error: native library not loaded"
        return nativeConnect(server, username, password, mfaCode, loginType, ignoreServerCert, routesCsv)
    }
}
