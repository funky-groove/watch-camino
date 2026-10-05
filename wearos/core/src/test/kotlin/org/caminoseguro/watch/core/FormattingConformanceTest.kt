package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Test

class FormattingConformanceTest {
    private val data = Shared.conformance("formatting.json")

    @Test
    fun distance() {
        val cases = data["distance"]!!.arr
        assertEquals(21, cases.size)
        for (c in cases) {
            val m = c.obj["meters"]!!.d
            assertEquals("m=$m", c.obj["text"]!!.s, Formatters.distance(m))
        }
    }

    @Test
    fun duration() {
        val cases = data["duration"]!!.arr
        assertEquals(10, cases.size)
        for (c in cases) {
            val s = c.obj["seconds"]!!.i.toLong()
            assertEquals("s=$s", c.obj["text"]!!.s, Formatters.duration(s))
        }
    }

    @Test
    fun steps() {
        val cases = data["steps"]!!.arr
        assertEquals(7, cases.size)
        for (c in cases) {
            val n = c.obj["steps"]!!.i
            assertEquals("n=$n", c.obj["text"]!!.s, Formatters.steps(n))
        }
    }

    @Test
    fun spokenVariants() {
        assertEquals("4,2 kilómetros", Formatters.distanceSpoken(4200.0))
        assertEquals("340 metros", Formatters.distanceSpoken(340.0))
        assertEquals("22 kilómetros", Formatters.distanceSpoken(22200.0))
        assertEquals("0 minutos", Formatters.durationSpoken(0))
        assertEquals("1 minuto", Formatters.durationSpoken(60))
        assertEquals("1 hora 5 minutos", Formatters.durationSpoken(3900))
        assertEquals("2 horas 0 minutos", Formatters.durationSpoken(7200))
        assertEquals("1.234 pasos", Formatters.stepsSpoken(1234))
        assertEquals("1 paso", Formatters.stepsSpoken(1))
    }

    @Test
    fun poiAlertText() {
        val poi = Poi("p", "s", "Fuente de Barbadelo", PoiCategory.water, GeoPoint(0.0, 0.0))
        assertEquals("💧 Fuente de Barbadelo · 340 m", Formatters.poiAlertText(poi, 342.0))
    }
}
