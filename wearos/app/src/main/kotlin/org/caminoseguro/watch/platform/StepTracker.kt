package org.caminoseguro.watch.platform

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * `StepSource` de Wear OS: `Sensor.TYPE_STEP_COUNTER` (acumulado desde el arranque del reloj).
 * Entrega la lectura bruta; la normalización (baseline/offset) es lógica pura del núcleo.
 */
class StepTracker(context: Context, private val onRaw: (raw: Long) -> Unit) : SensorEventListener {
    private val appContext = context.applicationContext
    private val sensorManager: SensorManager? = appContext.getSystemService(SensorManager::class.java)
    private val sensor: Sensor? = sensorManager?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
    private var running = false

    val hasSensor: Boolean get() = sensor != null
    val isRunning: Boolean get() = running

    fun start(): Boolean {
        if (running) return true
        val sm = sensorManager ?: return false
        val s = sensor ?: return false
        if (ContextCompat.checkSelfPermission(appContext, Manifest.permission.ACTIVITY_RECOGNITION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        running = sm.registerListener(this, s, SensorManager.SENSOR_DELAY_NORMAL, MAX_REPORT_LATENCY_US)
        Log.i(TAG, if (running) "Pasos iniciados" else "No se pudo registrar el sensor de pasos")
        return running
    }

    fun stop() {
        if (!running) return
        sensorManager?.unregisterListener(this)
        running = false
        Log.i(TAG, "Pasos detenidos")
    }

    override fun onSensorChanged(event: SensorEvent?) {
        val e = event ?: return
        if (e.sensor?.type != Sensor.TYPE_STEP_COUNTER || e.values.isEmpty()) return
        onRaw(e.values[0].toLong())
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    /** Contador de arranques del sistema, para detectar reinicios del reloj. */
    fun bootId(): Long? {
        val n = Settings.Global.getInt(appContext.contentResolver, Settings.Global.BOOT_COUNT, -1)
        return if (n >= 0) n.toLong() else null
    }

    private companion object {
        const val TAG = "CaminoSteps"
        const val MAX_REPORT_LATENCY_US = 10_000_000 // agrupa lecturas hasta 10 s (batería)
    }
}
