# Camino Seguro Watch — Especificación compartida V1 (A1)

Fuente única de verdad para **watchOS** (`watchos/`) y **Wear OS** (`wearos/`).
Si una implementación diverge de este documento, el bug está en la implementación.
Las reglas numéricas están fijadas además como vectores ejecutables en
`shared/conformance/*.json`; ambos núcleos (Swift y Kotlin) deben pasarlos todos.

## 0. Estado del contrato backend — BLOQUEADO

No existe en este repositorio ningún contrato real del backend
(`WATCH_CLIENT_HANDOFF.md`, `WATCH_API_CONTRACT.md`, `openapi-watch.json`,
`openapi.json` o equivalente). Ver `contracts/README.md`.

Consecuencias obligatorias:

- **No se inventa** ningún endpoint, URL, schema, JWT, flujo de auth, Premium ni modelo remoto.
- Toda llamada remota pasa por el puerto `CaminoApi`. Sólo existen dos adaptadores:
  - `BlockedCaminoApi`: devuelve siempre `SendResult.Blocked`. **Es el adaptador de Release.**
  - `MockCaminoApi`: sólo Debug. Acepta todo tras una latencia simulada. La UI muestra la marca `DEMO`.
- No hay cliente HTTP real en V1. Cuando llegue el contrato se añade un tercer adaptador sin tocar el dominio.
- Etapas y POIs vienen de fixtures empaquetadas (`shared/fixtures/`), marcadas como **datos de demostración con coordenadas aproximadas**. No sirven para orientarse en el Camino real.

## 1. Arquitectura

```
          Camino Seguro API  (contrato pendiente)
              ▲          ▲
        HTTPS │          │ HTTPS
          watchOS      Wear OS        ← standalone; el teléfono NO es dependencia
```

Cada plataforma tiene dos capas:

| Capa | watchOS | Wear OS | Contenido |
|---|---|---|---|
| Núcleo puro | `watchos/CaminoCore` (Swift Package, sólo Foundation) | `wearos/core` (módulo Kotlin/JVM, sin Android) | dominio, reglas, motores, puertos, adaptadores mock/fixture, tests de conformidad |
| App | `watchos/CaminoWatch` (SwiftUI) | `wearos/app` (Compose for Wear OS) | UI, sensores, persistencia, notificaciones, Keychain/Keystore |

El núcleo no importa nada de UI, sensores ni plataforma. Todo lo de plataforma entra por puertos.

## 2. Alcance V1 (y nada más)

1. **COMENZAR ETAPA**
2. **CONSULTAR ETAPA**
3. **VER ESTADÍSTICAS**
4. **RECIBIR AVISOS POI**
5. **FINALIZAR ETAPA**
6. **SINCRONIZAR**

Fuera de alcance: navegación turn-by-turn, mapas, clon de la PWA, social, admin,
pausar etapa, editar etapas, login interactivo (bloqueado por contrato), Premium,
HealthKit/Health Services (no hay necesidad funcional demostrada: los pasos salen de
CoreMotion / sensor de pasos).

## 3. Modelo de dominio (nombres idénticos en ambas plataformas)

```
Stage        { id: String, name: String, from: String, to: String,
               distanceMeters: Int, start: GeoPoint, end: GeoPoint }
GeoPoint     { lat: Double, lon: Double }
PoiCategory  = water | shelter | pharmacy | health | food | landmark
Poi          { id: String, stageId: String, name: String, category: PoiCategory, location: GeoPoint }
LocationFix  { point: GeoPoint, accuracyMeters: Double, timestamp: Instant }

StageSession { sessionId: String (UUID v4, generado en el reloj),
               stageId: String, startedAt: Instant,
               steps: Int, distanceMeters: Double,
               lastFix: LocationFix?,          // para el acumulador de distancia
               alertedPoiIds: Set<String>, lastAlertAt: Instant? }

SessionSummary { sessionId, stageId, startedAt, finishedAt,
                 steps: Int, distanceMeters: Int (redondeado), activeSeconds: Int }

SessionState = Idle | Active(StageSession)
History      = [SessionSummary]   (orden: más reciente primero)
```

