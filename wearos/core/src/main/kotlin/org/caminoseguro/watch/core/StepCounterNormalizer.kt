package org.caminoseguro.watch.core

import kotlinx.serialization.Serializable
import kotlin.math.max

/**
 * Estado persistido para normalizar `Sensor.TYPE_STEP_COUNTER` (acumulado desde el arranque del
 * reloj) a "pasos desde `startedAt`" — §4.
 *
 * @property bootId identificador del arranque (en Android, `Settings.Global.BOOT_COUNT`); null si
 *   no se conoce. Detecta reinicios aunque el contador nuevo ya supere al anterior.
 * @property baseline lectura bruta que equivale a "0 pasos" en el arranque actual.
 * @property offset pasos acumulados en arranques anteriores durante esta sesión.
 * @property lastRaw última lectura bruta vista en el arranque actual.
 */
@Serializable
data class StepCounterState(
    val sessionId: String,
    val bootId: Long? = null,
    val baseline: Long? = null,
    val offset: Long = 0,
    val lastRaw: Long? = null,
)

/** Lógica pura de baseline/offset del contador de pasos de Wear OS. */
object StepCounterNormalizer {

    fun initial(sessionId: String): StepCounterState = StepCounterState(sessionId = sessionId)

    data class Reading(val state: StepCounterState, val steps: Int)

    fun onReading(state: StepCounterState, raw: Long, bootId: Long?): Reading {
        val value = max(0L, raw)
        val baseline = state.baseline
        val lastRaw = state.lastRaw
        if (baseline == null || lastRaw == null) {
            // Primera lectura de la sesión: es el "cero".
            val next = state.copy(baseline = value, lastRaw = value, bootId = bootId)
            return Reading(next, toSteps(next.offset))
        }
        val bootChanged = bootId != null && state.bootId != null && bootId != state.bootId
        val counterWentDown = value < lastRaw
        val next = if (bootChanged || counterWentDown) {
            // Reinicio del reloj: lo contado antes del reinicio pasa al offset y el contador
            // nuevo empezó en 0 al arrancar.
            state.copy(
                offset = state.offset + max(0L, lastRaw - baseline),
                baseline = 0L,
                lastRaw = value,
                bootId = bootId ?: state.bootId,
            )
        } else {
            state.copy(lastRaw = value, bootId = bootId ?: state.bootId)
        }
        return Reading(next, toSteps(next.offset + (value - (next.baseline ?: 0L))))
    }

    private fun toSteps(n: Long): Int = n.coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
}
