# Verificación final independiente — Camino Seguro Watch

Fecha: 2026-10-05 · HEAD `fb7f886` · Verificador adversarial (no se ha modificado código de producto).

## Resumen

Intenté demostrar que la app es incorrecta, deshonesta o insegura. **No encontré ningún camino
de Release que llame ni abra el 112 sin un toque explícito**, ni uso de `ACTION_CALL`/`CALL_PHONE`,
ni red, ni coordenadas en logs, notificaciones, instantáneas del widget ni complicaciones. Los dos
núcleos pasan sus tests y se comportan igual en mis casos adversariales.

Lo que sí aparece:

- **Críticos: 0 · Altos: 0.**
- **Medios: 2.**
  - F-01: en Debug, el escenario demo de Wear OS cambia el marcador por uno falso. El SOS muestra
    entonces «Marcador abierto con el 112» sin ninguna marca DEMO. Cualquier app puede activarlo,
    porque la actividad está exportada.
  - F-02: la matriz SOS afirma que Debug/DEMO usa el marcador real, y no es así.
- **Bajos: 6.**
  - La subida hecha durante una pausa se suma al reanudar.
  - El perfil se rompe en puntos sueltos a partir de unos 60 km.
  - Hay deep links implícitos de Navigation abiertos en Release.
  - El tiempo en movimiento en vivo no está acotado por la duración.
  - Finalizar con fallo de disco no se comporta igual en las dos plataformas.
  - La complicación Wear OS no tiene marca DEMO ni aviso de «sin GPS».
- **Informativos: 3.**

Ejecutado aquí:

| Prueba | Resultado |
|---|---|
| `./gradlew -PcoreOnly=true :core:test --rerun-tasks` | 21 suites, **126 tests, 0 fallos** |
| `swift test` (Docker `swift:6.0-noble`) | **100 tests XCTest, 0 fallos** |
| `python3 shared/conformance/reference.py` | Regenera los 9 vectores; `git status` limpio: los vectores versionados coinciden |
| `watchos/tools/gen_strings.py --check` | 284 claves es/en (app) y 21 (widgets), al día |
| Script propio de claves y marcadores es/en (Wear y watchOS) | 0 claves que falten, 0 discrepancias de `%1$s`/`%ld`/`%@` |
| Tests adversariales propios, Kotlin y Swift, en una copia fuera del repo (`git archive`) | Resultados idénticos en ambos núcleos (ver abajo) |

## Tabla de hallazgos

