package org.caminoseguro.watch

import android.app.Application
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.caminoseguro.watch.core.CaminoApi
import org.caminoseguro.watch.core.CaminoController
import org.caminoseguro.watch.core.CredentialStore
import org.caminoseguro.watch.core.FixturePoiSource
import org.caminoseguro.watch.core.FixtureStageCatalog
import org.caminoseguro.watch.core.MockCaminoApi
import org.caminoseguro.watch.core.SyncEngine
import org.caminoseguro.watch.core.UuidGenerator
import org.caminoseguro.watch.core.WallClock
import org.caminoseguro.watch.data.FileSessionStore
import org.caminoseguro.watch.data.FileStepCounterStore
import org.caminoseguro.watch.data.FileSyncQueueStore
import org.caminoseguro.watch.platform.PoiNotifier
import org.caminoseguro.watch.platform.SessionRuntime
import org.caminoseguro.watch.security.KeystoreCredentialStore
import java.io.File

/** Composición manual de dependencias (sin framework de DI). */
class AppContainer(private val app: Application) {

    val appScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

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

    /** Restaura la sesión persistida y reengancha sensores/servicio si estaba activa. */
    fun boot() {
        appScope.launch {
            controller.restore()
            runtime.attach()
            // Arranque de la app ≈ vuelta a primer plano: disparador de sync de §7.
            controller.requestSync(manual = false)
        }
    }

    private fun readAsset(name: String): String =
        app.assets.open(name).bufferedReader(Charsets.UTF_8).use { it.readText() }
}
