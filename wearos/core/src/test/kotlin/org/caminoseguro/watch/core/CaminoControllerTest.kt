package org.caminoseguro.watch.core

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CaminoControllerTest {
    private val stagesJson = Shared.fixture("stages.json")
    private val poisJson = Shared.fixture("pois.json")

    private class Env(
        val scope: TestScope,
        val sessionStore: InMemorySessionStore = InMemorySessionStore(),
        val queueStore: InMemorySyncQueueStore = InMemorySyncQueueStore(),
        val clock: MutableClock = MutableClock(epoch(1_000_000.0)),
        val api: CaminoApi = BlockedCaminoApi(),
    )

    private fun controller(env: Env): CaminoController {
        val sync = SyncEngine(env.queueStore, env.api, env.clock, NoJitter)
        return CaminoController(
            catalog = FixtureStageCatalog(stagesJson),
            poiSource = FixturePoiSource(poisJson),
            sessionStore = env.sessionStore,
            sync = sync,
            clock = env.clock,
            ids = SequentialIdGenerator(),
            scope = env.scope,
        )
    }

    @Test
    fun startPersistsAndEnqueuesAndSyncsBlocked() = runTest {
        val env = Env(this)
        val c = controller(env)
        c.restore()
        val out = c.start("cf-sarria-portomarin")
        assertTrue(out is StartOutcome.Started)
        advanceUntilIdle()
        assertNotNull(env.sessionStore.load().activeSession)
        assertEquals(1, env.queueStore.load().queue.size)
        assertEquals(SyncStatus.Blocked, c.syncSnapshot.value.status)
        assertEquals(3, c.activePois.value.size)
    }

    @Test
    fun restoresActiveSessionAfterProcessDeath() = runTest {
        val env = Env(this)
        val first = controller(env)
        first.restore()
        first.start("cf-sarria-portomarin")
        env.clock.advanceSeconds(60)
        first.updateLocation(LocationFix(GeoPoint(42.7808, -7.4141), 5.0, env.clock.now()))
        env.clock.advanceSeconds(30)
        first.updateLocation(LocationFix(GeoPoint(42.7812497, -7.4141), 5.0, env.clock.now()))
        first.updateSteps(77)
        first.flush()
        advanceUntilIdle()

        // "Muerte" del proceso: nuevo controlador sobre los mismos stores.
        val second = controller(env)
        second.restore()
        val session = second.snapshot.value.activeSession
        assertNotNull(session)
        assertEquals(77, session!!.steps)
        assertEquals(50.0044, session.distanceMeters, 0.01)
        assertEquals(3, second.activePois.value.size)
        assertEquals(1, second.syncSnapshot.value.queued)

        // Sigue contando y finaliza.
        env.clock.advanceSeconds(30)
        second.updateLocation(LocationFix(GeoPoint(42.7816993, -7.4141), 5.0, env.clock.now()))
        val fin = second.finish()
        assertTrue(fin is FinishOutcome.Finished)
        val summary = (fin as FinishOutcome.Finished).summary
        assertEquals(100, summary.distanceMeters)
        assertEquals(120, summary.activeSeconds)
        assertEquals(2, env.queueStore.load().queue.size)
        assertNull(env.sessionStore.load().activeSession)
        assertEquals(1, env.sessionStore.load().history.size)
        advanceUntilIdle()
    }

    @Test
    fun poiAlertEmittedOncePerSession() = runTest {
        val env = Env(this)
        val c = controller(env)
        c.restore()
        c.start("cf-sarria-portomarin")
        // Junto a p03 (Albergue de Portomarín).
        val alert = c.updateLocation(LocationFix(GeoPoint(42.8070, -7.6150), 5.0, env.clock.now()))
        assertEquals("p03", alert?.poi?.id)
        env.clock.advanceSeconds(120)
        assertNull(c.updateLocation(LocationFix(GeoPoint(42.8070, -7.6150), 5.0, env.clock.now())))
        advanceUntilIdle()
    }

    @Test
    fun idleUpdatesAreIgnoredWithoutError() = runTest {
        val env = Env(this)
        val c = controller(env)
        c.restore()
        c.updateSteps(10)
        assertNull(c.updateLocation(LocationFix(GeoPoint(0.0, 0.0), 5.0, env.clock.now())))
        assertEquals(SessionSnapshot(), c.snapshot.value)
        assertEquals(FinishOutcome.Rejected(SessionError.notActive), c.finish())
    }

    @Test
    fun mockApiSyncsEverything() = runTest {
        val env = Env(this, api = MockCaminoApi(latencyMillis = 100))
        val c = controller(env)
        c.restore()
        c.start("cf-sarria-portomarin")
        c.finish()
        advanceUntilIdle()
        assertEquals(SyncStatus.Synced, c.syncSnapshot.value.status)
        assertTrue(env.queueStore.load().queue.isEmpty())
    }

    @Test
    fun suggestedStageIsNextAfterLastFinished() = runTest {
        val env = Env(this)
        val c = controller(env)
        c.restore()
        assertEquals("cf-sarria-portomarin", CaminoStats.stagesWithSuggestionFirst(c.stages.value, emptyList()).first().id)
        c.start("cf-sarria-portomarin")
        c.finish()
        val ordered = CaminoStats.stagesWithSuggestionFirst(c.stages.value, c.snapshot.value.history)
        assertEquals("cf-portomarin-palas", ordered.first().id)
        assertEquals(5, ordered.size)
        val totals = CaminoStats.totals(c.snapshot.value.history)
        assertEquals(1, totals.stages)
        advanceUntilIdle()
    }

    @Test
    fun remainingMetersNeverNegative() {
        val stage = Stage("s", "n", "a", "b", 1000, GeoPoint(0.0, 0.0), GeoPoint(0.0, 0.0))
        assertEquals(400.0, CaminoStats.remainingMeters(stage, StageSession("S", "s", epoch(0.0), distanceMeters = 600.0)), 0.0)
        assertEquals(0.0, CaminoStats.remainingMeters(stage, StageSession("S", "s", epoch(0.0), distanceMeters = 1600.0)), 0.0)
    }
}