## 4. Máquina de estados de la etapa

| Estado | Comando | Resultado |
|---|---|---|
| Idle | `start(stageId, sessionId, now)` | `Active` con steps=0, distance=0; encola `stage_started` |
| Idle | `start` con stageId desconocido | error `unknownStage`, sin cambios |
| Active | `start(...)` | error `alreadyActive`, sin cambios |
| Active | `updateSteps(n)` | `steps = max(steps, n)` (los pasos nunca bajan) |
| Active | `updateLocation(fix)` | acumulador de distancia (§5) + motor POI (§6) |
| Active | `finish(now)` | añade `SessionSummary` a History, vuelve a `Idle`; encola `stage_finished` |
| Idle | `finish` / `updateSteps` / `updateLocation` | error `notActive` (update*: ignorado sin error en la app) |

- `activeSeconds = max(0, floor(finishedAt − startedAt))`. No hay pausa en V1.
- **Persistencia en cada transición**: si el sistema mata la app, al relanzar se restaura `Active` y se sigue contando.
- Pasos: el número es **acumulado desde `startedAt`**.
  - watchOS: `CMPedometer.startUpdates(from: startedAt)` (re-consultable tras relanzar).
  - Wear OS: `Sensor.TYPE_STEP_COUNTER` (acumulado desde arranque del reloj). Guardar `baseline` al empezar;
    si el contador baja (reinicio del reloj), sumar lo acumulado antes del reinicio a un `offset` persistido.

Vectores: `shared/conformance/session_transitions.json`.

## 5. Distancia recorrida (acumulador)

Fuente única: posiciones GPS, con la misma regla en ambas plataformas (no la distancia del podómetro,
que difiere entre fabricantes).

Para cada `fix` nuevo en sesión activa:

1. Si `fix.accuracyMeters > 50` → descartar (no cambia nada).
2. Si no hay `lastFix` → `lastFix = fix`, distancia sin cambios.
3. `d = haversine(lastFix.point, fix.point)`, `dt = fix.timestamp − lastFix.timestamp` (segundos).
4. Si `d < max(10, fix.accuracyMeters)` → descartar (ruido; `lastFix` NO cambia).
5. Si `dt <= 0` o `d / dt > 4.0` m/s → `lastFix = fix` pero **no** se suma (salto o vehículo).
6. Si no → `distanceMeters += d`, `lastFix = fix`.

Haversine con radio terrestre **R = 6 371 008.8 m**.
Vectores: `shared/conformance/haversine.json`, `shared/conformance/distance_accumulator.json`.

## 6. Avisos POI

Sólo con sesión `Active`, sólo POIs de la etapa activa. En cada fix aceptado por el paso 1 de §5:

1. Candidatos = POIs con `id ∉ alertedPoiIds` y `haversine(fix, poi) <= 300 m`.
2. Si no hay candidatos → nada.
3. Si `lastAlertAt != nil` y `now − lastAlertAt < 60 s` → nada (límite de ritmo; se reintentará en el siguiente fix).
4. Si no → avisar del candidato **más cercano** (empate: menor `id` lexicográfico),
   añadirlo a `alertedPoiIds`, `lastAlertAt = now`.

Un POI se avisa como máximo una vez por sesión. El aviso es: notificación local + háptica +
texto `"<icono> <nombre> · <distancia>"` (formato §8).
Vectores: `shared/conformance/poi_alerts.json`.

## 7. Sincronización (offline-first)

Cola persistente de eventos, FIFO:

```
SyncEvent { eventId: String (UUID v4, clave de idempotencia), type: "stage_started" | "stage_finished",
            sessionId, occurredAt: Instant, payload }
  stage_started.payload  = { stageId, startedAt }
  stage_finished.payload = { stageId, startedAt, finishedAt, steps, distanceMeters, activeSeconds }
```

**Privacidad**: nunca se envía la traza GPS ni posiciones; sólo agregados.

`SendResult = Accepted | Retryable(reason) | Permanent(reason) | Unauthorized | Blocked`

