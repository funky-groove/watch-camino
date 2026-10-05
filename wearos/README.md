# Camino Seguro Watch — Wear OS

App **independiente** de Wear OS (Compose for Wear OS) para peregrinos del Camino de Santiago.
Fuente de verdad: [`docs/WATCH_V1_SPEC.md`](../docs/WATCH_V1_SPEC.md). Si el código diverge de la
spec, el bug está en el código.

## Compilar y probar

Requisitos: JDK 17+ (CI usa 17). El wrapper descarga Gradle 8.11.1.

```bash
cd wearos

# Núcleo (Kotlin/JVM puro): conformidad + tests propios. Funciona SIN Android SDK ni Google Maven.
./gradlew -PcoreOnly=true :core:test

# Con Android SDK (lo que hace .github/workflows/wearos.yml):
./gradlew :core:test
./gradlew :app:testDebugUnitTest
./gradlew :app:assembleDebug :app:assembleRelease
./gradlew :app:lintDebug
```

### `-PcoreOnly=true`

Para entornos sin Android SDK o sin acceso a `dl.google.com` / `maven.google.com`:

- `settings.gradle.kts` sólo incluye `:core` (no `:app`).
- `build.gradle.kts` no añade AGP ni el plugin de Compose al classpath ni declara el repositorio
  de Google, así que no se resuelve nada de Google Maven.

Sin la propiedad se incluyen `:core` y `:app` (necesita Android SDK + Google Maven).

### Cómo se cargan los plugins

AGP y los plugins de Kotlin van en el `buildscript` raíz (classpath compartido), no en bloques
`plugins { … version … }` por módulo, para que AGP y el plugin de Kotlin compartan classloader y
para poder omitir AGP condicionalmente con `coreOnly`. Las versiones están en
`gradle/libs.versions.toml`.

## Estructura

```
wearos/
├── core/                       Kotlin/JVM puro (sin Android) — org.caminoseguro.watch.core
│   ├── Models.kt               §3 modelos @Serializable (Instant ↔ ISO-8601)
│   ├── StageMachine.kt         §4 máquina de estados (start/updateSteps/updateLocation/finish)
│   ├── DistanceAccumulator.kt  §5 acumulador de distancia
│   ├── Geo.kt                  haversine, R = 6 371 008.8 m
│   ├── PoiAlertEngine.kt       §6 avisos POI
│   ├── SyncModels.kt, SyncEngine.kt, Backoff.kt   §7 cola offline-first, backoff + jitter inyectable,
│   │                           un solo sync en vuelo (Mutex)
│   ├── Formatters.kt           §8 distancia/duración/pasos (regla implementada a mano) + variantes habladas
│   ├── Ports.kt                §9 puertos (StageCatalog, PoiSource, SessionStore, SyncQueueStore,
│   │                           CaminoApi, CredentialStore, Clock, IdGenerator, JitterSource)
│   ├── Adapters.kt             FixtureStageCatalog, FixturePoiSource, BlockedCaminoApi, MockCaminoApi,
│   │                           stores en memoria, relojes, generadores de id
│   ├── StepCounterNormalizer.kt  baseline/offset de TYPE_STEP_COUNTER (reinicios del reloj)
│   ├── CaminoStats.kt          estadísticas, etapa sugerida, km restantes
│   ├── TripFigures.kt          cifras del trayecto sin ceros falsos + ActionGate (sin doble inicio)
│   ├── EmergencyInfo.kt        SOS: EmergencyNumber (112 ES/UE), DialResult, EmergencyDialer,
│   │                           FakeEmergencyDialer, EmergencyLocationSummary (paridad watchOS)
│   ├── SosPresentation.kt      SosController + texto «Llamar/Marcar 112» y mensajes honestos
│   ├── DesignTokens.kt         paleta Negro/Perla (mismos hex que watchOS) + requisitos de contraste
│   └── CaminoController.kt     servicio de aplicación: máquina + stores + sync con StateFlow
│   └── src/test/               un test por fichero de shared/conformance/*.json + tests propios
└── app/                        Wear OS (minSdk 30, target/compileSdk 35)
    ├── src/main/…/ui/          Compose for Wear OS: Inicio, Elegir etapa, Confirmar, Etapa activa,
    │                           Finalizar (confirmación), Resumen, Estadísticas, Sincronización
    ├── src/main/…/platform/    LocationManager, sensor de pasos, foreground service `location`,
    │                           notificaciones/canales, permisos, SessionRuntime
    ├── src/main/…/data/        persistencia JSON atómica en filesDir
    ├── src/main/…/security/    KeystoreCredentialStore (AES-256/GCM, clave en Android Keystore)
    ├── src/debug/…/ApiModule.kt    MockCaminoApi  → la UI muestra "DEMO"
    └── src/release/…/ApiModule.kt  BlockedCaminoApi
```

