package org.caminoseguro.watch.core

import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

// Tokens de diseño de Camino Seguro Watch (docs/design/DESIGN_TOKENS.md), réplica para Wear OS de
// `watchos/CaminoCore/Sources/CaminoDesign/DesignTokens.swift` con los MISMOS valores hex
// (`DesignTokensTest` compara ambos ficheros). Datos puros, sin Compose: la app los convierte a
// `Color` en `ui/Theme.kt` y el contraste se verifica con tests JVM.
//
// PROCEDENCIA: todos los colores son ESTIMADOS (ver DESIGN_TOKENS.md).

/** Color sRGB opaco, 8 bits por canal. */
data class Rgb(val hex: Int) {
    val red: Int get() = (hex shr 16) and 0xFF
    val green: Int get() = (hex shr 8) and 0xFF
    val blue: Int get() = hex and 0xFF

    override fun toString(): String = String.format("#%06X", hex and 0xFFFFFF)

    /** Luminancia relativa (WCAG 2.x). */
    val relativeLuminance: Double
        get() {
            fun channel(value: Int): Double {
                val c = value / 255.0
                return if (c <= 0.04045) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }

    companion object {
        /** Relación de contraste WCAG 2.x entre dos colores (1…21). */
        fun contrast(a: Rgb, b: Rgb): Double {
            val la = a.relativeLuminance
            val lb = b.relativeLuminance
            return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
        }
    }
}

/** Temas disponibles. Negro es el valor inicial. */
enum class ThemeId(val storageKey: String) {
    NEGRO("negro"),
    PERLA("perla"),
    ;

    companion object {
        val INITIAL: ThemeId = NEGRO

        /** Valor persistido → tema. Cualquier cosa desconocida o vacía vuelve a Negro. */
        fun fromStorage(text: String?): ThemeId {
            val key = text?.trim()?.lowercase() ?: return INITIAL
            return entries.firstOrNull { it.storageKey == key } ?: INITIAL
        }
    }
}

/** Paleta semántica. Las pantallas sólo usan estos nombres, nunca valores sueltos. */
data class Palette(
    /** Fondo de pantalla. */
    val background: Rgb,
    /** Tarjetas y filas. */
    val surface: Rgb,
    /** Superficie elevada. */
    val surfaceRaised: Rgb,
    val textPrimary: Rgb,
    val textSecondary: Rgb,
    /** Separadores y bordes finos decorativos. */
    val hairline: Rgb,
    /** Contorno de controles (acción secundaria). */
    val controlOutline: Rgb,
    val actionPrimaryFill: Rgb,
    val actionPrimaryText: Rgb,
    /** Estados: siempre acompañados de texto o símbolo. */
    val positive: Rgb,
    val warning: Rgb,
    /** Error / destructivo / emergencia (SOS). */
    val critical: Rgb,
) {
    companion object {
        fun of(theme: ThemeId): Palette = when (theme) {
            ThemeId.NEGRO -> NEGRO
            ThemeId.PERLA -> PERLA
        }

        val NEGRO = Palette(
            background = Rgb(0x000000),
            surface = Rgb(0x1A1A19),
            surfaceRaised = Rgb(0x262624),
            textPrimary = Rgb(0xF2EFE8),
            textSecondary = Rgb(0xA8A399),
            hairline = Rgb(0x3B3936),
            controlOutline = Rgb(0x77726A),
            actionPrimaryFill = Rgb(0xF2EFE8),
            actionPrimaryText = Rgb(0x141413),
            positive = Rgb(0x5DBB7E),
            warning = Rgb(0xE5A93D),
            critical = Rgb(0xFF7A6B),
        )

        val PERLA = Palette(
            background = Rgb(0xF3EFE7),
            surface = Rgb(0xEAE4D8),
            surfaceRaised = Rgb(0xE1D9CA),
            textPrimary = Rgb(0x1C1B19),
            textSecondary = Rgb(0x5B564E),
            hairline = Rgb(0xCBC2B2),
            controlOutline = Rgb(0x857D70),
            actionPrimaryFill = Rgb(0x1C1B19),
            actionPrimaryText = Rgb(0xF3EFE7),
            positive = Rgb(0x24633A),
            warning = Rgb(0x7E5200),
            critical = Rgb(0xA8291F),
        )
    }
}

/** Pares de color que la interfaz realmente combina, con el contraste mínimo exigido. */
data class ContrastRequirement(
    val name: String,
    val kind: Kind,
    val foreground: (Palette) -> Rgb,
    val background: (Palette) -> Rgb,
) {
    enum class Kind(val minimum: Double) {
        /** Texto de cualquier tamaño (4,5:1, también el grande, por margen). */
        TEXT(4.5),

        /** Componentes de interfaz y objetos gráficos (3:1). */
        NON_TEXT(3.0),
    }

    val minimum: Double get() = kind.minimum

    fun ratio(palette: Palette): Double = Rgb.contrast(foreground(palette), background(palette))

    companion object {
        val ALL: List<ContrastRequirement> by lazy {
            val grounds = listOf<Pair<String, (Palette) -> Rgb>>(
                "fondo" to { it.background },
                "superficie" to { it.surface },
                "superficie elevada" to { it.surfaceRaised },
            )
            val texts = listOf<Pair<String, (Palette) -> Rgb>>(
                "texto principal" to { it.textPrimary },
                "texto secundario" to { it.textSecondary },
                "positivo" to { it.positive },
                "advertencia" to { it.warning },
                "crítico" to { it.critical },
            )
            buildList {
                for ((textName, text) in texts) {
                    for ((groundName, ground) in grounds) {
                        add(ContrastRequirement("$textName sobre $groundName", Kind.TEXT, text, ground))
                    }
                }
                add(ContrastRequirement("texto de acción principal", Kind.TEXT, { it.actionPrimaryText }, { it.actionPrimaryFill }))
                add(ContrastRequirement("acción principal sobre fondo", Kind.NON_TEXT, { it.actionPrimaryFill }, { it.background }))
                // Acción de emergencia ("Llamar al 112"): relleno `critical` con el texto de acción
                // principal (oscuro en Negro, claro en Perla). Igual que en watchOS.
                add(ContrastRequirement("texto de acción de emergencia", Kind.TEXT, { it.actionPrimaryText }, { it.critical }))
                add(ContrastRequirement("acción de emergencia sobre fondo", Kind.NON_TEXT, { it.critical }, { it.background }))
                // Botón «SOS» de cabecera: texto `critical` y contorno `critical` sobre el fondo.
                add(ContrastRequirement("texto SOS de cabecera sobre fondo", Kind.TEXT, { it.critical }, { it.background }))
                add(ContrastRequirement("contorno de control sobre fondo", Kind.NON_TEXT, { it.controlOutline }, { it.background }))
                add(ContrastRequirement("contorno de control sobre superficie", Kind.NON_TEXT, { it.controlOutline }, { it.surface }))
            }
        }
    }
}
