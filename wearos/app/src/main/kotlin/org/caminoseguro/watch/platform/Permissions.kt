package org.caminoseguro.watch.platform

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

data class PermissionsState(
    val location: Boolean,
    val activityRecognition: Boolean,
    val notifications: Boolean,
)

object Permissions {
    /** Lo que se pide al pulsar "Comenzar etapa" (spec §11: en contexto, no al abrir). */
    fun runtimePermissions(): Array<String> = buildList {
        add(Manifest.permission.ACCESS_FINE_LOCATION)
        add(Manifest.permission.ACCESS_COARSE_LOCATION)
        add(Manifest.permission.ACTIVITY_RECOGNITION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
    }.toTypedArray()

    fun missing(context: Context): Array<String> =
        runtimePermissions().filterNot { granted(context, it) }.toTypedArray()

    fun state(context: Context): PermissionsState = PermissionsState(
        location = hasLocation(context),
        activityRecognition = granted(context, Manifest.permission.ACTIVITY_RECOGNITION),
        notifications = Notifications.canPostNotifications(context),
    )

    /** Ubicación precisa: el acumulador descarta precisiones > 50 m, así que la aproximada no sirve. */
    fun hasLocation(context: Context): Boolean = granted(context, Manifest.permission.ACCESS_FINE_LOCATION)

    private fun granted(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
}
