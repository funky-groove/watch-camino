package org.caminoseguro.watch.core

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Instant

sealed interface StartOutcome {
    data class Started(val session: StageSession) : StartOutcome
    data class Rejected(val error: SessionError) : StartOutcome
}

sealed interface FinishOutcome {
    data class Finished(val summary: SessionSummary) : FinishOutcome
    data class Rejected(val error: SessionError) : FinishOutcome
}

/**
 * Servicio de aplicación: orquesta máquina de estados + stores + sync y expone `StateFlow`s para
 * que la UI sea fina. Todos los comandos se serializan con un [Mutex].
 *
 * Persistencia (§4): `start` y `finish` persisten siempre (primero se encola el evento y luego se
 * guarda la sesión). Las actualizaciones de ubicación persisten en cada fix que cambia algo; las de
 * pasos se agrupan (como mucho una escritura cada [stepPersistIntervalSeconds]) para no escribir en
 * flash a cada paso: si el proceso muere, los pasos se recuperan del contador del sensor.
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

    /** Carga catálogo, sesión persistida (restaura `Active`) y cola. Idempotente. */
    suspend fun restore() = mutex.withLock {
        if (restored) return@withLock
        _stages.value = catalog.stages()
        val snap = sessionStore.load()
        _snapshot.value = snap
        val active = snap.activeSession
        _activePois.value = if (active != null) poiSource.pois(active.stageId) else emptyList()
        _latestFix.value = active?.lastFix
        sync.load()
        restored = true
        _ready.value = true
    }

    suspend fun start(stageId: String): StartOutcome {
        val outcome = mutex.withLock {
            val now = clock.now()
            val t = machine.start(_snapshot.value, stageId, ids.newId(), now, _stages.value.map { it.id }.toSet())
            val error = t.error
            if (error != null) return@withLock StartOutcome.Rejected(error)
            sync.enqueue(t.events)
            persist(t.snapshot, now)
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
            persist(t.snapshot, now)
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
            val t = machine.updateLocation(before, fix, now, _activePois.value)
            if (t.error == null && t.snapshot != before) persist(t.snapshot, now)
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
            sync.enqueue(t.events)
            persist(t.snapshot, now)
            _activePois.value = emptyList()
            _latestFix.value = null
            val summary = t.summary!!
            _lastSummary.value = summary
            FinishOutcome.Finished(summary)
        }
        if (outcome is FinishOutcome.Finished) requestSync(manual = false)
        return outcome
    }

    /** Persiste lo que esté pendiente (p. ej. pasos agrupados) — llamar al ir a segundo plano. */
    suspend fun flush() = mutex.withLock {
        persist(_snapshot.value, clock.now())
    }

    /** Lanza un `syncNow` (el motor garantiza que sólo hay uno en vuelo). */
    fun requestSync(manual: Boolean): Job = scope.launch { sync.syncNow(manual) }

    fun stage(stageId: String): Stage? = _stages.value.firstOrNull { it.id == stageId }

    private suspend fun persist(snapshot: SessionSnapshot, now: Instant) {
        sessionStore.save(snapshot)
        _snapshot.value = snapshot
        lastPersistAt = now
    }
}
