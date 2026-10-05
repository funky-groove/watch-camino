package org.caminoseguro.watch.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Instant

sealed interface StartOutcome {
    data class Started(val session: StageSession) : StartOutcome
    data class Rejected(val error: SessionError) : StartOutcome
    /** No se pudo guardar la sesión: no ha cambiado nada (ni estado ni cola). Se puede reintentar. */
    data object StorageFailed : StartOutcome
}

sealed interface FinishOutcome {
    data class Finished(val summary: SessionSummary) : FinishOutcome
    data class Rejected(val error: SessionError) : FinishOutcome
    /** No se pudo guardar: la etapa sigue activa y no se ha encolado nada (V-04). Se puede reintentar. */
    data object StorageFailed : FinishOutcome
}

/** Resultado de `pause()`/`resume()` (V1.1 §C). */
sealed interface PauseOutcome {
    /** Aplicado y publicado en `snapshot`. Si el guardado falló, sigue en memoria y se avisa en `storageIssues`. */
    data class Applied(val session: StageSession) : PauseOutcome
    data class Rejected(val error: SessionError) : PauseOutcome
}

/** Problemas de almacenamiento que la UI muestra como error recuperable (V-01, V-03). */
@Suppress("EnumEntryName")
enum class StorageIssue {
    /** Falló una escritura: los datos siguen en memoria y se reintenta en la siguiente. */
    saveFailed,

    /** No se pudo leer el estado anterior: se apartó una copia y se empezó de cero. */
    restoreFailed,
}

/**
 * Servicio de aplicación: orquesta máquina de estados + stores + sync y expone `StateFlow`s para
 * que la UI sea fina. Todos los comandos se serializan con un [Mutex].
 *
 * Persistencia (§4): `start` y `finish` persisten siempre (primero se guarda la sesión y después se
 * encola el evento: si falla el guardado no se encola nada y no se duplican eventos, V-04). Las
 * actualizaciones de ubicación persisten en cada fix que cambia algo; las de pasos se agrupan (como
 * mucho una escritura cada [stepPersistIntervalSeconds]) para no escribir en flash a cada paso: si
 * el proceso muere, los pasos se recuperan del contador del sensor.
 *
 * Errores de E/S (V-01): ningún comando lanza por un fallo de almacenamiento. Las actualizaciones
 * siguen en memoria y lo publican en [storageIssues]; `start`/`finish` devuelven `StorageFailed`.
 */
