package com.checkpoint.vpn.oneclick.data

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class SiteSecretsStore(context: Context) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs = EncryptedSharedPreferences.create(
        context,
        "checkpoint_vpn_secrets",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun password(site: String): String? = prefs.getString(passwordKey(site), null)
    fun totpSecret(site: String): String? = prefs.getString(totpKey(site), null)
    fun hasPassword(site: String): Boolean = !password(site).isNullOrEmpty()
    fun hasTotp(site: String): Boolean = !totpSecret(site).isNullOrEmpty()

    fun savePassword(site: String, password: String) {
        prefs.edit().putString(passwordKey(site.trim()), password).apply()
    }

    fun saveTotp(site: String, secret: String) {
        val normalized = Totp.parseSecret(secret)
        prefs.edit().putString(totpKey(site.trim()), normalized).apply()
    }

    fun clearSite(site: String) {
        prefs.edit()
            .remove(passwordKey(site.trim()))
            .remove(totpKey(site.trim()))
            .apply()
    }

    private fun passwordKey(site: String) = "password:$site"
    private fun totpKey(site: String) = "totp:$site"
}
