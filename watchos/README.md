# Camino Seguro Watch — watchOS

App **independiente** de Apple Watch (sin app iOS compañera) para peregrinos del Camino de Santiago.
La fuente de verdad es [`docs/WATCH_V1_SPEC.md`](../docs/WATCH_V1_SPEC.md); si este código diverge de ella,
el bug está aquí.

## Requisitos

- macOS con Xcode 16 (Swift 5.9+), SDK de watchOS 10 o posterior.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

## Generar y compilar

```sh
cd watchos

# 1. Núcleo puro: tests de conformidad + unitarios (no necesita simulador)
(cd CaminoCore && swift test)

# 2. Proyecto Xcode (se genera; no se versiona)
xcodegen generate

# 3. App para simulador
xcodebuild build \
  -project CaminoWatch.xcodeproj \
  -scheme CaminoWatch \
  -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' \
  CODE_SIGNING_ALLOWED=NO

# Release (usa BlockedCaminoApi)
xcodebuild build -project CaminoWatch.xcodeproj -scheme CaminoWatch \
  -configuration Release -destination 'generic/platform=watchOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Es lo mismo que ejecuta `.github/workflows/watchos.yml`. `xcodegen generate` también escribe
`CaminoWatch/Info.plist` a partir de `project.yml`: no se edita a mano.

Para ejecutar en un reloj real hay que poner un equipo de firma y cambiar el bundle id.
`org.caminoseguro.watch` es un **placeholder**.

## Estructura

```
watchos/
├── project.yml                 XcodeGen: target CaminoWatch (watchOS 10, watch-only) + paquete local
├── CaminoCore/                 Swift Package. Sólo Foundation: sin UI, sensores ni plataforma
│   ├── Sources/CaminoCore/
│   │   ├── Models.swift            §3: Stage, Poi, GeoPoint, LocationFix, StageSession, SessionSummary, SessionState
│   │   ├── SyncModels.swift        §7: SyncEvent, SendResult, SyncStatus, SyncQueueState
│   │   ├── Geo.swift               haversine con R = 6 371 008.8 m
│   │   ├── DistanceAccumulator.swift  §5
│   │   ├── PoiEngine.swift         §6
│   │   ├── StageSessionMachine.swift  §4: start / updateSteps / updateLocation / finish
│   │   ├── SyncEngine.swift        §7: cola FIFO, dead-letter, backoff con jitter inyectable
│   │   ├── Formatters.swift        §8: regla implementada a mano (sin NumberFormatter)
│   │   ├── Ports.swift             §9: StageCatalog, PoiSource, SessionStore, SyncQueueStore,
│   │   │                               CaminoApi, CredentialStore, CaminoClock, IdGenerator
│   │   ├── CaminoController.swift  servicio de aplicación: máquina + persistencia + sync
│   │   ├── CaminoJSON.swift        codificación de los ficheros locales
│   │   └── Adapters/               Fixture*, BlockedCaminoApi, MockCaminoApi, InMemory*,
│   │                                   SystemClock/FixedClock, SystemIdGenerator/SequentialIdGenerator
│   └── Tests/CaminoCoreTests/      un test por fichero de shared/conformance/ + unitarios
└── CaminoWatch/                App SwiftUI
    ├── CaminoWatchApp.swift, AppModel.swift, AppEnvironment.swift
    ├── L10n.swift + es.lproj/Localizable.strings   textos centralizados (base: español)
    ├── Accessibility.swift      textos que lee VoiceOver ("4,2 kilómetros restantes")
    ├── Views/                   Inicio, Elegir etapa, Etapa, Estadísticas, Resumen, Sincronización
    ├── Platform/                CLLocationManager, CMPedometer, notificaciones + háptica,
    │                                ficheros JSON protegidos, Keychain, os.Logger
    └── Assets.xcassets          AppIcon (vacío) y AccentColor
```

Las fixtures (`shared/fixtures/stages.json`, `pois.json`) se incluyen en el bundle **por referencia**
desde `project.yml`; no se copian. Los tests del núcleo leen `shared/conformance/*.json` y
`shared/fixtures/*.json` directamente del repositorio (ruta relativa a `#filePath`).

## Qué está bloqueado por contrato y por qué

No existe en el repositorio ningún contrato del backend (`contracts/README.md`). Por eso:

| Pieza | Estado V1 |
|---|---|
| Envío de eventos | Sólo a través del puerto `CaminoApi`. **Release → `BlockedCaminoApi`** (siempre `Blocked`, los eventos se quedan en la cola sin perderse). **Debug → `MockCaminoApi`** (acepta todo tras una latencia simulada) y la UI muestra la marca **DEMO**. La selección es `#if DEBUG` en `AppEnvironment.swift`. |
| Cliente HTTP, URLs, endpoints, schemas, JWT | No existen. No se inventan. |
| Vinculación / login (`Unauthorized` → `needsLink`) | El estado existe y se muestra ("Necesita vincular"), pero no hay flujo. |
| `KeychainCredentialStore` | Implementado (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), pero nada lo escribe en V1. |
| Etapas y POIs | Fixtures **de demostración con coordenadas aproximadas**. No sirven para orientarse. |
| Estado `offline` | Existe en `SyncStatus` por paridad con la spec, pero ningún adaptador V1 lo produce (no hay red). |

Cuando llegue el contrato se añade un `HttpCaminoApi` que implemente `CaminoApi`, sin tocar el dominio.

## Comportamiento en el reloj

- Permisos (ubicación, movimiento, notificaciones) se piden al pulsar **«Iniciar trayecto»**, no al abrir.
- SOS (spec §10.1): botón «SOS» en la cabecera → pantalla `SOSView` con «Llamar al 112»
  (`SystemEmergencyDialer` → `WKApplication.shared().openSystemURL(tel:112)`, con confirmación del sistema).
  Los escenarios DEMO (`-demo.scenario`, `-demo.route sos`) usan `MockEmergencyDialer`: no abren nada.
  Verificación por nivel (tests / simulador / hardware): `docs/accessibility/SOS_CAPABILITY_MATRIX.md`.
- Idiomas: español (base) e inglés. `python3 tools/gen_strings.py` genera `es.lproj` (desde el código) y
  `en.lproj` (desde `tools/strings_en.json`); `--check` falla si falta una clave en inglés.
- Sensores sólo con etapa activa. Ubicación: `kCLLocationAccuracyNearestTenMeters`, `distanceFilter` 20 m,
  intervalo mínimo 10 s, `allowsBackgroundLocationUpdates` sólo mientras hay etapa (background mode `location`).
- Pasos: `CMPedometer.startUpdates(from: startedAt)`. Tras relanzar se vuelve a consultar desde `startedAt`.
- Estado persistido en cada transición en Application Support (`session.json`, `sync-queue.json`) con
  `FileProtectionType.completeUntilFirstUserAuthentication`. Al relanzar se restaura la etapa activa y se
  reenganchan los sensores. Un fichero ilegible se aparta (`*.corrupt-<t>.json`) y se arranca en limpio.
- Sincronización: tras empezar, tras finalizar, al volver a primer plano y con el botón "Sincronizar ahora"
  (que ignora el backoff). La "recuperación de red" de §7 no se implementa: en V1 no hay red que vigilar.
- Logs con `os.Logger`: sin coordenadas, tokens ni identificadores.
- Sin HealthKit, sin complicación (llegará tras la V1 verde).
