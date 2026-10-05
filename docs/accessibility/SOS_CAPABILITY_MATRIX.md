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

| Capacidad | Tests unitarios | Simulador CI | Hardware | Notas |
|---|---|---|---|---|
| Número 112 con alcance España/UE, sin deducirlo del idioma | Sí (`EmergencyInfoTests`) | n/a | No | `EmergencyNumber.spainEU`; constante, documentada como no universal. |
| URL `tel:112` válida; número inválido → sin URL | Sí | n/a | No | `EmergencyNumber.telURL`. |
| Entrega al sistema con `WKApplication.shared().openSystemURL` | n/a | Sólo compila | No | `SystemEmergencyDialer`. La API no devuelve resultado: sólo `.handedToSystem`. Confirmación del sistema (y posible doble confirmación, bug de 2020) **sin verificar**. |
| Resultado honesto (`handedToSystem` / `failed`), nunca «conectada» | Sí (marcador simulado) | Sí (texto en pantalla, mock) | No | Texto: «Llamada solicitada al reloj. Si no aparece, usa el SOS del reloj…». |
| Marcador simulado en DEMO/capturas/tests (no abre nada) | Sí (`MockEmergencyDialer`) | Sí (escenarios `-demo.scenario`) | n/a | Todos los escenarios DEMO usan el mock. |
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
**CI build+lint** (`.github/workflows/wearos.yml`: `assembleDebug/Release`, `lintDebug`, `testDebugUnitTest`) ·
**Emulador** · **Hardware**. En esta sesión sólo se han ejecutado los tests JVM: el módulo `:app` no se
pudo compilar aquí (sin Android SDK ni acceso a Google Maven), así que **CI build+lint queda pendiente**
de la próxima ejecución del workflow. Emulador y hardware: **No** en todas las filas.

