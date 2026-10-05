package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

/** Contraste WCAG de los tokens Negro/Perla y paridad de valores con watchOS. */
class DesignTokensTest {

    @Test
    fun everyRequiredPairMeetsContrastInBothThemes() {
        val failures = mutableListOf<String>()
        for (theme in ThemeId.entries) {
            val palette = Palette.of(theme)
            for (req in ContrastRequirement.ALL) {
                val ratio = req.ratio(palette)
                if (ratio < req.minimum) failures += "${theme.storageKey}: ${req.name} = %.2f < ${req.minimum}".format(ratio)
            }
        }
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    @Test
    fun sosRedIsAtLeast4_5OnBackground() {
        // Valores documentados en docs/design/DESIGN_TOKENS.md.
        assertEquals(8.25, Rgb.contrast(Palette.NEGRO.critical, Palette.NEGRO.background), 0.01)
        assertEquals(6.10, Rgb.contrast(Palette.PERLA.critical, Palette.PERLA.background), 0.01)
        for (p in listOf(Palette.NEGRO, Palette.PERLA)) {
            assertTrue(Rgb.contrast(p.actionPrimaryText, p.critical) >= 4.5)
        }
    }

    @Test
    fun contrastFormulaKnownValues() {
        assertEquals(21.0, Rgb.contrast(Rgb(0x000000), Rgb(0xFFFFFF)), 1e-9)
        assertEquals(1.0, Rgb.contrast(Rgb(0x777777), Rgb(0x777777)), 1e-9)
        assertEquals(18.29, Rgb.contrast(Palette.NEGRO.textPrimary, Palette.NEGRO.background), 0.01)
        assertEquals(15.01, Rgb.contrast(Palette.PERLA.textPrimary, Palette.PERLA.background), 0.01)
    }

    @Test
    fun negroIsTheDefaultAndStorageRoundTrips() {
        assertEquals(ThemeId.NEGRO, ThemeId.INITIAL)
        assertEquals(ThemeId.NEGRO, ThemeId.fromStorage(null))
        assertEquals(ThemeId.NEGRO, ThemeId.fromStorage(""))
        assertEquals(ThemeId.NEGRO, ThemeId.fromStorage("desconocido"))
        for (t in ThemeId.entries) assertEquals(t, ThemeId.fromStorage(t.storageKey))
        assertEquals(ThemeId.PERLA, ThemeId.fromStorage(" Perla\n"))
    }

    /** Mismos hex que `watchos/CaminoCore/Sources/CaminoDesign/DesignTokens.swift`. */
    @Test
    fun paletteMatchesWatchOsTokens() {
        val repoRoot = Shared.conformanceDir.parentFile.parentFile
        val swift = File(repoRoot, "watchos/CaminoCore/Sources/CaminoDesign/DesignTokens.swift")
        assumeTrue("Sin fuente watchOS en este checkout", swift.isFile)
        val text = swift.readText()
        for ((name, palette) in listOf("negro" to Palette.NEGRO, "perla" to Palette.PERLA)) {
            val start = text.indexOf("static let $name = Palette(")
            assertTrue("No se encuentra la paleta $name en DesignTokens.swift", start >= 0)
            // Los 12 primeros `nombre: RGB(0x……)` tras la declaración son los de esa paleta.
            val swiftValues = Regex("""(\w+):\s*RGB\(0x([0-9A-Fa-f]{6})\)""").findAll(text, start)
                .take(12)
                .associate { it.groupValues[1] to it.groupValues[2].toInt(16) }
            val kotlinValues = mapOf(
                "background" to palette.background, "surface" to palette.surface,
                "surfaceRaised" to palette.surfaceRaised, "textPrimary" to palette.textPrimary,
                "textSecondary" to palette.textSecondary, "hairline" to palette.hairline,
                "controlOutline" to palette.controlOutline, "actionPrimaryFill" to palette.actionPrimaryFill,
                "actionPrimaryText" to palette.actionPrimaryText, "positive" to palette.positive,
                "warning" to palette.warning, "critical" to palette.critical,
            ).mapValues { it.value.hex }
            assertEquals("Paleta $name", swiftValues, kotlinValues)
        }
    }
}
