package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

class DistanceAccumulatorConformanceTest {
    private val data = Shared.conformance("distance_accumulator.json")
    private val tol = data["tolerance_m"]!!.d

    @Test
    fun allCases() {
        val cases = data["cases"]!!.arr
        assertEquals(10, cases.size)
        for (c in cases) {
            val name = c.obj["name"]!!.s
            val fixes = c.obj["fixes"]!!.arr.map {
                LocationFix(it.point(), it.obj["acc"]!!.d, epoch(it.obj["t"]!!.d))
            }
            var distance = 0.0
            var last: LocationFix? = null
            for (f in fixes) {
                val r = DistanceAccumulator.apply(distance, last, f)
                distance = r.distanceMeters
                last = r.lastFix
            }
            assertEquals(name, c.obj["distance_m"]!!.d, distance, tol)
            val idx = c.obj["last_fix_index"]
            if (idx.isNull) assertNull(name, last) else assertSame(name, fixes[idx!!.i], last)
        }
    }

    @Test
    fun sameRulesThroughStateMachine() {
        // El acumulador aplicado vía StageMachine.updateLocation produce lo mismo.
        val machine = StageMachine(SequentialIdGenerator())
        for (c in data["cases"]!!.arr) {
            var snap = machine.start(SessionSnapshot(), "s", "S", epoch(0.0), setOf("s")).snapshot
            for (it in c.obj["fixes"]!!.arr) {
                val fix = LocationFix(it.point(), it.obj["acc"]!!.d, epoch(it.obj["t"]!!.d))
                snap = machine.updateLocation(snap, fix, fix.timestamp, emptyList()).snapshot
            }
            assertEquals(c.obj["name"]!!.s, c.obj["distance_m"]!!.d, snap.activeSession!!.distanceMeters, tol)
        }
    }
}
