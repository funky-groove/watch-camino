package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Test

class BackoffConformanceTest {
    private val data = Shared.conformance("backoff.json")

    @Test
    fun allCases() {
        val jitter = data["jitter"]!!.d
        val cases = data["cases"]!!.arr
        assertEquals(9, cases.size)
        for (c in cases) {
            val attempt = c.obj["attempt"]!!.i
            val seconds = c.obj["seconds"]!!.i.toLong()
            assertEquals("attempt $attempt", seconds, Backoff.baseSeconds(attempt))
            assertEquals("attempt $attempt", seconds * 1000, Backoff.delayMillis(attempt, jitter))
        }
    }

    @Test
    fun jitterBoundsAndHugeAttempts() {
        assertEquals(36_000L, Backoff.delayMillis(1, 0.2))
        assertEquals(36_000L, Backoff.delayMillis(1, 5.0)) // se recorta a 20 %
        assertEquals(30_000L, Backoff.delayMillis(1, -1.0))
        assertEquals(1800L, Backoff.baseSeconds(1_000))
    }
}
