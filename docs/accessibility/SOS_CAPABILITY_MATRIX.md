# Matriz de capacidades del SOS — qué está verificado y dónde

Fecha: 2026-10-05. Reglas del producto: `docs/WATCH_V1_SPEC.md` §10.1. Fuentes de plataforma:
`SOS_FEASIBILITY.md` y `SOS_PLATFORM_CAPABILITIES.md`.

## Niveles de verificación (no son intercambiables)

| Nivel | Qué demuestra | Qué NO demuestra |
|---|---|---|
| **Tests unitarios** (núcleo, `swift test` en CI y en Linux/Docker) | La lógica pura: número y URL `tel:112`, clasificación y formato de la ubicación, marcador simulado. | Nada de la interfaz ni del sistema. |
| **Simulador (CI)** | Que la app compila (Debug y Release) y que las pantallas se dibujan con datos DEMO (capturas de `watchos/scripts/screenshots.sh`). Las capturas usan `MockEmergencyDialer`: **no** se pide ninguna llamada. | Que el sistema abra la llamada, la confirmación del sistema, la conectividad, VoiceOver real, la Digital Crown física. |
| **Hardware** | Comportamiento real de `openSystemURL(tel:112)`, confirmación del sistema, red (celular / Wi-Fi / iPhone cerca), SOS nativo, lectores de pantalla, legibilidad al sol. | — |

Estado: **Sí** = verificado en ese nivel · **No** = no verificado · **n/a** = ese nivel no puede verificarlo.
No se ha probado nada en hardware: la columna de hardware es **No** en todas las filas.

## watchOS

Niveles para watchOS: **Tests unitarios** (`swift test` de `CaminoCore`, en CI `macos-15` y en Docker) ·
**CI build** (`.github/workflows/watchos.yml`: `xcodebuild build` Debug y Release para el simulador,
`gen_strings.py --check`): **Sí** = compila, no demuestra comportamiento · **Simulador CI** (capturas de
`watchos/scripts/screenshots.sh`): **Sí** = la pantalla se dibuja con datos DEMO; las capturas usan el marcador
simulado y nunca piden una llamada real, así que el **marcador real no se ha probado en simulador** ·
**Hardware**: **No** en todas las filas. Las correcciones de la verificación final (F-03, F-04, F-06, F-07, F-08)
se validan en la próxima ejecución del workflow (aquí sólo `swift test` en Docker).

Qué marcador se usa (F-02): Release y Debug normal usan el **marcador real** (`SystemEmergencyDialer`,
`openSystemURL(tel:112)`). Sólo los escenarios DEMO (`-demo.scenario`, código entre `#if DEBUG`, que sólo
define la configuración Debug) usan `MockEmergencyDialer` (`AppEnvironment.makeDemo`); entonces la pantalla SOS
muestra la marca **DEMO**, «Modo demostración: no se abre ninguna llamada» y, tras pulsar, «Simulado: no se
ha pedido ninguna llamada» (nunca «Llamada solicitada al reloj»).