Los tests del núcleo leen los vectores **directamente** de `../shared/conformance` (ruta absoluta
pasada por la tarea `test` como `-Dcamino.conformanceDir`; si no, se busca subiendo directorios).
Las fixtures `../shared/fixtures/*.json` se empaquetan en el APK como assets
(`sourceSets.main.assets.srcDir`), sin copiarlas.

`applicationId`/`namespace` = `org.caminoseguro.watch` es un **placeholder** hasta que exista
identidad de publicación. Release no se firma (APK unsigned en CI) y no se minifica en V1.

## Qué está bloqueado por contrato y por qué

No existe contrato del backend (`contracts/README.md`). Por eso:

- **No hay cliente HTTP, endpoints, URLs, JWT, auth ni Premium.** Toda llamada remota pasa por
  `CaminoApi`.
- **Release usa `BlockedCaminoApi`**: devuelve siempre `Blocked`; los eventos se quedan en la cola
  local (no se pierde ninguno) y la UI muestra "Pendiente de backend".
- **Debug usa `MockCaminoApi`** (acepta todo tras una latencia simulada) y la UI muestra **DEMO**.
- **Sin permiso `INTERNET`** (ni en Debug): no hay nada a lo que conectarse. Por lo mismo, no hay
  monitor de red y el estado `Sin conexión` (`SyncStatus.Offline`) existe pero V1 nunca lo produce.
- **Vinculación del reloj (`Unauthorized` → "Necesita vincular")**: el flujo no existe;
  `KeystoreCredentialStore` está implementado pero nada escribe en él.
- **Etapas y POIs** son fixtures de demostración con coordenadas aproximadas.

Cuando llegue el contrato se añade un adaptador `HttpCaminoApi` en `src/release` (y el permiso
`INTERNET`) sin tocar el núcleo.

## Plataforma (resumen)

- Permisos pedidos al pulsar **Iniciar trayecto** (no al abrir). Si se deniegan, la etapa empieza
  igual y la pantalla de etapa dice qué falta (sin ubicación: ni distancia ni avisos; sin actividad:
  sin pasos; sin notificaciones: avisos sólo en pantalla).
- Sensores y foreground service (`location`, notificación en curso) **sólo** con sesión activa.
  Sin permiso de ubicación no se arranca el servicio (Android 14 lo prohíbe); los pasos se cuentan
  mientras viva el proceso.
- Ubicación: `FUSED_PROVIDER` (API ≥ 31) o `GPS_PROVIDER`; 10 s / 20 m.
- Pasos: `TYPE_STEP_COUNTER` + `StepCounterNormalizer` (baseline/offset persistidos; reinicio
  detectado por `Settings.Global.BOOT_COUNT` o porque el contador baja).
- Avisos POI: notificación en canal de alta importancia con vibración del canal (sin permiso
  `VIBRATE`) + háptica en pantalla.
- Persistencia: JSON con `AtomicFile` en `filesDir/camino/`; `allowBackup=false` y
  `dataExtractionRules` que excluyen todo; `cleartextTrafficPermitted=false`.
- Restauración: al relanzar se restaura la sesión `Active` y se reenganchan sensores y servicio.
  Sync al arrancar y al volver a primer plano.
- Logs sin coordenadas, tokens ni identificadores.

## Trayecto y SOS

- **Pantalla principal** (ruta `home`): sin trayecto, «Iniciar trayecto» (lleva a elegir etapa;
  deshabilitado tras el primer toque + `ActionGate` en el ViewModel) y estado real de permisos; con
  trayecto, cifras (restante, recorrido, pasos, tiempo; «sin datos» en vez de ceros falsos) en una
  `ScalingLazyColumn` (corona/bisel por defecto en Wear Compose 1.4) y, al final tras un divisor,
  «Finalizar trayecto» (confirmación; cancelar conserva los datos).
- **«SOS»** fijo arriba a la derecha, fuera de la lista (`TripScaffold`): bajo TimeText, fondo opaco,
  hueco reservado con `contentPadding` medido, objetivo ≥ 48×48 dp, rojo `critical` (≥ 4,5:1 en ambos
  temas). Abre la ruta `sos`; se vuelve con el gesto/atrás del sistema o «Volver». La posición de
  scroll de Inicio se conserva (`rememberScalingLazyListState` en la ruta `home`).
- **Pantalla SOS**: «Llamar al 112» (o «Marcar 112» si el reloj no declara llamadas) →
  `Intent.ACTION_DIAL tel:112` (`SystemEmergencyDialer`). **Nunca** `ACTION_CALL` ni `CALL_PHONE`
  ("ACTION_CALL cannot be used to call emergency numbers"). `<queries>` DIAL+`tel` en el manifest.
  `FEATURE_TELEPHONY(_CALLING)` sólo cambia el texto/aviso, nunca bloquea. Mensajes honestos
  («Marcador abierto con el 112. Pulsa llamar si es seguro.»). Debajo: ubicación breve (última
  conocida + una lectura `getCurrentLocation`, sin pedir permiso; no se envía a ningún sitio),
  «112: España y UE», ayuda genérica del SOS del reloj («varía según el fabricante») y satélite
  (sólo se menciona). No pausa ni finaliza el trayecto; funciona sin sesión ni backend. No hay
  continuación en el móvil (`RemoteActivityHelper` sólo admite `ACTION_VIEW`).
