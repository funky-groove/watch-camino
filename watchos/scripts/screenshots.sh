#!/usr/bin/env bash
# Capturas automáticas de Camino Seguro Watch en el simulador (macOS + Xcode).
#
#   cd watchos && scripts/screenshots.sh [carpeta_salida]      (por defecto: watchos/out)
#
# 1. Genera el proyecto (xcodegen) y compila Debug para simulador.
# 2. Elige el reloj MÁS PEQUEÑO disponible (preferencia: Apple Watch SE (40mm) (2nd generation))
#    y uno GRANDE (Ultra o 49/46/45 mm) del runtime watchOS más reciente (≥ 10).
# 3. Por cada tema (negro, perla) y pantalla lanza la app con argumentos de escenario
#    (DemoScenario: datos DEMO en memoria, nunca el almacenamiento real) y captura.
# 4. En el pequeño, además, texto grande (accessibility-large) en inicio activo y estadísticas,
#    y una pasada en inglés (-AppleLanguages "(en)" -AppleLocale en_US) de trayecto, SOS y ajustes.
#    Todas las demás pasadas fuerzan español (-AppleLanguages "(es)" -AppleLocale es_ES), sea cual
#    sea el idioma del simulador.
#    V1.1: trayecto en pausa, perfil ampliado, Lugares, ayuda de la esfera, aviso de primer uso
#    (forzado con -demo.route face-prompt), resumen y trayecto en unidades imperiales/velocidad.
#    Bienvenida visual (§K, sólo tema negro y reloj pequeño): `bienvenida`, con -demo.welcome show
#    (la capa queda fija para poder capturarla).
#    Las complicaciones (CaminoWidgets) NO se pueden capturar con simctl: se verifican con los
#    #Preview de CaminoWidgets.swift en Xcode (activo, pausado en millas, datos antiguos, sin
#    trayecto, sin datos).
#    La pantalla SOS usa SIEMPRE el marcador simulado (MockEmergencyDialer, por -demo.scenario):
#    no se abre ninguna llamada; además las capturas no pulsan nada.
# 5. Escribe out/index.md, out/contact_sheet.png (si hay Pillow) y vuelca en el log las
#    imágenes en base64 entre marcadores BEGIN_CONTACT_SHEET/END_CONTACT_SHEET y
#    BEGIN_PNG <nombre>/END_PNG.
#
# Tolerante a fallos por captura; termina con error sólo si no se obtuvo NINGUNA captura
# (o si falla la compilación / no hay simuladores watchOS).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${1:-$WATCHOS_DIR/out}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
DERIVED="${DERIVED_DATA_PATH:-$WATCHOS_DIR/build/screenshots-dd}"
BUNDLE_ID="org.caminoseguro.watch"
WAIT_SECONDS="${SCREENSHOT_WAIT:-4}"
PREFERRED_SMALL="Apple Watch SE (40mm) (2nd generation)"

log() { printf '[screenshots] %s\n' "$*"; }
warn() { printf '[screenshots] AVISO: %s\n' "$*" >&2; }
die() { printf '[screenshots] ERROR: %s\n' "$*" >&2; exit 1; }

command -v xcrun >/dev/null || die "xcrun no disponible (hace falta macOS + Xcode)"
command -v python3 >/dev/null || die "python3 no disponible"

# Pantallas: nombre|escenario|ruta|argumentos extra (ruta vacía = pantalla principal).
SCREENS=(
  "inicio-activo|active|"
  "inicio-activo-final|active||-demo.scrollToEnd YES"
  "inicio-pausado|paused|"
  "inicio-imperial-velocidad|active||-settings.units imperial -settings.paceMode speed"
  "perfil|active|profile"
  "sos|active|sos"
  "sos-sin-trayecto|idle|sos"
  "inicio-idle|idle|"
  "estadisticas|active|stats"
  "detalle-distancia|active|stat-distance"
  "cerca-agua|nearby|nearby-water"
  "lugares|nearby|places"
  "ficha-poi|alert|poi-p01"
  "ajustes|idle|settings"
  "ajustes-esfera|idle|settings-face"
  "aviso-esfera|idle|face-prompt"
  "sync|finished|sync"
  "aviso|alert|"
  "inicio-finalizado|finished|"
  "elegir-etapa|finished|picker"
  "resumen|finished|summary"
)
THEMES=(negro perla)
LARGE_TEXT_SCREENS=(
  "inicio-activo|active|"
  "estadisticas|active|stats"
  "sos|active|sos"
)
# Pasada en inglés (sólo en el reloj pequeño).
ENGLISH_SCREENS=(
  "inicio-activo|active|"
  "inicio-pausado|paused|"
  "sos|active|sos"
  "ajustes|idle|settings"
)
# Idioma SIEMPRE explícito: el simulador suele estar en inglés y, sin estos argumentos, las
# pasadas "en español" salían en inglés.
SPANISH_ARGS='-AppleLanguages (es) -AppleLocale es_ES'
ENGLISH_ARGS='-AppleLanguages (en) -AppleLocale en_US'

