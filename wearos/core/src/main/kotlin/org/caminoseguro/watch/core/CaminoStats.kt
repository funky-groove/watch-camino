package org.caminoseguro.watch.core

import java.time.Instant
import kotlin.math.max

/** Agregados de la pantalla Estadísticas — §10.4. */
data class Totals(
    val stages: Int,
    val distanceMeters: Double,
    val steps: Long,
    val activeSeconds: Long,
)

/** Cifras de "hoy": la sesión activa o, si no hay, la última terminada. */
data class DayFigures(
    val stageId: String,
    val isActive: Boolean,
    val distanceMeters: Double,
    val steps: Int,
    val activeSeconds: Long,
)

object CaminoStats {

    /** Acumulado del Camino: suma de History. */
    fun totals(history: List<SessionSummary>): Totals = Totals(
        stages = history.size,
        distanceMeters = history.sumOf { it.distanceMeters.toDouble() },
        steps = history.sumOf { it.steps.toLong() },
        activeSeconds = history.sumOf { it.activeSeconds.toLong() },
    )

    fun today(snapshot: SessionSnapshot, now: Instant): DayFigures? {
        snapshot.activeSession?.let {
            return DayFigures(
                stageId = it.stageId,
                isActive = true,
                distanceMeters = it.distanceMeters,
                steps = it.steps,
                activeSeconds = StageMachine.activeSeconds(it.startedAt, now).toLong(),
            )
        }
        val last = snapshot.history.firstOrNull() ?: return null
        return DayFigures(last.stageId, false, last.distanceMeters.toDouble(), last.steps, last.activeSeconds.toLong())
    }

    /** km restantes: `max(0, distanceMeters_plan − recorridos)`. */
    fun remainingMeters(stage: Stage, session: StageSession): Double =
        max(0.0, stage.distanceMeters - session.distanceMeters)

    /**
     * Orden para "Elegir etapa": la primera es la sugerida (la siguiente a la última terminada,
     * según el orden del catálogo); el resto, en orden de catálogo. Sin historial o si la última
     * terminada es la final del catálogo, se sugiere la primera del catálogo.
     */
    fun stagesWithSuggestionFirst(stages: List<Stage>, history: List<SessionSummary>): List<Stage> {
        val suggested = suggestedStage(stages, history) ?: return stages
        return listOf(suggested) + stages.filter { it.id != suggested.id }
    }

    fun suggestedStage(stages: List<Stage>, history: List<SessionSummary>): Stage? {
        if (stages.isEmpty()) return null
        val lastId = history.firstOrNull()?.stageId ?: return stages.first()
        val idx = stages.indexOfFirst { it.id == lastId }
        return if (idx >= 0 && idx + 1 < stages.size) stages[idx + 1] else stages.first()
    }
}
