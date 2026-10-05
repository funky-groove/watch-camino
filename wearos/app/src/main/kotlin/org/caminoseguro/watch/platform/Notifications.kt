package org.caminoseguro.watch.platform

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.DisplayFormat
import org.caminoseguro.watch.core.PoiAlert
import org.caminoseguro.watch.core.PoiCategory
import org.caminoseguro.watch.ui.MainActivity

object Notifications {
    const val CHANNEL_SESSION = "session"
    const val CHANNEL_POI = "poi_alerts"
    const val SESSION_NOTIFICATION_ID = 1001
    private const val POI_NOTIFICATION_BASE_ID = 2000

    private val POI_VIBRATION = longArrayOf(0, 250, 150, 250)

    fun createChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val session = NotificationChannel(
            CHANNEL_SESSION,
            context.getString(R.string.channel_session_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = context.getString(R.string.channel_session_desc)
            setShowBadge(false)
        }
        // Háptica del aviso POI: vibración del canal (no requiere el permiso VIBRATE).
        val poi = NotificationChannel(
            CHANNEL_POI,
            context.getString(R.string.channel_poi_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.channel_poi_desc)
            enableVibration(true)
            vibrationPattern = POI_VIBRATION
        }
        manager.createNotificationChannels(listOf(session, poi))
    }

    fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /** Notificación en curso del foreground service (sólo con sesión activa). */
    fun sessionOngoing(context: Context): Notification =
        NotificationCompat.Builder(context, CHANNEL_SESSION)
            .setSmallIcon(R.drawable.ic_stat_camino)
            .setContentTitle(context.getString(R.string.notif_session_title))
            .setContentText(context.getString(R.string.notif_session_text))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openAppIntent(context))
            .build()

    fun canPostNotifications(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    fun poiNotificationId(poiId: String): Int = POI_NOTIFICATION_BASE_ID + (poiId.hashCode() and 0x0FFF)

    @SuppressLint("MissingPermission") // comprobado con canPostNotifications()
    fun postPoiAlert(context: Context, alert: PoiAlert, format: DisplayFormat) {
        if (!canPostNotifications(context)) return
        val category = context.getString(categoryLabel(alert.poi.category))
        // Unidades del usuario (V1.1 §G); distancia en línea recta.
        val text = format.poiAlertText(alert.poi, alert.distanceMeters)
        val notification = NotificationCompat.Builder(context, CHANNEL_POI)
            .setSmallIcon(R.drawable.ic_stat_camino)
            .setContentTitle(context.getString(R.string.notif_poi_title, category))
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVibrate(POI_VIBRATION)
            .setAutoCancel(true)
            .setContentIntent(openAppIntent(context))
            .build()
        try {
            NotificationManagerCompat.from(context).notify(poiNotificationId(alert.poi.id), notification)
        } catch (e: SecurityException) {
            Log.w("CaminoNotify", "Aviso POI no publicado: ${e.javaClass.simpleName}")
        }
    }

    fun categoryLabel(category: PoiCategory): Int = when (category) {
        PoiCategory.water -> R.string.poi_water
        PoiCategory.shelter -> R.string.poi_shelter
        PoiCategory.pharmacy -> R.string.poi_pharmacy
        PoiCategory.health -> R.string.poi_health
        PoiCategory.food -> R.string.poi_food
        PoiCategory.landmark -> R.string.poi_landmark
    }
}

/** Adaptador `Notifier` de la capa app: notificación local + vibración del canal. */
class PoiNotifier(private val context: Context, private val format: () -> DisplayFormat) {
    fun notify(alert: PoiAlert) {
        // Sin nombre ni coordenadas en el log.
        Log.i("CaminoNotify", "Aviso POI (${alert.poi.category.name})")
        Notifications.postPoiAlert(context, alert, format())
    }
}
