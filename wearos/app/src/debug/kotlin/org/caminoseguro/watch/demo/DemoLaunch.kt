package org.caminoseguro.watch.demo

import android.content.Intent
import org.caminoseguro.watch.core.ThemeId

/**
 * Parámetros de un lanzamiento de demostración (SÓLO Debug), leídos de los extras del Intent:
 *
 *     adb shell am start -n org.caminoseguro.watch/.ui.MainActivity \
 *         --es demo.scenario active --es demo.route sos --es demo.theme perla --es demo.lang en
 *
 * - `demo.scenario`: idle | active | paused | finished | nearby (obligatorio para activar la demo).
 * - `demo.route`:    ruta de navegación de `CaminoApp` (p. ej. `settings`, `sos`, `place/p01`).
 *                    Vacío o `home` = pantalla principal.
 * - `demo.theme`:    negro | perla (por defecto, negro).
 * - `demo.lang`:     es | en (por defecto, el idioma del sistema).
 * - `demo.facehint`: show | hide (por defecto, hide): aviso «Accede desde tu esfera» (§I) sin
 *                    decidir (se ofrece) o ya descartado (no tapa las demás pantallas).
 * - `demo.welcome`:  show | hide (por defecto, hide): bienvenida visual (§K). Con show se muestra
 *                    sobre la pantalla pedida y se mantiene hasta un toque (para capturarla).
 */
data class DemoLaunch(
    val scenario: DemoScenario,
    val route: String?,
    val theme: ThemeId?,
    val lang: String?,
    val showFaceHint: Boolean = false,
    val showWelcome: Boolean = false,
) {
    companion object {
        const val EXTRA_SCENARIO = "demo.scenario"
        const val EXTRA_ROUTE = "demo.route"
        const val EXTRA_THEME = "demo.theme"
        const val EXTRA_LANG = "demo.lang"
        const val EXTRA_FACE_HINT = "demo.facehint"
        const val EXTRA_WELCOME = "demo.welcome"

        /** Null si el Intent no pide escenario (lanzamiento normal) o el escenario no existe. */
        fun from(intent: Intent?): DemoLaunch? {
            if (intent == null) return null
            val raw = intent.getStringExtra(EXTRA_SCENARIO) ?: return null
            val scenario = DemoScenario.parse(raw) ?: return null
            val route = intent.getStringExtra(EXTRA_ROUTE)
                ?.trim()
                ?.trim('/')
                ?.takeIf { it.isNotEmpty() && it != "home" }
            val theme = intent.getStringExtra(EXTRA_THEME)?.let { ThemeId.fromStorage(it) }
            val lang = intent.getStringExtra(EXTRA_LANG)
                ?.trim()
                ?.lowercase()
                ?.takeIf { it == "es" || it == "en" }
            val showFaceHint = intent.getStringExtra(EXTRA_FACE_HINT)?.trim()?.lowercase() == "show"
            val showWelcome = intent.getStringExtra(EXTRA_WELCOME)?.trim()?.lowercase() == "show"
            return DemoLaunch(scenario, route, theme, lang, showFaceHint, showWelcome)
        }
    }
}

enum class DemoScenario(val key: String) {
    IDLE("idle"),
    ACTIVE("active"),
    PAUSED("paused"),
    FINISHED("finished"),
    NEARBY("nearby"),
    ;

    companion object {
        fun parse(raw: String): DemoScenario? {
            val key = raw.trim().lowercase()
            return entries.firstOrNull { it.key == key }
        }
    }
}
