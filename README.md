# Camino Seguro Watch

Apps oficiales de reloj de **Camino Seguro** para peregrinos del Camino de Santiago:

| Plataforma | Carpeta | Stack |
|---|---|---|
| Apple Watch (watchOS 10+) | [`watchos/`](watchos/) | Swift, SwiftUI, CoreLocation, CoreMotion, UserNotifications, Keychain |
| Wear OS 3+ | [`wearos/`](wearos/) | Kotlin, Compose for Wear OS, Coroutines, Android Keystore |

Las dos son clientes **independientes del teléfono**: hablan directamente con la API de Camino Seguro.
El móvil podrá ser una optimización futura, nunca una dependencia.

Principio UX: **levantar muñeca → entender → actuar.**

## Alcance V1

Comenzar etapa · Consultar etapa · Ver estadísticas · Recibir avisos POI · Finalizar etapa · Sincronizar.
Nada de navegación turn-by-turn, mapas, social ni administración.

## Estado

> **Contrato del backend: AUSENTE.** Ver [`contracts/README.md`](contracts/README.md).
> Las apps funcionan completas en local con datos de demostración; la integración remota está
> bloqueada explícitamente (`BlockedCaminoApi` en Release) hasta que se aporte el contrato real.

## Documentos

- [`docs/WATCH_V1_SPEC.md`](docs/WATCH_V1_SPEC.md) — especificación compartida (fuente de verdad).
- [`shared/conformance/`](shared/conformance/) — vectores ejecutables que ambas plataformas deben pasar.
- [`shared/fixtures/`](shared/fixtures/) — etapas y POIs de demostración (coordenadas aproximadas).

## Compilación y CI

GitHub Actions compila y testea ambas apps en cada push:

- `watchOS` (macOS runner): `swift test` del núcleo + `xcodebuild` Debug y Release para simulador.
- `Wear OS` (Ubuntu runner): tests del núcleo + `assembleDebug`/`assembleRelease` + lint.