Algoritmo `syncNow(now)`:

1. Si hay un backoff activo y `now < nextAttemptAt` y el disparo **no** es manual → no enviar nada
   (estado `pending` si la cola tiene eventos, `synced` si está vacía).
2. Recorrer la cola en orden. Por cada evento:
   - `Accepted` → borrarlo de la cola, `attempt = 0`, continuar.
   - `Retryable` → `attempt += 1`, `nextAttemptAt = now + backoff(attempt)`, **parar**.
   - `Permanent` → mover a dead-letter (persistida, visible como contador), continuar.
   - `Unauthorized` → estado `needsLink`, **parar** (el flujo de vinculación está BLOQUEADO por contrato).
   - `Blocked` → estado `blocked`, **parar**. No se pierde ningún evento.
3. Cola vacía → estado `synced`.

`backoff(attempt) = min(30 · 2^(attempt−1), 1800)` segundos, más jitter aleatorio en `[0, 20 %]`
(el jitter se inyecta; los vectores usan jitter 0). Vectores: `shared/conformance/backoff.json`.

Disparadores: tras `start`, tras `finish`, al volver la app a primer plano, botón manual, recuperación de red.
Un solo `syncNow` en vuelo a la vez.

`SyncStatus` para la UI: `synced | pending(n) | offline | blocked | needsLink | syncing`, más `deadLetters: Int`.

## 8. Formato de presentación (es-ES)

| Magnitud | Regla | Ejemplos |
|---|---|---|
| Distancia | `m = max(0, m)`; `r = floor(m/10 + 0.5)·10`; si `r < 1000` → `"r m"`; si no `t = floor(m/100 + 0.5)`; si `t < 100` → `"t/10,t%10 km"`; si no → `"floor(m/1000 + 0.5) km"` | `0 m`, `340 m`, `1,0 km`, `9,9 km`, `10 km`, `22 km` |
| Duración | `s = max(0, s)`; `< 3600` → `"floor(s/60) min"`; resto → `"H h MM min"` (MM con dos dígitos) | `0 min`, `45 min`, `1 h 05 min` |
| Pasos | `max(0, n)`, separador de miles con punto | `999`, `1.234`, `25.000` |

Vectores: `shared/conformance/formatting.json`. **No** usar el formateador del sistema para estos tres
campos (diverge entre plataformas y locales); implementar la regla.

Iconos POI: water 💧 · shelter 🛏 · pharmacy ➕ · health 🏥 · food 🍽 · landmark ⛪ — siempre acompañados de texto (no sólo icono).

## 9. Puertos (interfaces del núcleo)

| Puerto | Responsabilidad | Adaptadores V1 |
|---|---|---|
| `StageCatalog` | lista de etapas | `FixtureStageCatalog` |
| `PoiSource` | POIs por etapa | `FixturePoiSource` |
| `SessionStore` | persistir `SessionState` + `History` | fichero JSON (app), memoria (tests) |
| `SyncQueueStore` | persistir cola, dead-letter, backoff | fichero JSON (app), memoria (tests) |
| `CaminoApi` | `send(SyncEvent) -> SendResult` | `BlockedCaminoApi`, `MockCaminoApi` |
| `CredentialStore` | token opaco: read/write/clear | Keychain / Keystore (app), memoria (tests). Nada lo escribe en V1 |
| `Clock` | `now()` | sistema / fijo en tests |
| `IdGenerator` | UUID v4 | sistema / secuencial en tests |

Sensores (`StepSource`, `LocationSource`) y `Notifier` viven en la capa app.

## 10. UX — levantar muñeca → entender → actuar

Pantallas (máximo 2 toques para cualquier acción V1):

1. **Inicio (Idle)**: botón grande **"Comenzar etapa"**; debajo, fila de estado de sincronización.
2. **Elegir etapa**: lista; la primera es la sugerida (la siguiente a la última terminada). Toque → **confirmar** → `Active`.
3. **Etapa (Active)** — pantalla principal, legible de un vistazo:
   - Grande: **km restantes** (`max(0, distanceMeters_plan − recorridos)`).
   - Secundario: recorrido, pasos, tiempo.
   - Línea "Próximo POI": el no avisado más cercano con su distancia, si hay fix.
   - Botón **"Finalizar"** con confirmación explícita (nunca se termina por un toque accidental).
