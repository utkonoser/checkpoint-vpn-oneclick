package com.checkpoint.vpn.oneclick.ui

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.checkpoint.vpn.oneclick.CheckpointVpnApp
import com.checkpoint.vpn.oneclick.data.QrImporter
import com.checkpoint.vpn.oneclick.data.Totp
import com.checkpoint.vpn.oneclick.vpn.NativeEngine
import com.checkpoint.vpn.oneclick.vpn.TunnelController
import com.checkpoint.vpn.oneclick.vpn.TunnelState
import com.checkpoint.vpn.oneclick.vpn.TunnelStatus
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class FormDraft(
    val site: String = "",
    val sites: Set<String> = emptySet(),
    val username: String = "",
    val loginType: String = "vpn_VPN_RA",
    val ignoreServerCert: Boolean = true,
    val splitDestinations: String = "",
)

data class UiState(
    val form: FormDraft = FormDraft(),
    val tunnel: TunnelStatus = TunnelStatus(),
    val hasPassword: Boolean = false,
    val hasTotp: Boolean = false,
    val totpCode: String = "------",
    val totpSeconds: Long = 30,
    val engineInfo: String = NativeEngine.helloOrStub(),
    val message: String? = null,
    val showQrScanner: Boolean = false,
)

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as CheckpointVpnApp
    private val _form = MutableStateFlow(FormDraft())
    private val _message = MutableStateFlow<String?>(null)
    private val _totpCode = MutableStateFlow("------")
    private val _totpSeconds = MutableStateFlow(30L)
    private val _showQr = MutableStateFlow(false)
    private val _vpnPermission = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val vpnPermissionRequests = _vpnPermission.asSharedFlow()

    private var pendingConnect = false
    private var persistJob: Job? = null

    val uiState: StateFlow<UiState> = combine(
        _form,
        TunnelController.status,
        _message,
        _totpCode,
        _totpSeconds,
    ) { form, tunnel, message, totpCode, totpSeconds ->
        UiState(
            form = form,
            tunnel = tunnel,
            hasPassword = app.secrets.hasPassword(form.site),
            hasTotp = app.secrets.hasTotp(form.site),
            totpCode = totpCode,
            totpSeconds = totpSeconds,
            engineInfo = NativeEngine.helloOrStub(),
            message = message,
        )
    }.combine(_showQr) { state, showQr ->
        state.copy(showQrScanner = showQr)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), UiState())

    init {
        viewModelScope.launch {
            hydrateFromStore()
        }
        viewModelScope.launch {
            while (isActive) {
                val site = _form.value.site
                val secret = app.secrets.totpSecret(site)
                if (!secret.isNullOrEmpty()) {
                    _totpCode.value = Totp.currentCode(secret)
                    _totpSeconds.value = Totp.secondsRemaining()
                } else {
                    _totpCode.value = "------"
                    _totpSeconds.value = 30
                }
                delay(1000)
            }
        }
    }

    private suspend fun hydrateFromStore() {
        val s = app.settings.settings.first()
        _form.value = FormDraft(
            site = s.site,
            sites = s.sites,
            username = s.username,
            loginType = s.loginType,
            ignoreServerCert = s.ignoreServerCert,
            splitDestinations = s.splitDestinations,
        )
    }

    private fun schedulePersist() {
        persistJob?.cancel()
        persistJob = viewModelScope.launch {
            delay(350)
            val f = _form.value
            app.settings.update {
                it.copy(
                    site = f.site,
                    username = f.username,
                    loginType = f.loginType,
                    ignoreServerCert = f.ignoreServerCert,
                    splitDestinations = f.splitDestinations,
                )
            }
        }
    }

    fun onSiteChange(value: String) {
        _form.update { it.copy(site = value) }
        schedulePersist()
    }

    fun onUsernameChange(value: String) {
        _form.update { it.copy(username = value) }
        schedulePersist()
    }

    fun onLoginTypeChange(value: String) {
        _form.update { it.copy(loginType = value) }
        schedulePersist()
    }

    fun onSplitChange(value: String) {
        _form.update { it.copy(splitDestinations = value) }
        schedulePersist()
    }

    fun onIgnoreCertChange(value: Boolean) {
        _form.update { it.copy(ignoreServerCert = value) }
        schedulePersist()
    }

    fun saveSite() = viewModelScope.launch {
        val site = _form.value.site.trim()
        if (site.isEmpty()) return@launch
        app.settings.selectSite(site)
        _form.update { it.copy(site = site, sites = it.sites + site) }
        _message.value = "Gateway saved"
    }

    fun forgetSite() = viewModelScope.launch {
        val site = _form.value.site.trim()
        app.secrets.clearSite(site)
        app.settings.forgetSite(site)
        hydrateFromStore()
        _message.value = "Gateway removed"
    }

    fun selectSite(site: String) = viewModelScope.launch {
        persistJob?.cancel()
        app.settings.selectSite(site)
        hydrateFromStore()
    }

    fun savePassword(password: String) {
        val site = _form.value.site.trim()
        if (site.isEmpty() || password.isEmpty()) return
        viewModelScope.launch {
            app.settings.selectSite(site)
            _form.update { it.copy(sites = it.sites + site) }
        }
        app.secrets.savePassword(site, password)
        _message.value = "Password saved"
    }

    fun saveTotp(secret: String) {
        val site = _form.value.site.trim()
        if (site.isEmpty() || secret.isEmpty()) return
        runCatching {
            app.secrets.saveTotp(site, secret)
            viewModelScope.launch {
                app.settings.selectSite(site)
                _form.update { it.copy(sites = it.sites + site) }
            }
            _message.value = "TOTP secret saved"
        }.onFailure {
            _message.value = it.message ?: "Invalid TOTP secret"
        }
    }

    fun importTotpFromUri(uri: Uri) = viewModelScope.launch {
        runCatching {
            val secret = QrImporter.decodeUri(getApplication(), uri)
            saveTotp(secret)
            _showQr.value = false
        }.onFailure {
            _message.value = it.message ?: "Could not read QR"
        }
    }

    fun importTotpRaw(raw: String) {
        runCatching {
            val secret = QrImporter.normalizeTotpPayload(raw)
            saveTotp(secret)
            _showQr.value = false
        }.onFailure {
            _message.value = it.message ?: "Invalid QR payload"
        }
    }

    fun openQrScanner() {
        _showQr.value = true
    }

    fun closeQrScanner() {
        _showQr.value = false
    }

    fun connect() {
        pendingConnect = true
        _vpnPermission.tryEmit(Unit)
    }

    fun disconnect() {
        TunnelController.requestDisconnect(getApplication())
    }

    fun onVpnPermissionResult(granted: Boolean) {
        if (!pendingConnect) return
        pendingConnect = false
        if (!granted) {
            TunnelController.updateStatus(TunnelState.Error, "VPN permission denied")
            return
        }
        TunnelController.requestConnect(getApplication())
    }

    fun clearMessage() {
        _message.value = null
    }
}
