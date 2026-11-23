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
  53_tu_musica_ordenar 54_playlists_ordenar 55_playlists_ordenar_oscuro
  56_cuenta_sin_crear 57_cuenta_crear 58_cuenta_tu_clave 58_cuenta_tu_clave_oscuro 59_cuenta_entrar
  60_cuenta_dispositivos 61_cuenta_comprobar 62_cuenta_borrar
  63_cuenta_qr 64_cuenta_qr_emojis 65_cuenta_anadir 66_cuenta_anadir_emojis 67_cuenta_conectada 68_cuenta_sincronizado 68_cuenta_sincronizado_oscuro 69_cuenta_bloqueado
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
  # Arranque, hojas y navegación (0,3 s) y el título que se revela con símbolos en el reproductor. Antes eran 7 s
  # fijos y a veces no bastaban (la 01 en blanco, la 43 sin entrar, la 46 sin la hoja; T10 de la revisión del
  # bloque 1): ahora, como mínimo 6 s y después hasta que dos capturas seguidas salen iguales (la pantalla está quieta)
  # y no es una pantalla casi vacía. Como mucho unos 20 s; si no se queda quieta, se guarda la última.
  sleep 6
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/$s.png" >/dev/null
  tries=0
  while (( tries < 10 )); do
    sleep 1.5
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$s.next.png" >/dev/null
    same=0; cmp -s "$OUT/$s.png" "$OUT/$s.next.png" && same=1
    mv "$OUT/$s.next.png" "$OUT/$s.png"
    # Una pantalla en blanco (sólo la barra de estado) pesa unos pocos KB; cualquier pantalla de verdad, cientos.
    (( same == 1 && $(wc -c < "$OUT/$s.png") > 150000 )) && break
    tries=$((tries + 1))
  done
  (( tries == 10 )) && echo "⚠ $s no se ha quedado quieta en 21 s: se guarda la última" || true
  echo "✓ $s"
done
