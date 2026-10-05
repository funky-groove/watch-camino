# Vectores de conformidad

Generados por `reference.py` (implementación de referencia de `docs/WATCH_V1_SPEC.md`).
**No editar los JSON a mano.** Para cambiar una regla: especificación → `reference.py` → regenerar.

Los tests del núcleo Swift (`watchos/CaminoCore/Tests`) y Kotlin (`wearos/core/src/test`) leen
estos ficheros directamente desde esta carpeta y deben pasarlos todos. Es lo que garantiza que
las dos apps se comportan igual.

Convenciones:

- Instantes (`t`, `now`, `lastAlertAt`, `nextAttemptAt`) en **segundos epoch** (`Double`).
- Distancias en metros; comparar con la tolerancia indicada en cada fichero.
- `acc` = precisión horizontal en metros.
- `sync_engine.json`: `responses` se consumen en orden, una por envío; `sent` es la lista de
  eventos que se intentaron enviar en esa ejecución.
- `session_transitions.json`: `queued` es la lista de tipos de evento en la cola de sync tras el paso.

| Fichero | Sección de la spec |
|---|---|
| `haversine.json` | §5 |
| `distance_accumulator.json` | §5 |
| `poi_alerts.json` | §6 |
| `session_transitions.json` | §4 |
| `sync_engine.json`, `backoff.json` | §7 |
| `formatting.json` | §8 |
