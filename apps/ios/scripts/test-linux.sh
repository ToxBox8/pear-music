#!/usr/bin/env bash
# Tests de iOS que no necesitan Apple (sólo Foundation), con Swift para Linux: AppVersion (versión con beta y
# comparación de versiones del aviso de versión nueva) y library.json con carpetas (LibraryModel.swift, con los casos
# comunes de shared/library/) y artistas seguidos con la mezcla de Novedades (LibraryModel.swift y ReleasesModel.swift).
# Mismo requisito que check-linux.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFT="${SWIFT:-$HOME/tools/swift/usr/bin/swiftc}"
export LD_LIBRARY_PATH="$HOME/tools/swift/compat${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
cp scripts/tests/AppVersionTests.swift "$OUT/main.swift"
"$SWIFT" -o "$OUT/tests" Sources/AppVersion.swift "$OUT/main.swift"
"$OUT/tests"

mkdir "$OUT/carpetas"
cp scripts/tests/LibraryFoldersTests.swift "$OUT/carpetas/main.swift"
"$SWIFT" -o "$OUT/carpetas/tests" Sources/LibraryModel.swift Sources/I18n.swift "$OUT/carpetas/main.swift"
"$OUT/carpetas/tests" ../../shared/library

mkdir "$OUT/seguidos"
cp scripts/tests/FollowedArtistsTests.swift "$OUT/seguidos/main.swift"
"$SWIFT" -o "$OUT/seguidos/tests" Sources/LibraryModel.swift Sources/ReleasesModel.swift Sources/I18n.swift "$OUT/seguidos/main.swift"
"$OUT/seguidos/tests" ../../shared/library
