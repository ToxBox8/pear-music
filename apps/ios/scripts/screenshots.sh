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
  14_jam 15_importar
)

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
  xcrun simctl launch "$UDID" "$BUNDLE" -screenshotScenario "$s" >/dev/null
  # Arranque, hojas y navegación (0,3 s) y el título que se revela con símbolos en el reproductor.
  sleep 7
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$s.png" >/dev/null
  echo "✓ $s"
done
