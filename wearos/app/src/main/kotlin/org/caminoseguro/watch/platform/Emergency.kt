package org.caminoseguro.watch.platform

import android.Manifest
import android.annotation.SuppressLint
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.CancellationSignal
import android.util.Log
import androidx.core.content.ContextCompat
import org.caminoseguro.watch.core.DialResult
import org.caminoseguro.watch.core.EmergencyDialer
import org.caminoseguro.watch.core.EmergencyLocationPermission
import org.caminoseguro.watch.core.EmergencyNumber
import org.caminoseguro.watch.core.GeoPoint
import org.caminoseguro.watch.core.LocationFix
import org.caminoseguro.watch.core.TelephonyCapability
import java.time.Instant

/**
 * Entrega del 112 al sistema con `ACTION_DIAL` (docs/accessibility/SOS_PLATFORM_CAPABILITIES.md §1):
 * "this Intent [ACTION_CALL] cannot be used to call emergency numbers. Applications can dial emergency
 * numbers using ACTION_DIAL". El marcador muestra el número y el USUARIO pulsa llamar. No se declara
 * `CALL_PHONE`. Nunca se comprueba la telefonía antes: se intenta siempre y se captura el fallo.
 */
class SystemEmergencyDialer(context: Context) : EmergencyDialer {
    private val appContext = context.applicationContext

    override fun requestDial(number: EmergencyNumber): DialResult {
        val uri = number.telUri ?: return DialResult.Failed
        // Contexto de aplicación: hace falta NEW_TASK para abrir una actividad desde él.
        val intent = Intent(Intent.ACTION_DIAL, Uri.parse(uri)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            appContext.startActivity(intent)
            DialResult.HandedToSystem
        } catch (e: ActivityNotFoundException) {
            Log.w(TAG, "Sin marcador para ACTION_DIAL")
            DialResult.NoDialer
        } catch (e: SecurityException) {
            Log.w(TAG, "Marcador denegado: ${e.javaClass.simpleName}")
            DialResult.Failed
        } catch (e: RuntimeException) {
            Log.w(TAG, "Marcador fallido: ${e.javaClass.simpleName}")
            DialResult.Failed
        }
    }

    private companion object {
        const val TAG = "CaminoSos"
    }
}

/**
 * Lo que el reloj DECLARA de telefonía. Sólo elige el texto («Llamar al 112» / «Marcar 112») y un
 * aviso; nunca bloquea el intento. Tener Internet (Wi-Fi/LTE de datos) no implica poder llamar.
 */
object TelephonyProbe {
    fun read(context: Context): TelephonyCapability {
        val pm = context.packageManager
        val telephony = pm.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)
        val calling = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_CALLING)
        } else {
            null
        }
        return TelephonyCapability(hasTelephony = telephony, hasCallingFeature = calling)
    }
}

/**
 * Ubicación para la pantalla SOS: nunca pide permiso ni bloquea. Si hay permiso, da la última
 * conocida y pide UNA lectura (`getCurrentLocation`, API 30+) que se cancela al salir. No envía la
 * ubicación a ningún sitio y no la registra en logs.
 */
class EmergencyLocationReader(context: Context) {
    private val appContext = context.applicationContext
    private val manager: LocationManager? = appContext.getSystemService(LocationManager::class.java)

    fun permission(): EmergencyLocationPermission {
        val fine = granted(Manifest.permission.ACCESS_FINE_LOCATION)
        val coarse = granted(Manifest.permission.ACCESS_COARSE_LOCATION)
        return if (fine || coarse) EmergencyLocationPermission.GRANTED else EmergencyLocationPermission.DENIED
    }

    @SuppressLint("MissingPermission") // permission() comprobado justo antes; SecurityException capturada
    fun lastKnown(): LocationFix? {
        val lm = manager ?: return null
        if (permission() != EmergencyLocationPermission.GRANTED) return null
        return providers(lm).mapNotNull { provider ->
            try {
                lm.getLastKnownLocation(provider)
            } catch (e: SecurityException) {
                null
            } catch (e: IllegalArgumentException) {
                null
            }
        }.maxByOrNull { it.time }?.toEmergencyFix()
    }

    /**
     * Pide una lectura única. Devuelve la señal para cancelarla (o null si no se pudo pedir).
     * [onResult] se llama en el hilo principal, con null si no hubo posición.
     */
    @SuppressLint("MissingPermission") // permission() comprobado justo antes; SecurityException capturada
    fun requestCurrent(onResult: (LocationFix?) -> Unit): CancellationSignal? {
        val lm = manager ?: return null
        if (permission() != EmergencyLocationPermission.GRANTED) return null
        val provider = providers(lm).firstOrNull() ?: return null
        val signal = CancellationSignal()
        return try {
            lm.getCurrentLocation(provider, signal, appContext.mainExecutor) { location: Location? ->
                onResult(location?.toEmergencyFix())
            }
            signal
        } catch (e: SecurityException) {
            Log.w(TAG, "Lectura única denegada: ${e.javaClass.simpleName}")
            null
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Proveedor no disponible: ${e.javaClass.simpleName}")
            null
        }
    }

    /** Proveedores utilizables con el permiso concedido, del más preciso al menos. */
    private fun providers(lm: LocationManager): List<String> {
        val fine = granted(Manifest.permission.ACCESS_FINE_LOCATION)
        val candidates = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(LocationManager.FUSED_PROVIDER)
            if (fine) add(LocationManager.GPS_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
        }
        val available = try {
            lm.allProviders.toSet()
        } catch (e: RuntimeException) {
            emptySet()
        }
        return candidates.filter { it in available }
    }

    private fun granted(permission: String): Boolean =
        ContextCompat.checkSelfPermission(appContext, permission) == PackageManager.PERMISSION_GRANTED

    private companion object {
        const val TAG = "CaminoSos"
    }
}

/** Precisión desconocida → 0 (el resumen la muestra como "sin precisión", no como ±1 000 000 m). */
private fun Location.toEmergencyFix(): LocationFix = LocationFix(
    point = GeoPoint(latitude, longitude),
    accuracyMeters = if (hasAccuracy()) accuracy.toDouble() else 0.0,
    timestamp = Instant.ofEpochMilli(time),
)