| Capacidad | Tests JVM | CI build+lint | Emulador | Hardware | Notas |
|---|---|---|---|---|---|
| Número 112 (España/UE), no deducido del idioma; `tel:112`; número inválido → sin URI | Sí (`EmergencyInfoTest`, incl. con varios `Locale`) | pendiente | No | No | `EmergencyNumber.SPAIN_EU`. |
| Entrega con `Intent.ACTION_DIAL` + `FLAG_ACTIVITY_NEW_TASK`; nunca `ACTION_CALL`; sin `CALL_PHONE` | Parcial (`AppResourcesTest` comprueba manifest y que no se usa `Intent.ACTION_CALL`) | pendiente | No | No | `platform/Emergency.kt` `SystemEmergencyDialer`. `<queries>` DIAL+`tel`. |
| `ActivityNotFoundException` → `NoDialer`; `SecurityException`/otros → `Failed`; sin excepción → `HandedToSystem` | Sí para la presentación (`SosPresentationTest`); el adaptador real sólo revisado | pendiente | No | No | `HandedToSystem` sólo significa que `startActivity` no lanzó, no que haya llamada. |
| Mensajes: «Marcador abierto con el 112. Pulsa llamar si es seguro.» / instrucciones de SOS del reloj y del móvil; nunca «Emergencia enviada», «Ayuda en camino» ni «llamada realizada» | Sí (`SosPresentationTest`, `AppResourcesTest` es/en) | pendiente | No | No | Anunciado con `liveRegion` (TalkBack sin verificar). |
| Texto «Llamar al 112» / «Marcar 112» según `FEATURE_TELEPHONY` (+ `FEATURE_TELEPHONY_CALLING` en API 33+); el intento NUNCA se bloquea | Sí (`SosPresentationTest`) | pendiente | No | No | Valor real de las features en relojes BT/LTE: sin verificar. |
| `FakeEmergencyDialer` (no abre nada) | Sí | n/a | n/a | n/a | Sólo tests. Debug/DEMO usa el marcador real: un SOS que no marca en una build instalada sería peligroso. |
| Resumen de ubicación: 5 decimales con punto, N/S/E/O (W en inglés), ±m, antigüedad; `CURRENT` ≤ 60 s / `LAST_KNOWN` ≤ 5 min / `STALE` / `NO_SIGNAL` / `PERMISSION_DENIED` | Sí (paridad con `EmergencyInfoTests.swift`) | pendiente | No | No | `core/EmergencyInfo.kt`. |
| SOS no pide permiso ni espera GPS; última conocida + una lectura `getCurrentLocation` (API 30+) con `CancellationSignal` al salir | n/a | pendiente | No | No | `EmergencyLocationReader`. «Estas coordenadas no se envían al 112 automáticamente.» Nada se envía. |
| «SOS» fijo arriba a la derecha (fuera de la `ScalingLazyColumn`, bajo TimeText), con fondo opaco y hueco reservado por `contentPadding` | n/a | pendiente | No | No | Revisión de código; comprobar en redondo 192 dp y cuadrado, con letra grande. |
| Objetivo táctil «SOS» ≥ 48×48 dp, visual compacto, texto (no icono) | n/a | pendiente | No | No | `sizeIn(minWidth = 48.dp, minHeight = 48.dp)`. |
| Contraste ≥ 4,5:1 del rojo `critical` (texto SOS y «Llamar al 112») en Negro y Perla | Sí (`DesignTokensTest`: 8,25 y 6,10 sobre fondo) | n/a | No | No | Mismos hex que `DesignTokens.swift` (test de paridad). Al sol: hardware. |
| Tema Negro/Perla persistido, Negro por defecto | Sí (`ThemeId.fromStorage`) | pendiente | No | No | `data/ThemeStore.kt`; selector en Ajustes. |
| Volver (gesto del sistema, atrás o «Volver») restaura Inicio y su posición de scroll | n/a | pendiente | No | No | `rememberScalingLazyListState` en la ruta `home` (guardado con la entrada del back stack). |
| Abrir/cerrar SOS no pausa ni finaliza el trayecto; funciona sin sesión ni backend | n/a | pendiente | No | No | La ruta `sos` no toca el `CaminoController`. |
| Sin doble inicio («Iniciar trayecto» deshabilitado + `ActionGate` en el ViewModel) | Sí (`ActionGate` en `TripFiguresTest`) | pendiente | No | No | |
| Cifras sin ceros falsos («sin datos» si no hay sensor/permiso) | Sí (`TripFiguresTest`, `PresentationTest` de `:app` en CI) | pendiente | No | No | |
| «Finalizar trayecto» al final, tras divisor; confirmación; cancelar conserva datos | n/a | pendiente | No | No | Ruta `confirm_finish` existente. |
| TalkBack: «SOS, botón, … abrir la pantalla de emergencia»; orden cabecera → cifras → finalizar; unidades en palabras | n/a | pendiente | No | No | `contentDescription` + `onClickLabel`; probar con TalkBack real. |
| Letra grande sin recortes; corona/bisel (`ScalingLazyColumn`, rotary por defecto en Wear Compose 1.4) | n/a | pendiente | No | No | |
| Español e inglés con las mismas claves y marcadores | Sí (`AppResourcesTest`) | pendiente (lint `MissingTranslation`) | No | No | |
| SOS nativo (Pixel: corona ×5; Samsung: Home ×3; otros) | n/a | n/a | n/a | No | Sin identificación fiable del gesto: texto genérico + «varía según el fabricante». |
| Satélite (Pixel Watch 4/5 LTE, por texto) | n/a | n/a | n/a | No | Sin API; la app sólo lo menciona y no lo controla. |
| Continuar en el móvil | n/a | n/a | n/a | n/a | No implementado: `RemoteActivityHelper` sólo admite `ACTION_VIEW` + `BROWSABLE`. |

## Pendiente en hardware / emulador (Wear OS)

1. CI: `assembleDebug/Release`, `lintDebug` y `testDebugUnitTest` del módulo `:app` (no ejecutados en esta sesión).
2. Qué app maneja `ACTION_DIAL tel:112` en Pixel Watch / Galaxy Watch (LTE y sólo Bluetooth) y qué
   resultado da (`HandedToSystem` / `NoDialer`). **Sin completar la llamada.**
