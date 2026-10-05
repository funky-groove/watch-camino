package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Test

class SerializationTest {
    private val fix = LocationFix(GeoPoint(42.78, -7.41), 4.5, epoch(1234.567))

    @Test
    fun sessionSnapshotRoundTrip() {
        val active = SessionSnapshot(
            state = SessionState.Active(
                StageSession(
                    sessionId = "8b0d2c1e-0000-4000-8000-000000000001",
                    stageId = "cf-sarria-portomarin",
                    startedAt = epoch(1000.25),
                    steps = 4321,
                    distanceMeters = 1234.5678,
                    lastFix = fix,
                    alertedPoiIds = setOf("p01", "p02"),
                    lastAlertAt = epoch(1100.0),
                ),
            ),
            history = listOf(SessionSummary("old", "x", epoch(1.0), epoch(2.0), 10, 20, 1)),
        )
        assertEquals(active, CaminoJson.decodeSession(CaminoJson.encodeSession(active)))
        val idle = SessionSnapshot()
        assertEquals(idle, CaminoJson.decodeSession(CaminoJson.encodeSession(idle)))
    }

    @Test
    fun syncQueueRoundTrip() {
        val started = fakeEvent("e1")
        val finished = SyncEvent(
            eventId = "e2",
            type = SyncEventType.StageFinished,
            sessionId = "S",
            occurredAt = epoch(50.0),
            payload = SyncPayload.StageFinished("s", epoch(0.0), epoch(50.0), 100, 80, 50),
        )
        val state = SyncQueueState(listOf(started, finished), listOf(started), attempt = 3, nextAttemptAt = epoch(99.5))
        assertEquals(state, CaminoJson.decodeSyncQueue(CaminoJson.encodeSyncQueue(state)))
    }

    @Test
    fun stepCounterRoundTrip() {
        val s = StepCounterState("S", bootId = 7, baseline = 100, offset = 50, lastRaw = 300)
        assertEquals(s, CaminoJson.decodeStepCounter(CaminoJson.encodeStepCounter(s)))
    }

    @Test
    fun toleratesUnknownKeys() {
        val text = """{"state":{"type":"idle"},"history":[],"futuro":1}"""
        assertEquals(SessionSnapshot(), CaminoJson.decodeSession(text))
    }
}
