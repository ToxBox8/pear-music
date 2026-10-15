#!/bin/sh
# Prueba rápida en el móvil conectado por USB: instala la versión de pruebas (app.libremusic.debug), abre la app y
# varias pantallas con los atajos, guarda capturas y mira si hubo cierres.
#
#   scripts/smoke.sh [carpeta-de-capturas]        (por defecto docs/pruebas/smoke-AAAA-MM-DD)
#
# Reglas (docs/plan.md): sólo el móvil que se ve en `adb devices`; si no hay uno autorizado o está bloqueado, se para
# (nunca se mete un PIN); no se cambia ningún ajuste del móvil, sólo se instala y se abre la app de pruebas.
set -eu
cd "$(dirname "$0")/.."
PKG=app.libremusic.debug
OUT="${1:-../../docs/pruebas/smoke-$(date +%F)}"

devices=$(adb devices | awk 'NR>1 && $2=="device" {print $1}')
count=$(printf '%s\n' "$devices" | grep -c . || true)
if [ "$count" -ne 1 ]; then
    echo "Hace falta exactamente un móvil autorizado en «adb devices» (hay $count). Se para." >&2
    adb devices >&2
    exit 1
fi
if adb shell dumpsys window | grep -q "mDreamingLockscreen=true\|isKeyguardShowing=true\|mShowingLockscreen=true"; then
    echo "El móvil está bloqueado. Desbloquéalo tú y vuelve a lanzar el script (no se introduce ningún PIN)." >&2
    exit 1
fi

[ -f app/build/outputs/apk/usr/debug/app-usr-debug.apk ] || { echo "Compila antes: gradle assembleUsrDebug" >&2; exit 1; }
adb install -r app/build/outputs/apk/usr/debug/app-usr-debug.apk >/dev/null
adb logcat -b crash -c
mkdir -p "$OUT"

shot() {
    sleep "$2"
    adb exec-out screencap -p > "$OUT/$1.png"
    echo "  $1.png"
}

echo "Capturas en $OUT:"
adb shell am start -W -n "$PKG/app.libremusic.MainActivity" >/dev/null
shot 01_inicio 4
for k in discover search; do
    adb shell am start -W -n "$PKG/app.libremusic.MainActivity" -a app.libremusic.action.SHORTCUT --es shortcut "$k" >/dev/null
    shot "02_$k" 3
done
adb shell input keyevent KEYCODE_HOME

crashes=$(adb logcat -b crash -d | grep -c "FATAL EXCEPTION" || true)
if [ "$crashes" -gt 0 ]; then
    adb logcat -b crash -d > "$OUT/cierres.txt"
    echo "⚠️  $crashes cierre(s): $OUT/cierres.txt" >&2
    exit 2
fi
echo "Sin cierres."
