package org.caminoseguro.watch.ui

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import org.caminoseguro.watch.CaminoApplication
import org.caminoseguro.watch.DemoHooks
import org.caminoseguro.watch.complication.CaminoComplicationService
import org.caminoseguro.watch.platform.AppLocale

class MainActivity : ComponentActivity() {

    private val viewModel: CaminoViewModel by viewModels(
        factoryProducer = { CaminoViewModel.Factory(application as CaminoApplication) },
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = (application as CaminoApplication).container
        // Idioma efectivo de esta actividad (LocaleManager la recrea al cambiarlo).
        container.refreshLanguage(AppLocale.effective(this))
        // Escenarios de demostración: sólo Debug rellena el gancho (no-op en main/Release).
        DemoHooks.apply?.let { hook ->
            try {
                hook(container)
            } catch (e: RuntimeException) {
                Log.w(TAG, "Escenario de demostración no aplicado: ${e.javaClass.simpleName}")
            }
        }
        // F-05: antes de crear el NavHost (que resuelve los deep links del Intent de la actividad).
        dropExternalDeepLinks(intent)
        handleIntent(intent)
        setContent { CaminoApp(viewModel) }
    }

    override fun onNewIntent(intent: Intent) {
        dropExternalDeepLinks(intent)
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    /**
     * F-05: la actividad está exportada (launcher) y Navigation registra un deep link implícito
     * `android-app://androidx.navigation/<ruta>` por cada `composable(route)`. Sin este filtro
     * cualquier app instalada podría abrir directamente `sos`, `confirm_finish`, `place/{id}`…
     * La app no usa deep links propios: los únicos lanzamientos legítimos son el launcher y la
     * complicación (`ACTION_OPEN_TRIP`, sin `data`). Por eso se descarta todo `data` (y los
     * extras de deep link explícito de NavController) salvo la URI exacta que haya puesto el
     * instalador de escenarios de Debug ([DemoHooks.allowedNavUri], null en Release).
     */
    private fun dropExternalDeepLinks(intent: Intent?) {
        if (intent == null) return
        try {
            val data = intent.dataString
            if (data != null && data != DemoHooks.allowedNavUri) {
                if (intent.data?.scheme == NAV_SCHEME) Log.w(TAG, "Deep link de navegación externo descartado")
                intent.data = null
            }
            for (key in NAV_DEEP_LINK_EXTRAS) intent.removeExtra(key)
        } catch (e: RuntimeException) {
            // Extras malformados (BadParcelableException…): se descartan todos.
            Log.w(TAG, "Intent con extras ilegibles: ${e.javaClass.simpleName}")
            intent.data = null
            intent.replaceExtras(null as android.os.Bundle?)
        }
    }

    /** Toque en la complicación: abre Trayecto (inicio o estadísticas). Nunca inicia nada. */
    private fun handleIntent(intent: Intent?) {
        if (intent?.action == CaminoComplicationService.ACTION_OPEN_TRIP) viewModel.openTrip()
    }

    override fun onStart() {
        super.onStart()
        viewModel.onForeground()
    }

    override fun onStop() {
        viewModel.onBackground()
        super.onStop()
    }

    private companion object {
        const val TAG = "CaminoMain"
        const val NAV_SCHEME = "android-app"

        /** Claves de `NavController.KEY_DEEP_LINK_*` (deep link explícito por ids de destino). */
        val NAV_DEEP_LINK_EXTRAS = listOf(
            "android-support-nav:controller:deepLinkIds",
            "android-support-nav:controller:deepLinkArgs",
            "android-support-nav:controller:deepLinkExtras",
            "android-support-nav:controller:deepLinkIntent",
        )
    }
}
