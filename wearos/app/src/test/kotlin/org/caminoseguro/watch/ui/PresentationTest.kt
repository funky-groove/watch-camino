package org.caminoseguro.watch.ui

import org.caminoseguro.watch.core.GeoPoint
import org.caminoseguro.watch.core.LocationFix
import org.caminoseguro.watch.core.Poi
import org.caminoseguro.watch.core.PoiCategory
import org.caminoseguro.watch.core.SessionSnapshot
import org.caminoseguro.watch.core.SessionState
import org.caminoseguro.watch.core.SessionSummary
import org.caminoseguro.watch.core.Stage
import org.caminoseguro.watch.core.StageSession
import org.caminoseguro.watch.core.SyncStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class PresentationTest {
    private val sarria = GeoPoint(42.7808, -7.4141)
    private val stages = listOf(
        Stage("a", "A – B", "A", "B", 22200, sarria, GeoPoint(42.8075, -7.6156)),
        Stage("b", "B – C", "B", "C", 24800, GeoPoint(42.8075, -7.6156), GeoPoint(42.8733, -7.8686)),
    )
    private val t0: Instant = Instant.ofEpochSecond(1_000_000)

    @Test
    fun idleHasNoActiveStage() {
        assertNull(Presentation.activeStage(SessionSnapshot(), stages, emptyList(), null, t0))
    }

    @Test
    fun activeStageFigures() {
        val session = StageSession("S", "a", t0, steps = 1234, distanceMeters = 4000.0, alertedPoiIds = setOf("p1"))
        val pois = listOf(
            Poi("p1", "a", "Ya avisado", PoiCategory.water, sarria),
            Poi("p2", "a", "Albergue", PoiCategory.shelter, GeoPoint(42.7835, -7.4141)),
        )
        val fix = LocationFix(sarria, 5.0, t0)
        val ui = Presentation.activeStage(
            SessionSnapshot(SessionState.Active(session)), stages, pois, fix, t0.plusSeconds(3900),
        )!!
        assertEquals("A – B", ui.stageName)
        assertEquals(18200.0, ui.remainingMeters, 0.0)
        assertEquals(3900L, ui.elapsedSeconds)
        assertEquals("p2", ui.nextPoi?.poi?.id)
        assertTrue(ui.hasFix)
    }

    @Test
    fun activeStageWithoutSensorsShowsNoFalseZeros() {
        val session = StageSession("S", "a", t0)
        val ui = Presentation.activeStage(
            SessionSnapshot(SessionState.Active(session)), stages, emptyList(), null, t0.plusSeconds(120),
            locationAvailable = false,
            stepsAvailable = false,
        )!!
        assertNull(ui.figures.walkedMeters)
        assertNull(ui.figures.remainingMeters)
        assertNull(ui.figures.steps)
        assertEquals(120L, ui.figures.elapsedSeconds)
    }

    @Test
    fun noNextPoiWithoutFix() {
        val session = StageSession("S", "a", t0)
        val pois = listOf(Poi("p2", "a", "Albergue", PoiCategory.shelter, sarria))
        val ui = Presentation.activeStage(SessionSnapshot(SessionState.Active(session)), stages, pois, null, t0)!!
        assertNull(ui.nextPoi)
        assertFalse(ui.hasFix)
    }

    @Test
    fun suggestedStageFirst() {
        val history = listOf(SessionSummary("S", "a", t0, t0.plusSeconds(10), 0, 0, 10))
        val choices = Presentation.stageChoices(stages, history)
        assertEquals(listOf("b", "a"), choices.map { it.stage.id })
        assertTrue(choices.first().suggested)
        assertFalse(choices.last().suggested)
    }

    @Test
    fun statsTotalsAndToday() {
        val history = listOf(
            SessionSummary("S2", "b", t0, t0.plusSeconds(100), 200, 2000, 100),
            SessionSummary("S1", "a", t0, t0.plusSeconds(50), 100, 1000, 50),
        )
        val stats = Presentation.stats(SessionSnapshot(history = history), stages, t0)
        assertEquals(2, stats.totals.stages)
        assertEquals(3000.0, stats.totals.distanceMeters, 0.0)
        assertEquals(300L, stats.totals.steps)
        assertEquals(150L, stats.totals.activeSeconds)
        assertNotNull(stats.today)
        assertEquals("B – C", stats.todayStageName)
    }

    @Test
    fun syncLabels() {
        assertEquals(SyncLabel.SYNCED, Presentation.syncLabel(SyncStatus.Synced))
        assertEquals(SyncLabel.PENDING, Presentation.syncLabel(SyncStatus.Pending(3)))
        assertEquals(SyncLabel.OFFLINE, Presentation.syncLabel(SyncStatus.Offline))
        assertEquals(SyncLabel.BLOCKED, Presentation.syncLabel(SyncStatus.Blocked))
        assertEquals(SyncLabel.NEEDS_LINK, Presentation.syncLabel(SyncStatus.NeedsLink))
        assertEquals(SyncLabel.SYNCING, Presentation.syncLabel(SyncStatus.Syncing))
    }
}
