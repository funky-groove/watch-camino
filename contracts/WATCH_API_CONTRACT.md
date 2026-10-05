# Contrato del backend para el reloj — PARCIAL

Estado: **PARCIAL** (2026-10-05). Sustituye a "AUSENTE" en `contracts/README.md`.

Procedencia: inventario **medido** por la sesión de Claude Code que trabaja en el repositorio del
backend (`stjames-dev/stjames`, rama `ai/security-p0-trust-landing-v3`), leyendo el contrato generado
del BFF (`packages/edge-contract/src/edge-contract.ts`) y con peticiones reales. **No verificado desde
este repositorio**: la red de este entorno no permite todavía `api.camino-seguro.app`.
Faltan los **schemas** de petición/respuesta (OpenAPI): sin ellos no se implementa ningún adaptador.

## Topología real

```
reloj → TLS (edge de Fly) camino-seguro-bff  [api.camino-seguro.app]
      → BFF (Hono): origin gate → CSRF → gate del contrato generado → rate limit → X-Internal-Token
      → camino-seguro-api (FastAPI): token interno → verify_supabase_jwt → revocación → ownership
      → Postgres/Supabase (asyncpg) · ~36 rutas vía PostgREST con el JWT del usuario
```

El Cloudflare Worker **no** está en el camino de producción. El reloj habla sólo con el BFF.
`X-Internal-Token`, la `service_role` y cualquier secreto de servidor **nunca** van al reloj.

## Base

`https://api.camino-seguro.app` — sólo `/api/*` es enrutable (el BFF quita `/api` y compara con el
contrato). Las grafías no generalizan: `/api/stamps/check-in` existe, `/api/v1/stamps/check-in` da 404.

## Rutas relevantes para el reloj (según el contrato generado)

| Capacidad | Método y ruta | Límite (por IP) | Uso en el reloj |
|---|---|---|---|
| Iniciar sesión | `POST /api/auth/login` | 10/min | Ver bloqueo B2 |
| Renovar | `POST /api/auth/refresh` | 30/min | `CredentialStore` |
| Cerrar sesión | `POST /api/auth/logout` | 30/min | Ajustes |
| Quién soy | `GET /api/auth/me` | 60/min | Estado de sesión |
| Journey actual | `GET /api/journeys/current` | 60/min | Recuperación |
| Crear journey | `POST /api/journeys` | 10/min | Iniciar trayecto |
| Iniciar / finalizar journey | `POST /api/journeys/{id}/start`, `/finish` | 10/min | — |
| Iniciar / finalizar etapa | `POST /api/journeys/{id}/stages/start`, `/stages/finish` | 30/min | `stage_started` / `stage_finished` |
| Puntos | `POST /api/journeys/{id}/points/relevant`, `/points/manual` | 60/min | (no V1: sin traza GPS) |
| POI cercanos | `GET /api/pois/nearby?lat=&lon=&…` | 60/min, caché 600 s | `PoiSource` |
| Listado POI | `GET /api/pois?bbox=…` | 120/min, caché 300 s | Lugares |
| JWKS | `GET /.well-known/jwks.json` | 200/min, sin Origin | — |

## Bloqueos (se arreglan en el backend, no en el reloj)

| ID | Bloqueo | Efecto en el reloj | Arreglo propuesto (backend) |
|---|---|---|---|
| **B1** | **Muro de `Origin`**: sin `Origin` las rutas autenticadas devuelven `403 origin_forbidden`; con `Origin: https://camino-seguro.app` → 200. | Un cliente nativo sólo pasaría **fingiendo ser un navegador**. El reloj **no lo hará** (sería eludir un control de seguridad). | Filas del contrato para clientes nativos que no exijan `Origin` pero sí Bearer válido (y, idealmente, atestación de app). |
| **B2** | Login por contraseña en `/api/auth/login`; no hay `/api/auth/native/*` (su ausencia está fijada por test) ni identidad de dispositivo. | Wear OS prohíbe pedir usuario/contraseña en el reloj (WO-P6). Sin revocación por dispositivo. | Flujo nativo: Google (ID token) y código de vinculación aprobado desde la PWA; sesiones por dispositivo revocables. |
| **B3** | `POST /api/pois/nearby` da 404 (sólo existe `GET`). | Ninguno si el reloj usa `GET`. | Alinear PWA y contrato. |
| **B4** | Rate limit por IP, 60/min para toda la superficie autenticada. | Reloj y teléfono detrás del mismo NAT comparten cubo. | Límite por usuario/dispositivo. |
| **B5** | No hay endpoint de entitlement (premium). | El reloj no puede saber si el usuario es premium. | Endpoint de lectura de entitlements. |
| **B6** | Manifiesto de la imagen de bienvenida (backoffice) aún no existe. | Bienvenida con logo incluido. | Endpoint de manifiesto `{url, sha256, bytes}` en estas mismas rutas. |

## Medición desde este repositorio (2026-10-05, ~21:00 UTC, sin `Origin`, sin credenciales)

| Petición | Respuesta |
|---|---|
| `GET /health` | `200 {"status":"ok","service":"bff"}` — el BFF responde |
| `GET /api/health`, `/openapi.json`, `/api/openapi.json`, `/api/docs` | `404 No route` — no hay OpenAPI publicado |
| `GET /.well-known/jwks.json` | `403 {"detail":"Privileged route requires Worker proxy bearer (X-Internal-Token)"}` |
| `GET /api/pois/nearby?lat=42.78&lon=-7.41` | ídem 403 |
| `GET /api/auth/me`, `GET /api/journeys/current` | ídem 403 |

Lectura: el error tiene formato de FastAPI (`detail`), así que el BFF **sí** reenvía la petición, pero
FastAPI rechaza el token interno con el que llega. Incluso JWKS, que el contrato declara pública, falla.
Es coherente con el incidente de producción ya identificado en la sesión del backend
(`INTERNAL_FASTAPI_TOKEN` con valores distintos en API/BFF/backoffice y secretos de la API en estado
*Staged* sin aplicar). **Mientras eso no se corrija, ningún cliente (tampoco el reloj) puede usar rutas
del API a través del BFF.** No es un problema del reloj.

## Cloudflare Worker (README del repositorio del backend, aportado por el equipo)

- Diseño previsto: PWA → Worker (CORS, rate limit, proxy; inyecta `X-Internal-Token`) → FastAPI.
- Dominio de ejemplo del README `worker.camino.app`: **no resuelve en DNS** (2026-10-05).
  `worker.camino-seguro.app` tampoco. `api.camino-seguro.app` resuelve a `camino-seguro-bff.fly.dev`
  y sus cabeceras (`server: Fly`, `via: fly.io`, sin `cf-ray`) no muestran Cloudflare.
- Su lista de rutas permitidas sólo cubre certificados, sellos, compras, revocaciones, verificación y
  JWKS: **no** incluye `/api/auth/*`, `/api/journeys/*` ni `/api/pois/*`, que son las que usa el reloj.
- También exige `Origin` en `ALLOWED_ORIGINS` (mismo bloqueo B1).

Conclusión: hoy el reloj sólo puede hablar con el BFF de Fly (`api.camino-seguro.app`); el Worker,
si se reactiva, necesitaría las mismas rutas nativas que el BFF.

## Qué falta para implementar el adaptador HTTP

1. OpenAPI (o schemas) de las rutas de la tabla.
2. Resolver B1 y B2.
3. Acceso de red de este entorno a `api.camino-seguro.app` para pruebas reales.
4. Una cuenta de prueba en un entorno no productivo.
