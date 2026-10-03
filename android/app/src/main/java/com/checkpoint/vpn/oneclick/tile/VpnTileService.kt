package com.checkpoint.vpn.oneclick.tile

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.checkpoint.vpn.oneclick.CheckpointVpnApp
import com.checkpoint.vpn.oneclick.vpn.TunnelController
import com.checkpoint.vpn.oneclick.vpn.TunnelState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class VpnTileService : TileService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var collectJob: Job? = null

    override fun onStartListening() {
        super.onStartListening()
        collectJob?.cancel()
        collectJob = scope.launch {
            TunnelController.status.collectLatest { status ->
                qsTile?.apply {
                    state = when (status.state) {
                        TunnelState.Connected -> Tile.STATE_ACTIVE
                        TunnelState.Connecting -> Tile.STATE_UNAVAILABLE
                        else -> Tile.STATE_INACTIVE
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        subtitle = status.detail
                    }
                    updateTile()
                }
            }
        }
    }

    override fun onStopListening() {
        collectJob?.cancel()
        collectJob = null
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        val current = TunnelController.status.value.state
        if (current == TunnelState.Connected || current == TunnelState.Connecting) {
            TunnelController.requestDisconnect(this)
        } else {
            scope.launch {
                val settings = CheckpointVpnApp.instance.settings.settings.first()
                if (settings.site.isBlank()) {
                    TunnelController.updateStatus(TunnelState.Error, "Configure a gateway in the app")
                    return@launch
                }
                TunnelController.requestConnect(this@VpnTileService)
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
