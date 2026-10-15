#!/usr/bin/env bash
# Compila una variante de Pear Music y, si es dev o pref, la instala en el móvil conectado por USB.
#
#   scripts/variante.sh usr  [debug|release]   APK público (release: firmado si están las variables de la clave)
#   scripts/variante.sh pref [debug|release]   «Pear Pref», sólo para el móvil de Toxbox (se instala por adb)
#   scripts/variante.sh dev  [debug|release]   «Pear Dev», con Administración (se instala por adb)
#
# dev y pref nunca se publican: no se suben a GitHub, a la web ni a ningún sitio. Ver docs/FLAVORS.md.
# Variables: GRADLE (por defecto `gradle`), JAVA_HOME; para firmar, ANDROID_KEYSTORE_* (ver docs/RELEASING.md).
set -euo pipefail
canal="${1:-}"; tipo="${2:-release}"
case "$canal" in usr|pref|dev) ;; *) sed -n '2,8p' "$0"; exit 1 ;; esac
case "$tipo" in debug|release) ;; *) echo "Tipo: debug o release" >&2; exit 1 ;; esac
cd "$(dirname "$0")/.."
Canal="$(tr '[:lower:]' '[:upper:]' <<<"${canal:0:1}")${canal:1}"
Tipo="$(tr '[:lower:]' '[:upper:]' <<<"${tipo:0:1}")${tipo:1}"
"${GRADLE:-gradle}" -q "assemble${Canal}${Tipo}"
apk="app/build/outputs/apk/$canal/$tipo/app-$canal-$tipo.apk"
echo "APK: $apk"
[ "$canal" = usr ] && exit 0
adb get-state >/dev/null 2>&1 || { echo "No hay móvil conectado por USB con la depuración activada." >&2; exit 2; }
adb install -r "$apk"
echo "Instalada en $(adb shell getprop ro.product.model | tr -d '\r')."
