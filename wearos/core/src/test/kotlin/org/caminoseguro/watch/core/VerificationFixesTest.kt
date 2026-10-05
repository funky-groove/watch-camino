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

/** Regresiones de docs/security/VERIFICATION_REPORT.md (V-01…V-08) en el núcleo Kotlin. */
@OptIn(ExperimentalCoroutinesApi::class)
class VerificationFixesTest {
    private val stagesJson = Shared.fixture("stages.json")
    private val poisJson = Shared.fixture("pois.json")
    private val stageId = "cf-sarria-portomarin"

    /** Almacén de sesión que falla mientras [failing] sea true (disco lleno, AtomicFile…). */
    private class FlakySessionStore(var failing: Boolean = false, var unreadable: Boolean = false) : SessionStore {
        val inner = InMemorySessionStore()
        override suspend fun load(): SessionSnapshot = inner.load()
        override suspend fun save(snapshot: SessionSnapshot) {
            if (failing) throw IOException("ENOSPC")
            inner.save(snapshot)
        }
        override fun takeUnreadableNotice(): Boolean = unreadable.also { unreadable = false }
    }

    private fun controller(
        scope: TestScope,
        store: SessionStore,
        queue: InMemorySyncQueueStore = InMemorySyncQueueStore(),
        clock: MutableClock = MutableClock(epoch(1_000_000.0)),
        api: CaminoApi = BlockedCaminoApi(),
    ) = CaminoController(
        catalog = FixtureStageCatalog(stagesJson),
        poiSource = FixturePoiSource(poisJson),
        sessionStore = store,
        sync = SyncEngine(queue, api, clock, NoJitter),
        clock = clock,
        ids = SequentialIdGenerator(),
        scope = scope,
    )

    // V-01: un fallo de escritura no lanza; sigue en memoria y se publica como error recuperable.
    @Test
    fun saveFailureDuringStageDoesNotThrow() = runTest {
        val store = FlakySessionStore()
        val clock = MutableClock(epoch(1_000_000.0))
        val c = controller(this, store, clock = clock)
        c.restore()
        assertTrue(c.start(stageId) is StartOutcome.Started)
        store.failing = true
        clock.advanceSeconds(60)
        c.updateLocation(LocationFix(GeoPoint(42.7808, -7.4141), 5.0, clock.now()))
        clock.advanceSeconds(30)
        c.updateLocation(LocationFix(GeoPoint(42.7812497, -7.4141), 5.0, clock.now()))
        c.updateSteps(500)
        c.flush()
        assertEquals(50.0044, c.snapshot.value.activeSession!!.distanceMeters, 0.01)
        assertTrue(StorageIssue.saveFailed in c.storageIssues.value)
        // Se recupera en la siguiente escritura correcta.
        store.failing = false
        c.flush()
        assertFalse(StorageIssue.saveFailed in c.storageIssues.value)
        assertEquals(500, store.inner.load().activeSession!!.steps)
        advanceUntilIdle()
    }

    // V-04: si falla el guardado al finalizar no se encola nada; reintentar da un único stage_finished.
    @Test
    fun finishSaveFailureDoesNotDuplicateStageFinished() = runTest {
        val store = FlakySessionStore()
        val queue = InMemorySyncQueueStore()
        val c = controller(this, store, queue)
        c.restore()
        c.start(stageId)
        store.failing = true
        assertEquals(FinishOutcome.StorageFailed, c.finish())
        assertNotNull(c.snapshot.value.activeSession)
        assertEquals(listOf(SyncEventType.StageStarted), queue.load().queue.map { it.type })
        store.failing = false
        assertTrue(c.finish() is FinishOutcome.Finished)
        val finished = queue.load().queue.filter { it.type == SyncEventType.StageFinished }
        assertEquals(1, finished.size)
        assertNull(store.inner.load().activeSession)
        advanceUntilIdle()
    }

    // V-04 (relanzar): un segundo stage_finished de la misma sesión no se encola.
    @Test
    fun enqueueDeduplicatesStageFinishedPerSession() = runTest {
        val queue = InMemorySyncQueueStore()
        val engine = SyncEngine(queue, BlockedCaminoApi(), MutableClock(), NoJitter)
        val payload = SyncPayload.StageFinished("s", epoch(0.0), epoch(10.0), 0, 0, 10)
        engine.enqueue(listOf(SyncEvent("e1", SyncEventType.StageFinished, "S", epoch(10.0), payload)))
        engine.enqueue(listOf(SyncEvent("e2", SyncEventType.StageFinished, "S", epoch(20.0), payload)))
        assertEquals(listOf("e1"), queue.load().queue.map { it.eventId })
    }

