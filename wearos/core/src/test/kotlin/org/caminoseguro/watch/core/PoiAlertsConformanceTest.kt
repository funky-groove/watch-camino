package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PoiAlertsConformanceTest {
    private val data = Shared.conformance("poi_alerts.json")

    @Test
    fun constantsMatch() {
        assertEquals(data["radius_m"]!!.d, PoiAlertEngine.RADIUS_M, 0.0)
        assertEquals(data["min_interval_s"]!!.d, PoiAlertEngine.MIN_INTERVAL_S, 0.0)
    }

    @Test
    fun allCases() {
        val cases = data["cases"]!!.arr
        assertEquals(11, cases.size)
        for (c in cases) {
            val o = c.obj
            val name = o["name"]!!.s
            val pois = o["pois"]!!.arr.map { it.poi() }
            val alerted = o["alreadyAlerted"]!!.arr.map { it.s }.toSet()
            val lastAlertAt = o["lastAlertAt"].let { if (it.isNull) null else epoch(it!!.d) }
            val now = epoch(o["now"]!!.d)
            val pos = o["position"]!!
            val got = PoiAlertEngine.evaluate(pois, alerted, lastAlertAt, now, pos.point(), pos.obj["acc"]!!.d)
            val expected = o["expected"]
            if (expected.isNull) assertNull(name, got) else assertEquals(name, expected!!.s, got?.poi?.id)
        }
    }

    @Test
    fun allCasesThroughStateMachine() {
        // Mismo resultado vía StageMachine: alerta, alertedPoiIds y lastAlertAt actualizados.
        val machine = StageMachine(SequentialIdGenerator())
        for (c in data["cases"]!!.arr) {
            val o = c.obj
            val name = o["name"]!!.s
            val pois = o["pois"]!!.arr.map { it.poi() }
            val alerted = o["alreadyAlerted"]!!.arr.map { it.s }.toSet()
            val lastAlertAt = o["lastAlertAt"].let { if (it.isNull) null else epoch(it!!.d) }
            val now = epoch(o["now"]!!.d)
            val pos = o["position"]!!
            val session = StageSession("S", "s", epoch(0.0), alertedPoiIds = alerted, lastAlertAt = lastAlertAt)
            val snap = SessionSnapshot(SessionState.Active(session))
            val fix = LocationFix(pos.point(), pos.obj["acc"]!!.d, now)
            val t = machine.updateLocation(snap, fix, now, pois)
            val expected = o["expected"]
            if (expected.isNull) {
                assertNull(name, t.alert)
                assertEquals(name, alerted, t.snapshot.activeSession!!.alertedPoiIds)
                assertEquals(name, lastAlertAt, t.snapshot.activeSession!!.lastAlertAt)
            } else {
                assertEquals(name, expected!!.s, t.alert?.poi?.id)
                assertEquals(name, alerted + expected.s, t.snapshot.activeSession!!.alertedPoiIds)
                assertEquals(name, now, t.snapshot.activeSession!!.lastAlertAt)
            }
        }
    }

    @Test
    fun onlyPoisOfActiveStage() {
        val machine = StageMachine(SequentialIdGenerator())
        val here = GeoPoint(42.7808, -7.4141)
        val other = Poi("x", "otra-etapa", "x", PoiCategory.water, here)
        val snap = SessionSnapshot(SessionState.Active(StageSession("S", "s", epoch(0.0))))
        val t = machine.updateLocation(snap, LocationFix(here, 5.0, epoch(10.0)), epoch(10.0), listOf(other))
        assertNull(t.alert)
    }
}