| Capacidad | Tests unitarios | Simulador CI | Hardware | Notas |
|---|---|---|---|---|
| Número 112 con alcance España/UE, sin deducirlo del idioma | Sí (`EmergencyInfoTests`) | n/a | No | `EmergencyNumber.spainEU`; constante, documentada como no universal. |
| URL `tel:112` válida; número inválido → sin URL | Sí | n/a | No | `EmergencyNumber.telURL`. |
| Entrega al sistema con `WKApplication.shared().openSystemURL` | n/a | Sólo compila (CI build Debug y Release: Sí) | No | `SystemEmergencyDialer`. La API no devuelve resultado: sólo `.handedToSystem`. Confirmación del sistema (y posible doble confirmación, bug de 2020) **sin verificar**. |
| Resultado honesto (`handedToSystem` / `failed`), nunca «conectada» | Sí (marcador simulado) | Sí (texto en pantalla, mock) | No | Marcador real: «Llamada solicitada al reloj. Si no aparece, usa el SOS del reloj…». Simulado (DEMO): «Simulado: no se ha pedido ninguna llamada.». |
| Marcador simulado en DEMO/capturas/tests (no abre nada) | Sí (`MockEmergencyDialer`) | Sí (escenarios `-demo.scenario`) | n/a | Todos los escenarios DEMO (sólo Debug) usan el mock, con marca DEMO y «Simulado» en la pantalla SOS. Debug sin escenario y Release usan el marcador real. |
| Resumen de ubicación: 5 decimales N/S/E/O, ±m, antigüedad | Sí | Sí (captura `sos`, datos DEMO) | No | `EmergencyLocationSummary`. |
| Clasificación `current` (≤ 60 s) / `lastKnown` / `stale` (> 5 min) / `noSignal` / `permissionDenied` | Sí | Parcial (sólo los estados que dan los escenarios) | No | |
| SOS no pide permiso ni espera al GPS; lectura única sólo con permiso concedido | n/a | No (revisión de código) | No | `AppModel.refreshLocationIfAuthorized()`. |
| Ubicación no se envía a ningún sitio | n/a | No (revisión de código) | No | Sin red ni API de mensajes en el flujo SOS. |
| Botón «SOS» en cabecera (`.topBarTrailing`), visible al desplazar | n/a | Parcial (capturas `inicio-activo`, `inicio-activo-final`) | No | Fijación al desplazar con la corona: comprobar en hardware. |
| Objetivo táctil ≥ 44×44 pt del «SOS» | n/a | No (revisión de código: `frame(minWidth:minHeight:)` + `contentShape`) | No | El tamaño efectivo dentro de la barra del sistema debe medirse con Accessibility Inspector. |
| Contraste del «SOS» y de «Llamar al 112» (Negro y Perla) | Sí (`ContrastTests`) | Sí (capturas) | No | Pares «crítico sobre fondo», «texto de acción de emergencia», «acción de emergencia sobre fondo». Legibilidad al sol: hardware. |
| Volver del sistema restaura la pantalla y el desplazamiento | n/a | No | No | `NavigationStack` apila `Route.sos` sobre la raíz, que no se reconstruye. |
| Abrir/cerrar SOS no pausa ni finaliza el trayecto | n/a | No (revisión de código) | No | `SOSView` no toca la sesión. |
| VoiceOver: «SOS, botón, abre la pantalla de emergencia»; orden cabecera → cifras → resto → finalizar | n/a | No | No | Etiqueta + pista en código; probar con VoiceOver real. |
| Texto grande sin recortes | n/a | Parcial (capturas `_texto-grande`) | No | |
| Español e inglés con las mismas claves | Sí (`gen_strings.py --check` en CI) | Sí (pasada `_en`) | No | |
| SOS nativo (mantener botón lateral) | n/a | n/a | No | Función del sistema; la app sólo lo explica. Texto de Apple sólo como fragmento [P]. |
| Satélite (Ultra 3+, regiones compatibles, mensajes) | n/a | n/a | No | Función del sistema; la app no lo controla ni lo simula. Demo oficial en Ajustes del reloj. |
| Saber si el reloj tiene celular / puede llamar | n/a | n/a | n/a | No hay API pública (`SOS_PLATFORM_CAPABILITIES.md` §4.2): la UI no depende de ello. |

## Wear OS

Niveles para Wear OS: **Tests JVM** (`cd wearos && ./gradlew -PcoreOnly=true :core:test`, sin Android SDK) ·
**CI build+lint** (`.github/workflows/wearos.yml`: `:core:test`, `testDebugUnitTest`, `assembleDebug/Release`,
`lintDebug` con `abortOnError`) · **Emulador** (capturas de `wearos/scripts/screenshots.sh`,
`docs/qa/WEAROS_SCREENSHOTS.md`) · **Hardware**. CI build+lint **Sí** = el código compila y pasa lint en CI;
no demuestra comportamiento. Las correcciones de la verificación final (F-01, F-05, F-06, F-08) se validan en la
próxima ejecución del workflow (aquí sólo compila `:core`). **Emulador Sí** = la pantalla se dibuja en una
captura con datos DEMO; las capturas usan el marcador simulado y nunca pulsan «Llamar», así que el
**marcador real no se ha probado en emulador**. Hardware: **No** en todas las filas.

