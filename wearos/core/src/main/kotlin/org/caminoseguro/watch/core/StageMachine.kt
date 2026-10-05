package org.caminoseguro.watch.core

import java.time.Duration
import java.time.Instant
import kotlin.math.max
import kotlin.math.roundToInt

@Suppress("EnumEntryName")
enum class SessionError { alreadyActive, unknownStage, notActive, alreadyPaused, notPaused }

/**
 * Resultado de aplicar un comando. Si [error] no es null, [snapshot] es el de entrada sin cambios
 * y [events] está vacío.
 */
data class Transition(
    val snapshot: SessionSnapshot,
    val events: List<SyncEvent> = emptyList(),
    val error: SessionError? = null,
    val alert: PoiAlert? = null,
    val summary: SessionSummary? = null,
) {
    val changed: Boolean get() = error == null
}

/** Máquina de estados de la etapa — §4. Pura: no persiste ni envía; devuelve eventos a encolar. */
class StageMachine(private val ids: IdGenerator) {

    fun start(
        current: SessionSnapshot,
        stageId: String,
        sessionId: String,
        now: Instant,
        knownStageIds: Set<String>,
    ): Transition {
        if (current.state is SessionState.Active) return Transition(current, error = SessionError.alreadyActive)
        if (stageId !in knownStageIds) return Transition(current, error = SessionError.unknownStage)
        val session = StageSession(sessionId = sessionId, stageId = stageId, startedAt = now)
        val event = SyncEvent(
            eventId = ids.newId(),
            type = SyncEventType.StageStarted,
            sessionId = sessionId,
            occurredAt = now,
            payload = SyncPayload.StageStarted(stageId = stageId, startedAt = now),
        )
        return Transition(current.copy(state = SessionState.Active(session)), events = listOf(event))
    }

    fun updateSteps(current: SessionSnapshot, steps: Int): Transition {
        val session = current.activeSession ?: return Transition(current, error = SessionError.notActive)
        if (steps <= session.steps) return Transition(current) // los pasos nunca bajan
        return Transition(current.copy(state = SessionState.Active(session.copy(steps = steps))))
    }

    /**
     * §5 + §6 + V1.1 §C–F. [now] es el instante para el límite de ritmo de avisos; [pois] los de la
     * etapa activa. En pausa sólo se evalúan los avisos POI (ninguna métrica cambia).
     */
    fun updateLocation(current: SessionSnapshot, fix: LocationFix, now: Instant, pois: List<Poi>): Transition {
        val session = current.activeSession ?: return Transition(current, error = SessionError.notActive)
        if (!DistanceAccumulator.isAccurateEnough(fix)) return Transition(current)

        var next = TripMetrics.applyFix(session, fix)

        val stagePois = pois.filter { it.stageId == session.stageId }
        val alert = PoiAlertEngine.evaluate(
            pois = stagePois,
            alreadyAlerted = next.alertedPoiIds,
            lastAlertAt = next.lastAlertAt,
            now = now,
            position = fix.point,
            accuracyMeters = fix.accuracyMeters,
        )
        if (alert != null) {
            next = next.copy(alertedPoiIds = next.alertedPoiIds + alert.poi.id, lastAlertAt = now)
        }
        return Transition(current.copy(state = SessionState.Active(next)), alert = alert)
    }

    /** V1.1 §C: → Pausado. Errores `notActive`, `alreadyPaused`. */
    fun pause(current: SessionSnapshot, now: Instant): Transition {
        val session = current.activeSession ?: return Transition(current, error = SessionError.notActive)
        val next = TripMetrics.pause(session, now) ?: return Transition(current, error = SessionError.alreadyPaused)
        return Transition(current.copy(state = SessionState.Active(next)))
    }

    /** V1.1 §C: → En marcha. Errores `notActive`, `notPaused`. */
    fun resume(current: SessionSnapshot, now: Instant): Transition {
        val session = current.activeSession ?: return Transition(current, error = SessionError.notActive)
        val next = TripMetrics.resume(session, now) ?: return Transition(current, error = SessionError.notPaused)
        return Transition(current.copy(state = SessionState.Active(next)))
    }

    fun finish(current: SessionSnapshot, now: Instant): Transition {
        val session = current.activeSession ?: return Transition(current, error = SessionError.notActive)
        val summary = summarize(session, now)
        val event = SyncEvent(
            eventId = ids.newId(),
            type = SyncEventType.StageFinished,
            sessionId = session.sessionId,
            occurredAt = now,
            payload = SyncPayload.StageFinished(
                stageId = summary.stageId,
                startedAt = summary.startedAt,
                finishedAt = summary.finishedAt,
                steps = summary.steps,
                distanceMeters = summary.distanceMeters,
                activeSeconds = summary.activeSeconds,
                movingSeconds = summary.movingSeconds,
                pausedSeconds = summary.pausedSeconds,
                ascentMeters = summary.ascentMeters,
                descentMeters = summary.descentMeters,
            ),
        )
        return Transition(
            snapshot = SessionSnapshot(state = SessionState.Idle, history = listOf(summary) + current.history),
            events = listOf(event),
            summary = summary,
        )
    }

    companion object {
        /** `activeSeconds = max(0, floor(finishedAt − startedAt))`. */
        fun activeSeconds(startedAt: Instant, until: Instant): Int {
            // Duration.getSeconds() es floor (los nanos siempre son positivos).
            val s = Duration.between(startedAt, until).seconds
            return max(0L, s).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        }

        /** Cierra la pausa en curso (si la hay) y resume. Enteros V1.1 con redondeo half-up. */
        fun summarize(session: StageSession, finishedAt: Instant): SessionSummary {
            val closed = TripMetrics.closePause(session, finishedAt)
            val active = activeSeconds(session.startedAt, finishedAt)
            return SessionSummary(
                sessionId = closed.sessionId,
                stageId = closed.stageId,
                startedAt = closed.startedAt,
                finishedAt = finishedAt,
                steps = max(0, closed.steps),
                distanceMeters = max(0.0, closed.distanceMeters).roundToInt(),
                activeSeconds = active,
                // §D: tiempo en movimiento ≤ duración (también si el reloj ha ido hacia atrás).
                movingSeconds = halfUp(closed.movingSeconds).coerceAtMost(active),
                pausedSeconds = halfUp(closed.pausedSeconds),
                ascentMeters = halfUp(closed.ascentMeters),
                descentMeters = halfUp(closed.descentMeters),
                profile = closed.profile,
            )
        }
    }
}
