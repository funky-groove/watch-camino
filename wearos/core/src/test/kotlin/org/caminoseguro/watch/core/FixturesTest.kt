package org.caminoseguro.watch.core

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FixturesTest {
    private val catalog = FixtureStageCatalog(Shared.fixture("stages.json"))
    private val pois = FixturePoiSource(Shared.fixture("pois.json"))

    @Test
    fun loadsFiveStagesAndThirteenPois() = runTest {
        val stages = catalog.stages()
        assertEquals(5, stages.size)
        assertEquals("cf-sarria-portomarin", stages.first().id)
        assertEquals(22200, stages.first().distanceMeters)
        assertEquals(13, pois.allPois().size)
        assertEquals(3, pois.pois("cf-sarria-portomarin").size)
        assertEquals(PoiCategory.health, pois.allPois().single { it.id == "p08" }.category)
    }

    @Test
    fun everyPoiBelongsToAKnownStage() = runTest {
        val ids = catalog.stages().map { it.id }.toSet()
        assertTrue(pois.allPois().all { it.stageId in ids })
    }

    @Test
    fun stagesAreChained() = runTest {
        val stages = catalog.stages()
        for (i in 1 until stages.size) assertEquals(stages[i - 1].end, stages[i].start)
    }
}
