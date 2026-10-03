package com.checkpoint.vpn.oneclick.vpn

import android.app.Notification
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import com.checkpoint.vpn.oneclick.CheckpointVpnApp
import com.checkpoint.vpn.oneclick.MainActivity
import com.checkpoint.vpn.oneclick.R
import com.checkpoint.vpn.oneclick.data.SplitDestinations
import com.checkpoint.vpn.oneclick.data.Totp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class CheckpointVpnService : VpnService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var tun: ParcelFileDescriptor? = null
    private var connectJob: Job? = null
    private var activeSite: String = ""

    override fun onCreate() {
        super.onCreate()
        TunEstablisher.service = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT -> {
                disconnect()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_CONNECT, null -> {
                startForeground(NOTIFICATION_ID, notification(getString(R.string.vpn_notification_connecting)))
                connectJob?.cancel()
                connectJob = scope.launch { connect() }
            }
        }
        return START_STICKY
    }

    private suspend fun connect() {
        TunnelController.updateStatus(TunnelState.Connecting, "Connecting…")
        val app = CheckpointVpnApp.instance
        val settings = app.settings.settings.first()
        val site = settings.site.trim()
        val username = settings.username.trim()
        if (site.isEmpty() || username.isEmpty()) {
            fail("Gateway and username are required")
            return
        }
        val password = app.secrets.password(site)
        val totpRaw = app.secrets.totpSecret(site)
        if (password.isNullOrEmpty() || totpRaw.isNullOrEmpty()) {
            fail("Save password and TOTP secret for this site first")
            return
        }

        activeSite = site

        // Resolve split destinations on the physical network BEFORE any TUN is up.
        val routes = withContext(Dispatchers.IO) {
            SplitDestinations.resolveRoutes(settings.splitDestinations)
        }
        val routesCsv = routes.joinToString(",") { "${it.first}/${it.second}" }
        val mfa = Totp.currentCode(totpRaw)

        // Auth + IKE must run with normal DNS/routing. TUN is opened later via TunEstablisher
        // when snxcore is ready to attach the packet path.
        val result = withContext(Dispatchers.IO) {
            NativeEngine.connectOrError(
                server = site,
                username = username,
                password = password,
                mfaCode = mfa,
                loginType = settings.loginType.ifBlank { "vpn_VPN_RA" },
                ignoreServerCert = settings.ignoreServerCert,
                routesCsv = routesCsv,
            )
        }

        if (result.startsWith("ok") || result == "connected") {
            TunnelController.updateStatus(TunnelState.Connected, "Connected to $site")
            startForeground(NOTIFICATION_ID, notification(getString(R.string.vpn_notification_connected)))
            if (!NativeEngine.loaded) {
                TunnelController.updateStatus(
                    TunnelState.Connected,
                    "Native engine stub — $site",
                )
            }
        } else if (result.startsWith("error:")) {
            val message = result.removePrefix("error:").trim()
            TunnelController.updateStatus(TunnelState.Error, message)
            disconnect()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        } else {
            TunnelController.updateStatus(TunnelState.Connected, result)
            startForeground(NOTIFICATION_ID, notification(getString(R.string.vpn_notification_connected)))
        }
    }

    /** Called from JNI on the engine thread after Check Point auth succeeds. */
    fun establishTunForEngine(
        address: String,
        prefix: Int,
        mtu: Int,
        dnsCsv: String,
        routesCsv: String,
    ): Int {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return establishTunOnMain(address, prefix, mtu, dnsCsv, routesCsv)
        }
        val done = CountDownLatch(1)
        var fd = -1
        Handler(mainLooper).post {
            fd = establishTunOnMain(address, prefix, mtu, dnsCsv, routesCsv)
            done.countDown()
        }
        return if (done.await(20, TimeUnit.SECONDS)) fd else -1
    }

    private fun establishTunOnMain(
        address: String,
        prefix: Int,
        mtu: Int,
        dnsCsv: String,
        routesCsv: String,
    ): Int {
        return try {
            val builder = Builder()
                .setSession("Checkpoint VPN ($activeSite)")
                .setMtu(mtu.coerceIn(576, 9000))
                .addAddress(address, prefix.coerceIn(0, 32))
                .setBlocking(true)

            dnsCsv.split(',')
                .map { it.trim() }
                .filter { it.isNotEmpty() }
                .forEach { runCatching { builder.addDnsServer(it) } }

            val routes = parseRoutesCsv(routesCsv)
            if (routes.isEmpty()) {
                // Fall back to the assigned Office Mode network only — never 0.0.0.0/0 here,
                // or gateway/ESP traffic gets swallowed by the TUN.
                builder.addRoute(address, prefix.coerceIn(0, 32))
            } else {
                for ((ip, p) in routes) {
                    runCatching { builder.addRoute(ip, p) }
                }
            }

            runCatching { builder.allowFamily(android.system.OsConstants.AF_INET) }

            val pfd = builder.establish() ?: return -1
            tun?.close()
            tun = pfd
            if (NativeEngine.loaded) {
                NativeEngine.nativeSetTunFd(pfd.fd)
            }
            pfd.fd
        } catch (_: Exception) {
            -1
        }
    }

    private fun parseRoutesCsv(csv: String): List<Pair<String, Int>> {
        if (csv.isBlank()) return emptyList()
        return csv.split(',').mapNotNull { part ->
            val trimmed = part.trim()
            if (trimmed.isEmpty()) return@mapNotNull null
            val bits = trimmed.split('/', limit = 2)
            val ip = bits[0]
            val prefix = bits.getOrNull(1)?.toIntOrNull() ?: 32
            ip to prefix.coerceIn(0, 32)
        }
    }

    private fun fail(message: String) {
        TunnelController.updateStatus(TunnelState.Error, message)
        disconnect()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun disconnect() {
        connectJob?.cancel()
        connectJob = null
        if (NativeEngine.loaded) {
            runCatching { NativeEngine.nativeDisconnect() }
        }
        tun?.close()
        tun = null
        TunnelController.updateStatus(TunnelState.Disconnected, "Disconnected")
    }

    private fun notification(content: String): Notification {
        val pending = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CheckpointVpnApp.NOTIFICATION_CHANNEL_ID)
            .setContentTitle(getString(R.string.vpn_notification_title))
            .setContentText(content)
            .setSmallIcon(R.drawable.ic_vpn_key)
            .setContentIntent(pending)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        if (TunEstablisher.service === this) {
            TunEstablisher.service = null
        }
        disconnect()
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        const val ACTION_CONNECT = "com.checkpoint.vpn.oneclick.CONNECT"
        const val ACTION_DISCONNECT = "com.checkpoint.vpn.oneclick.DISCONNECT"
        private const val NOTIFICATION_ID = 42
    }
}
