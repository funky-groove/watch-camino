#!/usr/bin/env python3
"""Regenera las tablas de textos de la app:

- CaminoWatch/es.lproj/Localizable.strings a partir de las llamadas
  tr("clave", "valor") / format("clave", "valor", …) de CaminoWatch/**/*.swift (base: español).
- CaminoWatch/en.lproj/Localizable.strings a partir de watchos/tools/strings_en.json
  (clave → texto en inglés). Debe tener EXACTAMENTE las mismas claves que es.

Además comprueba que CaminoWidgets/en.lproj tiene las mismas claves que CaminoWidgets/es.lproj
(ambas tablas de widgets se mantienen a mano) y que cada traducción conserva los mismos
marcadores de formato (%@, %ld…) que el español.

    python3 watchos/tools/gen_strings.py          # escribe es y en
    python3 watchos/tools/gen_strings.py --check  # falla si algo no está al día o falta una clave (CI)
"""
import json, pathlib, re, sys

WATCHOS = pathlib.Path(__file__).resolve().parent.parent
ROOT = WATCHOS / "CaminoWatch"
OUT_ES = ROOT / "es.lproj" / "Localizable.strings"
OUT_EN = ROOT / "en.lproj" / "Localizable.strings"
EN_SOURCE = WATCHOS / "tools" / "strings_en.json"
WIDGETS_ES = WATCHOS / "CaminoWidgets" / "es.lproj" / "Localizable.strings"
WIDGETS_EN = WATCHOS / "CaminoWidgets" / "en.lproj" / "Localizable.strings"

PATTERN = re.compile(r'\b(?:tr|format)\(\s*"([^"]+)"\s*,\s*"((?:[^"\\]|\\.)*)"')
STRINGS_LINE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDuUxXoOfeEgGcCsSpaAF]")


def collect():
    entries = {}
    for path in sorted(ROOT.rglob("*.swift")):
        for key, value in PATTERN.findall(path.read_text(encoding="utf-8")):
            if key in entries and entries[key] != value:
                sys.exit(f"clave duplicada con valores distintos: {key} ({path})")
            entries[key] = value
    return entries


def escape(value):
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def render(entries, lang, source):
    lines = ["/*", f"  Localizable.strings ({lang}) — Camino Seguro Watch",
             f"  GENERADO por watchos/tools/gen_strings.py a partir de {source}.",
             "  No editar a mano.", "*/", ""]
    lines += [f'"{k}" = "{v}";' for k, v in sorted(entries.items())]
    return "\n".join(lines) + "\n"


def parse_strings(path):
    keys = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = STRINGS_LINE.match(line)
        if match:
            keys[match.group(1)] = match.group(2)
    return keys


def placeholders(value):
    return sorted(PLACEHOLDER.findall(value.replace("%%", "")))


def compare(name, es, en):
    """Errores de paridad: claves que faltan o sobran y marcadores distintos."""
    errors = []
    missing = sorted(set(es) - set(en))
    extra = sorted(set(en) - set(es))
    if missing:
        errors.append(f"{name}: faltan en inglés {len(missing)} claves: {', '.join(missing)}")
    if extra:
        errors.append(f"{name}: sobran en inglés {len(extra)} claves: {', '.join(extra)}")
    for key in sorted(set(es) & set(en)):
        if placeholders(es[key]) != placeholders(en[key]):
            errors.append(f"{name}: marcadores distintos en {key}: {es[key]!r} / {en[key]!r}")
    return errors


def load_english():
    if not EN_SOURCE.exists():
        sys.exit(f"falta {EN_SOURCE}")
    data = json.loads(EN_SOURCE.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not all(isinstance(v, str) for v in data.values()):
        sys.exit(f"{EN_SOURCE}: debe ser un objeto clave → texto")
    return {k: escape(v) for k, v in data.items()}


if __name__ == "__main__":
    es = collect()
    en = load_english()
    errors = compare("CaminoWatch", es, en)
    if WIDGETS_ES.exists():
        if not WIDGETS_EN.exists():
            errors.append(f"falta {WIDGETS_EN}")
        else:
            errors += compare("CaminoWidgets", parse_strings(WIDGETS_ES), parse_strings(WIDGETS_EN))
    es_text = render(es, "es", "las llamadas tr()/format()")
    en_text = render({k: v for k, v in en.items() if k in es}, "en", "watchos/tools/strings_en.json")

    if "--check" in sys.argv:
        if not OUT_ES.exists() or OUT_ES.read_text(encoding="utf-8") != es_text:
            errors.append("es.lproj/Localizable.strings no está al día: ejecuta watchos/tools/gen_strings.py")
        if not OUT_EN.exists() or OUT_EN.read_text(encoding="utf-8") != en_text:
            errors.append("en.lproj/Localizable.strings no está al día: ejecuta watchos/tools/gen_strings.py")
        if errors:
            sys.exit("\n".join(errors))
        print(f"Localizable.strings al día (es y en, {len(es)} claves; widgets con las mismas claves)")
    else:
        if errors:
            sys.exit("\n".join(errors))
        OUT_ES.write_text(es_text, encoding="utf-8")
        OUT_EN.parent.mkdir(parents=True, exist_ok=True)
        OUT_EN.write_text(en_text, encoding="utf-8")
        print(f"{len(es)} claves escritas en {OUT_ES} y {OUT_EN}")
