#!/usr/bin/env bash
# Tests de iOS que no necesitan Apple (sólo Foundation), con Swift para Linux: hoy, AppVersion (versión con beta y
# comparación de versiones del aviso de versión nueva). Mismo requisito que check-linux.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFT="${SWIFT:-$HOME/tools/swift/usr/bin/swiftc}"
export LD_LIBRARY_PATH="$HOME/tools/swift/compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
cp scripts/tests/AppVersionTests.swift "$OUT/main.swift"
"$SWIFT" -o "$OUT/tests" Sources/AppVersion.swift "$OUT/main.swift"
"$OUT/tests"