# Posición simulada coherente con cada escenario (por si la app pide una lectura real).
scenario_location() {
  case "$1" in
    active|paused)  echo "42.77109,-7.45139" ;;
    alert)   echo "42.77085,-7.45231" ;;
    *)       echo "42.9132,-8.0118" ;;
  esac
}

# ---------------------------------------------------------------- 1. Compilación
cd "$WATCHOS_DIR" || die "no se puede entrar en $WATCHOS_DIR"
if command -v xcodegen >/dev/null; then
  log "xcodegen generate"
  xcodegen generate || die "xcodegen falló"
else
  [ -d CaminoWatch.xcodeproj ] || die "falta xcodegen (brew install xcodegen)"
  warn "xcodegen no instalado; se usa el CaminoWatch.xcodeproj existente"
fi

log "Compilando Debug para watchOS Simulator (derivedDataPath=$DERIVED)"
BUILD_LOG="$OUT/build.log"
if ! xcodebuild build \
    -project CaminoWatch.xcodeproj \
    -scheme CaminoWatch \
    -configuration Debug \
    -destination 'generic/platform=watchOS Simulator' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO >"$BUILD_LOG" 2>&1; then
  tail -n 80 "$BUILD_LOG" >&2
  die "la compilación falló (ver $BUILD_LOG)"
fi
APP_PATH="$(find "$DERIVED/Build/Products" -maxdepth 2 -type d -name 'CaminoWatch.app' -path '*watchsimulator*' | head -n 1)"
[ -n "$APP_PATH" ] && [ -d "$APP_PATH" ] || die "no se encontró CaminoWatch.app en $DERIVED"
log "App: $APP_PATH"

# ---------------------------------------------------------------- 2. Dispositivos
SIM_JSON_DT="$OUT/.devicetypes.json"
SIM_JSON_RT="$OUT/.runtimes.json"
xcrun simctl list devicetypes -j >"$SIM_JSON_DT" || die "simctl list devicetypes falló"
xcrun simctl list runtimes -j >"$SIM_JSON_RT" || die "simctl list runtimes falló"

SELECT_PY="$OUT/.select_device.py"
cat >"$SELECT_PY" <<'PY'
import json, re, sys

devtypes = json.load(open(sys.argv[1])).get("devicetypes", [])
runtimes = json.load(open(sys.argv[2])).get("runtimes", [])
preferred = sys.argv[3]

def vkey(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "0"))

watch_rts = [r for r in runtimes
             if (r.get("platform") == "watchOS" or "watchOS" in r.get("name", ""))
             and r.get("isAvailable", True)
             and vkey(r.get("version")) >= (10,)]
if not watch_rts:
    sys.exit("sin runtime watchOS >= 10 disponible")
rt = max(watch_rts, key=lambda r: vkey(r.get("version")))

supported = rt.get("supportedDeviceTypes")
if supported:
    cands = [d for d in supported if d.get("productFamily", "Apple Watch") == "Apple Watch"]
else:
    cands = [d for d in devtypes if d.get("productFamily") == "Apple Watch"]
if not cands:
    sys.exit("sin tipos de dispositivo Apple Watch para " + rt.get("name", "?"))

def mm(d):
    m = re.search(r"(\d+)\s*mm", d.get("name", ""))
    return int(m.group(1)) if m else None

sized = [d for d in cands if mm(d) is not None]
small = next((d for d in cands if d.get("name") == preferred), None)
if small is None:
    small = min(sized, key=lambda d: (mm(d), d.get("name"))) if sized else cands[0]

ultra = [d for d in cands if "Ultra" in d.get("name", "")]
if ultra:
    large = sorted(ultra, key=lambda d: d.get("name"))[-1]
