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
7. **TRAYECTO + SOS** (§10.1): en la interfaz la sesión se llama **trayecto** («Iniciar trayecto»,
   «Finalizar trayecto», «trayecto en curso»; el modelo sigue siendo etapa). Botón «SOS» fijo arriba a
   la derecha que abre la pantalla de emergencia con «Llamar al 112».

Fuera de alcance: navegación turn-by-turn, mapas, clon de la PWA, social, admin,
pausar etapa, editar etapas, login interactivo (bloqueado por contrato), Premium,
HealthKit/Health Services (no hay necesidad funcional demostrada: los pasos salen de
CoreMotion / sensor de pasos). Del SOS quedan fuera: llamada automática o sin confirmación del
sistema, envío de ubicación o mensajes a nadie, contactos de emergencia, satélite propio, deducir el
número de emergencia del idioma o la región (ver §10.1).

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
3. Si `lastAlertAt != nil` y `0 ≤ now − lastAlertAt < 60 s` → nada (límite de ritmo; se reintentará en el siguiente fix).
   `now` es la hora del **reloj del sistema** al procesar el fix (no `fix.timestamp`): así un lote de fixes
   atrasados no produce dos avisos seguidos. Si el reloj ha ido hacia atrás (`now < lastAlertAt`) no se bloquea.
   Las categorías desactivadas por el usuario en Ajustes no son candidatas (no avisan ni consumen el límite).
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
4. **Excepción**: si el adaptador es `BlockedCaminoApi` (Release sin contrato), el estado es siempre `blocked`,
   también con la cola vacía. Nunca se muestra "sincronizado" si no existe servidor.

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

### 10.1 Trayecto y SOS (pantalla principal y pantalla de emergencia)

Pantalla principal (sustituye a los puntos 1 y 3 en lo que contradigan):
- **Cabecera compacta fija** (barra nativa, respeta la hora y las zonas seguras): ajustes a la izquierda y
  **«SOS»** a la derecha, visible al desplazar y alcanzable sin recorrer las estadísticas. No es una
  superposición: no tapa contenido.
- **Sin trayecto**: acción principal **«Iniciar trayecto»** (→ elegir etapa → confirmar). Doble toque = un
  solo inicio (botón desactivado tras el primer toque y guarda `isStarting` en el modelo de la app).
  Permisos: estado real (permitido / se pedirá al iniciar / denegado) con su propósito en una línea.
- **Con trayecto**: estadísticas como contenido principal con desplazamiento vertical nativo (corona); datos
  ausentes o antiguos se dicen («esperando GPS», «sin datos de pasos», «ubicación antigua»), nunca un cero
  ficticio. Agua cercana como fila del contenido, cerca de arriba (1 pulsación).
- **«Finalizar trayecto»** al final del contenido, separado (línea + espacio), con confirmación breve;
  cancelar lo conserva todo. Persistencia y recuperación tras muerte del proceso como en §4/§12.
- «SOS» y «Finalizar trayecto» inequívocamente distintos: texto, posición (cabecera / final) y forma
  (cápsula compacta roja / botón ancho neutro).

Botón «SOS»: etiqueta de texto (no sólo icono), rojo sobrio con contraste verificado, objetivo táctil
≥ 44×44 pt (watchOS) / 48 dp (Wear OS). Un toque abre la pantalla de emergencia apilada en la navegación
(volver del sistema restaura la pantalla anterior y su desplazamiento). Sin gestos personalizados.
Lector de pantalla: «SOS, botón, abre la pantalla de emergencia».

Pantalla de emergencia:
- Acción principal **«Llamar al 112»** (grande, roja, texto, ≥ 52 pt de alto en watchOS). Entrega `tel:112`
  al sistema (watchOS: `WKApplication.shared().openSystemURL`), que pide confirmación. **Sin** confirmación
  propia, cuenta atrás, pulsación prolongada, menús ni formularios.
- Resultado honesto: la app sólo sabe que **entregó la petición** (`DialResult.handedToSystem`) o que falló
  (`.failed(motivo)`); nunca «llamada conectada», «emergencia enviada» ni «ayuda en camino». Texto tras
  entregar: «Llamada solicitada al reloj. Si no aparece, usa el SOS del reloj: mantén pulsado el botón lateral.»
- Alcance del número: **112 = España y UE**, constante documentada; no se deduce del idioma ni de la región.
- Ubicación: la que ya hay, sin pedir permiso ni esperar al GPS (`EmergencyLocationSummary`): coordenadas con
  5 decimales y N/S/E/O, precisión ±m, antigüedad; `current` (≤ 60 s), `lastKnown`, `stale` (> 5 min),
  `noSignal`, `permissionDenied`. Si el permiso ya está concedido se pide una lectura única. **No se envía a
  ningún sitio**: «Estas coordenadas no se envían al 112 automáticamente.»