4. **Estadísticas**: hoy (sesión activa o última) y acumulado del Camino (suma de History): etapas, km, pasos, tiempo.
5. **Resumen al finalizar**: km, pasos, tiempo, y estado "Guardado · se sincronizará".
6. **Sincronizar**: estado legible (`Sincronizado`, `3 pendientes`, `Sin conexión`, `Pendiente de backend`,
   `Necesita vincular`) + botón "Sincronizar ahora".

Reglas:
- Textos en español, centralizados en recursos localizables (es como base).
- Respeta tamaño de texto del sistema; nada de tamaños fijos que corten texto.
- Objetivos táctiles ≥ 44 pt (watchOS) / 48 dp (Wear OS).
- Color nunca es la única señal. Contraste AA.
- Etiquetas de accesibilidad en todo control y valor (VoiceOver / TalkBack leen "4,2 kilómetros restantes", no "4,2 km").
- Wear OS: pantallas redondas (`ScalingLazyColumn`, `TimeText`), soporte de corona/rotary.
- Marca `DEMO` visible siempre que el adaptador sea `MockCaminoApi`.

Glance (después de la V1 verde): complicación WidgetKit (watchOS) y Tile (Wear OS) con km restantes.

## 11. Seguridad y privacidad

- Release usa `BlockedCaminoApi`: imposible enviar datos a un servidor inventado.
- Sin tráfico en claro: ATS por defecto (watchOS); `cleartextTrafficPermitted=false` (Wear OS).
- Tokens: Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` / clave AES-GCM en Android Keystore.
  Nunca en logs, nunca en ficheros planos, nunca en backups (`android:allowBackup="false"`).
- Datos locales: sesión e historial en almacenamiento privado de la app
  (watchOS: `FileProtectionType.completeUntilFirstUserAuthentication`).
- Logs: sin coordenadas, sin tokens, sin identificadores de usuario.
- Permisos mínimos, pedidos en contexto (al pulsar "Comenzar etapa", no al abrir):
  - watchOS: ubicación (en uso + background mode `location`), movimiento, notificaciones.
  - Wear OS: `ACCESS_FINE_LOCATION`, `ACTIVITY_RECOGNITION`, `POST_NOTIFICATIONS`,
    `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION`. Nada de `INTERNET` mientras no haya contrato
    (Debug/mock tampoco lo necesita).
- Si se deniega un permiso, la etapa sigue funcionando con lo disponible y la UI lo dice.

## 12. Batería y ciclo de vida

- Sensores **sólo** con sesión `Active`; se paran al finalizar.
- Ubicación: precisión ~10 m, `distanceFilter`/`minDistance` 20 m, intervalo mínimo 10 s.
- watchOS: background mode `location` mientras hay sesión activa; sin HKWorkoutSession en V1.
- Wear OS: foreground service de tipo `location` con notificación en curso mientras hay sesión activa.
- Restauración tras muerte del proceso: estado `Active` persistido + reenganche de sensores al relanzar.
- Sin polling de red: la sincronización sólo ocurre por los disparadores de §7.

## 13. Plataformas mínimas

- watchOS 10.0+, Swift 5.9+, app **independiente** (sin app iOS compañera), proyecto generado con XcodeGen.
- Wear OS 3+ (`minSdk 30`), `compileSdk/targetSdk 35`, Kotlin 2.0, Compose for Wear OS.

## 14. Verificación

- Local (Linux): `wearos` → `./gradlew -PcoreOnly=true :core:test`.
- CI GitHub Actions:
  - `watchos.yml` (macOS): `swift test` del núcleo + `xcodegen` + `xcodebuild build` para simulador.
  - `wearos.yml` (Ubuntu): tests del núcleo + `assembleDebug` + `assembleRelease` + `lintDebug`.
