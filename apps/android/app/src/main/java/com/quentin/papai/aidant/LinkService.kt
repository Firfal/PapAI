package com.quentin.papai.aidant

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * Service de premier plan : garde le processus (et donc la connexion WebSocket)
 * vivant quand l'app est fermée, pour que le support soit prévenu tout de suite.
 * Sur Android on n'a pas besoin du son muet de l'iPhone.
 */
class LinkService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            ServiceCompat.startForeground(
                this, NOTIF_ID, notification(this),
                if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0,
            )
        } catch (e: Exception) {
            // Démarrage refusé (app en arrière-plan) : la connexion vit tant que l'app est ouverte.
            stopSelf()
            return START_NOT_STICKY
        }
        Helper.start()
        return START_STICKY
    }

    companion object {
        const val NOTIF_ID = 1

        fun start(ctx: Context) {
            try {
                ctx.startForegroundService(Intent(ctx, LinkService::class.java))
            } catch (_: Exception) {
            }
        }

        fun stop(ctx: Context) = ctx.stopService(Intent(ctx, LinkService::class.java))

        fun notification(ctx: Context): Notification {
            val open = PendingIntent.getActivity(
                ctx, 0, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE,
            )
            return NotificationCompat.Builder(ctx, PapAIApp.CHANNEL_LINK)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setPublicVersion(NotificationCompat.Builder(ctx, PapAIApp.CHANNEL_LINK)
                    .setSmallIcon(R.drawable.ic_notif)
                    .setContentTitle("PapAI est connecté")
                    .setContentIntent(open)
                    .build())
                .setSmallIcon(R.drawable.ic_notif)
                .setContentTitle(Helper.orgTitle)
                .setContentText("Vous serez prévenu dès qu'une demande d'aide arrive.")
                .setOngoing(true)
                .setSilent(true)
                .setPriority(NotificationCompat.PRIORITY_MIN)
                .setContentIntent(open)
                .build()
        }

        fun refresh(ctx: Context) {
            val manager = ctx.getSystemService(android.app.NotificationManager::class.java)
            if (manager.activeNotifications.any { it.id == NOTIF_ID }) {
                manager.notify(NOTIF_ID, notification(ctx))
            }
        }
    }
}
