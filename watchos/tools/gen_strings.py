#!/usr/bin/env python3
"""Regenera CaminoWatch/es.lproj/Localizable.strings a partir de las llamadas
tr("clave", "valor") / format("clave", "valor", …) de CaminoWatch/**/*.swift.

    python3 watchos/tools/gen_strings.py          # escribe
    python3 watchos/tools/gen_strings.py --check  # falla si no está al día (CI)
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "CaminoWatch"
OUT = ROOT / "es.lproj" / "Localizable.strings"
PATTERN = re.compile(r'\b(?:tr|format)\(\s*"([^"]+)"\s*,\s*"((?:[^"\\]|\\.)*)"')

def collect():
    entries = {}
    for path in sorted(ROOT.rglob("*.swift")):
        for key, value in PATTERN.findall(path.read_text(encoding="utf-8")):
            if key in entries and entries[key] != value:
                sys.exit(f"clave duplicada con valores distintos: {key} ({path})")
            entries[key] = value
    return entries

def render(entries):
    lines = ["/*", "  Localizable.strings (es) — Camino Seguro Watch",
             "  GENERADO por watchos/tools/gen_strings.py a partir de las llamadas tr()/format().",
             "  No editar a mano.", "*/", ""]
    lines += [f'"{k}" = "{v}";' for k, v in sorted(entries.items())]
    return "\n".join(lines) + "\n"

if __name__ == "__main__":
    text = render(collect())
    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            sys.exit("Localizable.strings no está al día: ejecuta watchos/tools/gen_strings.py")
        print("Localizable.strings al día")
    else:
        OUT.write_text(text, encoding="utf-8")
        print(f"{len(collect())} claves escritas en {OUT}")
