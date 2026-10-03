package com.checkpoint.vpn.oneclick

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import com.checkpoint.vpn.oneclick.data.SettingsRepository
import com.checkpoint.vpn.oneclick.data.SiteSecretsStore

class CheckpointVpnApp : Application() {
    lateinit var settings: SettingsRepository
        private set
    lateinit var secrets: SiteSecretsStore
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        settings = SettingsRepository(this)
        secrets = SiteSecretsStore(this)
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            getString(R.string.vpn_notification_channel),
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        const val NOTIFICATION_CHANNEL_ID = "checkpoint_vpn_tunnel"
        lateinit var instance: CheckpointVpnApp
            private set
    }
}
