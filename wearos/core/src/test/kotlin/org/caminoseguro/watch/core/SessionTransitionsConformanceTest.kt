package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionTransitionsConformanceTest {
    private val data = Shared.conformance("session_transitions.json")
    private val known = data["knownStageIds"]!!.arr.map { it.s }.toSet()

    @Test
    fun allCases() {
        val cases = data["cases"]!!.arr
        assertEquals(6, cases.size)
        for (c in cases) {
            val caseName = c.obj["name"]!!.s
            val machine = StageMachine(SequentialIdGenerator("ev-"))
            var snap = SessionSnapshot()
            val queued = mutableListOf<SyncEvent>()
            for ((i, step) in c.obj["steps"]!!.arr.withIndex()) {
                val o = step.obj
                val label = "$caseName#$i ${o["op"]!!.s}"
                val t = when (o["op"]!!.s) {
                    "start" -> machine.start(snap, o["stageId"]!!.s, o["sessionId"]!!.s, epoch(o["t"]!!.d), known)
                    "updateSteps" -> machine.updateSteps(snap, o["n"]!!.i)
                    "finish" -> machine.finish(snap, epoch(o["t"]!!.d))
                    else -> error("op desconocida")
                }
                snap = t.snapshot
                queued += t.events
                val e = o["expect"]!!.obj

                val state = if (snap.state is SessionState.Active) "active" else "idle"
                assertEquals(label, e["state"]!!.s, state)
                val expError = e["error"]
                assertEquals(label, if (expError.isNull) null else expError!!.s, t.error?.name)
                assertEquals(label, e["history"]!!.i, snap.history.size)
                assertEquals(label, e["queued"]!!.arr.map { it.s }, queued.map { it.type.wireName })
                e["steps"]?.let { assertEquals(label, it.i, snap.activeSession!!.steps) }
                e["activeSeconds"]?.let { assertEquals(label, it.i, snap.history.first().activeSeconds) }
                e["summarySteps"]?.let { assertEquals(label, it.i, snap.history.first().steps) }
            }
        }
    }

    @Test
    fun idleUpdatesAreNotActive() {
        val machine = StageMachine(SequentialIdGenerator())
        val idle = SessionSnapshot()
        assertEquals(SessionError.notActive, machine.updateSteps(idle, 5).error)
        val fix = LocationFix(GeoPoint(0.0, 0.0), 5.0, epoch(0.0))
        assertEquals(SessionError.notActive, machine.updateLocation(idle, fix, epoch(0.0), emptyList()).error)
    }

    @Test
    fun eventsCarryAggregatesOnly() {
        val machine = StageMachine(SequentialIdGenerator("ev-"))
        var snap = machine.start(SessionSnapshot(), "a", "S1", epoch(100.0), setOf("a")).snapshot
        snap = machine.updateSteps(snap, 500).snapshot
        snap = machine.updateLocation(snap, LocationFix(GeoPoint(42.7808, -7.4141), 5.0, epoch(110.0)), epoch(110.0), emptyList()).snapshot
        snap = machine.updateLocation(snap, LocationFix(GeoPoint(42.7812497, -7.4141), 5.0, epoch(140.0)), epoch(140.0), emptyList()).snapshot
        val t = machine.finish(snap, epoch(400.5))
        val ev = t.events.single()
        val p = ev.payload as SyncPayload.StageFinished
        assertEquals(SyncEventType.StageFinished, ev.type)
        assertEquals("S1", ev.sessionId)
        assertEquals(500, p.steps)
        assertEquals(50, p.distanceMeters)
        assertEquals(300, p.activeSeconds)
        val json = CaminoJson.encodeEvent(ev)
        assertTrue(json, !json.contains("lat") && !json.contains("lon") && !json.contains("lastFix"))
        assertTrue(json.contains("\"type\":\"stage_finished\""))
    }
}
