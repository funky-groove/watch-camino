# Camino Seguro Watch — estado real y hoja de ruta

Actualizado: 2026-10-05. Rama `claude/security-p0-trust-landing-2zoot0`.

Leyenda de evidencia:

- **Tests** = tests unitarios/conformidad ejecutados (Swift 6.0.3 en Linux y macOS CI; Kotlin/JVM local y CI).
- **CI** = compila en GitHub Actions (Xcode 16 / Android SDK) en Debug y Release; Wear OS además con lint.
- **Sim/Emu** = capturas reales en simulador watchOS / emulador Wear OS con escenarios DEMO (datos simulados).
- **HW** = probado en reloj físico. **Nada está probado en hardware todavía.**

## 1. Capacidades por plataforma

| Capacidad | watchOS | Wear OS | Evidencia | Falta |
|---|---|---|---|---|
| Iniciar / pausar / reanudar / finalizar trayecto, sin doble inicio | Implementado | Implementado | Tests + CI + Sim/Emu | HW |
| Persistencia y recuperación tras cierre (incl. ficheros corruptos) | Implementado | Implementado | Tests | HW (muerte real del proceso) |
| Distancia GPS, tiempo en movimiento, ritmo/velocidad | Implementado | Implementado | Tests (vectores comunes) | HW (precisión real del GPS) |
| Altitud, subida/bajada con histéresis, perfil registrado | Implementado | Implementado | Tests + Sim/Emu | HW (altitud GPS real) |
| Pasos | CMPedometer | Sensor de pasos | CI | HW |
| Avisos de lugares (1 por lugar y trayecto, ≤1/min, por categoría) | Implementado | Implementado | Tests | HW (notificaciones en segundo plano) |
| Lugares + ficha + «Llamar» si hay teléfono | Implementado | Implementado | Tests + CI | Datos reales (fixtures sin teléfonos) |
| SOS: pantalla, «Llamar al 112» entregado al sistema | `openSystemURL(tel:112)` | `ACTION_DIAL tel:112` | Tests (mock) + CI + capturas | **HW: confirmar qué abre el sistema sin completar la llamada** |
| SOS: ubicación con antigüedad y precisión | Implementado | Implementado | Tests | HW |
| SOS satelital | Sólo instrucciones (lo gestiona el sistema) | Sólo instrucciones | Docs oficiales | Demo oficial en Ultra 3 / Pixel Watch 4 |
| Complicación (sin trayecto «Iniciar trayecto»; distancia + en marcha/pausado; «sin GPS») | WidgetKit | ComplicationDataSourceService | CI (previews en Xcode) | HW (refresco real según presupuesto) |
| Aviso «Accede desde tu esfera» + Ajustes → Cómo añadirlo | Implementado | Implementado | CI + Sim/Emu | — |
| Temas Negro / Perla con contraste verificado | Implementado | Implementado | Tests de contraste | Legibilidad al sol (HW) |
| Español / inglés | Idioma del reloj | Selector (API 33+) | CI (claves completas) | Revisión nativa del inglés |
| Unidades métricas/imperiales, ritmo/velocidad | Implementado | Implementado | Tests (vectores) | — |
| Accesibilidad (VoiceOver/TalkBack, texto grande, objetivos ≥44 pt/48 dp) | Implementado | Implementado | Revisión de código + capturas con texto grande | Prueba con lectores de pantalla y con personas |
| Inicio de sesión (Supabase Auth) | **No implementado** | **No implementado** | — | Configuración Supabase + decisión de flujo |
| Sincronización con backend | Cola offline lista, adaptador bloqueado | Igual | Tests | Contrato del backend |

## 2. Bloqueos externos (no se resuelven con código)

| Bloqueo | Quién | Qué hace falta |
|---|---|---|
| Contrato del backend / Supabase | Equipo backend | URL del proyecto, clave anon/publishable, proveedor Google y URLs de redirección, si el reloj habla con PostgREST o con el API FastAPI (OpenAPI + validación JWT). Nunca la `service_role`. |
| Autenticación de usuarios de correo y contraseña en el reloj | Equipo backend | Código de vinculación aprobado desde la PWA (Wear OS prohíbe pedir usuario/contraseña en el reloj, WO-P6). |
| Identificadores definitivos | Producto | Confirmar dominio y fijar `com.caminoseguro.app` / `.watchkitapp` (PROPUESTA en `docs/release/DISTRIBUTION_AND_IDENTITY.md`). Irreversible tras la primera subida. |
| Cuentas | Producto | Apple Developer Program, Google Play Console (prueba cerrada obligatoria si la cuenta es personal y nueva). |
| Iconos definitivos | Diseño | Subir a `design/icons/` (SVG o PNG 1024). Hoy: icono provisional. |
| Relojes físicos | QA | Un Apple Watch (idealmente con celular) y un Wear OS (LTE y sólo Bluetooth). |
| PWA «Usar en el reloj» | Equipo web | Integrar `docs/pwa/USAR_EN_EL_RELOJ.md` en el repo de la PWA. |
| Evaluación con usuarios | QA/UX | Ejecutar `docs/qa/USABILITY_TEST_PROTOCOL.md`. |

## 3. Siguientes pasos

1. **Autenticación Supabase** (≈1 día tras recibir la configuración): Google (Credential Manager en Wear OS; `ASWebAuthenticationSession` + PKCE en watchOS), tokens en Keychain/Keystore, renovación y cierre de sesión; código de vinculación cuando exista en el backend.
2. **Adaptador HTTP real** de `CaminoApi` contra el contrato (≈1–2 días), sin tocar el dominio.
3. **Pruebas en hardware** con la lista de `docs/accessibility/SOS_CAPABILITY_MATRIX.md` (sin completar nunca una llamada al 112).
4. **Iconos definitivos** y revisión de textos en inglés.
5. **TestFlight interno y pista interna de Play** con los identificadores definitivos.

## 4. Recomendación: ¿publicar el reloj primero o con la app principal?

**Fijar ya la identidad, probar internamente ya, publicar cuando exista el contrato del backend.**

- Hoy el reloj funciona completo en local, pero sin cuenta ni sincronización: publicarlo así
  daría una app que no conecta con Camino Seguro.
- El identificador es lo único irreversible: decidirlo ahora evita tener que publicar otra app
  distinta cuando llegue la app iOS (Capacitor).
- Con el contrato y la autenticación hechos, el reloj **puede publicarse antes** que la app
  principal (watch-only en Apple; app Wear OS standalone con el mismo `applicationId` futuro en
  Google Play), sin esperar a la app móvil.
- Riesgo de revisión de Apple a vigilar: guideline 5.1.5 (la app no debe presentarse como
  servicio de emergencia; el SOS sólo entrega la llamada al sistema).
