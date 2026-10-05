package org.caminoseguro.watch.platform

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.caminoseguro.watch.core.CaminoController
import org.caminoseguro.watch.core.LocationFix
import org.caminoseguro.watch.core.StepCounterNormalizer
import org.caminoseguro.watch.core.StepCounterState
import org.caminoseguro.watch.data.FileStepCounterStore

data class SensorsState(
    val locationActive: Boolean = false,
    val stepsActive: Boolean = false,
    val hasStepSensor: Boolean = true,
)

/**
 * Ciclo de vida de plataforma ligado a la sesión (spec §12):
 * - Sensores **sólo** con sesión `Active`; se paran al finalizar.
 * - Foreground service de tipo `location` mientras hay sesión activa y permiso de ubicación.
 * - Avisos POI → notificación + vibración.
 * Las lecturas de sensores se procesan en orden en una única corrutina por fuente.
 */
class SessionRuntime(
    context: Context,
    private val controller: CaminoController,
    private val stepStore: FileStepCounterStore,
    private val notifier: PoiNotifier,
    private val scope: CoroutineScope,
) {
    private val appContext = context.applicationContext

    private val fixes = Channel<LocationFix>(capacity = 64)
    private val rawSteps = MutableStateFlow<Long?>(null)

    private val locationTracker = LocationTracker(appContext) { fix -> fixes.trySend(fix) }
    private val stepTracker = StepTracker(appContext) { raw -> rawSteps.value = raw }

    private val _sensors = MutableStateFlow(SensorsState(hasStepSensor = stepTracker.hasSensor))
    val sensors: StateFlow<SensorsState> = _sensors.asStateFlow()

    private val stepMutex = Mutex()
    private var attached = false
    @Volatile private var activeSessionId: String? = null
    private var stepState: StepCounterState? = null
    private var stepStatePersistedAtMs = 0L

    /** Llamar una vez tras `controller.restore()`. */
    fun attach() {
        if (attached) return
        attached = true

        scope.launch {
            for (fix in fixes) controller.updateLocation(fix)
        }
        scope.launch {
            rawSteps.filterNotNull().collect { raw -> onRawSteps(raw) }
        }
        scope.launch {
            controller.alerts.collect { alert -> notifier.notify(alert) }
        }
        scope.launch {
            controller.snapshot
                .map { it.activeSession?.sessionId }
                .distinctUntilChanged()
                .collect { sessionId -> onActiveSessionChanged(sessionId) }
        }
    }

    /** Re-evalúa sensores y servicio (p. ej. tras conceder permisos o volver a primer plano). */
    fun refresh() {
        scope.launch { withContext(Dispatchers.Main) { applySensors(activeSessionId != null) } }
    }

    private suspend fun onActiveSessionChanged(sessionId: String?) {
        stepMutex.withLock { resetStepState(sessionId) }
        withContext(Dispatchers.Main) { applySensors(sessionId != null) }
    }

    private suspend fun resetStepState(sessionId: String?) {
        activeSessionId = sessionId
        if (sessionId != null) {
            val stored = stepStore.load()
            stepState = if (stored != null && stored.sessionId == sessionId) stored else {
                StepCounterNormalizer.initial(sessionId).also { stepStore.save(it) }
            }
        } else {
            stepState = null
            rawSteps.value = null
            stepStore.clear()
        }
    }

    private suspend fun onRawSteps(raw: Long) {
        val steps = stepMutex.withLock { normalize(raw) } ?: return
        controller.updateSteps(steps)
    }

    private suspend fun normalize(raw: Long): Int? {
        val current = stepState ?: return null
        val reading = StepCounterNormalizer.onReading(current, raw, stepTracker.bootId())
        stepState = reading.state
        val now = System.currentTimeMillis()
        val rebooted = reading.state.offset != current.offset || current.baseline == null
        if (rebooted || now - stepStatePersistedAtMs >= STEP_PERSIST_INTERVAL_MS) {
            stepStore.save(reading.state)
            stepStatePersistedAtMs = now
        }
        return reading.steps
    }

    /** Siempre en el hilo principal (registro de listeners y arranque del servicio). */
    private fun applySensors(active: Boolean) {
        if (active) {
            val locationOk = locationTracker.start()
            val stepsOk = stepTracker.start()
            if (locationOk) startService() else stopService()
            _sensors.value = SensorsState(locationOk, stepsOk, stepTracker.hasSensor)
        } else {
            locationTracker.stop()
            stepTracker.stop()
            stopService()
            _sensors.value = SensorsState(false, false, stepTracker.hasSensor)
        }
    }

    private fun startService() {
        try {
            ContextCompat.startForegroundService(appContext, Intent(appContext, SessionService::class.java))
        } catch (e: IllegalStateException) {
            // Android 12+: no se puede iniciar desde segundo plano. Se reintenta al volver a primer plano.
            Log.w(TAG, "Servicio no iniciado: ${e.javaClass.simpleName}")
        } catch (e: SecurityException) {
            Log.w(TAG, "Servicio no iniciado: ${e.javaClass.simpleName}")
        }
    }

    private fun stopService() {
        appContext.stopService(Intent(appContext, SessionService::class.java))
    }

    private companion object {
        const val TAG = "CaminoRuntime"
        const val STEP_PERSIST_INTERVAL_MS = 30_000L
    }
}