class CaminoController(
    private val catalog: StageCatalog,
    private val poiSource: PoiSource,
    private val sessionStore: SessionStore,
    val sync: SyncEngine,
    private val clock: Clock,
    private val ids: IdGenerator,
    private val scope: CoroutineScope,
    private val stepPersistIntervalSeconds: Long = 30,
) {
    private val mutex = Mutex()
    private val machine = StageMachine(ids)
    private var restored = false
    private var lastPersistAt: Instant? = null

    private val _snapshot = MutableStateFlow(SessionSnapshot())
    val snapshot: StateFlow<SessionSnapshot> = _snapshot.asStateFlow()

    private val _stages = MutableStateFlow<List<Stage>>(emptyList())
    val stages: StateFlow<List<Stage>> = _stages.asStateFlow()

    /** POIs de la etapa activa (vacío en Idle). */
    private val _activePois = MutableStateFlow<List<Poi>>(emptyList())
    val activePois: StateFlow<List<Poi>> = _activePois.asStateFlow()

    /** Última posición con precisión aceptable (sólo memoria; no se persiste ni se envía). */
    private val _latestFix = MutableStateFlow<LocationFix?>(null)
    val latestFix: StateFlow<LocationFix?> = _latestFix.asStateFlow()

    /** Resumen de la última etapa finalizada en esta ejecución (pantalla Resumen). */
    private val _lastSummary = MutableStateFlow<SessionSummary?>(null)
    val lastSummary: StateFlow<SessionSummary?> = _lastSummary.asStateFlow()

    private val _alerts = MutableSharedFlow<PoiAlert>(extraBufferCapacity = 8)
    val alerts: SharedFlow<PoiAlert> = _alerts.asSharedFlow()

    private val _ready = MutableStateFlow(false)
    val ready: StateFlow<Boolean> = _ready.asStateFlow()

    val syncSnapshot: StateFlow<SyncSnapshot> get() = sync.snapshot

    private val _storageIssues = MutableStateFlow<Set<StorageIssue>>(emptySet())
    val storageIssues: StateFlow<Set<StorageIssue>> = _storageIssues.asStateFlow()

    private val _alertCategories = MutableStateFlow(PoiCategory.entries.toSet())
    val alertCategoriesState: StateFlow<Set<PoiCategory>> = _alertCategories.asStateFlow()

    /**
     * Categorías que avisan (Ajustes; por defecto todas). Las desactivadas no son candidatas: no
     * avisan ni consumen el límite de ritmo (§6.3).
     */
    var alertCategories: Set<PoiCategory>
        get() = _alertCategories.value
        set(value) {
            _alertCategories.value = value.toSet()
        }

    /** Carga catálogo, sesión persistida (restaura `Active`) y cola. Idempotente. */
    suspend fun restore() = mutex.withLock {
        if (restored) return@withLock
        _stages.value = catalog.stages()
        val snap = try {
            sessionStore.load()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
        if (snap == null || sessionStore.takeUnreadableNotice()) addIssue(StorageIssue.restoreFailed)
        _snapshot.value = snap ?: SessionSnapshot()
        val active = _snapshot.value.activeSession
        _activePois.value = if (active != null) poiSource.pois(active.stageId) else emptyList()
        _latestFix.value = active?.lastFix
        val queueUnreadable = try {
            sync.load()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            true
        }
        if (queueUnreadable) addIssue(StorageIssue.restoreFailed)
        restored = true
        _ready.value = true
    }

    suspend fun start(stageId: String): StartOutcome {
        val outcome = mutex.withLock {
            val now = clock.now()
            val t = machine.start(_snapshot.value, stageId, ids.newId(), now, _stages.value.map { it.id }.toSet())
            val error = t.error
            if (error != null) return@withLock StartOutcome.Rejected(error)
            if (!persistStrict(t.snapshot, now)) return@withLock StartOutcome.StorageFailed
            enqueueSafely(t.events)
            _activePois.value = poiSource.pois(stageId)
            _latestFix.value = null
            _lastSummary.value = null
            StartOutcome.Started(t.snapshot.activeSession!!)
        }
        if (outcome is StartOutcome.Started) requestSync(manual = false)
        return outcome
    }

    /** Ignorado sin error si no hay sesión activa. */
    suspend fun updateSteps(steps: Int) = mutex.withLock {
        val before = _snapshot.value
        val t = machine.updateSteps(before, steps)
        if (t.error != null || t.snapshot == before) return@withLock
        val now = clock.now()
        val last = lastPersistAt
        if (last == null || secondsBetween(last, now) >= stepPersistIntervalSeconds) {
            persistBestEffort(t.snapshot, now)
        } else {
            _snapshot.value = t.snapshot
        }
    }

    /** Devuelve el aviso POI a mostrar, si lo hay. Ignorado sin error si no hay sesión activa. */
    suspend fun updateLocation(fix: LocationFix): PoiAlert? {
        val alert = mutex.withLock {
            val before = _snapshot.value
            if (before.activeSession == null) return@withLock null
            if (DistanceAccumulator.isAccurateEnough(fix)) _latestFix.value = fix
            val now = clock.now()
            // `now` = reloj del sistema (§6.3), no fix.timestamp. Sólo categorías activadas (§6.3).
            val enabled = _alertCategories.value
            val candidates = _activePois.value.filter { it.category in enabled }
            val t = machine.updateLocation(before, fix, now, candidates)
            if (t.error == null && t.snapshot != before) persistBestEffort(t.snapshot, now)
            t.alert
        }
        if (alert != null) _alerts.tryEmit(alert)
        return alert
    }

    suspend fun finish(): FinishOutcome {
        val outcome = mutex.withLock {
            val now = clock.now()
            val t = machine.finish(_snapshot.value, now)
            val error = t.error
            if (error != null) return@withLock FinishOutcome.Rejected(error)
            // V-04: primero la sesión; si falla, la etapa sigue activa y no se encola nada.
            if (!persistStrict(t.snapshot, now)) return@withLock FinishOutcome.StorageFailed
            enqueueSafely(t.events)
            _activePois.value = emptyList()
            _latestFix.value = null
            val summary = t.summary!!
            _lastSummary.value = summary
            FinishOutcome.Finished(summary)
        }
        if (outcome is FinishOutcome.Finished) requestSync(manual = false)
        return outcome
    }

    /** V1.1 §C: pausa el trayecto (los pasos no se pausan). Nunca lanza por E/S. */
    suspend fun pause(): PauseOutcome = pauseOrResume(pause = true)

    /** V1.1 §C: reanuda el trayecto. Nunca lanza por E/S. */
    suspend fun resume(): PauseOutcome = pauseOrResume(pause = false)

    private suspend fun pauseOrResume(pause: Boolean): PauseOutcome = mutex.withLock {
        val now = clock.now()
        val before = _snapshot.value
        val t = if (pause) machine.pause(before, now) else machine.resume(before, now)
        val error = t.error
        if (error != null) return@withLock PauseOutcome.Rejected(error)
        // Best-effort: el cambio se publica siempre; si el guardado falla queda en `storageIssues`.
        persistBestEffort(t.snapshot, now)
        PauseOutcome.Applied(t.snapshot.activeSession!!)
    }

    /** Persiste lo que esté pendiente (p. ej. pasos agrupados) — llamar al ir a segundo plano. */
    suspend fun flush() = mutex.withLock {
        persistBestEffort(_snapshot.value, clock.now())
    }

    /** Lanza un `syncNow` (el motor garantiza que sólo hay uno en vuelo). Nunca lanza (V-01). */
    fun requestSync(manual: Boolean): Job = scope.launch {
        try {
            sync.syncNow(manual)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            addIssue(StorageIssue.saveFailed)
        }
    }

    /** Para la capa app: un fallo de E/S fuera del controlador (p. ej. contador de pasos). */
    fun reportStorageFailure() = addIssue(StorageIssue.saveFailed)

    /** El usuario ha leído el aviso. */
    fun dismissStorageIssue(issue: StorageIssue) {
        _storageIssues.update { it - issue }
    }

    fun stage(stageId: String): Stage? = _stages.value.firstOrNull { it.id == stageId }

    /** Guarda y publica; si falla no cambia nada y devuelve `false`. */
    private suspend fun persistStrict(snapshot: SessionSnapshot, now: Instant): Boolean {
        if (!save(snapshot)) return false
        _snapshot.value = snapshot
        lastPersistAt = now
        return true
    }

    /** Publica siempre (sigue en memoria); si falla el guardado se reintenta en la siguiente escritura. */
    private suspend fun persistBestEffort(snapshot: SessionSnapshot, now: Instant) {
        _snapshot.value = snapshot
        if (save(snapshot)) lastPersistAt = now
    }

    private suspend fun save(snapshot: SessionSnapshot): Boolean = try {
        sessionStore.save(snapshot)
        _storageIssues.update { it - StorageIssue.saveFailed }
        true
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        addIssue(StorageIssue.saveFailed)
        false
    }

    private suspend fun enqueueSafely(events: List<SyncEvent>) {
        try {
            sync.enqueue(events)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            addIssue(StorageIssue.saveFailed)
        }
    }

    private fun addIssue(issue: StorageIssue) {
        _storageIssues.update { it + issue }
    }
}
