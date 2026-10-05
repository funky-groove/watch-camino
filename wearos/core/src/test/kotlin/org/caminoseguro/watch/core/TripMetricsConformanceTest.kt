package org.caminoseguro.watch.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** V1.1 §C–F: `shared/conformance/trip_metrics.json` (reference.py::trip_metrics). */
class TripMetricsConformanceTest {
    private val data = Shared.conformance("trip_metrics.json")
    private val tol = data["tolerance"]!!.d
    private val cases = data["cases"]!!.arr

    private fun fixOf(e: JsonElement): LocationFix = LocationFix(
        point = e.point(),
        accuracyMeters = e.obj["acc"]!!.d,
        timestamp = epoch(e.obj["t"]!!.d),
        altitudeMeters = e.obj["alt"]?.d,
        verticalAccuracyMeters = e.obj["vacc"]?.d,
    )

    private fun newSession() = StageSession(sessionId = "S", stageId = "s", startedAt = epoch(0.0))

    private fun check(name: String, expected: JsonElement, s: StageSession, ignored: List<Int>) {
        val e = expected.obj
        assertEquals("$name distance", e["distance_m"]!!.d, s.distanceMeters, tol)
        assertEquals("$name moving", e["moving_s"]!!.d, s.movingSeconds, tol)
        assertEquals("$name paused", e["paused"]!!.jsonPrimitive.boolean, s.isPaused)
        assertEquals("$name paused_s", e["paused_s"]!!.d, s.pausedSeconds, tol)
        assertEquals("$name ascent", e["ascent_m"]!!.d, s.ascentMeters, tol)
        assertEquals("$name descent", e["descent_m"]!!.d, s.descentMeters, tol)
        if (e["altitude_m"].isNull) {
            assertNull(name, s.altitude)
            assertNull(name, s.altitudeAt)
        } else {
            assertEquals("$name altitude", e["altitude_m"]!!.d, s.altitude!!, tol)
            assertEquals("$name altitudeAt", epoch(e["altitude_t"]!!.d), s.altitudeAt)
        }
        val profile = e["profile"]!!.arr
        assertEquals("$name profile size", profile.size, s.profile.size)
        for ((k, p) in profile.withIndex()) {
            val got = s.profile[k]
            assertEquals("$name profile[$k].d", p.obj["d"]!!.d, got.d, tol)
            assertEquals("$name profile[$k].alt", p.obj["alt"]!!.d, got.alt, tol)
            assertEquals("$name profile[$k].gap", p.obj["gapBefore"]!!.jsonPrimitive.boolean, got.gapBefore)
        }
        assertEquals("$name ignored", e["ignored_events"]!!.arr.map { it.i }, ignored)
    }

    @Test
    fun allCasesPure() {
        assertEquals(10, cases.size)
        for (c in cases) {
            val name = c.obj["name"]!!.s
            val cap = c.obj["profileCap"]!!.i
            var s = newSession()
            val ignored = mutableListOf<Int>()
            for ((i, ev) in c.obj["events"]!!.arr.withIndex()) {
                val t = epoch(ev.obj["t"]!!.d)
                when (ev.obj["type"]!!.s) {
                    "pause" -> TripMetrics.pause(s, t)?.let { s = it } ?: ignored.add(i)
                    "resume" -> TripMetrics.resume(s, t)?.let { s = it } ?: ignored.add(i)
                    "fix" -> s = TripMetrics.applyFix(s, fixOf(ev), profileCap = cap)
                    else -> error("evento desconocido")
                }
            }
            check(name, c.obj["expected"]!!, s, ignored)
        }
    }

    @Test
    fun sameResultsThroughStateMachine() {
        val machine = StageMachine(SequentialIdGenerator())
        var checked = 0
        for (c in cases) {
            if (c.obj["profileCap"]!!.i != TripMetrics.PROFILE_CAP) continue
            val name = c.obj["name"]!!.s
            var snap = machine.start(SessionSnapshot(), "s", "S", epoch(0.0), setOf("s")).snapshot
            val ignored = mutableListOf<Int>()
            for ((i, ev) in c.obj["events"]!!.arr.withIndex()) {
                val t = epoch(ev.obj["t"]!!.d)
                val tr = when (ev.obj["type"]!!.s) {
                    "pause" -> machine.pause(snap, t)
                    "resume" -> machine.resume(snap, t)
                    else -> machine.updateLocation(snap, fixOf(ev), t, emptyList())
                }
                when (tr.error) {
                    null -> Unit
                    SessionError.alreadyPaused, SessionError.notPaused -> ignored.add(i)
                    else -> error("$name: ${tr.error}")
                }
                snap = tr.snapshot
            }
            check(name, c.obj["expected"]!!, snap.activeSession!!, ignored)
            checked++
        }
        assertEquals(9, checked)
    }
}
