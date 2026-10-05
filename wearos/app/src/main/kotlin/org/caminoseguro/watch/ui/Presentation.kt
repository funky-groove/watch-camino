package org.caminoseguro.watch.ui

import org.caminoseguro.watch.core.CaminoStats
import org.caminoseguro.watch.core.DayFigures
import org.caminoseguro.watch.core.LocationFix
import org.caminoseguro.watch.core.Places
import org.caminoseguro.watch.core.Poi
import org.caminoseguro.watch.core.PoiAlertEngine
import org.caminoseguro.watch.core.PoiDistance
import org.caminoseguro.watch.core.ProfileSample
import org.caminoseguro.watch.core.SessionSnapshot
import org.caminoseguro.watch.core.SessionSummary
import org.caminoseguro.watch.core.Stage
import org.caminoseguro.watch.core.StageMachine
import org.caminoseguro.watch.core.SyncStatus
import org.caminoseguro.watch.core.TripFigures
import org.caminoseguro.watch.core.Totals
import java.time.Instant

// Lógica de presentación pura (sin Android): testeable en JVM.

data class ActiveStageUi(
    val stageId: String,
    val stageName: String,
    val remainingMeters: Double,
    val walkedMeters: Double,
    val steps: Int,
    val elapsedSeconds: Long,
    /** Null si aún no hay fix (o no quedan POIs sin avisar). */
    val nextPoi: PoiDistance?,
    val hasFix: Boolean,
    /** Cifras para la pantalla principal, sin ceros falsos (null = "sin datos"). */
    val figures: TripFigures,
    // ---- V1.1 ----
    /** «Pausado» (true) / «En marcha» (false). */
    val paused: Boolean = false,
    /** Tiempo en movimiento (§D); se muestra diferenciado de la duración total. */
    val movingSeconds: Long = 0,
    /** Última altitud GPS válida; null si nunca hubo. */
    val altitude: Double? = null,
    /** La altitud tiene más de 5 min (o no hay). */
    val altitudeStale: Boolean = true,
    /** Hubo al menos una altitud válida: subida/bajada son reales (si no, "sin datos"). */
    val hasAltitudeData: Boolean = false,
    val ascentMeters: Double = 0.0,
    val descentMeters: Double = 0.0,
    /** Perfil registrado (§F). */
    val profile: List<ProfileSample> = emptyList(),
    /** Lugares útiles: máx. 3 (agua, alojamiento, resto), distancia en línea recta. */
    val usefulPlaces: List<PoiDistance> = emptyList(),
)

/**
 * Lugares: POIs (de la etapa activa o todos) y la posición para medir la distancia en línea recta.
 * [demoData]: los lugares vienen de fixtures de DEMOSTRACIÓN con coordenadas aproximadas (§0).
 */
data class PlacesSource(val pois: List<Poi>, val position: LocationFix?, val demoData: Boolean)

data class StageChoice(val stage: Stage, val suggested: Boolean)

data class StatsUi(
    val today: DayFigures?,
    val todayStageName: String?,
    val totals: Totals,
)

data class SummaryUi(
    val stageName: String,
    val distanceMeters: Double,
    val steps: Int,
    /** Duración total (`finishedAt − startedAt`). */
    val activeSeconds: Long,
    /** Tiempo en movimiento (≤ duración total). */
    val movingSeconds: Long = 0,
    val pausedSeconds: Long = 0,
    val ascentMeters: Int = 0,
    val descentMeters: Int = 0,
    val profile: List<ProfileSample> = emptyList(),
)

enum class SyncLabel { SYNCED, PENDING, OFFLINE, BLOCKED, NEEDS_LINK, SYNCING }

object Presentation {

    fun stageName(stages: List<Stage>, stageId: String): String =
        stages.firstOrNull { it.id == stageId }?.name ?: stageId

    fun activeStage(
        snapshot: SessionSnapshot,
        stages: List<Stage>,
        pois: List<Poi>,
        latestFix: LocationFix?,
        now: Instant,
        locationAvailable: Boolean = true,
        stepsAvailable: Boolean = true,
    ): ActiveStageUi? {
        val session = snapshot.activeSession ?: return null
        val stage = stages.firstOrNull { it.id == session.stageId }
        val remaining = if (stage != null) CaminoStats.remainingMeters(stage, session) else 0.0
        val next = latestFix?.let { PoiAlertEngine.nearestUnalerted(pois, session.alertedPoiIds, it.point) }
        val elapsed = StageMachine.activeSeconds(session.startedAt, now).toLong()
        return ActiveStageUi(
            stageId = session.stageId,
            stageName = stage?.name ?: session.stageId,
            remainingMeters = remaining,
            walkedMeters = session.distanceMeters,
            steps = session.steps,
            elapsedSeconds = elapsed,
            nextPoi = next,
            hasFix = latestFix != null,
            figures = TripFigures.of(session, stage, now, locationAvailable, stepsAvailable),
            paused = session.isPaused,
            // Igual que el resumen: tiempo en movimiento ≤ duración (p. ej. reloj del sistema hacia atrás).
            movingSeconds = minOf(session.movingSeconds.toLong(), elapsed).coerceAtLeast(0),
            altitude = session.altitude,
            altitudeStale = session.isAltitudeStale(now),
            // `altitudeRef` se borra al pausar (§C); `altitude` conserva la última válida.
            hasAltitudeData = session.altitude != null,
            ascentMeters = session.ascentMeters,
            descentMeters = session.descentMeters,
            profile = session.profile,
            usefulPlaces = Places.useful(pois, latestFix?.point),
        )
    }

    fun stageChoices(stages: List<Stage>, history: List<SessionSummary>): List<StageChoice> {
        val ordered = CaminoStats.stagesWithSuggestionFirst(stages, history)
        return ordered.mapIndexed { i, s -> StageChoice(s, suggested = i == 0) }
    }

    fun stats(snapshot: SessionSnapshot, stages: List<Stage>, now: Instant): StatsUi {
        val today = CaminoStats.today(snapshot, now)
        return StatsUi(
            today = today,
            todayStageName = today?.let { stageName(stages, it.stageId) },
            totals = CaminoStats.totals(snapshot.history),
        )
    }

    fun summary(summary: SessionSummary, stages: List<Stage>): SummaryUi = SummaryUi(
        stageName = stageName(stages, summary.stageId),
        distanceMeters = summary.distanceMeters.toDouble(),
        steps = summary.steps,
        activeSeconds = summary.activeSeconds.toLong(),
        movingSeconds = summary.movingSeconds.toLong(),
        pausedSeconds = summary.pausedSeconds.toLong(),
        ascentMeters = summary.ascentMeters,
        descentMeters = summary.descentMeters,
        profile = summary.profile,
    )

    fun syncLabel(status: SyncStatus): SyncLabel = when (status) {
        SyncStatus.Synced -> SyncLabel.SYNCED
        is SyncStatus.Pending -> SyncLabel.PENDING
        SyncStatus.Offline -> SyncLabel.OFFLINE
        SyncStatus.Blocked -> SyncLabel.BLOCKED
        SyncStatus.NeedsLink -> SyncLabel.NEEDS_LINK
        SyncStatus.Syncing -> SyncLabel.SYNCING
    }
}
