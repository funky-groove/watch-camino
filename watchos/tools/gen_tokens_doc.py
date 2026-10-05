#!/usr/bin/env python3
"""Genera docs/design/DESIGN_TOKENS.md a partir de CaminoDesign/DesignTokens.swift.
El contraste se calcula con la misma fórmula WCAG que ContrastTests (que es quien hace cumplir los umbrales)."""
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = (ROOT / "watchos/CaminoCore/Sources/CaminoDesign/DesignTokens.swift").read_text(encoding="utf-8")
OUT = ROOT / "docs/design/DESIGN_TOKENS.md"

ON_SURFACE_DEFAULTS = {"onSurfacePrimary": "textPrimary", "onSurfaceSecondary": "textSecondary",
                       "positiveOnSurface": "positive", "warningOnSurface": "warning",
                       "criticalOnSurface": "critical"}


def pal(name):
    block = SRC.split(f"public static let {name} = Palette(")[1].split("\n    )")[0]
    values = dict(re.findall(r"(\w+): RGB\(0x([0-9A-F]{6})\)", block))
    # Igual que el init de Palette: sin valor propio, "sobre superficie" = "sobre fondo".
    for key, fallback in ON_SURFACE_DEFAULTS.items():
        values.setdefault(key, values[fallback])
    return values

def lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def cr(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)

N, W, P = pal("negro"), pal("perlaWatch"), pal("perla")
DESC = {
    "background": "Fondo de pantalla", "surface": "Tarjetas y filas", "surfaceRaised": "Superficie elevada / pulsada",
    "textPrimary": "Texto principal sobre el fondo", "textSecondary": "Texto secundario sobre el fondo",
    "hairline": "Separadores y bordes finos (decorativos)", "controlOutline": "Contorno de acción secundaria",
    "actionPrimaryFill": "Fondo de acción principal", "actionPrimaryText": "Texto de acción principal",
    "positive": "Positivo / progreso (sobre el fondo)", "warning": "Pendiente / advertencia (sobre el fondo)",
    "critical": "Error / destructivo / emergencia (sobre el fondo)",
    "onSurfacePrimary": "Texto principal sobre superficie (tarjetas, filas, botones)",
    "onSurfaceSecondary": "Texto secundario sobre superficie",
    "positiveOnSurface": "Positivo sobre superficie", "warningOnSurface": "Advertencia sobre superficie",
    "criticalOnSurface": "Crítico sobre superficie",
}
NAMES = {"background": "fondo", "surface": "superficie", "surfaceRaised": "superficie elevada",
         "textPrimary": "texto principal", "textSecondary": "texto secundario", "positive": "positivo",
         "warning": "advertencia", "critical": "crítico", "onSurfacePrimary": "texto principal",
         "onSurfaceSecondary": "texto secundario", "positiveOnSurface": "positivo",
         "warningOnSurface": "advertencia", "criticalOnSurface": "crítico"}
# Mismo orden y mismos pares que ContrastRequirement.all (DesignTokens.swift).
pairs = []
for t in ["textPrimary", "textSecondary", "positive", "warning", "critical"]:
    pairs.append((f"{NAMES[t]} sobre fondo", 4.5, t, "background"))
for t in ["onSurfacePrimary", "onSurfaceSecondary", "positiveOnSurface", "warningOnSurface", "criticalOnSurface"]:
    for g in ["surface", "surfaceRaised"]:
        pairs.append((f"{NAMES[t]} (`{t}`) sobre {NAMES[g]}", 4.5, t, g))
pairs += [("texto de acción principal", 4.5, "actionPrimaryText", "actionPrimaryFill"),
          ("acción principal sobre fondo", 3.0, "actionPrimaryFill", "background"),
          ("texto de acción de emergencia", 4.5, "actionPrimaryText", "critical"),
          ("acción de emergencia sobre fondo", 3.0, "critical", "background"),
          ("contorno de control sobre fondo", 3.0, "controlOutline", "background"),
          ("contorno de control sobre superficie", 3.0, "controlOutline", "surface")]

color_rows = "\n".join(f"| `{k}` | {v} | `#{N[k]}` | `#{W[k]}` | `#{P[k]}` |" for k, v in DESC.items())
contrast_rows = "\n".join(
    f"| {name} | {mn} | {cr(N[f], N[b]):.2f} | {cr(W[f], W[b]):.2f} | {cr(P[f], P[b]):.2f} |"
    for name, mn, f, b in pairs)
for name, mn, f, b in pairs:
    for label, palette in (("negro", N), ("perlaWatch", W), ("perla", P)):
        if cr(palette[f], palette[b]) < mn:
            raise SystemExit(f"{label}: {name} no llega a {mn}:1")

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(f"""# Tokens de diseño — Camino Seguro Watch

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
{color_rows}

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
{contrast_rows}

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
""", encoding="utf-8")
print("escrito", OUT)
