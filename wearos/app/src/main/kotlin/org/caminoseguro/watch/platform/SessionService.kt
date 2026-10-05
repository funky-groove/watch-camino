package org.caminoseguro.watch.platform

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.util.Log
import androidx.core.app.ServiceCompat

/**
 * Foreground service de tipo `location` (spec §12): mantiene vivo el proceso mientras hay sesión
 * activa. Los sensores los gestiona [SessionRuntime]; el servicio sólo aporta la notificación en
 * curso y la prioridad de proceso.
 */
class SessionService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!Permissions.hasLocation(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        return try {
            ServiceCompat.startForeground(
                this,
                Notifications.SESSION_NOTIFICATION_ID,
                Notifications.sessionOngoing(this),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
            START_STICKY
        } catch (e: Exception) {
            // p. ej. ForegroundServiceStartNotAllowedException / SecurityException.
            Log.w(TAG, "startForeground falló: ${e.javaClass.simpleName}")
            stopSelf()
            START_NOT_STICKY
        }
    }

    override fun onDestroy() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private companion object {
        const val TAG = "CaminoService"
    }
}
