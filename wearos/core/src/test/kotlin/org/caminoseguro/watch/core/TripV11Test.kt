package org.caminoseguro.watch.core

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/** V1.1: pausa (§C), resumen/payload, compatibilidad con estado V1 y teléfono de POI (§J). */
@OptIn(ExperimentalCoroutinesApi::class)
class TripV11Test {
    private val machine = StageMachine(SequentialIdGenerator())
    private val origin = GeoPoint(42.7808, -7.4141)
    private fun north(m: Double) = GeoPoint(origin.lat + m / Geo.EARTH_RADIUS_M * 180 / Math.PI, origin.lon)

    private fun started(t: Double = 0.0) =
        machine.start(SessionSnapshot(), "s", "S", epoch(t), setOf("s")).snapshot

    @Test
    fun pauseAndResumeErrors() {
        val idle = SessionSnapshot()
        assertEquals(SessionError.notActive, machine.pause(idle, epoch(0.0)).error)
        assertEquals(SessionError.notActive, machine.resume(idle, epoch(0.0)).error)

        val active = started()
        assertEquals(SessionError.notPaused, machine.resume(active, epoch(5.0)).error)
        val paused = machine.pause(active, epoch(10.0))
        assertNull(paused.error)
        assertTrue(paused.events.isEmpty())
        assertTrue(paused.snapshot.activeSession!!.isPaused)
        val again = machine.pause(paused.snapshot, epoch(20.0))
        assertEquals(SessionError.alreadyPaused, again.error)
        assertEquals(paused.snapshot, again.snapshot)
        val resumed = machine.resume(paused.snapshot, epoch(70.0)).snapshot.activeSession!!
        assertFalse(resumed.isPaused)
        assertEquals(60.0, resumed.pausedSeconds, 1e-9)
        // Reloj hacia atrás: no resta.
        val back = machine.resume(machine.pause(started(), epoch(100.0)).snapshot, epoch(50.0)).snapshot
        assertEquals(0.0, back.activeSession!!.pausedSeconds, 1e-9)
    }

    @Test
    fun pauseClearsAnchorAndOnlyEvaluatesPoiAlerts() {
        var snap = started()
        snap = machine.updateLocation(snap, LocationFix(origin, 5.0, epoch(0.0), 500.0, 5.0), epoch(0.0), emptyList()).snapshot
        snap = machine.pause(snap, epoch(5.0)).snapshot
        assertNull(snap.activeSession!!.lastFix)
        val poi = Poi("p", "s", "Fuente", PoiCategory.water, north(150.0))
        val t = machine.updateLocation(snap, LocationFix(north(100.0), 5.0, epoch(60.0), 520.0, 5.0), epoch(60.0), listOf(poi))
        assertEquals("p", t.alert?.poi?.id)
        val s = t.snapshot.activeSession!!
        assertEquals(0.0, s.distanceMeters, 0.0)
        assertEquals(0.0, s.movingSeconds, 0.0)
        assertNull(s.lastFix)
        assertEquals(500.0, s.altitude!!, 0.0)
        assertEquals(1, s.profile.size)
        assertEquals(setOf("p"), s.alertedPoiIds)
    }

    @Test
    fun finishWhilePausedClosesPauseAndReportsIntegers() {
        var snap = started(0.0)
        var t = 0.0
        for (k in 0..10) {
            val fix = LocationFix(north(14.0 * k), 5.0, epoch(t), 400.0 + 2.0 * k, 5.0)
            snap = machine.updateLocation(snap, fix, epoch(t), emptyList()).snapshot
            t += 10
        }
        snap = machine.pause(snap, epoch(100.0)).snapshot
        val fin = machine.finish(snap, epoch(400.5))
        val sum = fin.summary!!
        assertEquals(400, sum.activeSeconds)
        assertEquals(100, sum.movingSeconds)
        assertEquals(301, sum.pausedSeconds) // 300,5 → half-up
        assertEquals(20, sum.ascentMeters)
        assertEquals(0, sum.descentMeters)
        assertEquals(140, sum.distanceMeters)
        assertTrue(sum.profile.isNotEmpty())
        val payload = fin.events.single().payload as SyncPayload.StageFinished
        assertEquals(listOf(100, 301, 20, 0), listOf(payload.movingSeconds, payload.pausedSeconds, payload.ascentMeters, payload.descentMeters))
        // El payload nunca lleva perfil ni posiciones.
        val wire = CaminoJson.encodeEvent(fin.events.single())
        assertFalse(wire.contains("profile"))
        assertFalse(wire.contains("lat"))
        assertTrue(wire.contains("\"movingSeconds\":100"))
    }

