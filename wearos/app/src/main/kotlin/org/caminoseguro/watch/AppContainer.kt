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
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.caminoseguro.watch.complication.ComplicationUpdates
import org.caminoseguro.watch.core.AppLanguage
import org.caminoseguro.watch.core.BlockedBrandAssetSource
import org.caminoseguro.watch.core.BrandAssetRepository
import org.caminoseguro.watch.core.CaminoApi
import org.caminoseguro.watch.core.CaminoController
import org.caminoseguro.watch.core.CredentialStore
import org.caminoseguro.watch.core.DisplayFormat
import org.caminoseguro.watch.core.DisplayPreferences
import org.caminoseguro.watch.core.EmergencyDialer
import org.caminoseguro.watch.core.FaceHintState
import org.caminoseguro.watch.core.FileBrandAssetStore
import org.caminoseguro.watch.core.FixturePoiSource
import org.caminoseguro.watch.core.FixtureStageCatalog
import org.caminoseguro.watch.core.MockCaminoApi
import org.caminoseguro.watch.core.PaceMode
import org.caminoseguro.watch.core.Poi
import org.caminoseguro.watch.core.PoiCategory
import org.caminoseguro.watch.core.SosController
import org.caminoseguro.watch.core.SyncEngine
import org.caminoseguro.watch.core.TelephonyCapability
import org.caminoseguro.watch.core.ThemeId
import org.caminoseguro.watch.core.UnitSystem
import org.caminoseguro.watch.core.UuidGenerator
import org.caminoseguro.watch.core.WallClock
import org.caminoseguro.watch.data.FileAlertPreferencesStore
import org.caminoseguro.watch.data.FileDisplayPreferencesStore
import org.caminoseguro.watch.data.FileFaceHintStore
import org.caminoseguro.watch.data.FileSessionStore
import org.caminoseguro.watch.data.FileStepCounterStore
import org.caminoseguro.watch.data.FileSyncQueueStore
import org.caminoseguro.watch.data.FileThemeStore
import org.caminoseguro.watch.platform.AppLocale
import org.caminoseguro.watch.platform.BrandBitmaps
import org.caminoseguro.watch.platform.EmergencyLocationReader
import org.caminoseguro.watch.platform.PoiNotifier
import org.caminoseguro.watch.platform.SessionRuntime
import org.caminoseguro.watch.platform.SystemEmergencyDialer
import org.caminoseguro.watch.platform.TelephonyProbe
import org.caminoseguro.watch.security.KeystoreCredentialStore
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

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
    private var alertPrefs = FileAlertPreferencesStore(File(dataDir, "alert_categories.json"))

    /** POIs empaquetados (DATOS DE DEMOSTRACIÓN, coordenadas aproximadas). */
    private val poiSource = FixturePoiSource(readAsset("pois.json"))

    /** Todos los lugares de demostración (Lugares sin trayecto). */
    val allPois: List<Poi> get() = poiSource.allPois()

    /**
     * `false` cuando un escenario DEMO ([installDemo]) usa almacenes en memoria: el resumen no dice
     * entonces «Guardado en el reloj» (F-09).
     */
    @Volatile var sessionPersisted: Boolean = true
        private set

    /** Controlador del trayecto. Sólo [installDemo] (escenarios Debug) lo sustituye. */
    var controller: CaminoController = CaminoController(
        catalog = FixtureStageCatalog(readAsset("stages.json")),
        poiSource = poiSource,
        sessionStore = FileSessionStore(File(dataDir, "session.json")),
        sync = syncEngine,
        clock = WallClock,
        ids = UuidGenerator,
        scope = appScope,
    )
        private set

    // ---------------------------------------------------------------- Unidades e idioma (V1.1 §G)

    private var displayPrefsStore = FileDisplayPreferencesStore(File(dataDir, "display_prefs.json"))
    private val _displayPreferences = MutableStateFlow(DisplayPreferences())
    val displayPreferences: StateFlow<DisplayPreferences> = _displayPreferences.asStateFlow()
    @Volatile private var displayPrefsChosen = false

    /**
     * Idioma efectivo (el de los recursos). Lo fija el sistema (LocaleManager en API 33+ o el idioma
     * del reloj); [refreshLanguage] lo vuelve a leer al crear la actividad o al cambiarlo.
     */
    private val _language = MutableStateFlow(AppLocale.effective(app))
    val language: StateFlow<AppLanguage> = _language.asStateFlow()

    /** Formato de todas las cifras (pantalla, TalkBack, notificaciones y complicación). */
    val displayFormat: StateFlow<DisplayFormat> =
        combine(_displayPreferences, _language) { prefs, lang -> DisplayFormat.of(prefs, lang) }
            .stateIn(appScope, SharingStarted.Eagerly, DisplayFormat.of(DisplayPreferences(), _language.value))

    fun setUnits(units: UnitSystem) = updateDisplayPreferences { it.copy(units = units) }

    fun setPaceMode(mode: PaceMode) = updateDisplayPreferences { it.copy(paceMode = mode) }

    private fun updateDisplayPreferences(change: (DisplayPreferences) -> DisplayPreferences) {
        displayPrefsChosen = true
        _displayPreferences.value = change(_displayPreferences.value)
        appScope.launch {
            try {
                displayPrefsStore.save(_displayPreferences.value) // siempre el último valor
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Unidades no guardadas: ${e.javaClass.simpleName}")
            }
        }
    }

    /** Relee el idioma efectivo (la actividad se recrea al cambiarlo con LocaleManager). */
    fun refreshLanguage(effective: AppLanguage = AppLocale.effective(app)) {
        if (_language.value != effective) {
            _language.value = effective
            complications.requestNow()
        }
    }

    /** Idioma elegido en la app (null = el del reloj). Sólo API 33+; en API 30–32 no hace nada. */
    fun setLanguage(language: AppLanguage?) {
        AppLocale.choose(app, language)
    }

    val runtime: SessionRuntime = SessionRuntime(
        context = app,
        controller = controller,
        stepStore = FileStepCounterStore(File(dataDir, "step_counter.json")),
        notifier = PoiNotifier(app) { displayFormat.value },
        scope = appScope,
    )

    /** Complicación de esfera: peticiones de actualización por eventos (V1.1 §H). */
    val complications: ComplicationUpdates = ComplicationUpdates(app, appScope)

    // ---------------------------------------------------------------- Aviso «Accede desde tu esfera» (§I)

    private var faceHintStore = FileFaceHintStore(File(dataDir, "face_hint.json"))
    private val _faceHint = MutableStateFlow(FaceHintState.notDecided)
    @Volatile private var faceHintChosen = false
    @Volatile private var alertsChosen = false
    val faceHint: StateFlow<FaceHintState> = _faceHint.asStateFlow()
    private val _faceHintLoaded = MutableStateFlow(false)

    /** El estado del aviso se ha leído (hasta entonces no se ofrece). */
    val faceHintLoaded: StateFlow<Boolean> = _faceHintLoaded.asStateFlow()

    /** En este arranque se restauró un trayecto activo: el aviso se aplaza hasta otro arranque. */
    private val _restoredActiveThisLaunch = MutableStateFlow(false)
    val restoredActiveThisLaunch: StateFlow<Boolean> = _restoredActiveThisLaunch.asStateFlow()

    /** Guarda la decisión («Ahora no» → dismissed, «Cómo añadirlo» → helpOpened). */
    fun setFaceHint(state: FaceHintState) {
        faceHintChosen = true
        _faceHint.value = state
        appScope.launch {
            try {
                faceHintStore.save(state)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Aviso de esfera no guardado: ${e.javaClass.simpleName}")
            }
        }
    }

    // ---------------------------------------------------------------- Bienvenida visual (§K)

    /**
     * Caché del recurso de marca. El origen remoto está BLOQUEADO ([BlockedBrandAssetSource]: no
     * descarga nada y el manifiesto no declara INTERNET), así que en la práctica se usa siempre el
     * logo incluido. Al abrir sólo se lee la caché local ([BrandAssetRepository.current], en IO).
     */
    val brandAssets: BrandAssetRepository = BrandAssetRepository(
        store = FileBrandAssetStore(File(dataDir, "brand")),
        source = BlockedBrandAssetSource,
        clock = WallClock,
        decodable = BrandBitmaps::canDecode,
    )

    private val brandRefreshRequested = AtomicBoolean(false)

    /** Refresco del recurso de marca SÓLO en segundo plano (al salir de la app), una vez por proceso. */
    fun refreshBrandAssetInBackground() {
        if (!brandRefreshRequested.compareAndSet(false, true)) return
        appScope.launch(Dispatchers.IO) {
            val outcome = brandAssets.refresh()
            Log.i(TAG, "Recurso de marca: $outcome")
        }
    }

    private val activityCreatedOnce = AtomicBoolean(false)

    /**
     * §K.2 (1): apertura desde cero = primer `onCreate` de la actividad en este proceso y sin
     * estado guardado (una recreación por idioma/configuración no cuenta). Se consume al llamarla.
     */
    fun takeColdStart(hasSavedState: Boolean): Boolean =
        !activityCreatedOnce.getAndSet(true) && !hasSavedState

    /** §K.2 (4): la bienvenida ya se mostró en este proceso. */
    @Volatile var welcomeShown: Boolean = false

    // ---------------------------------------------------------------- SOS (sin sesión ni backend)

    /**
     * Marcador real (`ACTION_DIAL`) en Release y en Debug normal (sin escenario). SÓLO los
     * escenarios DEMO de Debug ([installDemo], lanzados con el extra `demo.scenario`) lo sustituyen
     * por `FakeEmergencyDialer`, que no abre nada: entonces la pantalla SOS muestra la marca DEMO y
     * «Simulado: no se ha abierto el marcador» (`EmergencyDialer.isSimulated`), nunca «Marcador
     * abierto». Los tests JVM también usan el simulado.
     */
    var emergencyDialer: EmergencyDialer = SystemEmergencyDialer(app)
        private set
    var sos: SosController = SosController(emergencyDialer)
        private set

    /** Sólo para el texto «Llamar al 112» / «Marcar 112» y el aviso; nunca bloquea. */
    val telephony: TelephonyCapability by lazy { TelephonyProbe.read(app) }
    val emergencyLocation: EmergencyLocationReader = EmergencyLocationReader(app)

    // ---------------------------------------------------------------- Tema (Negro/Perla)

    private var themeStore = FileThemeStore(File(dataDir, "theme.json"))
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
                val saved = displayPrefsStore.load()
                if (!displayPrefsChosen) _displayPreferences.value = saved
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Unidades no leídas: ${e.javaClass.simpleName}")
            }
            try {
                val saved = faceHintStore.load()
                // Si el usuario (o un escenario demo) ya decidió en esta ejecución, no se pisa.
                if (!faceHintChosen) _faceHint.value = saved
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Aviso de esfera no leído: ${e.javaClass.simpleName}")
            }
            _faceHintLoaded.value = true
            try {
                val saved = alertPrefs.load()
                if (!alertsChosen) controller.alertCategories = saved
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "Ajustes de avisos no leídos: ${e.javaClass.simpleName}")
            }
            controller.restore()
            if (controller.snapshot.value.activeSession != null) _restoredActiveThisLaunch.value = true
            runtime.attach()
            complications.observe(controller.snapshot, displayFormat)
            // Arranque de la app ≈ vuelta a primer plano: disparador de sync de §7.
            controller.requestSync(manual = false)
        }
    }

    /** Activa/desactiva una categoría y la persiste. Un fallo de escritura no cierra la app. */
    fun setAlertCategory(category: PoiCategory, enabled: Boolean) {
        alertsChosen = true
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

    // ---------------------------------------------------------------- Escenarios de demostración

    /**
     * API explícita para escenarios de demostración/capturas (la usa SÓLO `src/debug` a través de
     * [DemoHooks] o de su inicializador; en `main` nada la llama). Debe invocarse ANTES de crear el
     * ViewModel (p. ej. en `onActivityPreCreated` o desde `DemoHooks.apply`, que `MainActivity`
     * llama antes de `setContent`):
     * - sustituye el controlador (p. ej. uno con almacenes en memoria y reloj desplazable);
     * - sustituye el marcador de emergencia (p. ej. `FakeEmergencyDialer`: SOS no abre nada y la
     *   pantalla lo marca DEMO/«Simulado») y el SOS;
     * - mueve TODOS los almacenes de preferencias (tema, avisos, unidades, aviso de esfera) a
     *   [storageDir], para no escribir nunca en el almacenamiento real del usuario;
     * - deja las preferencias en memoria en sus valores iniciales (Negro, todas las categorías,
     *   métrico + ritmo, aviso sin decidir) y marcadas como elegidas, para que una carga en curso
     *   de `boot()` no las pise. Después se pueden fijar con [setTheme], [setUnits], [setPaceMode],
     *   [setFaceHint] y [setAlertCategory] (persisten ya en [storageDir]).
     * Los sensores reales ([runtime]) y la complicación siguen ligados al controlador original.
     */
    fun installDemo(controller: CaminoController, dialer: EmergencyDialer, storageDir: File) {
        storageDir.mkdirs()
        themeStore = FileThemeStore(File(storageDir, "theme.json"))
        alertPrefs = FileAlertPreferencesStore(File(storageDir, "alert_categories.json"))
        displayPrefsStore = FileDisplayPreferencesStore(File(storageDir, "display_prefs.json"))
        faceHintStore = FileFaceHintStore(File(storageDir, "face_hint.json"))
        themeChosen = true
        _theme.value = ThemeId.INITIAL
        displayPrefsChosen = true
        _displayPreferences.value = DisplayPreferences()
        faceHintChosen = true
        _faceHint.value = FaceHintState.notDecided
        _faceHintLoaded.value = true
        alertsChosen = true
        _restoredActiveThisLaunch.value = false
        emergencyDialer = dialer
        sos = SosController(dialer)
        controller.alertCategories = PoiCategory.entries.toSet()
        sessionPersisted = false
        this.controller = controller
    }

    private fun readAsset(name: String): String =
        app.assets.open(name).bufferedReader(Charsets.UTF_8).use { it.readText() }

    private companion object {
        const val TAG = "CaminoApp"
    }
}
