# Contrato del backend — AUSENTE

Estado: **BLOQUEADO** (2026-10-05).

Ninguno de estos ficheros existe en el repositorio ni ha sido suministrado:

- `WATCH_CLIENT_HANDOFF.md`
- `WATCH_API_CONTRACT.md`
- `openapi-watch.json`
- `openapi.json`

El backend de Camino Seguro vive en un repositorio que este proyecto no puede leer.
Mientras no se copie aquí el contrato real, las apps de reloj **no** contienen:
endpoints, URLs, schemas remotos, JWT, flujo de autenticación, Premium ni modelos remotos.

Toda integración remota pasa por el puerto `CaminoApi` (ver `docs/WATCH_V1_SPEC.md` §0 y §9),
cuyo adaptador de Release es `BlockedCaminoApi`.

## Para desbloquear

1. Copiar aquí el contrato real (OpenAPI + documento de handoff) tal como lo publica el backend.
2. Responder en él, como mínimo: URL base por entorno, autenticación del reloj (cómo obtiene y
   renueva credenciales un dispositivo sin teclado), endpoint de catálogo de etapas y POIs,
   endpoint de ingesta de eventos con idempotencia (`eventId`), códigos de error y semántica de reintento.
3. Implementar un adaptador `HttpCaminoApi` en cada plataforma contra ese contrato, sin tocar el dominio.
