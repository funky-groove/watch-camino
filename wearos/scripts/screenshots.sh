#!/usr/bin/env bash
# Capturas automáticas de Camino Seguro Watch (Wear OS) en un emulador ya arrancado.
#
#   cd wearos && scripts/screenshots.sh [carpeta_salida] [etiqueta_dispositivo] [full|base]
#
#   carpeta_salida        por defecto wearos/out
#   etiqueta_dispositivo  prefijo de los ficheros (p. ej. small-round); por defecto, el modelo del AVD
#   full | base           full (por defecto): pantallas en negro y perla + inglés (trayecto, SOS)
#                         + texto grande (font_scale 1.3, trayecto). base: sólo negro y perla.
#
# Requisitos: adb en el PATH y UN emulador Wear OS arrancado (en CI lo arranca
# reactivecircus/android-emulator-runner). Si no existe el APK Debug se compila con Gradle.
#
# Cada pantalla se lanza en frío (am force-stop + am start) con extras de escenario que lee
# DemoScenarioInstaller (src/debug): datos DEMO en memoria, nunca el almacenamiento real.
#   --es demo.scenario idle|active|paused|finished|nearby
#   --es demo.route    <ruta de CaminoApp> (vacío = pantalla principal)
#   --es demo.theme    negro|perla
#   --es demo.lang     es|en
#   --es demo.facehint show|hide (aviso de primer uso; por defecto, hide)
# Las capturas NO pulsan nada (SOS nunca toca «Llamar»; además el marcador es simulado en demo).
#
# Tolerante a fallos por captura; termina con error sólo si no se obtuvo NINGUNA captura
# (o si no hay adb / emulador / APK).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEAROS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="${1:-$WEAROS_DIR/out}"
DEVICE_LABEL="${2:-}"
MODE="${3:-full}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

PKG="${WEAR_PACKAGE:-org.caminoseguro.watch}"
COMPONENT="${WEAR_ACTIVITY:-$PKG/.ui.MainActivity}"
APK="${APK:-$WEAROS_DIR/app/build/outputs/apk/debug/app-debug.apk}"
WAIT_SECONDS="${SCREENSHOT_WAIT:-5}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-600}"

# Rutas de navegación (deben coincidir con las de wearos/app/src/main/.../ui/CaminoApp.kt).
ROUTE_PROFILE="${ROUTE_PROFILE:-profile}"
ROUTE_PLACES="${ROUTE_PLACES:-places}"
ROUTE_POI="${ROUTE_POI:-place/p01}"
ROUTE_SOS="${ROUTE_SOS:-sos}"
ROUTE_SETTINGS="${ROUTE_SETTINGS:-settings}"
ROUTE_FACE_HELP="${ROUTE_FACE_HELP:-face_help}"
ROUTE_FIRST_USE="${ROUTE_FIRST_USE:-face_hint}"
ROUTE_SUMMARY="${ROUTE_SUMMARY:-summary}"

# Pantallas: nombre|escenario|ruta[|aviso de esfera show] (ruta vacía = pantalla principal).
# El aviso de primer uso «Accede desde tu esfera» sólo se ofrece con show; en el resto, descartado.
SCREENS=(
  "inicio|idle|"
  "trayecto-activo|active|"
  "trayecto-pausado|paused|"
  "perfil|active|$ROUTE_PROFILE"
  "lugares|nearby|$ROUTE_PLACES"
  "ficha|active|$ROUTE_POI"
  "sos|active|$ROUTE_SOS"
  "ajustes|idle|$ROUTE_SETTINGS"
  "ayuda-esfera|idle|$ROUTE_FACE_HELP"
  "aviso-primer-uso|idle|$ROUTE_FIRST_USE|show"
  "resumen|finished|$ROUTE_SUMMARY"
)
THEMES=(negro perla)
ENGLISH_SCREENS=(
  "trayecto-activo|active|"
  "sos|active|$ROUTE_SOS"
)
LARGE_TEXT_SCREENS=(
  "trayecto-activo|active|"
)
LARGE_FONT_SCALE="1.3"

log() { printf '[wear-screenshots] %s\n' "$*"; }
warn() { printf '[wear-screenshots] AVISO: %s\n' "$*" >&2; }
die() { printf '[wear-screenshots] ERROR: %s\n' "$*" >&2; exit 1; }

command -v adb >/dev/null || die "adb no disponible"

# ---------------------------------------------------------------- 1. APK
if [ ! -f "$APK" ]; then
  log "No hay APK Debug en $APK; compilando :app:assembleDebug"
  (cd "$WEAROS_DIR" && ./gradlew --no-daemon :app:assembleDebug) || die "la compilación falló"
fi
[ -f "$APK" ] || die "no se encontró el APK Debug ($APK)"

