package com.checkpoint.vpn.oneclick.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore("checkpoint_vpn_settings")

data class AppSettings(
    val site: String = "",
    val sites: Set<String> = emptySet(),
    val username: String = "",
    val loginType: String = "vpn_VPN_RA",
    val ignoreServerCert: Boolean = true,
    val splitDestinations: String = "",
)

class SettingsRepository(private val context: Context) {
    private val siteKey = stringPreferencesKey("site")
    private val sitesKey = stringSetPreferencesKey("sites")
    private val usernameKey = stringPreferencesKey("username")
    private val loginTypeKey = stringPreferencesKey("login_type")
    private val ignoreCertKey = booleanPreferencesKey("ignore_server_cert")
    private val splitKey = stringPreferencesKey("split_destinations")

    val settings: Flow<AppSettings> = context.dataStore.data.map { prefs ->
        AppSettings(
            site = prefs[siteKey].orEmpty(),
            sites = prefs[sitesKey].orEmpty(),
            username = prefs[usernameKey].orEmpty(),
            loginType = prefs[loginTypeKey] ?: "vpn_VPN_RA",
            ignoreServerCert = prefs[ignoreCertKey] ?: true,
            splitDestinations = prefs[splitKey].orEmpty(),
        )
    }

    suspend fun update(transform: (AppSettings) -> AppSettings) {
        context.dataStore.edit { prefs ->
            val current = AppSettings(
                site = prefs[siteKey].orEmpty(),
                sites = prefs[sitesKey].orEmpty(),
                username = prefs[usernameKey].orEmpty(),
                loginType = prefs[loginTypeKey] ?: "vpn_VPN_RA",
                ignoreServerCert = prefs[ignoreCertKey] ?: true,
                splitDestinations = prefs[splitKey].orEmpty(),
            )
            val next = transform(current)
            prefs[siteKey] = next.site
            prefs[sitesKey] = next.sites
            prefs[usernameKey] = next.username
            prefs[loginTypeKey] = next.loginType
            prefs[ignoreCertKey] = next.ignoreServerCert
            prefs[splitKey] = next.splitDestinations
        }
    }

    suspend fun selectSite(site: String) {
        val trimmed = site.trim()
        if (trimmed.isEmpty()) return
        update { it.copy(site = trimmed, sites = it.sites + trimmed) }
    }

    suspend fun forgetSite(site: String) {
        val trimmed = site.trim()
        update {
            val remaining = it.sites - trimmed
            it.copy(
                sites = remaining,
                site = if (it.site == trimmed) remaining.firstOrNull().orEmpty() else it.site,
            )
        }
    }
}
