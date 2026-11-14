#!/usr/bin/env bash
# Capturas de iOS con los mismos nombres y estados que ScreenshotTest de Android.
# Uso: scripts/screenshots.sh <LibreMusic.app del simulador> <carpeta de salida>
# Cada escenario se abre con `-screenshotScenario <nombre>` (ver Sources/Screenshots.swift).
set -euo pipefail

APP="$1"
OUT="$2"
BUNDLE="com.example.libremusic"
SCENARIOS=(
  01_biblioteca_cristal 02_biblioteca_cristal_oscuro 03_biblioteca_aire 04_biblioteca_neon
  05_biblioteca_sistema 06_playlist 07_ajustes 08_temas 09_reproductor_normal
  10_reproductor_casete 11_reproductor_vinilo 12_reproductor_air 13_reproductor_neon
  14_jam 15_importar 37_barra_dos_pestanas 38_barra_simpmusic_dos
  43_carpetas 44_carpetas_oscuro 45_carpeta 46_mover_a 47_artistas_siguiendo 48_inicio_novedades
  49_artista_seguir 50_artista_siguiendo 51_eliminar_biblioteca 52_insignia_nuevo_claro 52_insignia_nuevo_oscuro
)
# DEMO=1: las del tráiler v2 con el catálogo del patrocinador (Sources/DemoCatalog.swift; sólo en Debug y Jiyu Dev).
# En castellano, como ScreenshotTest de Android: la app usa `language` (UserDefaults) o el idioma del sistema, y el
# simulador de la CI está en inglés (PARIDAD.md, 14-11-2026).
EXTRA=(-language es -AppleLanguages "(es)" -AppleLocale es_ES)
if [[ "${DEMO:-0}" == "1" ]]; then
  SCENARIOS=(v2_01_inicio v2_02_busqueda v2_03_artista v2_04_biblioteca v2_05_descargas v2_06_reproductor
    v2_07_aire v2_08_neon v2_09_sistema v2_10_casete v2_11_vinilo v2_12_air v2_13_jam v2_14_importar)
  EXTRA+=(-demoCatalog YES)
fi

# iPhone 16 (393×852 pt a 3x = 1179×2556, el tamaño de ScreenshotTest) con el iOS más reciente instalado.
RUNTIME="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(sorted(rts, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]["identifier"])')"
echo "Runtime: $RUNTIME"
UDID="$(xcrun simctl create LibreMusicShots com.apple.CoreSimulator.SimDeviceType.iPhone-16 "$RUNTIME")"
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
# Reducir movimiento como forceReduceMotion de Android: los fondos se quedan en su posición inicial.
xcrun simctl spawn "$UDID" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true || true
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$UDID" "$APP"

mkdir -p "$OUT"
for s in "${SCENARIOS[@]}"; do
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  [[ "$s" == *oscuro* ]] && xcrun simctl ui "$UDID" appearance dark || xcrun simctl ui "$UDID" appearance light
  xcrun simctl launch "$UDID" "$BUNDLE" -screenshotScenario "$s" ${EXTRA[@]+"${EXTRA[@]}"} >/dev/null
  # Arranque, hojas y navegación (0,3 s) y el título que se revela con símbolos en el reproductor.
  sleep 7
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$s.png" >/dev/null
  echo "✓ $s"
done
