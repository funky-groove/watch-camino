# Tokens de diseño — Camino Seguro Watch

> Generado por `watchos/tools/gen_tokens_doc.py`. No editar a mano.

Fuente única: [`DesignTokens.swift`](../../watchos/CaminoCore/Sources/CaminoDesign/DesignTokens.swift) ·
puente SwiftUI: [`watchos/CaminoWatch/Design/`](../../watchos/CaminoWatch/Design/).

## Procedencia de los valores

| Categoría | Valores en esta categoría |
|---|---|
| **Confirmado en código** (app principal) | **Ninguno.** Este repositorio no tiene acceso al código de la app principal (GitLab privado). |
| **Estimado visualmente** (capturas) | **Ninguno.** Las capturas de referencia no se han recibido en esta sesión. |
| **Estimado** | Todos los colores: elegidos según la descripción escrita (negro/antracita, perla cálido, verde/ámbar/rojo) y ajustados para cumplir los umbrales de contraste que `ContrastTests` hace cumplir. |
| **Adaptación watchOS** | Familia SF, objetivos de 44 pt, Negro forzado en Always On, estilos Dynamic Type, Perla con fondo negro (`perlaWatch`, ver abajo). |

Al recibir código o capturas se cambian los valores en `DesignTokens.swift`; `ContrastTests` impide que un valor nuevo rompa el contraste.

## Color

Todos los valores son **estimados** (ver procedencia).

| Token | Uso | Negro | Perla en watchOS (`perlaWatch`) | Perla de referencia (`perla`, Wear OS) |
|---|---|---|---|---|
| `background` | Fondo de pantalla | `#000000` | `#000000` | `#F3EFE7` |
| `surface` | Tarjetas y filas | `#1A1A19` | `#F3EFE7` | `#EAE4D8` |
| `surfaceRaised` | Superficie elevada / pulsada | `#262624` | `#EAE4D8` | `#E1D9CA` |
| `textPrimary` | Texto principal sobre el fondo | `#F2EFE8` | `#F2EFE8` | `#1C1B19` |
| `textSecondary` | Texto secundario sobre el fondo | `#A8A399` | `#A8A399` | `#5B564E` |
| `hairline` | Separadores y bordes finos (decorativos) | `#3B3936` | `#3B3936` | `#CBC2B2` |
| `controlOutline` | Contorno de acción secundaria | `#77726A` | `#857D70` | `#857D70` |
| `actionPrimaryFill` | Fondo de acción principal | `#F2EFE8` | `#F3EFE7` | `#1C1B19` |
| `actionPrimaryText` | Texto de acción principal | `#141413` | `#1C1B19` | `#F3EFE7` |
| `positive` | Positivo / progreso (sobre el fondo) | `#5DBB7E` | `#5DBB7E` | `#24633A` |
| `warning` | Pendiente / advertencia (sobre el fondo) | `#E5A93D` | `#E5A93D` | `#7E5200` |
| `critical` | Error / destructivo / emergencia (sobre el fondo) | `#FF7A6B` | `#FF7A6B` | `#A8291F` |
| `onSurfacePrimary` | Texto principal sobre superficie (tarjetas, filas, botones) | `#F2EFE8` | `#1C1B19` | `#1C1B19` |
| `onSurfaceSecondary` | Texto secundario sobre superficie | `#A8A399` | `#5B564E` | `#5B564E` |
| `positiveOnSurface` | Positivo sobre superficie | `#5DBB7E` | `#24633A` | `#24633A` |
| `warningOnSurface` | Advertencia sobre superficie | `#E5A93D` | `#7E5200` | `#7E5200` |
| `criticalOnSurface` | Crítico sobre superficie | `#FF7A6B` | `#A8291F` | `#A8291F` |

### Perla en watchOS (`Palette.perlaWatch`)

En watchOS la hora del sistema y el botón «atrás» son **siempre blancos** y no se pueden
configurar: sobre el fondo perla claro quedaban ilegibles. Por eso la app watchOS usa
`Palette.watchOS(.perla) = perlaWatch`:

- **Fondo de pantalla negro** (`#000000`) y texto/estados "sobre fondo" claros, iguales que Negro.
- **Superficies perla** (tarjetas, filas, botones secundarios: `#F3EFE7`, pulsado `#EAE4D8`) con texto
  y estados "sobre superficie" oscuros (`onSurface*`, `*OnSurface`, valores de la Perla de referencia).
- **Acción principal**: relleno perla con texto oscuro.
- Ningún color de estado cumple 4,5:1 a la vez sobre negro y sobre perla, así que cada estado tiene dos
  tokens (`positive` / `positiveOnSurface`, …). En Negro y en la Perla de referencia son iguales.
- `Palette.perla` (fondo claro) **no cambia**: es la que replica Wear OS (`DesignTokens.kt`).
- En SwiftUI, `Card`, `RowButtonStyle` y `SecondaryButtonStyle` pasan a su contenido
  `ThemePalette.onSurface`: cualquier vista anidada que lea `textPrimary` obtiene el color "sobre superficie".
