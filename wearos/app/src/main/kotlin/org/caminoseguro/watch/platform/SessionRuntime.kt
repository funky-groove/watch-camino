package org.caminoseguro.watch.platform

import android.app.ForegroundServiceStartNotAllowedException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CancellationException
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
    /**
     * V-20: hay etapa activa con ubicación pero el servicio en primer plano no se pudo iniciar
     * (p. ej. relanzado en segundo plano en Android 12+). La UI pide abrir la app.
     */
    val foregroundServiceBlocked: Boolean = false,
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

        // V-01: cada lectura va protegida para que un fallo no mate el bucle (ni cierre la app).
        scope.launch {
            for (fix in fixes) guarded("ubicación") { controller.updateLocation(fix) }
        }
        scope.launch {
            rawSteps.filterNotNull().collect { raw -> guarded("pasos") { onRawSteps(raw) } }
        }
        scope.launch {
            controller.alerts.collect { alert -> guarded("aviso") { notifier.notify(alert) } }
        }
        scope.launch {
            controller.snapshot
                .map { it.activeSession?.sessionId }
                .distinctUntilChanged()
                .collect { sessionId -> guarded("sesión") { onActiveSessionChanged(sessionId) } }
        }
    }

    /** Re-evalúa sensores y servicio (p. ej. tras conceder permisos o volver a primer plano). */
    fun refresh() {
        scope.launch { withContext(Dispatchers.Main) { applySensors(activeSessionId != null) } }
    }

    private inline fun guarded(what: String, block: () -> Unit) {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "Fallo procesando $what: ${e.javaClass.simpleName}")
            controller.reportStorageFailure()
        }
    }

    private suspend fun onActiveSessionChanged(sessionId: String?) {
        // Un fallo del almacén de pasos no debe impedir arrancar/parar sensores y servicio.
        guarded("contador de pasos") { stepMutex.withLock { resetStepState(sessionId) } }
        withContext(Dispatchers.Main) { applySensors(sessionId != null) }
    }

    private suspend fun resetStepState(sessionId: String?) {
        activeSessionId = sessionId
        if (sessionId != null) {
            val stored = stepStore.load()
            if (stored != null && stored.sessionId == sessionId) {
                stepState = stored
            } else {
                // Primero en memoria: si el guardado falla, los pasos siguen contando.
                val initial = StepCounterNormalizer.initial(sessionId)
                stepState = initial
                stepStore.save(initial)
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
            // Si falla se reintenta en la siguiente lectura; los pasos siguen contando en memoria.
            guarded("contador de pasos") {
                stepStore.save(reading.state)
                stepStatePersistedAtMs = now
            }
        }
        return reading.steps
    }

    /** Siempre en el hilo principal (registro de listeners y arranque del servicio). */
    private fun applySensors(active: Boolean) {
        if (active) {
            val locationOk = locationTracker.start()
            val stepsOk = stepTracker.start()
            val serviceOk = if (locationOk) startService() else {
                stopService()
                true
            }
            _sensors.value = SensorsState(locationOk, stepsOk, stepTracker.hasSensor, foregroundServiceBlocked = !serviceOk)
        } else {
            locationTracker.stop()
            stepTracker.stop()
            stopService()
            _sensors.value = SensorsState(false, false, stepTracker.hasSensor)
        }
    }

    /**
     * V-20: arranque seguro del servicio en primer plano (también al relanzar con etapa activa).
     * Sin permiso de ubicación precisa no se intenta (el servicio `location` lo exige). En Android 12+
     * puede lanzar [ForegroundServiceStartNotAllowedException] si la app está en segundo plano: se
     * captura, se avisa en la UI y se reintenta en [refresh] al volver a primer plano.
     * Devuelve `true` si se pidió el arranque.
     */
    private fun startService(): Boolean {
        if (!Permissions.hasLocation(appContext)) return false
        return try {
            ContextCompat.startForegroundService(appContext, Intent(appContext, SessionService::class.java))
            true
        } catch (e: IllegalStateException) {
            val notAllowed = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                e is ForegroundServiceStartNotAllowedException
            Log.w(TAG, "Servicio no iniciado (segundo plano=$notAllowed): ${e.javaClass.simpleName}")
            false
        } catch (e: SecurityException) {
            Log.w(TAG, "Servicio no iniciado: ${e.javaClass.simpleName}")
            false
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
