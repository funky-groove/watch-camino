package org.caminoseguro.watch.ui

import android.app.Application
import android.os.CancellationSignal
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.caminoseguro.watch.AppContainer
import org.caminoseguro.watch.CaminoApplication
import org.caminoseguro.watch.core.ActionGate
import org.caminoseguro.watch.core.DisplayPreferences
import org.caminoseguro.watch.core.EmergencyLocationPermission
import org.caminoseguro.watch.core.EmergencyLocationSummary
import org.caminoseguro.watch.core.FaceHintPolicy
import org.caminoseguro.watch.core.FaceHintState
import org.caminoseguro.watch.core.FinishOutcome
import org.caminoseguro.watch.core.LocationFix
import org.caminoseguro.watch.core.PaceMode
import org.caminoseguro.watch.core.PauseOutcome
import org.caminoseguro.watch.core.Poi
import org.caminoseguro.watch.core.PoiAlert
import org.caminoseguro.watch.core.PoiCategory
import org.caminoseguro.watch.core.SessionSnapshot
import org.caminoseguro.watch.core.Stage
import org.caminoseguro.watch.core.StartOutcome
import org.caminoseguro.watch.core.StorageIssue
import org.caminoseguro.watch.core.SosPresentation
import org.caminoseguro.watch.core.SosViewState
import org.caminoseguro.watch.core.SyncSnapshot
import org.caminoseguro.watch.core.ThemeId
import org.caminoseguro.watch.core.UnitSystem
import org.caminoseguro.watch.platform.Permissions
import org.caminoseguro.watch.platform.PermissionsState
import org.caminoseguro.watch.platform.SensorsState
import java.time.Instant

data class CaminoUiState(
    val ready: Boolean = false,
    val isDemo: Boolean = false,
    /** El trayecto se guarda en disco (false en escenarios DEMO en memoria). */
    val sessionPersisted: Boolean = true,
    val active: ActiveStageUi? = null,
    val choices: List<StageChoice> = emptyList(),
    val selected: Stage? = null,
    val sync: SyncSnapshot = SyncSnapshot(),
    val stats: StatsUi? = null,
    val summary: SummaryUi? = null,
    val lastAlert: PoiAlert? = null,
    val permissions: PermissionsState = PermissionsState(location = true, activityRecognition = true, notifications = true),
    val sensors: SensorsState = SensorsState(),
    /** Errores de almacenamiento recuperables (V-01, V-03). */
    val storageIssues: Set<StorageIssue> = emptySet(),
    /** Categorías de POI que avisan (Ajustes, V-08). */
    val alertCategories: Set<PoiCategory> = PoiCategory.entries.toSet(),
)

private data class SettingsInputs(
    val storageIssues: Set<StorageIssue>,
    val alertCategories: Set<PoiCategory>,
)

private data class CoreInputs(
    val ready: Boolean,
    val snapshot: SessionSnapshot,
    val stages: List<Stage>,
    val pois: List<org.caminoseguro.watch.core.Poi>,
    val latestFix: org.caminoseguro.watch.core.LocationFix?,
)

private data class ExtraInputs(
    val sync: SyncSnapshot,
    val lastSummary: org.caminoseguro.watch.core.SessionSummary?,
    val now: Instant,
    val permissions: PermissionsState,
    val sensors: SensorsState,
)

