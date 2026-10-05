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

## Tabla comparativa por plataforma

| Capacidad | watchOS | Wear OS |
|---|---|---|
| Número 112 (España/UE) y URL `tel:` | Tests unitarios: Sí · Simulador: n/a · Hardware: No | pendiente |
| Entrega de la llamada al sistema | Tests: n/a · Simulador: sólo compila · Hardware: No | pendiente |
| Mensaje honesto tras pedir la llamada | Tests: Sí (mock) · Simulador: Sí (mock) · Hardware: No | pendiente |
| Marcador simulado en DEMO/capturas/tests | Tests: Sí · Simulador: Sí · Hardware: n/a | pendiente |
| Resumen de ubicación (formato y estados) | Tests: Sí · Simulador: parcial · Hardware: No | pendiente |
| Botón «SOS» en cabecera, ≥ objetivo mínimo | Tests: n/a · Simulador: parcial · Hardware: No | pendiente |
| Contraste en ambos temas | Tests: Sí · Simulador: Sí · Hardware: No | pendiente |
| Volver restaura pantalla y desplazamiento | Tests: n/a · Simulador: No · Hardware: No | pendiente |
| Lector de pantalla | Tests: n/a · Simulador: No · Hardware: No | pendiente |
| Idiomas es/en | Tests: Sí · Simulador: Sí · Hardware: No | pendiente |
| SOS nativo / satélite (función del sistema) | Hardware: No (sólo se explica) | pendiente |

## Pendiente en hardware (watchOS)

1. `openSystemURL(tel:112)` en Apple Watch con celular, GPS con iPhone cerca y sin iPhone: número de
   confirmaciones, si se enruta como llamada de emergencia. **Sin completar la llamada** (cancelar en la
   confirmación) para no molestar al servicio.
2. Barra superior: «SOS» fijo al desplazar con la corona, tamaño táctil real, convivencia con la hora.
3. VoiceOver: lectura del «SOS», orden de lectura y distinción con «Finalizar trayecto».
4. Legibilidad al sol (Perla y Negro) y con Always On.
5. Lectura única de ubicación al abrir el SOS con permiso concedido y sin trayecto.
