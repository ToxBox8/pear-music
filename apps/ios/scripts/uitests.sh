#!/usr/bin/env bash
# Tests de interfaz de iOS (UITests/, XCUITest) en el simulador del iPhone 16, como scripts/screenshots.sh.
# Uso (desde apps/ios, con el proyecto ya generado por XcodeGen): scripts/uitests.sh <carpeta de salida> [Clase]
# [Clase] (opcional, p. ej. CuentaUITests): sólo esa clase de tests (-only-testing:LibreMusicUITests/<Clase>).
# Deja en la salida las capturas y notas de cada test (los tests las escriben en /tmp/jiyu-uitests) y el registro.
# Sale con 1 si algún test falla; los fallos van también como anotaciones de GitHub.
set -uo pipefail

OUT="$1"
SOLO="${2:-}"
SOLO_ARGS=()
if [[ -n "$SOLO" ]]; then
  [[ "$SOLO" =~ ^[A-Za-z0-9_/]+$ ]] || { echo "::error::Clase de tests no válida: $SOLO"; exit 2; }
  SOLO_ARGS=(-only-testing:"LibreMusicUITests/$SOLO")
  echo "Sólo: LibreMusicUITests/$SOLO"
fi
mkdir -p "$OUT"
rm -rf /tmp/jiyu-uitests

RUNTIME="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(sorted(rts, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]["identifier"])')"
echo "Runtime: $RUNTIME"
UDID="$(xcrun simctl create JiyuUITests com.apple.CoreSimulator.SimDeviceType.iPhone-16 "$RUNTIME")"
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
# Sin el teclado físico del Mac: que salga el de pantalla, como en un iPhone.
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false || true

xcodebuild test -project LibreMusic.xcodeproj -scheme LibreMusicUITests ${SOLO_ARGS[@]+"${SOLO_ARGS[@]}"} \
  -destination "id=$UDID" -derivedDataPath build-uitests CODE_SIGNING_ALLOWED=NO > "$OUT/xcodebuild.log" 2>&1
STATUS=$?

cp -R /tmp/jiyu-uitests/. "$OUT/" 2>/dev/null || true
grep -E "Test Case .* (passed|failed)" "$OUT/xcodebuild.log" | sed -E 's/^.*Test Case/Test Case/' | tee "$OUT/resumen.txt"
grep -E "error:" "$OUT/xcodebuild.log" | sort -u | head -60 | sed -E 's/^/::error::/'
exit $STATUS
