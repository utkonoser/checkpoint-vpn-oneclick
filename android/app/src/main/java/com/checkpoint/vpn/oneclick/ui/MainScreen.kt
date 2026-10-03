package com.checkpoint.vpn.oneclick.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.checkpoint.vpn.oneclick.ui.theme.AtmosphereBrush
import com.checkpoint.vpn.oneclick.ui.theme.Signal
import com.checkpoint.vpn.oneclick.ui.theme.TotpStyle
import com.checkpoint.vpn.oneclick.vpn.TunnelState

@Composable
fun MainScreen(viewModel: AppViewModel) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var password by remember { mutableStateOf("") }
    var totpSecret by remember { mutableStateOf("") }
    var sitesMenu by remember { mutableStateOf(false) }

    val galleryLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.PickVisualMedia(),
    ) { uri ->
        if (uri != null) viewModel.importTotpFromUri(uri)
    }

    LaunchedEffect(state.message) {
        if (state.message != null) {
            kotlinx.coroutines.delay(2800)
            viewModel.clearMessage()
        }
    }

    if (state.showQrScanner) {
        Dialog(
            onDismissRequest = viewModel::closeQrScanner,
            properties = DialogProperties(usePlatformDefaultWidth = false),
        ) {
            QrScannerScreen(
                onResult = viewModel::importTotpRaw,
                onPickGallery = {
                    galleryLauncher.launch(
                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                    )
                },
                onClose = viewModel::closeQrScanner,
            )
        }
    }

    val atmosphere = if (isSystemInDarkTheme()) {
        AtmosphereBrush
    } else {
        Brush.verticalGradient(listOf(Color(0xFFF3F7F5), Color(0xFFE4F0EA), Color(0xFFF7FAF8)))
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(atmosphere),
    ) {
        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 48.dp)
                .size(220.dp)
                .clip(CircleShape)
                .background(Signal.copy(alpha = 0.10f)),
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 28.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            BrandHeader()
            SessionHero(state = state, onConnect = viewModel::connect, onDisconnect = viewModel::disconnect)

            Panel(title = "Account", subtitle = "Gateway identity for this device") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Field(
                        value = state.form.site,
                        onValueChange = viewModel::onSiteChange,
                        label = "Gateway",
                        modifier = Modifier.weight(1f),
                        placeholder = "vpn.example.com",
                    )
                    Spacer(Modifier.width(4.dp))
                    IconButton(onClick = { sitesMenu = true }) {
                        Icon(Icons.Default.History, contentDescription = "Saved gateways", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    DropdownMenu(expanded = sitesMenu, onDismissRequest = { sitesMenu = false }) {
                        if (state.form.sites.isEmpty()) {
                            DropdownMenuItem(text = { Text("No saved gateways") }, onClick = { sitesMenu = false })
                        } else {
                            state.form.sites.sorted().forEach { site ->
                                DropdownMenuItem(
                                    text = { Text(site) },
                                    onClick = {
                                        viewModel.selectSite(site)
                                        password = ""
                                        totpSecret = ""
                                        sitesMenu = false
                                    },
                                )
                            }
                        }
                    }
                    IconButton(onClick = viewModel::saveSite) {
                        Icon(Icons.Default.Add, contentDescription = "Save gateway", tint = Signal)
                    }
                    IconButton(onClick = viewModel::forgetSite) {
                        Icon(Icons.Default.Remove, contentDescription = "Remove gateway", tint = MaterialTheme.colorScheme.error)
                    }
                }
                Field(
                    value = state.form.username,
                    onValueChange = viewModel::onUsernameChange,
                    label = "Username",
                    placeholder = "user.name",
                )
                Field(
                    value = state.form.loginType,
                    onValueChange = viewModel::onLoginTypeChange,
                    label = "Login type",
                    placeholder = "vpn_VPN_RA",
                )
            }

            Panel(title = "Authentication", subtitle = "Per-site secrets stay encrypted on device") {
                TotpBlock(state = state)

                Field(
                    value = password,
                    onValueChange = { password = it },
                    label = if (state.hasPassword) "Password · saved" else "Password",
                    sensitive = true,
                )
                Field(
                    value = totpSecret,
                    onValueChange = { totpSecret = it },
                    label = if (state.hasTotp) "TOTP secret · saved" else "TOTP secret / otpauth",
                    sensitive = true,
                )

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(
                        onClick = {
                            if (password.isNotEmpty()) viewModel.savePassword(password)
                            if (totpSecret.isNotEmpty()) viewModel.saveTotp(totpSecret)
                            password = ""
                            totpSecret = ""
                        },
                    ) { Text("Save secrets") }
                    OutlinedButton(onClick = viewModel::openQrScanner) {
                        Icon(Icons.Default.PhotoCamera, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Scan QR")
                    }
                    OutlinedButton(
                        onClick = {
                            galleryLauncher.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                            )
                        },
                    ) {
                        Icon(Icons.Default.PhotoLibrary, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Gallery")
                    }
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("Ignore server certificate", style = MaterialTheme.typography.titleMedium)
                        Text("Common on corporate gateways", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Switch(
                        checked = state.form.ignoreServerCert,
                        onCheckedChange = viewModel::onIgnoreCertChange,
                        colors = SwitchDefaults.colors(checkedTrackColor = Signal.copy(alpha = 0.5f), checkedThumbColor = Signal),
                    )
                }
            }

            Panel(title = "Split tunnel", subtitle = "Only listed destinations enter the VPN") {
                Text(
                    "One CIDR, IP, or hostname per line. Leave empty for gateway Office Mode routes.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Field(
                    value = state.form.splitDestinations,
                    onValueChange = viewModel::onSplitChange,
                    label = "Destinations",
                    singleLine = false,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(150.dp),
                )
            }

            Text(
                "Engine · ${state.engineInfo}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            )

            state.message?.let {
                Text(it, color = Signal, style = MaterialTheme.typography.labelLarge)
            }

            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun BrandHeader() {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            "CHECKPOINT",
            style = MaterialTheme.typography.displayLarge,
            color = MaterialTheme.colorScheme.onBackground,
        )
        Text(
            "VPN One-Click",
            style = MaterialTheme.typography.titleMedium,
            color = Signal,
        )
        Text(
            "Split-tunnel remote access · password + TOTP",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun SessionHero(
    state: UiState,
    onConnect: () -> Unit,
    onDisconnect: () -> Unit,
) {
    val statusColor by animateColorAsState(
        when (state.tunnel.state) {
            TunnelState.Connected -> Signal
            TunnelState.Connecting -> MaterialTheme.colorScheme.secondary
            TunnelState.Error -> MaterialTheme.colorScheme.error
            TunnelState.Disconnected -> MaterialTheme.colorScheme.onSurfaceVariant
        },
        label = "status",
    )
    val pulse by animateFloatAsState(
        if (state.tunnel.state == TunnelState.Connected) 1f else 0.45f,
        label = "pulse",
    )

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.92f))
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f), RoundedCornerShape(22.dp))
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .clip(CircleShape)
                    .background(statusColor.copy(alpha = pulse)),
            )
            Spacer(Modifier.width(10.dp))
            Text(
                state.tunnel.detail,
                style = MaterialTheme.typography.titleLarge,
                color = statusColor,
                modifier = Modifier.weight(1f),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Button(
                onClick = onConnect,
                enabled = state.tunnel.state != TunnelState.Connecting,
                modifier = Modifier.weight(1f).height(48.dp),
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Signal, contentColor = Color(0xFF0B1210)),
            ) { Text("Connect", style = MaterialTheme.typography.labelLarge) }
            OutlinedButton(
                onClick = onDisconnect,
                modifier = Modifier.weight(1f).height(48.dp),
                shape = RoundedCornerShape(14.dp),
            ) { Text("Disconnect") }
        }
    }
}

