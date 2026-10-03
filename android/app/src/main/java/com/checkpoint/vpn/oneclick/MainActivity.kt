package com.checkpoint.vpn.oneclick

import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import com.checkpoint.vpn.oneclick.ui.AppViewModel
import com.checkpoint.vpn.oneclick.ui.MainScreen
import com.checkpoint.vpn.oneclick.ui.theme.CheckpointTheme
import com.checkpoint.vpn.oneclick.vpn.TunnelController

class MainActivity : ComponentActivity() {
    private val viewModel: AppViewModel by viewModels()

    private val vpnPermission =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            viewModel.onVpnPermissionResult(result.resultCode == RESULT_OK)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        TunnelController.bind(this)
        setContent {
            CheckpointTheme {
                LaunchedEffect(Unit) {
                    viewModel.vpnPermissionRequests.collect {
                        val intent = VpnService.prepare(this@MainActivity)
                        if (intent != null) {
                            vpnPermission.launch(intent)
                        } else {
                            viewModel.onVpnPermissionResult(true)
                        }
                    }
                }
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .systemBarsPadding(),
                ) {
                    MainScreen(viewModel = viewModel)
                }
            }
        }
    }
}
