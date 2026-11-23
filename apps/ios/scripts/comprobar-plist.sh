#!/usr/bin/env bash
# Comprueba el Info.plist del .app compilado (DECISIONS 94): cada API que pide permiso tiene su texto. Sin
# NSFaceIDUsageDescription, evaluatePolicy con Face ID cierra la app; sin NSCameraUsageDescription, la cámara.
# Igual que PermisosTest en Android (USE_BIOMETRIC). Uso: scripts/comprobar-plist.sh <LibreMusic.app | Info.plist>
set -euo pipefail
cd "$(dirname "$0")/.."
ruta="${1:?Uso: $0 <LibreMusic.app o Info.plist>}"
plist="$ruta"; [ -d "$ruta" ] && plist="$ruta/Info.plist"
[ -f "$plist" ] || { echo "::error::No existe $plist"; exit 1; }

# Lo que se busca en Sources → la clave que tiene que llevar el Info.plist.
reglas=(
  "LAContext|NSFaceIDUsageDescription"
  "AVCaptureDevice|NSCameraUsageDescription"
  "MPMediaLibrary|NSAppleMusicUsageDescription"
)

valor() { # plutil en macOS; en Linux, python3 (plistlib lee XML y binario)
  if command -v plutil >/dev/null; then plutil -extract "$1" raw -o - "$plist" 2>/dev/null || true
  else python3 -c 'import plistlib,sys; print(plistlib.load(open(sys.argv[1],"rb")).get(sys.argv[2],""))' "$plist" "$1"; fi
}

fallos=0
for r in "${reglas[@]}"; do
  api="${r%%|*}"; clave="${r##*|}"
  grep -rqE "\b$api\b" Sources || continue
  v="$(valor "$clave")"
  if [ -z "$v" ]; then echo "::error::El código usa $api y el Info.plist no lleva $clave"; fallos=$((fallos + 1))
  else echo "bien: $clave ($api)"; fi
done
exit $((fallos > 0))