@Composable
private fun TotpBlock(state: UiState) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f))
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("Live code", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(
            if (state.hasTotp) state.totpCode else "······",
            style = TotpStyle,
            color = if (state.hasTotp) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (state.hasTotp) {
            val progress = (state.totpSeconds / 30f).coerceIn(0f, 1f)
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)),
                color = Signal,
                trackColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f),
            )
            Text("${state.totpSeconds}s remaining", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            Text("Scan a QR or paste a Base32 / otpauth secret", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Panel(
    title: String,
    subtitle: String,
    content: @Composable () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(MaterialTheme.colorScheme.surface.copy(alpha = 0.88f))
            .border(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.28f), RoundedCornerShape(20.dp))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleLarge)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        content()
    }
}

@Composable
private fun Field(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier.fillMaxWidth(),
    placeholder: String = "",
    sensitive: Boolean = false,
    singleLine: Boolean = true,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        placeholder = if (placeholder.isNotEmpty()) ({ Text(placeholder) }) else null,
        modifier = modifier,
        singleLine = singleLine,
        visualTransformation = if (sensitive) PasswordVisualTransformation() else VisualTransformation.None,
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = Signal,
            unfocusedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.4f),
            focusedLabelColor = Signal,
            cursorColor = Signal,
        ),
    )
}
