package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class TripFiguresTest {
    private val t0: Instant = Instant.ofEpochSecond(1_000_000)
    private val stage = Stage("a", "A – B", "A", "B", 22200, GeoPoint(42.78, -7.41), GeoPoint(42.80, -7.61))

    @Test
    fun allFiguresWhenEverythingIsAvailable() {
        val s = StageSession("S", "a", t0, steps = 1234, distanceMeters = 4000.0)
        val f = TripFigures.of(s, stage, t0.plusSeconds(3900), locationAvailable = true, stepsAvailable = true)
        assertEquals(18200.0, f.remainingMeters!!, 0.0)
        assertEquals(4000.0, f.walkedMeters!!, 0.0)
        assertEquals(1234, f.steps)
        assertEquals(3900L, f.elapsedSeconds)
    }

    @Test
    fun noFalseZerosWithoutSensorsOrPermissions() {
        val s = StageSession("S", "a", t0)
        val f = TripFigures.of(s, stage, t0.plusSeconds(60), locationAvailable = false, stepsAvailable = false)
        assertNull("sin ubicación no hay '0 m'", f.walkedMeters)
        assertNull("sin distancia no se puede decir lo que queda", f.remainingMeters)
        assertNull("sin sensor/permiso no hay '0 pasos'", f.steps)
        assertEquals(60L, f.elapsedSeconds)
    }

    @Test
    fun alreadyMeasuredValuesAreKeptIfPermissionIsLost() {
        val s = StageSession("S", "a", t0, steps = 50, distanceMeters = 120.0)
        val f = TripFigures.of(s, stage, t0, locationAvailable = false, stepsAvailable = false)
        assertEquals(120.0, f.walkedMeters!!, 0.0)
        assertEquals(50, f.steps)
    }

    @Test
    fun unknownStageHasNoRemaining() {
        val s = StageSession("S", "zz", t0, distanceMeters = 10.0)
        assertNull(TripFigures.of(s, null, t0, locationAvailable = true, stepsAvailable = true).remainingMeters)
    }

    @Test
    fun genuineZeroIsShownWhenMeasurable() {
        val s = StageSession("S", "a", t0)
        val f = TripFigures.of(s, stage, t0, locationAvailable = true, stepsAvailable = true)
        assertEquals(0.0, f.walkedMeters!!, 0.0)
        assertEquals(0, f.steps)
    }

    @Test
    fun actionGatePreventsDoubleStart() {
        val gate = ActionGate()
        assertTrue(gate.tryEnter())
        assertFalse("segundo toque ignorado", gate.tryEnter())
        assertTrue(gate.isBusy)
        gate.reset()
        assertTrue(gate.tryEnter())
    }
}
