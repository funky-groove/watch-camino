package org.caminoseguro.watch.ui

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import org.caminoseguro.watch.AppContainer
import org.caminoseguro.watch.CaminoApplication
import org.caminoseguro.watch.DemoHooks
import org.caminoseguro.watch.complication.CaminoComplicationService
import org.caminoseguro.watch.core.BrandLogo
import org.caminoseguro.watch.core.WelcomePolicy
import org.caminoseguro.watch.platform.AppLocale
import org.caminoseguro.watch.platform.BrandBitmaps
import org.caminoseguro.watch.platform.Notifications

class MainActivity : ComponentActivity() {

    private val viewModel: CaminoViewModel by viewModels(
        factoryProducer = { CaminoViewModel.Factory(application as CaminoApplication) },
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val container = (application as CaminoApplication).container
        // §K.2 (1): se consume aquí, en el primer onCreate del proceso.
        val coldStart = container.takeColdStart(hasSavedState = savedInstanceState != null)
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
        // §K.2 (3): se mira el Intent tal como llegó, antes de filtrar sus deep links.
        val fromDeepLink = launchedFromDeepLink(intent)
        val forSos = launchedForSos(intent)
        // F-05: antes de crear el NavHost (que resuelve los deep links del Intent de la actividad).
        dropExternalDeepLinks(intent)
        handleIntent(intent)
        val welcome = prepareWelcome(container, coldStart, fromDeepLink, forSos)
        setContent { WelcomeHost(welcome) { CaminoApp(viewModel) } }
    }

    /**
     * Bienvenida visual (§K): decide con [WelcomePolicy] y, si se muestra, empieza a leer y
     * decodificar la caché del recurso de marca en IO (sólo si existe). No espera a nada: la
     * interfaz se compone igual debajo. Si el controlador aún no ha restaurado, la capa observa el
     * estado y se retira al instante si aparece un trayecto activo. El splash del sistema no se toca.
     */
    private fun prepareWelcome(
        container: AppContainer,
        coldStart: Boolean,
        fromDeepLink: Boolean,
        forSos: Boolean,
    ): WelcomeLaunch? {
        val controller = container.controller
        val tripActive = combine(controller.snapshot, container.restoredActiveThisLaunch) { snapshot, restored ->
            snapshot.activeSession != null || restored
        }
        val tripActiveNow = controller.snapshot.value.activeSession != null || container.restoredActiveThisLaunch.value
        val demo = DemoHooks.welcomeDemo
        // Demo: true/false fijado por el escenario (una vez por proceso); si no, la política.
        val show = if (demo != null) demo && !container.welcomeShown else WelcomePolicy.shouldShow(
            coldStart = coldStart,
            hasActiveOrRestoredTrip = tripActiveNow,
            launchedFromDeepLink = fromDeepLink,
            launchedForSos = forSos,
            alreadyShown = container.welcomeShown,
        )
        if (!show) return null
        container.welcomeShown = true
        val welcome = WelcomeLaunch(
            reducedMotion = BrandBitmaps.reducedMotion(this),
            holdUntilTap = demo == true,
            tripActive = tripActive,
            tripActiveInitial = tripActiveNow,
        )
        container.appScope.launch(Dispatchers.IO) {
            try {
                val logo = container.brandAssets.current()
                if (logo is BrandLogo.Cached) welcome.cachedLogo = BrandBitmaps.decode(logo.bytes)?.asImageBitmap()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Recurso de marca no leído: ${e.javaClass.simpleName}")
            }
        }
        return welcome
    }

    /** Complicación, notificación o cualquier Intent con datos/extras de navegación. */
    private fun launchedFromDeepLink(intent: Intent?): Boolean {
        if (intent == null) return false
        if (intent.action == CaminoComplicationService.ACTION_OPEN_TRIP) return true
        if (intent.action == Notifications.ACTION_OPEN_FROM_NOTIFICATION) return true
        if (intent.data != null) return true
        return try {
            NAV_DEEP_LINK_EXTRAS.any { intent.hasExtra(it) }
        } catch (e: RuntimeException) {
            true // extras ilegibles: no es una apertura normal desde el launcher
        }
    }

    /** Apertura directa en la pantalla SOS (ruta `sos`). */
    private fun launchedForSos(intent: Intent?): Boolean =
        intent?.data?.lastPathSegment == SOS_ROUTE

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
        // §K.1: el recurso de marca sólo se refresca en segundo plano, nunca al abrir.
        if (!isChangingConfigurations) (application as CaminoApplication).container.refreshBrandAssetInBackground()
        super.onStop()
    }

    private companion object {
        const val TAG = "CaminoMain"
        const val NAV_SCHEME = "android-app"
        const val SOS_ROUTE = "sos"

        /** Claves de `NavController.KEY_DEEP_LINK_*` (deep link explícito por ids de destino). */
        val NAV_DEEP_LINK_EXTRAS = listOf(
            "android-support-nav:controller:deepLinkIds",
            "android-support-nav:controller:deepLinkArgs",
            "android-support-nav:controller:deepLinkExtras",
            "android-support-nav:controller:deepLinkIntent",
        )
    }
}
