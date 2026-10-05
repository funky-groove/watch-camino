package org.caminoseguro.watch.ui

import org.caminoseguro.watch.core.CaminoStats
import org.caminoseguro.watch.core.DayFigures
import org.caminoseguro.watch.core.LocationFix
import org.caminoseguro.watch.core.Poi
import org.caminoseguro.watch.core.PoiAlertEngine
import org.caminoseguro.watch.core.PoiDistance
import org.caminoseguro.watch.core.SessionSnapshot
import org.caminoseguro.watch.core.SessionSummary
import org.caminoseguro.watch.core.Stage
import org.caminoseguro.watch.core.StageMachine
import org.caminoseguro.watch.core.SyncStatus
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
)

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
    val activeSeconds: Long,
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
    ): ActiveStageUi? {
        val session = snapshot.activeSession ?: return null
        val stage = stages.firstOrNull { it.id == session.stageId }
        val remaining = if (stage != null) CaminoStats.remainingMeters(stage, session) else 0.0
        val next = latestFix?.let { PoiAlertEngine.nearestUnalerted(pois, session.alertedPoiIds, it.point) }
        return ActiveStageUi(
            stageId = session.stageId,
            stageName = stage?.name ?: session.stageId,
            remainingMeters = remaining,
            walkedMeters = session.distanceMeters,
            steps = session.steps,
            elapsedSeconds = StageMachine.activeSeconds(session.startedAt, now).toLong(),
            nextPoi = next,
            hasFix = latestFix != null,
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
