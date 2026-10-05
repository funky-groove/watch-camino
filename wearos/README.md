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

- Permisos pedidos al pulsar **Comenzar etapa** (no al abrir). Si se deniegan, la etapa empieza
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
