package org.caminoseguro.watch.demo

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.LocaleList
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import org.caminoseguro.watch.AppContainer
import org.caminoseguro.watch.DemoHooks
import org.caminoseguro.watch.core.CaminoController
import org.caminoseguro.watch.core.FaceHintState
import org.caminoseguro.watch.core.FakeEmergencyDialer
import org.caminoseguro.watch.core.FixturePoiSource
import org.caminoseguro.watch.core.FixtureStageCatalog
import org.caminoseguro.watch.core.InMemorySessionStore
import org.caminoseguro.watch.core.InMemorySyncQueueStore
import org.caminoseguro.watch.core.MockCaminoApi
import org.caminoseguro.watch.core.StartOutcome
import org.caminoseguro.watch.core.SyncEngine
import org.caminoseguro.watch.core.UuidGenerator
import java.io.File
import java.time.Instant
import java.util.Locale

/**
 * Escenarios de demostración para capturas (SÓLO Debug; este fichero no existe en Release).
 *
 * Aislamiento: antes de crear el ViewModel se llama a `AppContainer.installDemo`, que sustituye
 * el controlador por uno en memoria ([InMemorySessionStore] + [InMemorySyncQueueStore],
 * `MockCaminoApi(0)` sin red, reloj desplazable), el marcador de emergencia por
 * [FakeEmergencyDialer] (aunque se pulsara «Llamar», no abre nada) y lleva las preferencias a
 * `cacheDir/demo-scenario/` (se borra en cada lanzamiento de demo). Nunca se escribe en el
 * almacenamiento real del usuario.
 *
 * Los sensores reales (SessionRuntime) siguen enganchados al controlador original, que no se toca.
 */
object DemoScenarioInstaller {
    private const val TAG = "CaminoDemo"
    private const val DEMO_DIR = "demo-scenario"
    private const val SEED_TIMEOUT_MS = 5_000L

    /** Prefijo de los deep links implícitos que Navigation crea para cada ruta (`composable(route)`). */
    private const val NAV_ROUTE_URI_PREFIX = "android-app://androidx.navigation/"

    @Volatile private var pending: DemoLaunch? = null
    @Volatile private var installed = false

    /**
     * `onActivityPreCreated` (antes de `Activity.onCreate`): guarda el escenario pedido y aplica
     * idioma y ruta sobre la actividad que se está creando. Sin extras de demo no hace nada.
     */
    fun onActivityPreCreated(activity: Activity, firstCreate: Boolean) {
        val launch = DemoLaunch.from(activity.intent) ?: return
        pending = launch
        // Bienvenida visual (§K): un escenario DEMO no la muestra salvo demo.welcome=show.
        DemoHooks.welcomeDemo = launch.showWelcome
        Log.i(TAG, "Escenario demo: ${launch.scenario.key} ruta=${launch.route ?: "home"} tema=${launch.theme?.storageKey} idioma=${launch.lang} bienvenida=${launch.showWelcome}")
        launch.lang?.let { applyLocale(activity, it) }
        if (firstCreate) launch.route?.let { applyRoute(activity.intent, it) }
    }

    /**
     * Instala el escenario pendiente en [container]. Idempotente por proceso: el script de capturas
     * fuerza la parada de la app antes de cada lanzamiento. Nunca lanza.
     */
    fun install(app: Application, container: AppContainer) {
        val launch = pending ?: return
        synchronized(this) {
            if (installed) return
            installed = true
        }
        try {
            installUnsafe(app, container, launch)
        } catch (e: Exception) {
            Log.e(TAG, "Escenario demo no instalado: ${e.javaClass.simpleName}: ${e.message}")
        }
    }

    // ------------------------------------------------------------------ Idioma y ruta

    /** Idioma sólo para este proceso: no se guarda en ningún sitio (ni preferencia por app). */
    @Suppress("DEPRECATION")
    private fun applyLocale(activity: Activity, lang: String) {
        val locale = if (lang == "en") Locale.US else Locale.forLanguageTag("es-ES")
        Locale.setDefault(locale)
        for (res in listOf(activity.resources, activity.applicationContext.resources)) {
            val cfg = Configuration(res.configuration)
            cfg.setLocales(LocaleList(locale))
            res.updateConfiguration(cfg, res.displayMetrics)
        }
    }

    /**
     * Navigation da a cada `composable(route)` un deep link implícito
     * `android-app://androidx.navigation/<route>`, y el NavController lo resuelve con
     * `handleDeepLink(activity.intent)` al crear el grafo. Con NEW_TASK|CLEAR_TASK navega en el
     * sitio: inicio debajo y la ruta pedida encima (atrás vuelve a inicio).
     */
    private fun applyRoute(intent: Intent, route: String) {
        val uri = NAV_ROUTE_URI_PREFIX + route
        // MainActivity descarta cualquier otra URI de navegación (F-05).
        DemoHooks.allowedNavUri = uri
        intent.data = Uri.parse(uri)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
    }

    // ------------------------------------------------------------------ Contenedor

