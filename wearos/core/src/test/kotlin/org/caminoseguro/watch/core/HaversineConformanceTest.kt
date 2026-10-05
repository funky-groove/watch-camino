package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HaversineConformanceTest {
    private val data = Shared.conformance("haversine.json")
    private val tol = data["tolerance_m"]!!.d

    @Test
    fun allCases() {
        val cases = data["cases"]!!.arr
        assertTrue(cases.isNotEmpty())
        for ((idx, c) in cases.withIndex()) {
            val got = Geo.haversineMeters(c.obj["a"]!!.point(), c.obj["b"]!!.point())
            assertEquals("caso $idx", c.obj["meters"]!!.d, got, tol)
        }
    }

    @Test
    fun radiusIsSpecValue() {
        assertEquals(6_371_008.8, Geo.EARTH_RADIUS_M, 0.0)
    }
}
