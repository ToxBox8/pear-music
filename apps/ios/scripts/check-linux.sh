#!/bin/sh
# Comprueba la sintaxis de todo el código de iOS en Linux, sin Mac ni CI.
# Sólo sintaxis (swiftc -parse): SwiftUI, AVFoundation y UIKit no existen fuera de Apple, así que los tipos
# y el .ipa siguen dependiendo de ios.yml (macOS).
# Requisito: Swift para Linux de swift.org en ~/tools/swift (o SWIFT=/ruta/a/swiftc).
# En Arch/CachyOS hace falta el enlace ~/tools/swift/compat/libncurses.so.6 -> /usr/lib/libncursesw.so.6.
set -e
cd "$(dirname "$0")/.."
SWIFT="${SWIFT:-$HOME/tools/swift/usr/bin/swiftc}"
export LD_LIBRARY_PATH="$HOME/tools/swift/compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
"$SWIFT" -parse Sources/*.swift
echo "Sintaxis correcta en $(ls Sources/*.swift | wc -l) archivos."