- Ayuda breve: SOS nativo del reloj (mantener pulsado el botón lateral) y satélite sólo como función del
  sistema (Apple Watch Ultra 3 o posterior, regiones compatibles, mensajes; la app no lo controla).
- Abrir o cerrar la pantalla no pausa ni finaliza el trayecto. Funciona sin trayecto, sin cuenta y sin backend.
- Escenarios DEMO, capturas y tests usan un marcador simulado (`MockEmergencyDialer`) que no abre nada.
- Matriz de verificación por plataforma: `docs/accessibility/SOS_CAPABILITY_MATRIX.md`.

Idiomas: español (base) e inglés, con las mismas claves (`watchos/tools/gen_strings.py --check`).

## 11. Seguridad y privacidad

- Release usa `BlockedCaminoApi`: imposible enviar datos a un servidor inventado.
- Sin tráfico en claro: ATS por defecto (watchOS); `cleartextTrafficPermitted=false` (Wear OS).
- Tokens: Keychain `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` / clave AES-GCM en Android Keystore.
  Nunca en logs, nunca en ficheros planos, nunca en backups (`android:allowBackup="false"`).
- Datos locales: sesión e historial en almacenamiento privado de la app
  (watchOS: `FileProtectionType.completeUntilFirstUserAuthentication`).
- Logs: sin coordenadas, sin tokens, sin identificadores de usuario.
- Permisos mínimos, pedidos en contexto (al pulsar "Comenzar etapa" / «Iniciar trayecto», no al abrir;
  la pantalla SOS nunca pide permisos):
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

---

# V1.1 — Trayecto completo, complicaciones y organización

Ampliación pedida por producto (2026-10-05). Prevalece sobre lo anterior donde lo contradiga.
Vectores nuevos: `shared/conformance/trip_metrics.json` y `units_formatting.json` (generados por `reference.py`).

## A. Organización de la app

| Destino | Contenido | Acceso |
|---|---|---|
| **Trayecto** | Pantalla principal y destino de la complicación | Raíz |
| **Lugares** | Lista ampliada de puntos útiles + fichas | "Ver todos" en Trayecto; fila en Trayecto sin actividad |
| **Ajustes** | Preferencias, acceso desde la esfera | Botón de cabecera (watchOS) / fila (Wear OS) |
| SOS | Acción de emergencia, **no** destino de navegación cotidiana | Botón «SOS» arriba a la derecha en Trayecto |

Navegación nativa (pila con volver del sistema). Sin barra de pestañas.
En la interfaz se dice **trayecto**; en el modelo sigue siendo `StageSession` (etapa elegida).

## B. Pantalla Trayecto activa — orden del contenido

Cabecera compacta fija con «SOS» a la derecha. Contenido vertical:

- **A. Estadísticas principales** (primera vista, sin desplazarse): distancia (destacada), tiempo en movimiento,
  ritmo o velocidad (preferencia), estado «En marcha» / «Pausado» con texto y símbolo.
- **B. Altitud y desnivel**: altitud actual, subida y bajada acumuladas; ausentes/antiguas identificadas.
- **C. Perfil de altitud**: gráfica compacta (distancia × altitud) + resumen textual; tocar abre la vista ampliada.
  Sólo perfil **registrado** (no hay ruta con elevación verificada en los datos actuales: no se dibuja relieve futuro).
  Los tramos con `gapBefore` no se unen.
- **D. Lugares útiles**: como máximo 3 (agua, albergue, resto por distancia), nombre, distancia **en línea recta**
  (no hay rutas), sin estados de apertura/potabilidad (no hay datos). Tocar → ficha. «Ver todos» → Lugares.
- **E. Controles**: «Pausar»/«Reanudar»; «Finalizar trayecto» como último botón, con confirmación.

## C. Máquina de estados — pausa (§4.2)

`StageSession` añade `pausedAt: Instant?`, `pausedSeconds`, `movingSeconds`, `ascentMeters`, `descentMeters`,
`altitudeRef`, `altitude`, `altitudeAt`, `profile: [ProfileSample]`, `profileSpacing`.

| Comando | En marcha | Pausado |
|---|---|---|
| `pause(now)` | → Pausado, `pausedAt = now`, `lastFix = nil`, `altitudeRef = nil` | error `alreadyPaused` (sin cambios) |
| `resume(now)` | error `notPaused` | → En marcha, `pausedSeconds += max(0, now − pausedAt)` |
| `updateLocation` | distancia, movimiento, altitud, perfil, avisos | **sólo avisos POI**; nada de métricas |
| `finish(now)` | normal | cierra la pausa en curso (`pausedSeconds += now − pausedAt`) y finaliza |

