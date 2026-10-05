package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Test

class StepCounterNormalizerTest {
    private fun feed(vararg readings: Pair<Long, Long?>): Pair<StepCounterState, List<Int>> {
        var state = StepCounterNormalizer.initial("S")
        val out = mutableListOf<Int>()
        for ((raw, boot) in readings) {
            val r = StepCounterNormalizer.onReading(state, raw, boot)
            state = r.state
            out += r.steps
        }
        return state to out
    }

    @Test
    fun firstReadingIsBaseline() {
        val (state, steps) = feed(5000L to 1L, 5010L to 1L, 5250L to 1L)
        assertEquals(listOf(0, 10, 250), steps)
        assertEquals(5000L, state.baseline)
    }

    @Test
    fun rebootDetectedByCounterGoingDown() {
        // 300 pasos antes del reinicio, luego el contador vuelve a empezar desde 0.
        val (state, steps) = feed(1000L to null, 1300L to null, 40L to null, 100L to null)
        assertEquals(listOf(0, 300, 340, 400), steps)
        assertEquals(300L, state.offset)
        assertEquals(0L, state.baseline)
    }

    @Test
    fun rebootDetectedByBootIdEvenIfCounterIsHigher() {
        // Tras reiniciar se anduvo mucho antes de que la app volviera: 2000 > 1300.
        val (_, steps) = feed(1000L to 1L, 1300L to 1L, 2000L to 2L)
        assertEquals(listOf(0, 300, 2300), steps)
    }

    @Test
    fun twoReboots() {
        val (state, steps) = feed(500L to 1L, 600L to 1L, 50L to 2L, 80L to 2L, 10L to 3L)
        assertEquals(listOf(0, 100, 150, 180, 190), steps)
        assertEquals(180L, state.offset)
    }

    @Test
    fun processRestartWithoutRebootContinues() {
        val (persisted, _) = feed(1000L to 1L, 1100L to 1L)
        // Proceso muerto y relanzado (estado restaurado desde disco), mismo arranque.
        val r = StepCounterNormalizer.onReading(persisted, 1500L, 1L)
        assertEquals(500, r.steps)
    }

    @Test
    fun stepsNeverNegative() {
        val r = StepCounterNormalizer.onReading(StepCounterNormalizer.initial("S"), -5, null)
        assertEquals(0, r.steps)
    }
}
