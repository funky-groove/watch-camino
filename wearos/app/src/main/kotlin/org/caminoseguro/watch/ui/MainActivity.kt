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
        handleIntent(intent)
        setContent { CaminoApp(viewModel) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
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
    }
}