Los pasos no se pausan (el sensor no se puede pausar): se muestran tal cual. `lastFix = nil` y
`altitudeRef = nil` al pausar para que ni el tramo ni el desnivel recorridos en pausa se cuenten al reanudar.

`SessionSummary` añade `movingSeconds`, `pausedSeconds`, `ascentMeters`, `descentMeters` (enteros, redondeo
half-up) y `profile`. `stage_finished.payload` añade los cuatro enteros (nunca el perfil ni posiciones).

## D. Tiempo en movimiento (§5.2)

Cuando un tramo se **suma** a la distancia (§5 paso 6) y `d / dt ≥ 0,5 m/s` → `movingSeconds += dt`.
Duración total = `finishedAt − startedAt`; tiempo en movimiento ≤ duración. Se muestran **diferenciados**.

## E. Altitud y desnivel (§5.3)

Fuente: altitud GPS del fix (`altitudeMeters`, `verticalAccuracyMeters`). Procedencia mostrada: "GPS".
Un fix aporta altitud si pasa §5 paso 1, no está en pausa y `0 ≤ verticalAccuracy ≤ 15 m`.
Histéresis de 3 m: `ref` = primera altitud válida; si `alt − ref ≥ 3` → `ascent += alt − ref; ref = alt`;
si `ref − alt ≥ 3` → `descent += ref − alt; ref = alt`. Altitud "antigua" si `now − altitudeAt > 300 s`.

## F. Perfil registrado (§5.4)

Con cada altitud válida: si el perfil está vacío o `distance − último.d ≥ spacing` (inicial 50 m) se añade
`{d, alt, gapBefore = (perfil no vacío y distance − último.d > max(200 m, 2·spacing))}`. Si supera `cap` (500) muestras: se
conservan las de índice par, el `gapBefore` de una descartada pasa a la siguiente conservada, y `spacing *= 2`.

## G. Unidades e idioma (§8.2)

Preferencias: `units ∈ {metric, imperial}`, `paceMode ∈ {pace, speed}`. Idioma: español o inglés.
Separador decimal/miles según idioma (es `,`/`.`, en `.`/`,`). Reglas exactas en `reference.py`
(`fmt_distance_u`, `fmt_elevation`, `pace_text`, `speed_text`); sin dato (`< 100 m` o `< 60 s` en movimiento,
o ritmo > 99:59) → "sin datos", nunca 0. Se aplican a estadísticas, altitud, gráficas, resumen y complicaciones.
- watchOS: no hay API pública para fijar el idioma de una app desde la propia app; sigue el idioma del sistema
  (Ajustes lo explica). Wear OS: idioma por app con `LocaleManager` (API 33+); en API 30–32 sigue el sistema.

## H. Complicaciones

watchOS: WidgetKit (ya existe). Wear OS: `ComplicationDataSourceService` (androidx.wear.watchface.complications).
- Sin trayecto: icono + «Iniciar trayecto» si el formato admite texto.
- Con trayecto: distancia + «en marcha» / «pausado».
- Tocar abre Trayecto (inicio o estadísticas). **Nunca** inicia un trayecto ni una llamada.
- Datos compartidos locales (App Group en watchOS; almacenamiento privado de la app en Wear OS), sin red.
- Actualización por eventos y presupuesto del sistema; nunca "continua".

## I. Aviso de primer uso «Accede desde tu esfera»

Título «Accede desde tu esfera», texto «Abre Camino Seguro con un toque.», acciones «Cómo añadirlo» / «Ahora no».
Se muestra una vez, sin trayecto activo, tras la configuración inicial; se aplaza si hay trayecto o si se está
recuperando uno. Al descartarlo («Ahora no» o el gesto del sistema para cerrar/volver) o al abrir "Cómo añadirlo"
se guarda localmente y no se repite. Sólo si el proceso termina con el aviso abierto queda no decidido (se volverá a ofrecer). No afirma que la complicación esté instalada.
Ruta permanente: **Ajustes → Acceso desde la esfera → Cómo añadirlo** (instrucciones manuales de la plataforma;
no hay API pública verificada para abrir el editor de esfera desde una app de reloj).

## J. Lugares

Lista con filtros mínimos (todos / agua / alojamiento), estados (sin ubicación, sin resultados, datos de
demostración/caché). Ficha: nombre, categoría, distancia y método ("en línea recta"), «Llamar» sólo si el POI
tiene `phone` válido (E.164 o 9 dígitos españoles; los datos actuales no tienen teléfonos → no aparece).
