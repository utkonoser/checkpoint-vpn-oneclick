package com.checkpoint.vpn.oneclick.vpn

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class TunnelState {
    Disconnected,
    Connecting,
    Connected,
    Error,
}

data class TunnelStatus(
    val state: TunnelState = TunnelState.Disconnected,
    val detail: String = "Disconnected",
)

object TunnelController {
    private val _status = MutableStateFlow(TunnelStatus())
    val status: StateFlow<TunnelStatus> = _status.asStateFlow()

    private var appContext: Context? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var wantConnected = false

    fun bind(context: Context) {
        appContext = context.applicationContext
    }

    fun updateStatus(state: TunnelState, detail: String) {
        _status.value = TunnelStatus(state, detail)
    }

    fun requestConnect(context: Context) {
        wantConnected = true
        val intent = Intent(context, CheckpointVpnService::class.java).apply {
            action = CheckpointVpnService.ACTION_CONNECT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        registerNetworkCallback(context.applicationContext)
    }

    fun requestDisconnect(context: Context) {
        wantConnected = false
        unregisterNetworkCallback(context.applicationContext)
        val intent = Intent(context, CheckpointVpnService::class.java).apply {
            action = CheckpointVpnService.ACTION_DISCONNECT
        }
        context.startService(intent)
    }

    fun reconnectIfNeeded(context: Context) {
        if (!wantConnected) return
        if (_status.value.state == TunnelState.Connected || _status.value.state == TunnelState.Connecting) return
        requestConnect(context)
    }

    private fun registerNetworkCallback(context: Context) {
        if (networkCallback != null) return
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                reconnectIfNeeded(context)
            }

            override fun onLost(network: Network) {
                if (wantConnected) {
                    updateStatus(TunnelState.Error, "Network lost — will reconnect")
                }
            }
        }
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        cm.registerNetworkCallback(request, callback)
        networkCallback = callback
    }

    private fun unregisterNetworkCallback(context: Context) {
        val callback = networkCallback ?: return
        val cm = context.getSystemService(ConnectivityManager::class.java)
        runCatching { cm?.unregisterNetworkCallback(callback) }
        networkCallback = null
    }
}
