package org.caminoseguro.watch.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.LocalContentColor
import androidx.wear.compose.material.MaterialTheme
import org.caminoseguro.watch.core.Palette
import org.caminoseguro.watch.core.Rgb
import org.caminoseguro.watch.core.ThemeId

// Temas Negro/Perla (docs/design/DESIGN_TOKENS.md). Los valores vienen de `core/DesignTokens.kt`
// (mismos hex que watchOS) y su contraste lo verifica `DesignTokensTest` en JVM.

fun Rgb.toColor(): Color = Color(red = red, green = green, blue = blue)

/** Paleta semántica del tema actual (para lo que no cubre MaterialTheme: SOS, líneas finas). */
val LocalPalette = staticCompositionLocalOf { Palette.NEGRO }

/** Tema actual (p. ej. para no usar la viñeta negra sobre Perla). */
val LocalThemeId = staticCompositionLocalOf { ThemeId.INITIAL }

/**
 * Colores de Wear Material a partir de los tokens. Pares usados por los componentes:
 * Chip principal = onPrimary/primary (texto de acción principal), Chip secundario =
 * onSurface/surface, ListHeader = onSurfaceVariant/background (texto secundario).
 */
fun Palette.toWearColors(): Colors = Colors(
    primary = actionPrimaryFill.toColor(),
    primaryVariant = actionPrimaryFill.toColor(),
    secondary = positive.toColor(),
    secondaryVariant = positive.toColor(),
    background = background.toColor(),
    surface = surface.toColor(),
    error = critical.toColor(),
    onPrimary = actionPrimaryText.toColor(),
    onSecondary = background.toColor(),
    onBackground = textPrimary.toColor(),
    onSurface = textPrimary.toColor(),
    onSurfaceVariant = textSecondary.toColor(),
    onError = actionPrimaryText.toColor(),
)

@Composable
fun CaminoTheme(theme: ThemeId, content: @Composable () -> Unit) {
    val palette = Palette.of(theme)
    MaterialTheme(colors = palette.toWearColors()) {
        CompositionLocalProvider(
            LocalPalette provides palette,
            LocalThemeId provides theme,
            // Wear Material usa blanco por defecto para el texto suelto: sobre Perla sería invisible.
            LocalContentColor provides palette.textPrimary.toColor(),
            content = content,
        )
    }
}

/** Cifras monoespaciadas (tabulares): no "bailan" al cambiar cada 10 s. */
fun TextStyle.tabular(): TextStyle = copy(fontFeatureSettings = "tnum")