class CaminoViewModel(
    private val app: Application,
    private val container: AppContainer,
) : ViewModel() {

    private val controller = container.controller

    private val permissions = MutableStateFlow(Permissions.state(app))
    private val selectedStageId = MutableStateFlow<String?>(null)
    private val lastAlert = MutableStateFlow<PoiAlert?>(null)

    private val ticker = flow {
        while (true) {
            emit(Instant.now())
            delay(TICK_MS)
        }
    }

    private val core = combine(
        controller.ready,
        controller.snapshot,
        controller.stages,
        controller.activePois,
        controller.latestFix,
    ) { ready, snapshot, stages, pois, fix -> CoreInputs(ready, snapshot, stages, pois, fix) }

    private val extra = combine(
        controller.syncSnapshot,
        controller.lastSummary,
        ticker,
        permissions,
        container.runtime.sensors,
    ) { sync, summary, now, perms, sensors -> ExtraInputs(sync, summary, now, perms, sensors) }

    private val settings = combine(controller.storageIssues, controller.alertCategoriesState) { issues, cats ->
        SettingsInputs(issues, cats)
    }

    val ui: StateFlow<CaminoUiState> = combine(core, extra, selectedStageId, lastAlert, settings) { c, e, selectedId, alert, st ->
        val active = Presentation.activeStage(
            c.snapshot, c.stages, c.pois, c.latestFix, e.now,
            locationAvailable = e.permissions.location,
            stepsAvailable = e.sensors.hasStepSensor && e.permissions.activityRecognition,
        )
        CaminoUiState(
            ready = c.ready,
            isDemo = container.isDemo,
            sessionPersisted = container.sessionPersisted,
            active = active,
            choices = Presentation.stageChoices(c.stages, c.snapshot.history),
            selected = c.stages.firstOrNull { it.id == selectedId },
            sync = e.sync,
            stats = Presentation.stats(c.snapshot, c.stages, e.now),
            summary = e.lastSummary?.let { Presentation.summary(it, c.stages) },
            lastAlert = if (active != null) alert else null,
            permissions = e.permissions,
            sensors = e.sensors,
            storageIssues = st.storageIssues,
            alertCategories = st.alertCategories,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), CaminoUiState(isDemo = container.isDemo))

    /** Tema elegido en Ajustes (Negro por defecto, persistido). */
    val theme: StateFlow<ThemeId> = container.theme

    fun setTheme(theme: ThemeId) {
        container.setTheme(theme)
    }

    // ------------------------------------------------------------ Unidades, ritmo/velocidad e idioma (§G)

    val displayPreferences: StateFlow<DisplayPreferences> = container.displayPreferences

    fun setUnits(units: UnitSystem) = container.setUnits(units)

    fun setPaceMode(mode: PaceMode) = container.setPaceMode(mode)

    /** null = idioma del reloj. Sólo API 33+ (LocaleManager recrea la actividad). */
    fun setLanguage(language: org.caminoseguro.watch.core.AppLanguage?) = container.setLanguage(language)

    // ------------------------------------------------------------ Pausa (§C)

    private val pauseGate = ActionGate()

    /** «Pausar» / «Reanudar». Un toque doble no pausa y reanuda a la vez. */
    fun togglePause() {
        val active = state().active ?: return
        if (!pauseGate.tryEnter()) return
        launchGuarded {
            try {
                val out = if (active.paused) controller.resume() else controller.pause()
                // Rejected (ya pausado / no pausado / sin trayecto): el estado ya es el bueno; nada que hacer.
                if (out is PauseOutcome.Rejected) Log.i(TAG, "Pausa ignorada: ${out.error.name}")
            } finally {
                pauseGate.reset()
            }
        }
    }

    // ------------------------------------------------------------ Complicación → Trayecto

    private val _openTripPending = MutableStateFlow(false)

    /** Petición pendiente de volver a Trayecto (toque en la complicación); se consume al navegar. */
    val openTripPending: StateFlow<Boolean> = _openTripPending.asStateFlow()

    /** Sólo navega: nunca inicia un trayecto ni una llamada. */
    fun openTrip() {
        _openTripPending.value = true
    }

    fun consumeOpenTrip() {
        _openTripPending.value = false
    }

    // ------------------------------------------------------------ Aviso «Accede desde tu esfera» (§I)

    private val faceHintOffered = MutableStateFlow(false)

    /** ¿Ofrecer ahora el aviso? (una vez, sin trayecto, no tras recuperar uno en este arranque). */
    val faceHintOffer: StateFlow<Boolean> = combine(
        combine(container.faceHintLoaded, controller.ready) { loaded, ready -> loaded && ready },
        controller.snapshot,
        container.faceHint,
        container.restoredActiveThisLaunch,
        faceHintOffered,
    ) { ready, snapshot, hint, restored, offered ->
        FaceHintPolicy.shouldOffer(hint, ready, snapshot.activeSession != null, restored, offered)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    /** Se ha mostrado en este arranque: cerrarlo con «atrás» lo deja sin decidir (se ofrecerá otro día). */
    fun markFaceHintOffered() {
        faceHintOffered.value = true
    }

    fun dismissFaceHint() = container.setFaceHint(FaceHintState.dismissed)

    /**
     * F-10 (paridad con watchOS): cerrar el aviso con el gesto del sistema (deslizar/atrás) cuenta
     * como «Ahora no». No pisa una decisión ya tomada («Cómo añadirlo» → helpOpened).
     */
    fun dismissFaceHintIfUndecided() {
        if (container.faceHint.value == FaceHintState.notDecided) dismissFaceHint()
    }

    fun faceHintHelpOpened() = container.setFaceHint(FaceHintState.helpOpened)

    // ------------------------------------------------------------ Lugares (§J)

    /** Posición para Lugares sin trayecto: última conocida del sistema (nunca pide permiso). */
    private val placesFix = MutableStateFlow<LocationFix?>(null)

    /** Lugares: los de la etapa activa o, sin trayecto, todos los de demostración. */
    val places: StateFlow<PlacesSource> = combine(
        controller.activePois,
        controller.latestFix,
        placesFix,
        controller.ready,
    ) { activePois, tripFix, readFix, _ ->
        val pois = if (controller.snapshot.value.activeSession != null) activePois else container.allPois
        val fix = EmergencyLocationSummary.newest(tripFix, readFix)
        PlacesSource(pois = pois, position = fix, demoData = true)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlacesSource(emptyList(), null, true))

    /** Al abrir Lugares: última ubicación conocida (sin pedir permiso ni esperar al GPS). */
    fun refreshPlacesLocation() {
        val known = container.emergencyLocation.lastKnown() ?: return
        placesFix.value = EmergencyLocationSummary.newest(placesFix.value, known)
    }

    fun poi(id: String): Poi? = container.allPois.firstOrNull { it.id == id }

    // ------------------------------------------------------------ Iniciar trayecto sin doble inicio

    /** «Iniciar trayecto»: el primer toque abre el flujo; los siguientes se ignoran hasta volver a Inicio. */
    private val startFlowGate = ActionGate()
    private val _startFlowBusy = MutableStateFlow(false)
    val startFlowBusy: StateFlow<Boolean> = _startFlowBusy.asStateFlow()

    /** `true` si este toque inicia el flujo (permisos → elegir etapa); `false` si ya estaba en marcha. */
    fun beginStartFlow(): Boolean {
        if (state().active != null) return false
        val entered = startFlowGate.tryEnter()
        _startFlowBusy.value = startFlowGate.isBusy
        return entered
    }

    /** Al volver a Inicio (o tras iniciar/cancelar): se puede volver a pulsar. */
    fun resetStartFlow() {
        startFlowGate.reset()
        _startFlowBusy.value = false
    }

    /** Confirmación de inicio: un solo `controller.start` en vuelo. */
    private val confirmStartGate = ActionGate()

    private fun state(): CaminoUiState = ui.value

    // ------------------------------------------------------------ SOS (no toca el trayecto)

    private val sos = container.sos
    private val sosFix = MutableStateFlow<LocationFix?>(null)
    private val sosPermission = MutableStateFlow(EmergencyLocationPermission.NOT_DETERMINED)
    private var sosSignal: CancellationSignal? = null

    private val sosTicker = flow {
        while (true) {
            emit(Instant.now())
            delay(SOS_TICK_MS)
        }
    }

    val sosState: StateFlow<SosViewState> = combine(
        sos.lastResult,
        sosFix,
        controller.latestFix,
        sosPermission,
        sosTicker,
    ) { result, readFix, tripFix, permission, now ->
        val best = EmergencyLocationSummary.newest(readFix, tripFix?.normalizedAccuracy())
        SosPresentation.state(
            number = sos.number,
            capability = container.telephony,
            lastResult = result,
            location = EmergencyLocationSummary.of(best, now, permission),
            simulated = sos.isSimulated,
        )
    }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        SosPresentation.state(
            sos.number,
            container.telephony,
            null,
            EmergencyLocationSummary.of(null, Instant.now(), EmergencyLocationPermission.NOT_DETERMINED),
            simulated = sos.isSimulated,
        ),
    )

    /**
     * Al abrir la pantalla SOS: sin mensajes anteriores, última ubicación conocida y UNA lectura
     * si hay permiso. No pide permiso, no espera al GPS y no bloquea el botón.
     */
    fun onSosOpened() {
        sos.reset()
        val reader = container.emergencyLocation
        sosPermission.value = reader.permission()
        val known = reader.lastKnown()
        if (known != null) sosFix.value = EmergencyLocationSummary.newest(sosFix.value, known)
        sosSignal?.cancel()
        sosSignal = reader.requestCurrent { fix ->
            if (fix != null) sosFix.value = EmergencyLocationSummary.newest(sosFix.value, fix)
        }
    }

    fun onSosClosed() {
        sosSignal?.cancel()
        sosSignal = null
    }

    /** «Llamar al 112»: entrega `ACTION_DIAL tel:112` al sistema. No pausa ni finaliza el trayecto. */
    fun dialEmergency() {
        sos.dial()
    }

    override fun onCleared() {
        onSosClosed()
        super.onCleared()
    }

    private val _events = MutableStateFlow<UiEvent?>(null)
    val events: StateFlow<UiEvent?> = _events.asStateFlow()

    init {
        viewModelScope.launch { controller.alerts.collect { lastAlert.value = it } }
    }

    /** Permisos que faltan para pedirlos al pulsar "Comenzar etapa". */
    fun missingPermissions(): Array<String> = Permissions.missing(app)

    fun onPermissionsResult() {
        refreshPermissions()
        container.runtime.refresh()
    }

    fun selectStage(stageId: String) {
        selectedStageId.value = stageId
    }

    fun confirmStart() {
        val id = selectedStageId.value ?: return
        if (!confirmStartGate.tryEnter()) return
        launchGuarded {
            try {
                startStage(id)
            } finally {
                confirmStartGate.reset()
            }
        }
    }

    private suspend fun startStage(id: String) {
        when (val out = controller.start(id)) {
            is StartOutcome.Started -> {
                lastAlert.value = null
                _events.value = UiEvent.Started
            }
            is StartOutcome.Rejected -> _events.value = UiEvent.Rejected(out.error.name)
            // El aviso de error se ve en Inicio (storageIssues).
            StartOutcome.StorageFailed -> _events.value = UiEvent.Rejected(STORAGE)
        }
    }

    fun confirmFinish() {
        launchGuarded {
            when (val out = controller.finish()) {
                is FinishOutcome.Finished -> _events.value = UiEvent.Finished
                is FinishOutcome.Rejected -> _events.value = UiEvent.Rejected(out.error.name)
                // La etapa sigue activa; el aviso de error se ve en la pantalla de etapa.
                FinishOutcome.StorageFailed -> _events.value = UiEvent.Rejected(STORAGE)
            }
        }
    }

    fun dismissStorageIssue(issue: StorageIssue) {
        controller.dismissStorageIssue(issue)
    }

    fun setAlertCategory(category: PoiCategory, enabled: Boolean) {
        container.setAlertCategory(category, enabled)
    }

    /** V-01: un fallo inesperado se muestra como error recuperable, nunca cierra la app. */
    private fun launchGuarded(block: suspend () -> Unit) {
        viewModelScope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Acción fallida: ${e.javaClass.simpleName}")
                controller.reportStorageFailure()
                _events.value = UiEvent.Rejected(STORAGE)
            }
        }
    }

    fun consumeEvent() {
        _events.value = null
    }

    fun syncNow() {
        controller.requestSync(manual = true)
    }

    /** Al volver a primer plano: permisos, sensores y sincronización (disparador de §7). */
    fun onForeground() {
        refreshPermissions()
        container.runtime.refresh()
        if (controller.ready.value) controller.requestSync(manual = false)
    }

    fun onBackground() {
        container.appScope.launch { controller.flush() } // flush() no lanza; appScope tiene crashGuard
    }

    private fun refreshPermissions() {
        permissions.value = Permissions.state(app)
    }

    class Factory(private val app: CaminoApplication) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            require(modelClass.isAssignableFrom(CaminoViewModel::class.java)) { "ViewModel desconocido" }
            return CaminoViewModel(app, app.container) as T
        }
    }

    private companion object {
        const val TICK_MS = 10_000L
        const val SOS_TICK_MS = 5_000L
        const val TAG = "CaminoViewModel"
        const val STORAGE = "storage"
    }
}

sealed interface UiEvent {
    data object Started : UiEvent
    data object Finished : UiEvent
    data class Rejected(val reason: String) : UiEvent
}

/** El seguimiento usa `Double.MAX_VALUE` para "precisión desconocida"; en SOS se muestra sin precisión. */
private fun LocationFix.normalizedAccuracy(): LocationFix =
    if (accuracyMeters >= Double.MAX_VALUE) copy(accuracyMeters = 0.0) else this