# ---------------------------------------------------------------- 2. Emulador
log "Esperando al emulador (máx. ${BOOT_TIMEOUT}s)"
timeout "$BOOT_TIMEOUT" adb wait-for-device || die "no hay emulador conectado"
waited=0
until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  [ "$waited" -ge "$BOOT_TIMEOUT" ] && die "el emulador no terminó de arrancar"
  sleep 3
  waited=$((waited + 3))
done

SDK_INT="$(adb shell getprop ro.build.version.sdk | tr -d '\r')"
MODEL="$(adb shell getprop ro.product.model | tr -d '\r')"
SIZE="$(adb shell wm size | tr -d '\r' | sed -n 's/.*: //p' | tail -n 1)"
DENSITY="$(adb shell wm density | tr -d '\r' | sed -n 's/.*: //p' | tail -n 1)"
slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
[ -n "$DEVICE_LABEL" ] || DEVICE_LABEL="$MODEL"
DSLUG="$(slug "$DEVICE_LABEL")"
[ -n "$DSLUG" ] || DSLUG="wear"
DEVICE_DESC="$DEVICE_LABEL ($MODEL, ${SIZE:-?} px, ${DENSITY:-?} dpi, API $SDK_INT)"
log "Dispositivo: $DEVICE_DESC"

# Pantalla siempre encendida, sin animaciones ni bloqueo (todo opcional según la imagen).
adb shell svc power stayon true >/dev/null 2>&1 || true
adb shell settings put system screen_off_timeout 1800000 >/dev/null 2>&1 || true
adb shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1 || true
for k in window_animation_scale transition_animation_scale animator_duration_scale; do
  adb shell settings put global "$k" 0 >/dev/null 2>&1 || true
done
adb shell settings put system font_scale 1.0 >/dev/null 2>&1 || true
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell wm dismiss-keyguard >/dev/null 2>&1 || true

# Ubicación simulada del emulador (por si la pantalla SOS hace una lectura real): Sarria → Barbadelo.
adb emu geo fix -7.45139 42.77109 >/dev/null 2>&1 || true

log "Instalando $APK"
adb install -r -g "$APK" >&2 || die "adb install falló"
# Permisos ya declarados en el manifiesto: se conceden para que no salga el diálogo del sistema.
for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACTIVITY_RECOGNITION POST_NOTIFICATIONS; do
  adb shell pm grant "$PKG" "android.permission.$p" >/dev/null 2>&1 || true
done

# Idioma: lo aplica la propia app con el extra demo.lang (sólo en el proceso). No se usa el idioma
# por app del sistema (cmd locale set-app-locales) para que Ajustes muestre el estado por defecto.

INDEX_ROWS="$OUT/.index_rows_${DSLUG}.tsv"
: >"$INDEX_ROWS"
LOGCAT="$OUT/logcat_${DSLUG}.txt"
: >"$LOGCAT"
CAPTURED=0
FAILED=0

is_png() { [ -s "$1" ] && [ "$(head -c 4 "$1" | tail -c 3)" = "PNG" ]; }

app_on_top() {
  adb shell dumpsys activity activities 2>/dev/null | tr -d '\r' \
    | grep -E 'mResumedActivity|topResumedActivity|ResumedActivity:' | grep -q "$PKG/"
}

capture() {  # $1 pantalla, $2 escenario, $3 ruta, $4 tema, $5 idioma, $6 sufijo, $7 aviso de esfera
  local screen="$1" scenario="$2" route="$3" theme="$4" lang="$5" suffix="$6" facehint="${7:-hide}"
  local name="${DSLUG}_${theme}_${screen}${suffix}.png"
  local args=(--es demo.scenario "$scenario" --es demo.theme "$theme" --es demo.lang "$lang" --es demo.facehint "$facehint")
  [ -n "$route" ] && args+=(--es demo.route "$route")

  adb shell am force-stop "$PKG" >/dev/null 2>&1 || true
  adb logcat -c >/dev/null 2>&1 || true
  adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  local start_out
  start_out="$(adb shell am start -W -n "$COMPONENT" "${args[@]}" 2>&1 | tr -d '\r')"
  if echo "$start_out" | grep -qE '^Error|Exception'; then
    warn "am start falló ($name): $(echo "$start_out" | grep -E 'Error|Exception' | head -n 1)"
    FAILED=$((FAILED + 1))
    return 0
  fi
  sleep "$WAIT_SECONDS"

  {
    echo "===== $name (scenario=$scenario route=${route:-home} theme=$theme lang=$lang)"
    adb logcat -d -s CaminoDemo:V NavController:V AndroidRuntime:E 2>/dev/null | tr -d '\r' | tail -n 40
  } >>"$LOGCAT"

  if ! app_on_top; then
    warn "la app no está en primer plano ($name): ¿se cerró? (ver $(basename "$LOGCAT"))"
    FAILED=$((FAILED + 1))
    return 0
  fi
  if adb exec-out screencap -p >"$OUT/$name" 2>/dev/null && is_png "$OUT/$name"; then
    CAPTURED=$((CAPTURED + 1))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$DEVICE_DESC" "$theme" "$screen$suffix" "$scenario" "${route:-(inicio)}" "$lang" >>"$INDEX_ROWS"
    log "OK  $name"
  else
    rm -f "$OUT/$name"
    warn "screencap falló: $name"
    FAILED=$((FAILED + 1))
  fi
}