    // V-03: un estado anterior ilegible se avisa en la UI.
    @Test
    fun unreadableStoreIsReportedOnRestore() = runTest {
        val c = controller(this, FlakySessionStore(unreadable = true))
        c.restore()
        assertTrue(StorageIssue.restoreFailed in c.storageIssues.value)
        c.dismissStorageIssue(StorageIssue.restoreFailed)
        assertTrue(c.storageIssues.value.isEmpty())
    }

    // V-02 / §7.4: con BlockedCaminoApi el estado es `blocked` también con la cola vacía.
    @Test
    fun blockedApiIsBlockedEvenWithEmptyQueue() = runTest {
        val engine = SyncEngine(InMemorySyncQueueStore(), BlockedCaminoApi(), MutableClock(), NoJitter)
        assertEquals(SyncStatus.Blocked, engine.snapshot.value.status)
        engine.load()
        assertEquals(SyncStatus.Blocked, engine.snapshot.value.status)
        assertEquals(SyncStatus.Blocked, engine.syncNow(manual = true))
        assertEquals(SyncStatus.Blocked, engine.syncNow(manual = false))
    }

    // V-05: coordenadas o precisión no finitas se rechazan antes del acumulador.
    @Test
    fun nonFiniteFixesAreRejected() = runTest {
        val clock = MutableClock(epoch(1_000_000.0))
        val c = controller(this, InMemorySessionStore(), clock = clock)
        c.restore()
        c.start(stageId)
        val bad = listOf(
            LocationFix(GeoPoint(Double.NaN, -7.4141), 5.0, clock.now()),
            LocationFix(GeoPoint(42.7808, Double.POSITIVE_INFINITY), 5.0, clock.now()),
            LocationFix(GeoPoint(42.7808, -7.4141), Double.NaN, clock.now()),
            LocationFix(GeoPoint(42.7808, -7.4141), -1.0, clock.now()),
            LocationFix(GeoPoint(42.7808, -7.4141), Double.NEGATIVE_INFINITY, clock.now()),
        )
        for (fix in bad) {
            assertFalse(DistanceAccumulator.isAccurateEnough(fix))
            c.updateLocation(fix)
        }
        val session = c.snapshot.value.activeSession!!
        assertNull(session.lastFix)
        assertEquals(0.0, session.distanceMeters, 0.0)
        assertNull(c.latestFix.value)
        CaminoJson.encodeSession(c.snapshot.value) // no lanza
        advanceUntilIdle()
    }

    // V-06: si el reloj del sistema retrocede, el límite de ritmo no bloquea.
    @Test
    fun clockGoingBackwardsDoesNotBlockAlerts() {
        val here = GeoPoint(42.7808, -7.4141)
        val poi = Poi("a", "s", "a", PoiCategory.water, here)
        val got = PoiAlertEngine.evaluate(listOf(poi), emptySet(), epoch(5000.0), epoch(1400.0), here, 5.0)
        assertEquals("a", got?.poi?.id)
    }

    // V-08: una categoría desactivada no avisa ni consume el límite de ritmo.
    @Test
    fun disabledCategoryDoesNotAlertNorConsumeRateLimit() = runTest {
        val clock = MutableClock(epoch(1_000_000.0))
        val c = controller(this, InMemorySessionStore(), clock = clock)
        c.restore()
        c.start(stageId)
        assertEquals(PoiCategory.entries.toSet(), c.alertCategories)
        // Junto a p03 (albergue).
        val p03 = c.activePois.value.first { it.id == "p03" }
        assertEquals(PoiCategory.shelter, p03.category)
        c.alertCategories = PoiCategory.entries.toSet() - PoiCategory.shelter
        assertNull(c.updateLocation(LocationFix(p03.location, 5.0, clock.now())))
        val session = c.snapshot.value.activeSession!!
        assertNull(session.lastAlertAt)
        assertTrue(session.alertedPoiIds.isEmpty())
        // Al reactivarla avisa en el siguiente fix, sin esperar el límite de 60 s.
        clock.advanceSeconds(1)
        c.alertCategories = PoiCategory.entries.toSet()
        assertEquals("p03", c.updateLocation(LocationFix(p03.location, 5.0, clock.now()))?.poi?.id)
        advanceUntilIdle()
    }
}
