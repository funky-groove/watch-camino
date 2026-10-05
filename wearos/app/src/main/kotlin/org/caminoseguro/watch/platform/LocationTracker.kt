package org.caminoseguro.watch.platform

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import org.caminoseguro.watch.core.GeoPoint
import org.caminoseguro.watch.core.LocationFix
import java.time.Instant

/**
 * `LocationSource` de Wear OS sobre `LocationManager` (sin Play Services).
 * FUSED_PROVIDER si API ≥ 31 y existe; si no, GPS_PROVIDER. minTime 10 s, minDistance 20 m (§12).
 */
class LocationTracker(context: Context, private val onFix: (LocationFix) -> Unit) {
    private val appContext = context.applicationContext
    private val manager: LocationManager? = appContext.getSystemService(LocationManager::class.java)
    private var running = false

    private val listener = LocationListener { location -> onFix(location.toFix()) }

    val isRunning: Boolean get() = running

    @SuppressLint("MissingPermission") // comprobado justo antes
    fun start(): Boolean {
        if (running) return true
        val lm = manager ?: return false
        if (ContextCompat.checkSelfPermission(appContext, Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val provider = chooseProvider(lm) ?: run {
            Log.w(TAG, "Sin proveedor de ubicación")
            return false
        }
        return try {
            lm.requestLocationUpdates(provider, MIN_TIME_MS, MIN_DISTANCE_M, listener, Looper.getMainLooper())
            running = true
            Log.i(TAG, "Ubicación iniciada ($provider)")
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "Ubicación denegada: ${e.javaClass.simpleName}")
            false
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Proveedor no disponible: ${e.javaClass.simpleName}")
            false
        }
    }

    fun stop() {
        if (!running) return
        manager?.removeUpdates(listener)
        running = false
        Log.i(TAG, "Ubicación detenida")
    }

    private fun chooseProvider(lm: LocationManager): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (lm.hasProvider(LocationManager.FUSED_PROVIDER)) return LocationManager.FUSED_PROVIDER
            if (lm.hasProvider(LocationManager.GPS_PROVIDER)) return LocationManager.GPS_PROVIDER
            return null
        }
        return if (lm.allProviders.contains(LocationManager.GPS_PROVIDER)) LocationManager.GPS_PROVIDER else null
    }

    private companion object {
        const val TAG = "CaminoLocation"
        const val MIN_TIME_MS = 10_000L
        const val MIN_DISTANCE_M = 20f
    }
}

internal fun Location.toFix(): LocationFix = LocationFix(
    point = GeoPoint(latitude, longitude),
    // Sin precisión conocida → se trata como inaceptable (el acumulador la descartará).
    accuracyMeters = if (hasAccuracy()) accuracy.toDouble() else Double.MAX_VALUE,
    timestamp = Instant.ofEpochMilli(time),
)
