package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** V1.1 §G: `shared/conformance/units_formatting.json`. */
class UnitsFormattingConformanceTest {
    private val data = Shared.conformance("units_formatting.json")

    private fun text(e: kotlinx.serialization.json.JsonElement): String? =
        if (e.obj["text"].isNull) null else e.obj["text"]!!.s

    @Test
    fun distance() {
        val cases = data["distance"]!!.arr
        assertEquals(40, cases.size)
        for (c in cases) {
            val units = UnitSystem.valueOf(c.obj["units"]!!.s)
            val lang = AppLanguage.valueOf(c.obj["lang"]!!.s)
            assertEquals(c.toString(), text(c), UnitFormatter.distance(c.obj["meters"]!!.d, units, lang))
        }
    }

    @Test
    fun elevation() {
        val cases = data["elevation"]!!.arr
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val units = UnitSystem.valueOf(c.obj["units"]!!.s)
            assertEquals(c.toString(), text(c), UnitFormatter.elevation(c.obj["meters"]!!.d, units))
        }
    }

    @Test
    fun steps() {
        val cases = data["steps"]!!.arr
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val lang = AppLanguage.valueOf(c.obj["lang"]!!.s)
            assertEquals(c.toString(), text(c), UnitFormatter.steps(c.obj["steps"]!!.i, lang))
        }
    }

    @Test
    fun pace() {
        val cases = data["pace"]!!.arr
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val units = UnitSystem.valueOf(c.obj["units"]!!.s)
            assertEquals(c.toString(), text(c), UnitFormatter.pace(c.obj["distanceM"]!!.d, c.obj["movingS"]!!.d, units))
        }
    }

    @Test
    fun speed() {
        val cases = data["speed"]!!.arr
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val units = UnitSystem.valueOf(c.obj["units"]!!.s)
            val lang = AppLanguage.valueOf(c.obj["lang"]!!.s)
            assertEquals(
                c.toString(),
                text(c),
                UnitFormatter.speed(c.obj["distanceM"]!!.d, c.obj["movingS"]!!.d, units, lang),
            )
        }
    }

    @Test
    fun metricSpanishMatchesLegacyFormatters() {
        for (m in listOf(0.0, 340.0, 995.0, 1234.0, 9949.9, 22200.0)) {
            assertEquals(Formatters.distance(m), UnitFormatter.distance(m, UnitSystem.metric, AppLanguage.es))
        }
        assertEquals(Formatters.steps(1234567), UnitFormatter.steps(1234567, AppLanguage.es))
    }
}