| ID | Sev. | Plataforma | Fichero:línea | Evidencia | Recomendación |
|---|---|---|---|---|---|
| F-01 | **Medio** | Wear OS (sólo Debug) | `wearos/app/src/debug/.../demo/DemoScenarioInstaller.kt:130`; `wearos/app/src/main/AndroidManifest.xml:45`; `wearos/app/src/main/kotlin/.../ui/SosScreen.kt:84-99`; `wearos/core/.../EmergencyInfo.kt` (`FakeEmergencyDialer.nextResult = HandedToSystem`) | `MainActivity` está exportada (launcher). En Debug, cualquier app o `adb` puede lanzarla con `--es demo.scenario x`. El instalador sustituye entonces el marcador por `FakeEmergencyDialer` durante toda la vida del proceso (`installed` es un flag por proceso). En ese estado, «Llamar al 112» no abre nada, pero el SOS dice «Marcador abierto con el 112. Pulsa llamar si es seguro.». `SosScreen` no muestra marca DEMO. watchOS sí lo hace (`SOSView.swift:37-40`: `DemoBadge` + «Modo demostración: no se abre ninguna llamada»). CI publica el APK Debug como artefacto (`.github/workflows/wearos.yml:49-53`), así que puede acabar instalado en un reloj real. | Opción 1: mostrar en `SosScreen` una marca DEMO y el texto «no se abre ninguna llamada» cuando el marcador sea simulado (exponer `container.emergencyDialer is FakeEmergencyDialer`). Opción 2: hacer que el fake devuelva un resultado propio («simulado») en lugar de `HandedToSystem`. Valorar también aceptar `demo.*` sólo si `Build.TYPE`/`isDebuggable` y el llamante es shell. |
| F-02 | **Medio** (honestidad) | Wear OS / docs | `docs/accessibility/SOS_CAPABILITY_MATRIX.md:57` y `:93`; `wearos/app/src/main/kotlin/.../AppContainer.kt:202-205` | La matriz dice «`FakeEmergencyDialer` … Sólo tests. Debug/DEMO usa el marcador real». También dice «Debug/DEMO usa el marcador REAL (decisión de seguridad)». El comentario de `AppContainer` dice lo mismo («en TODAS las variantes, también Debug/DEMO»). No es cierto: `installDemo(..., dialer = FakeEmergencyDialer())` lo sustituye en todos los escenarios demo. Además, `:46-48` dice que «CI build+lint queda pendiente» y pone «Emulador: No» en todas las filas. Eso está desfasado: ambas apps compilan en CI y hay capturas SOS en el emulador (`docs/qa/WEAROS_SCREENSHOTS.md`). Esto último infravalora lo verificado, no lo exagera. | Corregir la matriz y el comentario: Debug normal usa el marcador real; los escenarios demo usan el simulado. Actualizar las columnas «CI build+lint» y «Emulador» (sólo render, sin marcado real). |
| F-03 | Bajo | Ambas (núcleo + `reference.py` + spec §C/§E) | `wearos/core/.../TripMetrics.kt:23-26`; `watchos/CaminoCore/.../TripMetrics.swift:99-105`; `shared/conformance/reference.py:311-316` | Pausar pone `lastFix = nil`, pero conserva `altitudeRef`. Caso adversarial: fix a 500 m de altitud → pausa → (bus o teleférico) → reanudar → fix a 900 m. Resultado: **`ascent = 400` m**, mientras que la distancia sólo suma 35 m (ADV1, igual en Kotlin y Swift). El desnivel recorrido en pausa se cuenta, lo que contradice la intención de §C («para que el tramo recorrido en pausa no se cuente»). Las tres implementaciones coinciden: es un hueco de la spec, no una divergencia. | Spec + `reference.py`: `altitudeRef = nil` al pausar (o al reanudar). Añadir el vector `pausa_con_cambio_de_altitud` y propagarlo a ambos núcleos. |
| F-04 | Bajo | Ambas (núcleo + spec §F) | `TripMetrics.kt:105`; `TripMetrics.swift:191`; `reference.py` (perfil) | Tras dos diezmados, `spacing` llega a 200 m y luego a 400 m. Cada muestra nueva cumple entonces `d − último.d > 200` y se marca `gapBefore`. Caso: 120 km con altitud continua → 268 muestras, **142 con `gapBefore`**, la primera a 60,4 km (ADV4, idéntico en las dos plataformas). `ProfileChart.swift:112` y `WatchPresentation.kt:253` parten la serie en cada hueco, así que la gráfica degenera en puntos sueltos. Sólo afecta a trayectos de más de ~50 km (o a uno que no se finaliza). | Umbral de hueco `max(200, 2·spacing)` (o comparar con `spacing` y no con una constante). Añadir un vector con `profileCap` pequeño y más de 3 diezmados. |
| F-05 | Bajo | Wear OS (Release incluida) | `AndroidManifest.xml:44-52`; `ui/CaminoApp.kt:117-279`; `ui/MainActivity.kt:44-46` | `SwipeDismissableNavHost` registra un deep link implícito `android-app://androidx.navigation/<ruta>` por cada `composable(route)`. El instalador demo usa precisamente ese mecanismo (`DemoScenarioInstaller.applyRoute`). Como la actividad es exportada, cualquier app instalada puede abrir en Release `sos`, `confirm_finish`, `summary`, `place/{id}`… con un intent explícito con `data`. Ninguna ruta ejecuta acciones: hace falta otro toque para marcar o finalizar. Pero abrir `sos` dispara `onSosOpened()`, que hace una lectura única de ubicación (no se envía a ningún sitio). watchOS valida su esquema propio y no tiene ruta SOS (`DeepLink.swift`). | En `MainActivity.onCreate`, descartar `intent.data` si no es la acción de la complicación o de MAIN/LAUNCHER, o bien `navController.handleDeepLink` sólo con una lista blanca. Documentarlo. |
| F-06 | Bajo | Ambas | `ui/Presentation.kt:112` (Wear); `Views/HomeView.swift:148`, `StatsView.swift:57` (watchOS) | El resumen acota `moving ≤ activeSeconds` (`StageMachine.kt:146`, `StageSessionMachine.swift:189`); la vista en vivo no. Caso: reloj del sistema hacia atrás (`now < startedAt`). Duración en vivo = 0 s y tiempo en movimiento = 20 s (ADV3). Viola «tiempo en movimiento ≤ duración» mientras dura. | Aplicar `min(moving, elapsed)` también en la presentación en vivo. |
| F-07 | Bajo (paridad V-04) | watchOS | `watchos/CaminoCore/Sources/CaminoCore/CaminoController.swift:282-289` | Kotlin no cambia el estado si falla el guardado al finalizar (`persistStrict`, `CaminoController.kt:198`). Swift, en cambio, pone la máquina en Idle, encola `stage_finished` y luego guarda con *best effort*. La UI es honesta («no se pudo guardar», `AppModel.swift:415`). Pero si el proceso muere, el disco sigue teniendo la sesión activa mientras la cola puede tener ya el `stage_finished`. Al finalizar otra vez saldría un segundo evento para la misma sesión. | Igualar a Kotlin: guardar antes de cambiar el estado y de encolar, o revertir si falla. |
| F-08 | Bajo (paridad) | Wear OS | `complication/CaminoComplicationService.kt:107-160`; `core/WatchPresentation.kt:283-289` | El widget watchOS muestra «DEMO», «Sin GPS» y «hace N min» si los datos son antiguos. La complicación Wear no muestra nada de eso: sin permiso de ubicación enseña «0,0 km · en marcha» y en Debug no lleva marca DEMO. | Añadir el estado «sin ubicación» y la marca DEMO al `ComplicationContent`. |
| F-09 | Info | Wear OS (Debug demo) | `ui/Screens.kt:213` | El resumen dice siempre «Guardado en el reloj». En Release es cierto, porque sólo se llega tras `persistStrict`. En los escenarios demo el almacén es `InMemorySessionStore` y no lo es (watchOS sí distingue `.memoryOnly`). | Pasar un flag de persistencia real. |
| F-10 | Info | Paridad §I | `AppModel.swift:481-489` frente a `CaminoApp.kt:247-259` | Cerrar el aviso de esfera con el gesto del sistema lo **descarta** en watchOS. En Wear OS (atrás) queda **sin decidir** y se vuelve a ofrecer. La spec sólo define «cerrar la app». | Decidir y documentar un único comportamiento. |
| F-11 | Info | Wear OS | `ui/CaminoApp.kt:109-114` | Carrera teórica: si `faceHintOffer` pasa a `true` justo cuando el usuario pulsa «SOS», el efecto puede navegar a `face_hint` encima del SOS antes de que `currentRoute` se actualice. Se recupera con «atrás». | Comprobar la ruta actual del `navController` dentro del efecto, o no ofrecer el aviso en los primeros segundos. |