- **Debug/DEMO usa el marcador real**: `FakeEmergencyDialer` es sólo para tests.
- Estado de verificación: [`docs/accessibility/SOS_CAPABILITY_MATRIX.md`](../docs/accessibility/SOS_CAPABILITY_MATRIX.md).

## Temas e idiomas

- Temas **Negro** (por defecto) y **Perla**, elegidos en Ajustes y persistidos en `theme.json`.
  `ui/Theme.kt` traduce `core/DesignTokens.kt` a `MaterialTheme` de Wear; el contraste y la paridad
  de hex con `watchos/.../DesignTokens.swift` se comprueban en `DesignTokensTest` (JVM).
- Español (`values/`, `tools:locale="es"`) e inglés (`values-en/`) con todas las cadenas.
  `AppResourcesTest` (en `:core`, sin Android SDK) comprueba claves y marcadores iguales, apóstrofos
  escapados, que toda `R.string.x` usada existe y que los textos SOS son honestos.

## V1.1: trayecto completo, Lugares, complicación

- **Trayecto activo** (spec V1.1 §B): estadísticas principales (distancia, tiempo en movimiento,
  ritmo/velocidad, «En marcha»/«Pausado») → altitud/subida/bajada (GPS) → perfil registrado (Canvas,
  sin unir huecos) → lugares útiles (máx. 3, "en línea recta") → «Pausar»/«Reanudar» → «Finalizar trayecto».
- **Preferencias**: unidades y ritmo/velocidad en `filesDir/camino/display_prefs.json`; idioma por app
  con `LocaleManager` (API 33+, `res/xml/locales_config.xml`); en API 30–32 sigue el idioma del reloj.
  Todas las cifras (pantalla, TalkBack, notificaciones, complicación) pasan por `core/DisplayFormat`.
- **Complicación** (`complication/CaminoComplicationService`, `watchface-complications-data-source-ktx`
  1.2.1): SHORT_TEXT, LONG_TEXT, MONOCHROMATIC_IMAGE y RANGED_VALUE. Lee el estado local del
  controlador (sin red). `UPDATE_PERIOD_SECONDS=0`; `ComplicationUpdates` pide `requestUpdateAll()` al
  empezar/pausar/reanudar/finalizar o cambiar unidades/idioma, y por distancia como mucho cada 5 min.
  **El sistema decide cuándo consulta y repinta la esfera**: la complicación puede ir con retraso.
  Tocarla abre Trayecto (`PendingIntent` inmutable); nunca inicia un trayecto ni una llamada.
- **Aviso «Accede desde tu esfera»** (`face_hint.json`: notDecided/dismissed/helpOpened) e
  instrucciones manuales: no hay API pública verificada para abrir el editor de esfera.
- **Escenarios de demostración** (sólo Debug): `DemoHooks.apply` (null en `main`) lo invoca
  `MainActivity.onCreate` antes de `setContent`; `AppContainer.installDemo(controller, dialer, storageDir)`
  sustituye controlador, marcador y almacenes de preferencias sin tocar los datos reales.

## Bienvenida visual (spec §K)

- **Núcleo** (`core/BrandAsset.kt`, tests `BrandAssetTest`): `BrandAssetValidator` (0 < bytes ≤ 512 KiB,
  firma PNG, IHDR legible con CRC, cuadrada 256–2048 px, `sha256` del manifiesto si lo hay),
  `BrandAssetCacheMeta`, `BrandAssetRepository` (al abrir lee sólo la caché; `refresh()` descarga a un
  temporal, valida + decodificación de plataforma y sustituye atómicamente; un recurso inválido nunca
  reemplaza a uno válido), `WelcomePolicy.shouldShow` y `WelcomeTiming` (0,6 s visible + 0,4 s fundido).
- **Origen remoto BLOQUEADO**: `BlockedBrandAssetSource` no descarga nada y no se declara `INTERNET`;
  la app muestra siempre el logo incluido (`res/drawable-nodpi/brand_logo.png`, concha de cruz roja).
  Caché en `filesDir/camino/brand/`; el refresco sólo se pide al pasar a segundo plano (`onStop`).
- **Presentación** (`ui/Welcome.kt`): capa negra sobre la interfaz ya compuesta; no consume toques
  (un toque la retira), sin semántica para TalkBack. Con escala de animaciones 0 («Quitar
  animaciones») se retira de golpe a los 0,6 s. Sólo en arranque en frío, sin trayecto activo ni
  restaurado, sin enlace directo (complicación, notificación, datos de navegación) ni SOS, una vez por
  proceso. Splash del sistema intacto.
- **Demo**: los escenarios no la muestran salvo `--es demo.welcome show` (se mantiene hasta un toque);
  `scripts/screenshots.sh` captura `bienvenida` (negro).