Qué marcador se usa (F-02): Release y Debug normal usan el **marcador real** (`SystemEmergencyDialer`,
`ACTION_DIAL`). Sólo los escenarios DEMO de Debug (extra `demo.scenario`, proceso depurable) lo cambian por
`FakeEmergencyDialer`; entonces la pantalla SOS muestra la marca **DEMO**, «Modo demostración: no se abre
ninguna llamada» y, tras pulsar, «Simulado: no se ha abierto el marcador» (nunca «Marcador abierto»).

| Capacidad | Tests JVM | CI build+lint | Emulador | Hardware | Notas |
|---|---|---|---|---|---|
| Número 112 (España/UE), no deducido del idioma; `tel:112`; número inválido → sin URI | Sí (`EmergencyInfoTest`, incl. con varios `Locale`) | Sí | Sí (captura `sos`: texto «Llamar/Marcar 112») | No | `EmergencyNumber.SPAIN_EU`. |
| Entrega con `Intent.ACTION_DIAL` + `FLAG_ACTIVITY_NEW_TASK`; nunca `ACTION_CALL`; sin `CALL_PHONE` | Parcial (`AppResourcesTest` comprueba manifest y que no se usa `Intent.ACTION_CALL`) | Sí | No (marcador real no probado) | No | `platform/Emergency.kt` `SystemEmergencyDialer`. `<queries>` DIAL+`tel`. |
| `ActivityNotFoundException` → `NoDialer`; `SecurityException`/otros → `Failed`; sin excepción → `HandedToSystem` | Sí para la presentación (`SosPresentationTest`); el adaptador real sólo revisado | Sí | No | No | `HandedToSystem` sólo significa que `startActivity` no lanzó, no que haya llamada. |
| Mensajes: «Marcador abierto con el 112. Pulsa llamar si es seguro.» (sólo marcador real) / «Simulado: no se ha abierto el marcador.» (DEMO) / instrucciones de SOS del reloj y del móvil; nunca «Emergencia enviada», «Ayuda en camino» ni «llamada realizada» | Sí (`SosPresentationTest`, `AppResourcesTest` es/en) | Sí | No (las capturas no pulsan «Llamar») | No | Anunciado con `liveRegion` (TalkBack sin verificar). |
| Texto «Llamar al 112» / «Marcar 112» según `FEATURE_TELEPHONY` (+ `FEATURE_TELEPHONY_CALLING` en API 33+); el intento NUNCA se bloquea | Sí (`SosPresentationTest`) | Sí | Sí (captura; valor del emulador) | No | Valor real de las features en relojes BT/LTE: sin verificar. |
| `FakeEmergencyDialer` (no abre nada, `isSimulated`) | Sí (`SosPresentationTest`: nunca `DIALER_OPENED`) | Sí | Sí (escenarios DEMO de las capturas) | n/a | Tests y escenarios DEMO de Debug. La pantalla SOS lo marca DEMO + «Simulado». Debug normal y Release usan el marcador real. |
| Resumen de ubicación: 5 decimales con punto, N/S/E/O (W en inglés), ±m, antigüedad; `CURRENT` ≤ 60 s / `LAST_KNOWN` ≤ 5 min / `STALE` / `NO_SIGNAL` / `PERMISSION_DENIED` | Sí (paridad con `EmergencyInfoTests.swift`) | Sí | Parcial (sólo los estados del emulador) | No | `core/EmergencyInfo.kt`. |
| SOS no pide permiso ni espera GPS; última conocida + una lectura `getCurrentLocation` (API 30+) con `CancellationSignal` al salir | n/a | Sí | No (revisión de código) | No | `EmergencyLocationReader`. «Estas coordenadas no se envían al 112 automáticamente.» Nada se envía. |
| La ruta `sos` sólo se abre desde la app (F-05): `MainActivity` descarta `intent.data` y los extras de deep link de Navigation de otras apps | n/a | Sí | No | No | Excepción: la URI exacta del escenario DEMO de Debug (`DemoHooks.allowedNavUri`, null en Release). |
| «SOS» fijo arriba a la derecha (fuera de la `ScalingLazyColumn`, bajo TimeText), con fondo opaco y hueco reservado por `contentPadding` | n/a | Sí | Sí (capturas redondo pequeño/grande, `font_scale 1.3`) | No | Cuadrado: sin verificar. |
| Objetivo táctil «SOS» ≥ 48×48 dp, visual compacto, texto (no icono) | n/a | Sí | No (revisión de código) | No | `sizeIn(minWidth = 48.dp, minHeight = 48.dp)`. |
| Contraste ≥ 4,5:1 del rojo `critical` (texto SOS y «Llamar al 112») en Negro y Perla | Sí (`DesignTokensTest`: 8,25 y 6,10 sobre fondo) | n/a | Sí (capturas negro/perla) | No | Mismos hex que `DesignTokens.swift` (test de paridad). Al sol: hardware. |
| Tema Negro/Perla persistido, Negro por defecto | Sí (`ThemeId.fromStorage`) | Sí | Sí (capturas) | No | `data/ThemeStore.kt`; selector en Ajustes. |
| Volver (gesto del sistema, atrás o «Volver») restaura Inicio y su posición de scroll | n/a | Sí | No | No | `rememberScalingLazyListState` en la ruta `home` (guardado con la entrada del back stack). |
| Abrir/cerrar SOS no pausa ni finaliza el trayecto; funciona sin sesión ni backend | n/a | Sí | No (revisión de código) | No | La ruta `sos` no toca el `CaminoController`. |
| Sin doble inicio («Iniciar trayecto» deshabilitado + `ActionGate` en el ViewModel) | Sí (`ActionGate` en `TripFiguresTest`) | Sí | No | No | |
| Cifras sin ceros falsos («sin datos» si no hay sensor/permiso) | Sí (`TripFiguresTest`, `PresentationTest` de `:app` en CI) | Sí | Parcial (capturas DEMO) | No | |
| «Finalizar trayecto» al final, tras divisor; confirmación; cancelar conserva datos | n/a | Sí | Parcial (captura de la ruta) | No | Ruta `confirm_finish` existente. |
| TalkBack: «SOS, botón, … abrir la pantalla de emergencia»; orden cabecera → cifras → finalizar; unidades en palabras | n/a | Sí | No | No | `contentDescription` + `onClickLabel`; probar con TalkBack real. |
| Letra grande sin recortes; corona/bisel (`ScalingLazyColumn`, rotary por defecto en Wear Compose 1.4) | n/a | Sí | Parcial (`font_scale 1.3`; rotary no) | No | |
| Español e inglés con las mismas claves y marcadores | Sí (`AppResourcesTest`) | Sí (lint `MissingTranslation`) | Sí (pasada en inglés) | No | |
| SOS nativo (Pixel: corona ×5; Samsung: Home ×3; otros) | n/a | n/a | n/a | No | Sin identificación fiable del gesto: texto genérico + «varía según el fabricante». |
| Satélite (Pixel Watch 4/5 LTE, por texto) | n/a | n/a | n/a | No | Sin API; la app sólo lo menciona y no lo controla. |
| Continuar en el móvil | n/a | n/a | n/a | n/a | No implementado: `RemoteActivityHelper` sólo admite `ACTION_VIEW` + `BROWSABLE`. |