else:
    big = [d for d in sized if mm(d) in (49, 46, 45)]
    pool = big or sized or cands
    large = max(pool, key=lambda d: (mm(d) or 0, d.get("name")))

for d in (small, large):
    print(d["identifier"] + "|" + d["name"])
print(rt["identifier"] + "|" + rt.get("name", "watchOS " + rt.get("version", "?")))
PY
SELECTION="$(python3 "$SELECT_PY" "$SIM_JSON_DT" "$SIM_JSON_RT" "$PREFERRED_SMALL")" || die "no se pudo elegir dispositivo"

SMALL_TYPE="$(echo "$SELECTION" | sed -n 1p | cut -d'|' -f1)"
SMALL_NAME="$(echo "$SELECTION" | sed -n 1p | cut -d'|' -f2-)"
LARGE_TYPE="$(echo "$SELECTION" | sed -n 2p | cut -d'|' -f1)"
LARGE_NAME="$(echo "$SELECTION" | sed -n 2p | cut -d'|' -f2-)"
RUNTIME_ID="$(echo "$SELECTION" | sed -n 3p | cut -d'|' -f1)"
RUNTIME_NAME="$(echo "$SELECTION" | sed -n 3p | cut -d'|' -f2-)"
log "Runtime: $RUNTIME_NAME ($RUNTIME_ID)"
log "Pequeño: $SMALL_NAME"
log "Grande:  $LARGE_NAME"

slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }

INDEX_ROWS="$OUT/.index_rows.tsv"
: >"$INDEX_ROWS"
CAPTURED=0
FAILED=0
CREATED_UDIDS=()