run_list() {  # $1 idioma, $2 sufijo, resto: entradas "pantalla|escenario|ruta[|show]"
  local lang="$1" suffix="$2"
  shift 2
  local theme entry screen scenario route facehint
  for theme in "${THEMES[@]}"; do
    for entry in "$@"; do
      IFS='|' read -r screen scenario route facehint <<<"$entry"
      capture "$screen" "$scenario" "$route" "$theme" "$lang" "$suffix" "${facehint:-hide}"
    done
  done
}

# ---------------------------------------------------------------- 3. Capturas
run_list es "" "${SCREENS[@]}"

if [ "$MODE" = "full" ]; then
  log "Pasada en inglés"
  run_list en "_en" "${ENGLISH_SCREENS[@]}"

  if adb shell settings put system font_scale "$LARGE_FONT_SCALE" >/dev/null 2>&1; then
    log "Texto grande (font_scale $LARGE_FONT_SCALE)"
    sleep 2
    run_list es "_texto-grande" "${LARGE_TEXT_SCREENS[@]}"
    adb shell settings put system font_scale 1.0 >/dev/null 2>&1 || true
  else
    warn "no se pudo cambiar font_scale; se omiten capturas de texto grande"
  fi
fi
adb shell am force-stop "$PKG" >/dev/null 2>&1 || true

log "Capturas ($DSLUG): $CAPTURED correctas, $FAILED fallos"

# ---------------------------------------------------------------- 4. Índice (acumulado entre dispositivos)
{
  echo "# Capturas de Camino Seguro Watch — Wear OS (DEMO)"
  echo
  echo "- Fecha: $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo "- Datos: escenarios de demostración (\`demo.scenario\`), en memoria. No son datos reales."
  echo "- Emulador; no verifica hardware, LTE, marcador real ni sensores (ver docs/qa/WEAROS_SCREENSHOTS.md)."
  echo
  echo "| Fichero | Dispositivo | Tema | Pantalla | Escenario | Ruta | Idioma |"
  echo "|---|---|---|---|---|---|---|"
  for rows in "$OUT"/.index_rows_*.tsv; do
    [ -f "$rows" ] || continue
    while IFS=$'\t' read -r f d t s sc r l; do
      [ -n "$f" ] || continue
      echo "| [\`$f\`]($f) | $d | $t | $s | $sc | $r | $l |"
    done <"$rows"
  done
} >"$OUT/index.md"
log "Índice: $OUT/index.md"

# ---------------------------------------------------------------- 5. Mosaico (opcional, Pillow)
if python3 -c 'import PIL' >/dev/null 2>&1; then
  python3 - "$OUT" <<'PY' || warn "falló la generación del mosaico"
import glob, os, sys
from PIL import Image, ImageDraw

out = sys.argv[1]
names = sorted(os.path.basename(p) for p in glob.glob(os.path.join(out, "*.png"))
               if not os.path.basename(p).startswith("contact_sheet"))
if names:
    cell, label_h, pad = 200, 28, 6
    cols = 6
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (cell + pad) + pad, rows * (cell + label_h + pad) + pad), (128, 128, 128))
    draw = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        try:
            im = Image.open(os.path.join(out, n)).convert("RGB")
        except Exception as e:  # noqa: BLE001
            print(f"[wear-screenshots] AVISO: no se pudo abrir {n}: {e}", file=sys.stderr)
            continue
        im.thumbnail((cell, cell))
        x = pad + (i % cols) * (cell + pad)
        y = pad + (i // cols) * (cell + label_h + pad)
        sheet.paste(im, (x, y))
        parts = n[:-4].split("_", 1)
        draw.text((x + 2, y + cell + 2), parts[0][:34], fill=(255, 255, 255))
        if len(parts) > 1:
            draw.text((x + 2, y + cell + 14), parts[1][:34], fill=(255, 255, 255))
    sheet.save(os.path.join(out, "contact_sheet.png"), optimize=True)
    print(f"[wear-screenshots] contact_sheet.png: {len(names)} capturas")
PY
else
  warn "Pillow no disponible; sin contact_sheet.png"
fi

if [ "$CAPTURED" -eq 0 ]; then
  die "no se obtuvo ninguna captura en $DEVICE_DESC"
fi
exit 0
