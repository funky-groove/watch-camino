package org.caminoseguro.watch.ui

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
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
import org.caminoseguro.watch.core.FinishOutcome
import org.caminoseguro.watch.core.PoiAlert
import org.caminoseguro.watch.core.SessionSnapshot
import org.caminoseguro.watch.core.Stage
import org.caminoseguro.watch.core.StartOutcome
import org.caminoseguro.watch.core.SyncSnapshot
import org.caminoseguro.watch.platform.Permissions
import org.caminoseguro.watch.platform.PermissionsState
import org.caminoseguro.watch.platform.SensorsState
import java.time.Instant

data class CaminoUiState(
    val ready: Boolean = false,
    val isDemo: Boolean = false,
    val active: ActiveStageUi? = null,
    val choices: List<StageChoice> = emptyList(),
    val selected: Stage? = null,
    val sync: SyncSnapshot = SyncSnapshot(),
    val stats: StatsUi? = null,
    val summary: SummaryUi? = null,
    val lastAlert: PoiAlert? = null,
    val permissions: PermissionsState = PermissionsState(location = true, activityRecognition = true, notifications = true),
    val sensors: SensorsState = SensorsState(),
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

    val ui: StateFlow<CaminoUiState> = combine(core, extra, selectedStageId, lastAlert) { c, e, selectedId, alert ->
        val active = Presentation.activeStage(c.snapshot, c.stages, c.pois, c.latestFix, e.now)
        CaminoUiState(
            ready = c.ready,
            isDemo = container.isDemo,
            active = active,
            choices = Presentation.stageChoices(c.stages, c.snapshot.history),
            selected = c.stages.firstOrNull { it.id == selectedId },
            sync = e.sync,
            stats = Presentation.stats(c.snapshot, c.stages, e.now),
            summary = e.lastSummary?.let { Presentation.summary(it, c.stages) },
            lastAlert = if (active != null) alert else null,
            permissions = e.permissions,
            sensors = e.sensors,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), CaminoUiState(isDemo = container.isDemo))

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
        viewModelScope.launch {
            when (val out = controller.start(id)) {
                is StartOutcome.Started -> {
                    lastAlert.value = null
                    _events.value = UiEvent.Started
                }
                is StartOutcome.Rejected -> _events.value = UiEvent.Rejected(out.error.name)
            }
        }
    }

    fun confirmFinish() {
        viewModelScope.launch {
            when (val out = controller.finish()) {
                is FinishOutcome.Finished -> _events.value = UiEvent.Finished
                is FinishOutcome.Rejected -> _events.value = UiEvent.Rejected(out.error.name)
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
        container.appScope.launch { controller.flush() }
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
    }
}

sealed interface UiEvent {
    data object Started : UiEvent
    data object Finished : UiEvent
    data class Rejected(val reason: String) : UiEvent
}