    private fun installUnsafe(app: Application, container: AppContainer, launch: DemoLaunch) {
        val demoDir = File(app.cacheDir, DEMO_DIR).apply {
            deleteRecursively()
            mkdirs()
        }

        // Controlador en memoria (sin red), marcador simulado y preferencias en el directorio de demo,
        // mediante la API explícita de AppContainer: nada toca el almacenamiento real del usuario.
        val clock = DemoOffsetClock()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val sync = SyncEngine(store = InMemorySyncQueueStore(), api = MockCaminoApi(latencyMillis = 0), clock = clock)
        val controller = CaminoController(
            catalog = FixtureStageCatalog(readAsset(app, "stages.json")),
            poiSource = FixturePoiSource(readAsset(app, "pois.json")),
            sessionStore = InMemorySessionStore(),
            sync = sync,
            clock = clock,
            ids = UuidGenerator,
            scope = scope,
        )
        // Marcador simulado: `isSimulated` → la pantalla SOS muestra DEMO y «Simulado: no se ha
        // abierto el marcador» (F-01); nunca «Marcador abierto».
        container.installDemo(controller = controller, dialer = FakeEmergencyDialer(), storageDir = demoDir)

        launch.theme?.let { container.setTheme(it) }
        // Aviso de esfera (§I): sólo se ofrece si se pide (demo.facehint=show).
        container.setFaceHint(if (launch.showFaceHint) FaceHintState.notDecided else FaceHintState.dismissed)

        // Siembra (en memoria; antes del primer frame).
        val ok = runBlocking {
            withTimeoutOrNull(SEED_TIMEOUT_MS) {
                controller.restore()
                seed(launch.scenario, controller, clock)
                true
            } ?: false
        }
        Log.i(TAG, if (ok) "Escenario ${launch.scenario.key} sembrado" else "Siembra incompleta (timeout)")
    }

    // ------------------------------------------------------------------ Siembra

    private suspend fun seed(scenario: DemoScenario, controller: CaminoController, clock: DemoOffsetClock) {
        when (scenario) {
            DemoScenario.IDLE -> Unit
            DemoScenario.ACTIVE -> seedActive(controller, clock, pause = false)
            DemoScenario.PAUSED -> seedActive(controller, clock, pause = true)
            DemoScenario.FINISHED -> seedFinished(controller, clock)
            DemoScenario.NEARBY -> seedNearby(controller, clock)
        }
    }

    private suspend fun startAt(controller: CaminoController, clock: DemoOffsetClock, stageId: String, offsetSeconds: Long): Boolean {
        clock.offsetSeconds = offsetSeconds
        val out = try {
            controller.start(stageId)
        } finally {
            clock.offsetSeconds = 0
        }
        if (out !is StartOutcome.Started) {
            Log.e(TAG, "No se pudo iniciar la etapa demo: $out")
            return false
        }
        return true
    }

    private suspend fun seedActive(controller: CaminoController, clock: DemoOffsetClock, pause: Boolean) {
        val now = Instant.now()
        if (!startAt(controller, clock, DemoData.ACTIVE_STAGE_ID, -DemoData.ACTIVE_ELAPSED_SECONDS)) return
        controller.updateSteps(DemoData.ACTIVE_STEPS)
        // Fixes entre 30 s después del inicio y 60 s antes de ahora (≈ 1,1 m/s).
        val fixes = DemoData.fixes(
            DemoData.interpolate(DemoData.activeWaypoints, maxStepMeters = 50.0),
            first = now.minusSeconds(DemoData.ACTIVE_ELAPSED_SECONDS - 30),
            last = now.minusSeconds(60),
            altitude = DemoData::activeAltitude,
        )
        for (fix in fixes) controller.updateLocation(fix)
        if (pause) {
            clock.offsetSeconds = -DemoData.PAUSED_SINCE_SECONDS
            try {
                controller.pause()
            } finally {
                clock.offsetSeconds = 0
            }
        }
    }

    private suspend fun seedNearby(controller: CaminoController, clock: DemoOffsetClock) {
        val now = Instant.now()
        if (!startAt(controller, clock, DemoData.NEARBY_STAGE_ID, -DemoData.NEARBY_ELAPSED_SECONDS)) return
        controller.updateSteps(DemoData.NEARBY_STEPS)
        val fixes = DemoData.fixes(
            DemoData.interpolate(DemoData.nearbyWaypoints, maxStepMeters = 50.0),
            first = now.minusSeconds(DemoData.NEARBY_ELAPSED_SECONDS - 30),
            last = now.minusSeconds(60),
            altitude = DemoData::nearbyAltitude,
        )
        for (fix in fixes) controller.updateLocation(fix)
    }

    private suspend fun seedFinished(controller: CaminoController, clock: DemoOffsetClock) {
        val now = Instant.now()
        val startedAt = now.plusSeconds(DemoData.FINISHED_START_OFFSET_SECONDS)
        if (!startAt(controller, clock, DemoData.ACTIVE_STAGE_ID, DemoData.FINISHED_START_OFFSET_SECONDS)) return
        // Durante la etapa el reloj «vive» en el pasado (límite de ritmo de avisos coherente).
        clock.offsetSeconds = DemoData.FINISHED_START_OFFSET_SECONDS
        try {
            controller.updateSteps(DemoData.FINISHED_STEPS)
            val fixes = DemoData.fixes(
                DemoData.interpolate(DemoData.finishedWaypoints, maxStepMeters = 100.0),
                first = startedAt.plusSeconds(30),
                last = startedAt.plusSeconds(DemoData.FINISHED_DURATION_SECONDS - 30),
                altitude = DemoData::finishedAltitude,
            )
            for (fix in fixes) controller.updateLocation(fix)
            clock.offsetSeconds = DemoData.FINISHED_START_OFFSET_SECONDS + DemoData.FINISHED_DURATION_SECONDS
            controller.finish()
        } finally {
            clock.offsetSeconds = 0
        }
    }

    // ------------------------------------------------------------------ Utilidades

    private fun readAsset(app: Application, name: String): String =
        app.assets.open(name).bufferedReader(Charsets.UTF_8).use { it.readText() }
}