## Pendiente en hardware / emulador (Wear OS)

1. CI: volver a pasar `assembleDebug/Release`, `lintDebug` y `testDebugUnitTest` tras las correcciones de la
   verificación final (no compilables aquí).
2. Emulador: el marcador real (`ACTION_DIAL`) no se ha probado; las capturas usan el simulado.
3. Qué app maneja `ACTION_DIAL tel:112` en Pixel Watch / Galaxy Watch (LTE y sólo Bluetooth) y qué
   resultado da (`HandedToSystem` / `NoDialer`). **Sin completar la llamada.**
4. Valores reales de `FEATURE_TELEPHONY` / `FEATURE_TELEPHONY_CALLING` por modelo.
5. Cabecera «SOS» en redondo 192 dp y cuadrado, con TimeText y tamaño de letra máximo; rotary.
6. TalkBack: lectura y orden; restauración del scroll al volver de SOS.
7. Lectura única de ubicación con permiso y sin trayecto; Perla al sol.

## Tabla comparativa por plataforma

| Capacidad | watchOS | Wear OS |
|---|---|---|
| Número 112 (España/UE) y URL `tel:` | Tests unitarios: Sí · CI build: Sí · Simulador: Sí (captura `sos`) · Hardware: No | Tests JVM: Sí (`EmergencyInfoTest`) · CI build+lint: Sí · Emulador: Sí (captura) · Hardware: No |
| Entrega de la llamada al sistema | `openSystemURL(tel:112)`. Tests: n/a · CI build: Sí (Debug y Release) · Simulador: No (marcador real no probado) · Hardware: No | `ACTION_DIAL tel:112` (nunca `ACTION_CALL`, sin `CALL_PHONE`). Tests JVM: n/a (sólo guarda de manifest/código en `AppResourcesTest`) · CI build+lint: Sí · Emulador: No (marcador real no probado) · Hardware: No |
| Mensaje honesto tras pedir la llamada | Tests: Sí (mock) · CI build: Sí · Simulador: Sí (mock: «Simulado…») · Hardware: No | Tests JVM: Sí (`SosPresentationTest`; textos en `AppResourcesTest`) · CI build+lint: Sí · Emulador: No (no se pulsa «Llamar») · Hardware: No |
| Marcador simulado en DEMO/capturas/tests | Tests: Sí (`MockEmergencyDialer`) · CI build: Sí · Simulador: Sí (escenarios DEMO de capturas). Debug normal y Release usan el marcador real; los escenarios DEMO usan el simulado, con marca DEMO y «Simulado: no se ha pedido ninguna llamada» · Hardware: n/a | Tests JVM: Sí (`FakeEmergencyDialer`, `isSimulated`) · CI build+lint: Sí · Emulador: Sí (escenarios DEMO de capturas). Debug normal y Release usan el marcador real; los escenarios DEMO usan el simulado, con marca DEMO y «Simulado: no se ha abierto el marcador» · Hardware: n/a |
| Resumen de ubicación (formato y estados) | Tests: Sí · Simulador: parcial · Hardware: No | Tests JVM: Sí (mismos casos que watchOS) · CI build+lint: Sí · Emulador: parcial · Hardware: No |
| Botón «SOS» en cabecera, ≥ objetivo mínimo | Tests: n/a · Simulador: parcial · Hardware: No | Tests JVM: n/a · CI build+lint: Sí · Emulador: Sí (render en capturas; tamaño táctil por revisión de código: 48×48 dp, fuera de la lista) · Hardware: No |
| Contraste en ambos temas | Tests: Sí · Simulador: Sí · Hardware: No | Tests JVM: Sí (`DesignTokensTest`, mismos hex que watchOS) · Emulador: Sí (capturas negro/perla) · Hardware: No |
| Volver restaura pantalla y desplazamiento | Tests: n/a · Simulador: No · Hardware: No | Tests JVM: n/a · Emulador: No (revisión de código: estado de lista en la ruta de Inicio) · Hardware: No |
| Lector de pantalla | Tests: n/a · Simulador: No · Hardware: No | Tests JVM: n/a · Emulador: No · Hardware: No (TalkBack) |
| Idiomas es/en | Tests: Sí · Simulador: Sí · Hardware: No | Tests JVM: Sí (claves y marcadores, `AppResourcesTest`) · CI lint `MissingTranslation`: Sí · Emulador: Sí (pasada en inglés) · Hardware: No |
| SOS nativo / satélite (función del sistema) | Hardware: No (sólo se explica) | Hardware: No (sólo se explica; genérico + «varía según el fabricante») |

## Pendiente en hardware (watchOS)

1. `openSystemURL(tel:112)` en Apple Watch con celular, GPS con iPhone cerca y sin iPhone: número de
   confirmaciones, si se enruta como llamada de emergencia. **Sin completar la llamada** (cancelar en la
   confirmación) para no molestar al servicio.
2. Barra superior: «SOS» fijo al desplazar con la corona, tamaño táctil real, convivencia con la hora.
3. VoiceOver: lectura del «SOS», orden de lectura y distinción con «Finalizar trayecto».
4. Legibilidad al sol (Perla y Negro) y con Always On.
5. Lectura única de ubicación al abrir el SOS con permiso concedido y sin trayecto.