## Intenté romperlo y aguantó

**SOS: nada llama ni abre el 112 sin un toque**

- **Wear OS.** La única llamada a `sos.dial()` es `SosScreen` → `onDial` (`CaminoApp.kt:274`), y sale de un `Chip.onClick`.
- **watchOS.** La única llamada a `requestEmergencyCall()` es el `Button` de `SOSView.swift:21-22`.
- **Complicación, widgets, notificaciones y deep links.**
  - El `PendingIntent` de la complicación es INMUTABLE y sólo lleva `ACTION_OPEN_TRIP`. Eso hace `popBackStack(HOME)`.
  - `DeepLink.parse` no tiene caso SOS ni ejecuta acciones; los ids van con una lista blanca de 64 caracteres.
  - `widgetURL` = `.stage`.
  - Ninguna ruta restaurada marca.
- **`ACTION_CALL` / `CALL_PHONE`.**
  - Ausentes en el manifest y en el código.
  - `ACTION_DIAL` + `<queries>` DIAL/tel.
  - `telUri` sólo con dígitos ASCII.
- **watchOS.** Usa `WKApplication.shared().openSystemURL(_:)`, documentado con cita literal en `SOS_FEASIBILITY.md` §1, en el hilo principal.

**SOS: textos, número y efecto sobre el trayecto**

- **Textos honestos (es/en).** Nunca «llamada realizada», «ayuda en camino» ni «ubicación enviada». Se dice explícitamente «no se envían al 112 automáticamente».
- **El 112 no se deduce del idioma.** Es una constante `SPAIN_EU`/`.spainEU`, con tests con varios `Locale`.
- **Abrir o cerrar el SOS no toca el `CaminoController`.** Sólo hace una lectura de ubicación, cancelada con `CancellationSignal` al salir.

**SOS: Release y DEMO**

- **watchOS.** Los escenarios DEMO quedan entre `#if DEBUG`, y `project.yml` sólo define `DEBUG` en la configuración Debug.
- **Wear OS.** `DemoBootstrapProvider` y el instalador existen sólo en `src/debug`. El provider es `exported=false`. `DemoHooks.apply` vale `null` en main.
- **Release usa siempre el marcador real.** Release usa `BlockedCaminoApi`, y el marcador real se usa también en Debug sin escenario.

**Privacidad y seguridad**

