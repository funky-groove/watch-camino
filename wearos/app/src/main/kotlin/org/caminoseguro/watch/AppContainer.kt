package org.caminoseguro.watch

import android.app.Application
import android.util.Log
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.caminoseguro.watch.core.CaminoApi
import org.caminoseguro.watch.core.CaminoController
import org.caminoseguro.watch.core.CredentialStore
import org.caminoseguro.watch.core.EmergencyDialer
import org.caminoseguro.watch.core.FixturePoiSource
import org.caminoseguro.watch.core.FixtureStageCatalog
import org.caminoseguro.watch.core.MockCaminoApi
import org.caminoseguro.watch.core.PoiCategory
import org.caminoseguro.watch.core.SosController
import org.caminoseguro.watch.core.SyncEngine
import org.caminoseguro.watch.core.TelephonyCapability
import org.caminoseguro.watch.core.ThemeId
import org.caminoseguro.watch.core.UuidGenerator
import org.caminoseguro.watch.core.WallClock
import org.caminoseguro.watch.data.FileAlertPreferencesStore
import org.caminoseguro.watch.data.FileSessionStore
import org.caminoseguro.watch.data.FileStepCounterStore
import org.caminoseguro.watch.data.FileSyncQueueStore
import org.caminoseguro.watch.data.FileThemeStore
import org.caminoseguro.watch.platform.EmergencyLocationReader
import org.caminoseguro.watch.platform.PoiNotifier
import org.caminoseguro.watch.platform.SessionRuntime
import org.caminoseguro.watch.platform.SystemEmergencyDialer
import org.caminoseguro.watch.platform.TelephonyProbe
import org.caminoseguro.watch.security.KeystoreCredentialStore
import java.io.File

/** Composición manual de dependencias (sin framework de DI). */
class AppContainer(private val app: Application) {

    /**
     * V-01: ninguna excepción no capturada en una corrutina de la app puede cerrar el proceso (en
     * Android lo haría, también con una etapa en curso). Se registra (sin contenido) y se muestra
     * como error recuperable.
     */
    private val crashGuard = CoroutineExceptionHandler { _, e ->
        Log.e(TAG, "Error no capturado: ${e.javaClass.simpleName}")
        // Sólo se invoca desde corrutinas lanzadas después de construir el contenedor.
        controller.reportStorageFailure()
    }

    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default + crashGuard)

    val api: CaminoApi = ApiModule.create()

    /** Marca DEMO visible siempre que el adaptador sea MockCaminoApi (spec §10). */
    val isDemo: Boolean = api is MockCaminoApi

    /** Nada lo escribe en V1: la vinculación del reloj está bloqueada por contrato. */
    val credentials: CredentialStore by lazy { KeystoreCredentialStore(app) }

    private val dataDir: File = File(app.filesDir, "camino").apply { mkdirs() }

    private val syncEngine = SyncEngine(
        store = FileSyncQueueStore(File(dataDir, "sync_queue.json")),
        api = api,
        clock = WallClock,
    )

    /** Ajustes de avisos por categoría (V-08). */
    private val alertPrefs = FileAlertPreferencesStore(File(dataDir, "alert_categories.json"))

    val controller: CaminoController = CaminoController(
        catalog = FixtureStageCatalog(readAsset("stages.json")),
        poiSource = FixturePoiSource(readAsset("pois.json")),
        sessionStore = FileSessionStore(File(dataDir, "session.json")),
        sync = syncEngine,
        clock = WallClock,
        ids = UuidGenerator,
        scope = appScope,
    )

    val runtime: SessionRuntime = SessionRuntime(
        context = app,
        controller = controller,
        stepStore = FileStepCounterStore(File(dataDir, "step_counter.json")),
        notifier = PoiNotifier(app),
        scope = appScope,
    )

    // ---------------------------------------------------------------- SOS (sin sesión ni backend)

    /**
     * Marcador real (`ACTION_DIAL`) en TODAS las variantes, también Debug/DEMO: un SOS que no abre
     * el marcador en una build instalada en un reloj sería peligroso. `FakeEmergencyDialer` (core)
     * queda para tests JVM y capturas.
     */
    val emergencyDialer: EmergencyDialer = SystemEmergencyDialer(app)
    val sos: SosController = SosController(emergencyDialer)

    /** Sólo para el texto «Llamar al 112» / «Marcar 112» y el aviso; nunca bloquea. */
    val telephony: TelephonyCapability by lazy { TelephonyProbe.read(app) }
    val emergencyLocation: EmergencyLocationReader = EmergencyLocationReader(app)

    // ---------------------------------------------------------------- Tema (Negro/Perla)

    private val themeStore = FileThemeStore(File(dataDir, "theme.json"))
    private val _theme = MutableStateFlow(ThemeId.INITIAL)
    val theme: StateFlow<ThemeId> = _theme.asStateFlow()

    /** El usuario eligió tema antes de terminar la carga: no se pisa con el valor leído. */
    @Volatile private var themeChosen = false

    /** Cambia el tema y lo persiste. Un fallo de escritura no cierra la app (el tema sigue en memoria). */
    fun setTheme(theme: ThemeId) {
        themeChosen = true
        _theme.value = theme
        appScope.launch {
            try {
                themeStore.save(_theme.value) // siempre el último valor
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Tema no guardado: ${e.javaClass.simpleName}")
            }
        }
    }

    /** Restaura la sesión persistida y reengancha sensores/servicio si estaba activa. */
    fun boot() {
        appScope.launch {
            try {
                val saved = themeStore.load()
                if (!themeChosen) _theme.value = saved
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Tema no leído: ${e.javaClass.simpleName}")
            }
            try {
                controller.alertCategories = alertPrefs.load()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Ajustes de avisos no leídos: ${e.javaClass.simpleName}")
            }
            controller.restore()
            runtime.attach()
            // Arranque de la app ≈ vuelta a primer plano: disparador de sync de §7.
            controller.requestSync(manual = false)
        }
    }

    /** Activa/desactiva una categoría y la persiste. Un fallo de escritura no cierra la app. */
    fun setAlertCategory(category: PoiCategory, enabled: Boolean) {
        val next = if (enabled) controller.alertCategories + category else controller.alertCategories - category
        controller.alertCategories = next
        appScope.launch {
            try {
                alertPrefs.save(controller.alertCategories) // siempre el último valor
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Ajustes de avisos no guardados: ${e.javaClass.simpleName}")
                controller.reportStorageFailure()
            }
        }
    }

    private fun readAsset(name: String): String =
        app.assets.open(name).bufferedReader(Charsets.UTF_8).use { it.readText() }

    private companion object {
        const val TAG = "CaminoApp"
    }
}