    @Test
    fun readsV1State() {
        val v1 = """{"state":{"type":"active","session":{"sessionId":"S","stageId":"cf","startedAt":"1970-01-01T00:16:40Z",
            "steps":12,"distanceMeters":34.5,"lastFix":{"point":{"lat":42.78,"lon":-7.41},"accuracyMeters":5.0,
            "timestamp":"1970-01-01T00:17:00Z"},"alertedPoiIds":["p01"],"lastAlertAt":null}},
            "history":[{"sessionId":"old","stageId":"x","startedAt":"1970-01-01T00:00:01Z","finishedAt":"1970-01-01T00:00:02Z",
            "steps":10,"distanceMeters":20,"activeSeconds":1}]}"""
        val snap = CaminoJson.decodeSession(v1)
        val s = snap.activeSession!!
        assertFalse(s.isPaused)
        assertEquals(0.0, s.movingSeconds, 0.0)
        assertNull(s.altitude)
        assertNull(s.lastFix!!.altitudeMeters)
        assertTrue(s.profile.isEmpty())
        assertEquals(TripMetrics.PROFILE_SPACING_M, s.profileSpacing, 0.0)
        assertEquals(0, snap.history.single().movingSeconds)
        assertEquals(snap, CaminoJson.decodeSession(CaminoJson.encodeSession(snap)))

        val v1Queue = """{"queue":[{"eventId":"e","type":"stage_finished","sessionId":"S","occurredAt":"1970-01-01T00:00:50Z",
            "payload":{"type":"stage_finished","stageId":"s","startedAt":"1970-01-01T00:00:00Z","finishedAt":"1970-01-01T00:00:50Z",
            "steps":1,"distanceMeters":2,"activeSeconds":50}}]}"""
        val p = CaminoJson.decodeSyncQueue(v1Queue).queue.single().payload as SyncPayload.StageFinished
        assertEquals(0, p.movingSeconds)

        val poi = CaminoJson.json.decodeFromString(
            Poi.serializer(),
            """{"id":"a","stageId":"s","name":"n","category":"water","location":{"lat":1.0,"lon":2.0}}""",
        )
        assertNull(poi.phone)
        assertNull(poi.telUri())
    }

    @Test
    fun v11StateRoundTrip() {
        var snap = started()
        snap = machine.updateLocation(snap, LocationFix(origin, 5.0, epoch(0.0), 500.0, 5.0), epoch(0.0), emptyList()).snapshot
        snap = machine.pause(snap, epoch(9.5)).snapshot
        assertEquals(snap, CaminoJson.decodeSession(CaminoJson.encodeSession(snap)))
    }

    @Test
    fun altitudeStaleAfter300s() {
        var snap = started()
        snap = machine.updateLocation(snap, LocationFix(origin, 5.0, epoch(0.0), 500.0, 5.0), epoch(0.0), emptyList()).snapshot
        val s = snap.activeSession!!
        assertFalse(s.isAltitudeStale(epoch(300.0)))
        assertTrue(s.isAltitudeStale(epoch(300.5)))
        assertTrue(started().activeSession!!.isAltitudeStale(epoch(0.0)))
    }

    @Test
    fun phoneNumbers() {
        for (ok in listOf("+34600111222", "+34 600 11 12 22", "600111222", "981 23 45 67", "712345678", "+12025550123", "+12345678")) {
            assertTrue(ok, PhoneNumber.isValid(ok))
        }
        for (bad in listOf(null, "", "112", "062", "091", "+112", "500111222", "60011122", "6001112223", "+1234567",
            "+1234567890123456", "tel:600111222", "600-11a-222", "0034600111222")) {
            assertFalse(bad.toString(), PhoneNumber.isValid(bad))
        }
        assertEquals("tel:+34600111222", PhoneNumber.telUri("600 111 222"))
        assertEquals("tel:+34600111222", PhoneNumber.telUri("+34 (600) 111-222"))
        assertNull(PhoneNumber.telUri("112"))
        val poi = Poi("a", "s", "n", PoiCategory.shelter, origin, phone = "982 000 000")
        assertEquals("tel:+34982000000", poi.telUri())
    }

    // ------------------------------------------------------------ controlador

    private class FlakyStore(var failing: Boolean = false) : SessionStore {
        val inner = InMemorySessionStore()
        override suspend fun load(): SessionSnapshot = inner.load()
        override suspend fun save(snapshot: SessionSnapshot) {
            if (failing) throw IOException("ENOSPC")
            inner.save(snapshot)
        }
    }

    private fun controller(scope: TestScope, store: SessionStore, clock: MutableClock) = CaminoController(
        catalog = FixtureStageCatalog(Shared.fixture("stages.json")),
        poiSource = FixturePoiSource(Shared.fixture("pois.json")),
        sessionStore = store,
        sync = SyncEngine(InMemorySyncQueueStore(), BlockedCaminoApi(), clock, NoJitter),
        clock = clock,
        ids = SequentialIdGenerator(),
        scope = scope,
    )

    @Test
    fun controllerPauseResumePersistsAndPublishes() = runTest {
        val store = FlakyStore()
        val clock = MutableClock(epoch(1_000_000.0))
        val c = controller(this, store, clock)
        c.restore()
        assertEquals(PauseOutcome.Rejected(SessionError.notActive), c.pause())
        c.start("cf-sarria-portomarin")
        assertEquals(PauseOutcome.Rejected(SessionError.notPaused), c.resume())

        clock.advanceSeconds(10)
        assertTrue(c.pause() is PauseOutcome.Applied)
        assertTrue(c.snapshot.value.activeSession!!.isPaused)
        assertTrue(store.inner.load().activeSession!!.isPaused)
        assertEquals(PauseOutcome.Rejected(SessionError.alreadyPaused), c.pause())

        // Fallo de E/S: no lanza, se publica igualmente y se avisa.
        store.failing = true
        clock.advanceSeconds(50)
        val out = c.resume()
        assertTrue(out is PauseOutcome.Applied)
        assertFalse(c.snapshot.value.activeSession!!.isPaused)
        assertEquals(50.0, c.snapshot.value.activeSession!!.pausedSeconds, 1e-9)
        assertTrue(StorageIssue.saveFailed in c.storageIssues.value)
        assertTrue(store.inner.load().activeSession!!.isPaused)

        store.failing = false
        clock.advanceSeconds(10)
        c.pause()
        clock.advanceSeconds(20)
        val fin = c.finish()
        assertTrue(fin is FinishOutcome.Finished)
        assertEquals(70, (fin as FinishOutcome.Finished).summary.pausedSeconds)
        assertNotNull(c.lastSummary.value)
        advanceUntilIdle()
    }
}