3. Valores reales de `FEATURE_TELEPHONY` / `FEATURE_TELEPHONY_CALLING` por modelo.
4. Cabecera «SOS» en redondo 192 dp y cuadrado, con TimeText y tamaño de letra máximo; rotary.
5. TalkBack: lectura y orden; restauración del scroll al volver de SOS.
6. Lectura única de ubicación con permiso y sin trayecto; Perla al sol.

## Tabla comparativa por plataforma

| Capacidad | watchOS | Wear OS |
|---|---|---|
| Número 112 (España/UE) y URL `tel:` | Tests unitarios: Sí · Simulador: n/a · Hardware: No | Tests JVM: Sí (`EmergencyInfoTest`) · CI build+lint: pendiente · Emulador: No · Hardware: No |
| Entrega de la llamada al sistema | Tests: n/a · Simulador: sólo compila · Hardware: No | `ACTION_DIAL tel:112` (nunca `ACTION_CALL`, sin `CALL_PHONE`). Tests JVM: n/a (sólo guarda de manifest/código en `AppResourcesTest`) · CI: pendiente · Emulador: No · Hardware: No |
| Mensaje honesto tras pedir la llamada | Tests: Sí (mock) · Simulador: Sí (mock) · Hardware: No | Tests JVM: Sí (`SosPresentationTest` con `FakeEmergencyDialer`; textos en `AppResourcesTest`) · CI: pendiente · Emulador: No · Hardware: No |
| Marcador simulado en DEMO/capturas/tests | Tests: Sí · Simulador: Sí · Hardware: n/a | Tests JVM: Sí (`FakeEmergencyDialer`) · Debug/DEMO usa el marcador REAL (decisión de seguridad) · Hardware: n/a |
| Resumen de ubicación (formato y estados) | Tests: Sí · Simulador: parcial · Hardware: No | Tests JVM: Sí (mismos casos que watchOS) · CI: pendiente · Emulador: No · Hardware: No |
| Botón «SOS» en cabecera, ≥ objetivo mínimo | Tests: n/a · Simulador: parcial · Hardware: No | Tests JVM: n/a · CI: pendiente · Emulador: No (revisión de código: 48×48 dp, fuera de la lista) · Hardware: No |
| Contraste en ambos temas | Tests: Sí · Simulador: Sí · Hardware: No | Tests JVM: Sí (`DesignTokensTest`, mismos hex que watchOS) · Emulador: No · Hardware: No |
| Volver restaura pantalla y desplazamiento | Tests: n/a · Simulador: No · Hardware: No | Tests JVM: n/a · Emulador: No (revisión de código: estado de lista en la ruta de Inicio) · Hardware: No |
| Lector de pantalla | Tests: n/a · Simulador: No · Hardware: No | Tests JVM: n/a · Emulador: No · Hardware: No (TalkBack) |
| Idiomas es/en | Tests: Sí · Simulador: Sí · Hardware: No | Tests JVM: Sí (claves y marcadores, `AppResourcesTest`) · CI lint `MissingTranslation`: pendiente · Hardware: No |
| SOS nativo / satélite (función del sistema) | Hardware: No (sólo se explica) | Hardware: No (sólo se explica; genérico + «varía según el fabricante») |

## Pendiente en hardware (watchOS)

1. `openSystemURL(tel:112)` en Apple Watch con celular, GPS con iPhone cerca y sin iPhone: número de
   confirmaciones, si se enruta como llamada de emergencia. **Sin completar la llamada** (cancelar en la
   confirmación) para no molestar al servicio.
2. Barra superior: «SOS» fijo al desplazar con la corona, tamaño táctil real, convivencia con la hora.
3. VoiceOver: lectura del «SOS», orden de lectura y distinción con «Finalizar trayecto».
4. Legibilidad al sol (Perla y Negro) y con Always On.
5. Lectura única de ubicación al abrir el SOS con permiso concedido y sin trayecto.