- **Red.** No hay permiso `INTERNET`, la configuración de red prohíbe el tráfico en claro y no se usa `URLSession` ni sockets.
- **Logs.**
  - Sólo eventos, nombres de clase de excepción y `Log.describe` (tipo + dominio#código).
  - Las notificaciones POI registran sólo la categoría.
  - `WidgetSnapshot` no lleva coordenadas, ids ni POI.
- **Componentes exportados.**
  - `ComplicationDataSourceService` exportado con `BIND_COMPLICATION_PROVIDER`.
  - `SessionService` con `exported=false`.
  - Todos los `PendingIntent` son `FLAG_IMMUTABLE`.
- **Copias de seguridad y credenciales.**
  - `allowBackup=false` y `dataExtractionRules` excluyen todo.
  - Token en `noBackupFilesDir` con AES-256/GCM cuya clave está en Keystore.
  - Keychain con `AfterFirstUnlockThisDeviceOnly`.
  - Ficheros con `.completeFileProtectionUntilFirstUserAuthentication` y escritura atómica.
- **App Group.** Uno solo (`group.org.caminoseguro.watch`).

**Corrección V1.1 (ADV1-ADV5, idénticos en Kotlin y Swift)**

| Caso | Resultado |
|---|---|
| ADV1: pausa → fix a 3 km → reanudar | **No suma el salto** (35 m), `moving` = 20 s, `pausedSeconds` correcto |
| ADV2: NaN/∞ en latitud, precisión, altitud y precisión vertical | Se descartan; ni la distancia ni el desnivel se envenenan |
| ADV3: finalizar con el reloj hacia atrás | `activeSeconds` = 0, `movingSeconds` = 0 (acotado); finalizar en pausa con el reloj hacia atrás da `pausedSeconds` = 0 |
| ADV5: doble inicio | `alreadyActive` sin eventos. Además, `ActionGate` y `confirmStartGate` en Wear |

- **Pausa.** En pausa se mantienen los avisos POI (`applyFix` no cambia nada, pero `PoiAlertEngine` sí se evalúa).
- **«Guardado en el reloj» (watchOS).** Se muestra sólo si `storageWriteFailed == false`, y el callback es síncrono.
- **«Sincronizado».**
  - En Release es imposible: `BlockedCaminoApi` deja el estado siempre `Blocked` («Nada pendiente · sin servidor»).
  - En Debug se dice «Demo · envío simulado».
- **Complicación.** Nunca inicia nada. Aplica unidades e idioma: Wear usa `DisplayFormat` + `AppLocale.effective`; watchOS lleva `units`/`lang` en la instantánea.
- **Aviso de esfera.**
  - No se muestra con trayecto ni tras restaurar uno.
  - Se persiste.
  - Ningún texto afirma que la complicación esté instalada (búsqueda de «instalad»/«installed»: 0 resultados).

**Integración**

- Todas las `R.string.*` usadas existen.
- Las claves `tr("…")` de Swift existen en es.
- Los marcadores de formato coinciden entre idiomas.
- Las rutas de `Routes` coinciden con las del script de capturas.

**Documentación**

- `SOS_FEASIBILITY.md` y `DISTRIBUTION_AND_IDENTITY.md` marcan como **[NV]/NO VERIFICADO** lo que no tiene fuente.
- La matriz SOS pone «Hardware: No» en todas las filas.
- No encontré ninguna afirmación de verificación en hardware.

## No verificable aquí

- **Hardware en general.** Ningún comportamiento en hardware: si `openSystemURL(tel:112)` muestra la confirmación y enruta como emergencia, ni si `ACTION_DIAL tel:112` abre el marcador en relojes Wear con o sin LTE. Tampoco TalkBack/VoiceOver reales ni la legibilidad al sol.
- **Builds de app.** Compilar `:app` (Android) y el proyecto Xcode, porque aquí no hay Android SDK ni Xcode. Por tanto:
  - el **manifest fusionado**: si alguna dependencia añade `INTERNET` u otros componentes exportados;
  - lint;
  - el comportamiento real de Navigation con deep links implícitos en `wear-compose-navigation 1.4.0` (F-05 se basa en el código de Navigation y en que el script de capturas depende de ello).
- **`PresentationTest` de `:app`**, que necesita AGP.
- **Wear OS en segundo plano.** Que un FGS de ubicación arrancado tras la muerte del proceso (por ejemplo, despertado por la complicación) se rechace en Android 12+. El código lo captura y lo reintenta al volver a primer plano, pero no se ha probado.
- **watchOS en segundo plano.** El seguimiento en segundo plano (`UIBackgroundModes: location`) y el presupuesto real de recargas de WidgetKit.