- `AccentColor` del catálogo: neutro claro `#F2EFE8` (títulos de navegación sobre el fondo negro de ambos temas).

- El color nunca comunica un estado por sí solo: siempre símbolo + texto.
- Sin degradados, cristal ni sombras.
- **Adaptación watchOS:** con pantalla siempre activa atenuada (`isLuminanceReduced`) se fuerza Negro: un fondo claro en Always On deslumbra y gasta batería. Perla es una preferencia explícita del producto, disponible en Ajustes, no el valor inicial.

## Contraste (WCAG 2.x)

Umbral aplicado: 4,5:1 a todo texto (también al grande, por margen) y 3:1 a componentes de interfaz. `hairline` es decorativo y no se exige.

| Par | Mínimo | Negro | Perla watchOS | Perla referencia |
|---|---|---|---|---|
| texto principal sobre fondo | 4.5 | 18.29 | 18.29 | 15.01 |
| texto secundario sobre fondo | 4.5 | 8.36 | 8.36 | 6.35 |
| positivo sobre fondo | 4.5 | 8.87 | 8.87 | 6.27 |
| advertencia sobre fondo | 4.5 | 10.07 | 10.07 | 5.92 |
| crítico sobre fondo | 4.5 | 8.25 | 8.25 | 6.10 |
| texto principal (`onSurfacePrimary`) sobre superficie | 4.5 | 15.17 | 15.01 | 13.59 |
| texto principal (`onSurfacePrimary`) sobre superficie elevada | 4.5 | 13.20 | 13.59 | 12.28 |
| texto secundario (`onSurfaceSecondary`) sobre superficie | 4.5 | 6.94 | 6.35 | 5.75 |
| texto secundario (`onSurfaceSecondary`) sobre superficie elevada | 4.5 | 6.04 | 5.75 | 5.19 |
| positivo (`positiveOnSurface`) sobre superficie | 4.5 | 7.36 | 6.27 | 5.68 |
| positivo (`positiveOnSurface`) sobre superficie elevada | 4.5 | 6.41 | 5.68 | 5.13 |
| advertencia (`warningOnSurface`) sobre superficie | 4.5 | 8.36 | 5.92 | 5.36 |
| advertencia (`warningOnSurface`) sobre superficie elevada | 4.5 | 7.27 | 5.36 | 4.84 |
| crítico (`criticalOnSurface`) sobre superficie | 4.5 | 6.84 | 6.10 | 5.53 |
| crítico (`criticalOnSurface`) sobre superficie elevada | 4.5 | 5.95 | 5.53 | 4.99 |
| texto de acción principal | 4.5 | 16.05 | 15.01 | 15.01 |
| acción principal sobre fondo | 3.0 | 18.29 | 18.31 | 15.01 |
| texto de acción de emergencia | 4.5 | 7.24 | 6.76 | 6.10 |
| acción de emergencia sobre fondo | 3.0 | 8.25 | 8.25 | 6.10 |
| contorno de control sobre fondo | 3.0 | 4.40 | 5.16 | 3.55 |
| contorno de control sobre superficie | 3.0 | 3.65 | 3.55 | 3.21 |

## Tipografía

Familia **SF (sistema)** — adaptación watchOS: la familia de la app principal no está confirmada ni se dispone de su licencia.

| Estilo | Base Dynamic Type | Peso | Uso |
|---|---|---|---|
| `title` | headline | semibold | Título de pantalla/etapa, en minúsculas por contenido |
| `sectionLabel` | footnote | semibold, MAYÚSCULAS, tracking 0,6 | Encabezados breves |
| `metricHero` | title | medium, dígitos monoespaciados | Distancia recorrida |
| `metric` | title3 | medium, dígitos monoespaciados | Tiempo, pasos |
| `body` | body | regular | Texto normal |
| `detail` | footnote | regular | Texto auxiliar |

Ningún estilo usa `minimumScaleFactor`: con texto grande el contenido se reorganiza (`ViewThatFits`) o se desplaza.
Información esencial nunca en `caption2`/`footnote2` (bajan de 12 pt en tamaños pequeños; ver matriz de normas).

## Espaciado, radios, líneas y objetivos táctiles

| Token | Valor (pt) | Procedencia |
|---|---|---|
| Spacing xxs / xs / s / m / l | 2 / 4 / 8 / 12 / 16 | Estimado (escala de 4 pt) |
| Radius card / control / bar | 14 / 22 / 2 | Estimado |
| Stroke hairline / control | 1 / 1,5 | Estimado |
| Target minimumHeight | 44 | Adaptación watchOS (HIG: 44×44 pt por defecto) |
| Target primaryHeight | 52 | Estimado |

## Iconografía

SF Symbols de contorno, peso regular, escala media (`IconView`), siempre acompañados de texto y ocultos a VoiceOver.