cleanup() {
  for u in "${CREATED_UDIDS[@]:-}"; do
    [ -n "$u" ] || continue
    xcrun simctl shutdown "$u" >/dev/null 2>&1 || true
    xcrun simctl delete "$u" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

PREP_UDID=""
prepare_sim() {  # $1 = devicetype id, $2 = nombre; deja el UDID en PREP_UDID
  local udid
  PREP_UDID=""
  udid="$(xcrun simctl create "CaminoShots $(slug "$2")" "$1" "$RUNTIME_ID")" || return 1
  [ -n "$udid" ] || return 1
  CREATED_UDIDS+=("$udid")
  PREP_UDID="$udid"
  xcrun simctl boot "$udid" >&2 || return 1
  # bootstatus puede no terminar en algunos runtimes: con límite de tiempo.
  ( xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 ) & local bpid=$!
  local waited=0
  while kill -0 "$bpid" 2>/dev/null && [ "$waited" -lt 240 ]; do sleep 2; waited=$((waited + 2)); done
  kill "$bpid" 2>/dev/null || true
  xcrun simctl status_bar "$udid" override --time "9:41" >/dev/null 2>&1 || warn "status_bar override no soportado ($2)"
  xcrun simctl install "$udid" "$APP_PATH" >&2 || return 1
  # Evita diálogos de permiso encima de las capturas (si el runtime lo admite).
  xcrun simctl privacy "$udid" grant location "$BUNDLE_ID" >/dev/null 2>&1 || warn "privacy location no aplicado ($2)"
  xcrun simctl privacy "$udid" grant motion "$BUNDLE_ID" >/dev/null 2>&1 || true
  return 0
}

capture() {  # $1 udid, $2 device slug, $3 device name, $4 tema, $5 pantalla, $6 escenario, $7 ruta, $8 sufijo, $9 args extra
  local udid="$1" dslug="$2" dname="$3" theme="$4" screen="$5" scenario="$6" route="$7" suffix="$8" extra="${9:-}"
  local name="${dslug}_${theme}_${screen}${suffix}.png"
  local args=(-settings.theme "$theme" -demo.scenario "$scenario")
  [ -n "$route" ] && args+=(-demo.route "$route")
  if [ -n "$extra" ]; then
    local extra_args=()
    read -r -a extra_args <<<"$extra"
    args+=("${extra_args[@]}")
  fi
  xcrun simctl location "$udid" set "$(scenario_location "$scenario")" >/dev/null 2>&1 || true
  if ! xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" "${args[@]}" >/dev/null 2>&1; then
    warn "launch falló: $name"
    FAILED=$((FAILED + 1))
    return 0
  fi
  sleep "$WAIT_SECONDS"
  if xcrun simctl io "$udid" screenshot "$OUT/$name" >/dev/null 2>&1 && [ -s "$OUT/$name" ]; then
    CAPTURED=$((CAPTURED + 1))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$dname" "$theme" "$screen$suffix" "$scenario" "${route:-(inicio)}" "$RUNTIME_NAME" >>"$INDEX_ROWS"
    log "OK  $name"
  else
    warn "screenshot falló: $name"
    FAILED=$((FAILED + 1))
  fi
}

run_device() {  # $1 devicetype, $2 nombre, $3 = "small" | "large"
  local udid dslug
  dslug="$(slug "$2")"
  if ! prepare_sim "$1" "$2" || [ -z "$PREP_UDID" ]; then
    warn "no se pudo preparar el simulador $2; se omite"
    FAILED=$((FAILED + 1))
    return 0
  fi
  udid="$PREP_UDID"
  log "Simulador $2 → $udid"
  local theme entry screen scenario route extra
  for theme in "${THEMES[@]}"; do
    for entry in "${SCREENS[@]}"; do
      IFS='|' read -r screen scenario route extra <<<"$entry"
      capture "$udid" "$dslug" "$2" "$theme" "$screen" "$scenario" "$route" "" "$SPANISH_ARGS${extra:+ $extra}"
    done
  done
  if [ "$3" = "small" ]; then
    # Bienvenida visual (§K): negro, sólo en el reloj pequeño (40 mm).
    capture "$udid" "$dslug" "$2" negro bienvenida idle "" "" "$SPANISH_ARGS -demo.welcome show"
    if xcrun simctl ui "$udid" content_size accessibility-large >/dev/null 2>&1; then
      log "Texto grande (accessibility-large) activado en $2"
      for theme in "${THEMES[@]}"; do
        for entry in "${LARGE_TEXT_SCREENS[@]}"; do
          IFS='|' read -r screen scenario route <<<"$entry"
          capture "$udid" "$dslug" "$2" "$theme" "$screen" "$scenario" "$route" "_texto-grande" "$SPANISH_ARGS"
        done
      done
      xcrun simctl ui "$udid" content_size large >/dev/null 2>&1 || true
    else
      warn "simctl ui content_size no soportado en $2; se omiten capturas de texto grande"
    fi
    log "Pasada en inglés en $2"
    for theme in "${THEMES[@]}"; do
      for entry in "${ENGLISH_SCREENS[@]}"; do
        IFS='|' read -r screen scenario route <<<"$entry"
        capture "$udid" "$dslug" "$2" "$theme" "$screen" "$scenario" "$route" "_en" "$ENGLISH_ARGS"
      done
    done
  fi
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------- 3. Capturas
run_device "$SMALL_TYPE" "$SMALL_NAME" small
if [ "$LARGE_TYPE" != "$SMALL_TYPE" ]; then
  run_device "$LARGE_TYPE" "$LARGE_NAME" large
else
  warn "sólo hay un tamaño de reloj disponible"
fi

log "Capturas: $CAPTURED correctas, $FAILED fallos"

# ---------------------------------------------------------------- 4. Índice
{
  echo "# Capturas de Camino Seguro Watch (DEMO)"
  echo
  echo "- Fecha: $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo "- Runtime: $RUNTIME_NAME (\`$RUNTIME_ID\`)"
  echo "- Dispositivo pequeño: $SMALL_NAME"
  echo "- Dispositivo grande: $LARGE_NAME"
  echo "- Xcode: $(xcodebuild -version 2>/dev/null | head -n 1)"
  echo "- Correctas: $CAPTURED · Fallos: $FAILED"
  echo "- Datos: escenarios de demostración (\`-demo.scenario\`), en memoria. No son datos reales."
  echo
  echo "| Fichero | Dispositivo | Tema | Pantalla | Escenario | Ruta | Runtime |"
  echo "|---|---|---|---|---|---|---|"
  while IFS=$'\t' read -r f d t s sc r rt; do
    echo "| [\`$f\`]($f) | $d | $t | $s | $sc | $r | $rt |"
  done <"$INDEX_ROWS"
} >"$OUT/index.md"
log "Índice: $OUT/index.md"

if [ "$CAPTURED" -eq 0 ]; then
  die "no se obtuvo ninguna captura"
fi

# ---------------------------------------------------------------- 5. Mosaico + volcado base64
PY="python3"
if ! python3 -c 'import PIL' >/dev/null 2>&1; then
  VENV="$WATCHOS_DIR/build/screenshots-venv"
  if python3 -m venv "$VENV" >/dev/null 2>&1 && "$VENV/bin/pip" install -q pillow >/dev/null 2>&1; then
    PY="$VENV/bin/python"
  else
    warn "Pillow no disponible; sin contact_sheet.png (las miniaturas se hacen con sips)"
    PY=""
  fi
fi

if [ -n "$PY" ]; then
  "$PY" - "$OUT" "$INDEX_ROWS" <<'PY' || warn "falló la generación del mosaico / volcado"
import base64, io, os, sys
from PIL import Image, ImageDraw

out, rows_path = sys.argv[1], sys.argv[2]
names = [l.split("\t")[0] for l in open(rows_path, encoding="utf-8") if l.strip()]
images = []
for n in names:
    try:
        images.append((n, Image.open(os.path.join(out, n)).convert("RGB")))
    except Exception as e:  # noqa: BLE001
        print(f"[screenshots] AVISO: no se pudo abrir {n}: {e}", file=sys.stderr)

def png_bytes(img, colors=None):
    buf = io.BytesIO()
    if colors:
        img = img.quantize(colors=colors, method=Image.Quantize.MEDIANCUT)
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()

def dump(begin, end, data):
    print(begin)
    print(base64.encodebytes(data).decode("ascii"), end="")
    print(end)

# Mosaico: celdas de ancho fijo con el nombre debajo.
if images:
    cell_w = 220
    label_h = 28
    scaled = []
    for n, im in images:
        h = round(im.height * cell_w / im.width)
        scaled.append((n, im.resize((cell_w, h), Image.LANCZOS)))
    cell_h = max(im.height for _, im in scaled) + label_h
    cols = 8 if len(scaled) > 16 else 4
    rows = (len(scaled) + cols - 1) // cols
    pad = 6
    sheet = Image.new("RGB", (cols * (cell_w + pad) + pad, rows * (cell_h + pad) + pad), (128, 128, 128))
    draw = ImageDraw.Draw(sheet)
    for i, (n, im) in enumerate(scaled):
        x = pad + (i % cols) * (cell_w + pad)
        y = pad + (i // cols) * (cell_h + pad)
        sheet.paste(im, (x, y))
        label = n[:-4]
        # Nombre en dos líneas cortas (sin depender de fuentes del sistema).
        parts = label.split("_", 1)
        draw.text((x + 2, y + im.height + 2), parts[0][:36], fill=(255, 255, 255))
        if len(parts) > 1:
            draw.text((x + 2, y + im.height + 14), parts[1][:36], fill=(255, 255, 255))
    sheet.save(os.path.join(out, "contact_sheet_full.png"), optimize=True)

    limit = 400 * 1024
    scale = 1.0
    data = png_bytes(sheet, colors=256)
    while len(data) >= limit and scale > 0.1:
        scale *= 0.8
        small = sheet.resize((max(1, int(sheet.width * scale)), max(1, int(sheet.height * scale))), Image.LANCZOS)
        data = png_bytes(small, colors=256)
    with open(os.path.join(out, "contact_sheet.png"), "wb") as f:
        f.write(data)
    print(f"[screenshots] contact_sheet.png: {len(data)} bytes, escala {scale:.2f}")
    dump("BEGIN_CONTACT_SHEET", "END_CONTACT_SHEET", data)

# Cada captura reducida a 200 px de ancho.
for n, im in images:
    h = max(1, round(im.height * 200 / im.width))
    thumb = im.resize((200, h), Image.LANCZOS)
    dump(f"BEGIN_PNG {n}", "END_PNG", png_bytes(thumb, colors=256))
PY
else
  TMP_THUMB="$OUT/.thumb.png"
  while IFS=$'\t' read -r f _rest; do
    [ -n "$f" ] || continue
    if sips --resampleWidth 200 "$OUT/$f" --out "$TMP_THUMB" >/dev/null 2>&1; then
      echo "BEGIN_PNG $f"
      base64 -i "$TMP_THUMB" | fold -w 76
      echo "END_PNG"
    fi
  done <"$INDEX_ROWS"
  rm -f "$TMP_THUMB"
fi

rm -f "$SIM_JSON_DT" "$SIM_JSON_RT" "$SELECT_PY" "$INDEX_ROWS"
log "Hecho: $CAPTURED capturas en $OUT"
exit 0
