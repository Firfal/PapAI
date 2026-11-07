package com.quentin.papai.aidant

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.RingtoneManager

class PapAIApp : Application() {
    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_HELP, "Demandes d'aide", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Votre proche demande de l'aide ou Holo a besoin de vous."
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400, 200, 600)
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT).build(),
                )
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_LINK, "Liaison", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Garde la liaison ouverte pour être prévenu tout de suite."
                setShowBadge(false)
            },
        )
        Helper.init(this)
    }

    companion object {
        const val CHANNEL_HELP = "help"
        const val CHANNEL_LINK = "link"
    }
}
