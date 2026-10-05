# Iconos de Camino Seguro

Fuentes recibidas del equipo (2026-10-05), convertidas a PNG sin cambios: `fuente-*.png`.

| Fuente | Uso decidido | Por qué |
|---|---|---|
| `fuente-cruz-roja.png` (concha marfil, cruz de Santiago roja, fondo negro) | **Icono de la app** (watchOS `AppIcon`, Wear OS primer plano adaptativo) | Plano, sin degradados (reglas Rams/Braun del sistema de diseño), usa los mismos colores que los temas Negro/Perla y la cruz sigue legible a ~40 px en la pantalla de apps. |
| `fuente-cruz-negra.png` (silueta blanca, cruz calada) | **Marca monocroma** (`marca-monocroma.png`): complicaciones, notificaciones, icono temático de Android | Es la forma más legible con una sola tinta, que es como el sistema pinta complicaciones y notificaciones. |
| `fuente-titanio.png`, `fuente-titanio-marco.png` | **Material promocional** (ficha de tienda, web, presentaciones) | Muy atractivo en grande, pero a tamaño de reloj la cruz gris sobre gris se pierde y sus degradados y relieve contradicen las reglas del sistema de diseño. Los iconos del sistema además no deben llevar marco ni esquinas propias (el reloj aplica su propia máscara). |

## Derivados generados

- `watchos/CaminoWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png` — 1024×1024 sin alfa.
- `watchos/CaminoWidgets/Assets.xcassets/ShellMark.imageset/` — marca plantilla @2x/@3x para complicaciones.
- `wearos/app/src/main/res/drawable-*/ic_launcher_foreground.png` — concha en la zona segura (60 dp de 108 dp) sobre fondo `#000000`.
- `wearos/app/src/main/res/drawable-*/ic_launcher_monochrome.png`, `ic_stat_camino.png`, `ic_complication.png` — marca monocroma.

Pendiente: si existen versiones vectoriales (SVG/PDF) de la concha, sustituirlas permitiría
generar las variantes Android como vectores y nitidez perfecta a cualquier escala.
