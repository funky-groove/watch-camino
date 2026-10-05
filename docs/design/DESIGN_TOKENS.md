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
| **Adaptación watchOS** | Familia SF, objetivos de 44 pt, Negro forzado en Always On, estilos Dynamic Type. |

Al recibir código o capturas se cambian los valores en `DesignTokens.swift`; `ContrastTests` impide que un valor nuevo rompa el contraste.

## Color

| Token | Uso | Negro | Perla | Procedencia |
|---|---|---|---|---|
| `background` | Fondo de pantalla | `#000000` | `#F3EFE7` | Estimado |
| `surface` | Tarjetas y filas | `#1A1A19` | `#EAE4D8` | Estimado |
| `surfaceRaised` | Superficie elevada / pulsada | `#262624` | `#E1D9CA` | Estimado |
| `textPrimary` | Texto principal | `#F2EFE8` | `#1C1B19` | Estimado |
| `textSecondary` | Texto secundario, etiquetas | `#A8A399` | `#5B564E` | Estimado |
| `hairline` | Separadores y bordes finos (decorativos) | `#3B3936` | `#CBC2B2` | Estimado |
| `controlOutline` | Contorno de acción secundaria | `#77726A` | `#857D70` | Estimado |
| `actionPrimaryFill` | Fondo de acción principal | `#F2EFE8` | `#1C1B19` | Estimado |
| `actionPrimaryText` | Texto de acción principal | `#141413` | `#F3EFE7` | Estimado |
| `positive` | Positivo / progreso | `#5DBB7E` | `#24633A` | Estimado |
| `warning` | Pendiente / advertencia | `#E5A93D` | `#7E5200` | Estimado |
| `critical` | Error / destructivo / emergencia | `#FF7A6B` | `#A8291F` | Estimado |

- El color nunca comunica un estado por sí solo: siempre símbolo + texto.
- Sin degradados, cristal ni sombras.
- **Adaptación watchOS:** con pantalla siempre activa atenuada (`isLuminanceReduced`) se fuerza Negro: un fondo claro en Always On deslumbra y gasta batería. Perla es una preferencia explícita del producto, disponible en Ajustes, no el valor inicial.

## Contraste (WCAG 2.x)

Umbral aplicado: 4,5:1 a todo texto (también al grande, por margen) y 3:1 a componentes de interfaz. `hairline` es decorativo y no se exige.

| Par | Mínimo | Negro | Perla |
|---|---|---|---|
| texto principal sobre fondo | 4.5 | 18.29 | 15.01 |
| texto principal sobre superficie | 4.5 | 15.17 | 13.59 |
| texto principal sobre superficie elevada | 4.5 | 13.20 | 12.28 |
| texto secundario sobre fondo | 4.5 | 8.36 | 6.35 |
| texto secundario sobre superficie | 4.5 | 6.94 | 5.75 |
| texto secundario sobre superficie elevada | 4.5 | 6.04 | 5.19 |
| positivo sobre fondo | 4.5 | 8.87 | 6.27 |
| positivo sobre superficie | 4.5 | 7.36 | 5.68 |
| positivo sobre superficie elevada | 4.5 | 6.41 | 5.13 |
| advertencia sobre fondo | 4.5 | 10.07 | 5.92 |
| advertencia sobre superficie | 4.5 | 8.36 | 5.36 |
| advertencia sobre superficie elevada | 4.5 | 7.27 | 4.84 |
| crítico sobre fondo | 4.5 | 8.25 | 6.10 |
| crítico sobre superficie | 4.5 | 6.84 | 5.53 |
| crítico sobre superficie elevada | 4.5 | 5.95 | 4.99 |
| texto de acción principal | 4.5 | 16.05 | 15.01 |
| acción principal sobre fondo | 3.0 | 18.29 | 15.01 |
| texto de acción de emergencia | 4.5 | 7.24 | 6.10 |
| acción de emergencia sobre fondo | 3.0 | 8.25 | 6.10 |
| contorno de control sobre fondo | 3.0 | 4.40 | 3.55 |
| contorno de control sobre superficie | 3.0 | 3.65 | 3.21 |

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
