#!/usr/bin/env bash
# Tests de iOS que no necesitan Apple (sólo Foundation), con Swift para Linux: AppVersion (versión con beta y
# comparación de versiones del aviso de versión nueva) y library.json con carpetas (LibraryModel.swift, con los casos
# comunes de shared/library/) y artistas seguidos con la mezcla de Novedades (LibraryModel.swift y ReleasesModel.swift).
# Y las carpetas y sus órdenes entre dos móviles con la sync (SyncCarpetasTests: LibraryFile + SyncModel), y un texto
# por cada código de error de la cuenta (ErroresCuentaTests: CuentaErrores con docs/spec/cuenta.md §7.1).
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

mkdir "$OUT/disco"
cp scripts/tests/LibraryDiskTests.swift "$OUT/disco/main.swift"
"$SWIFT" -o "$OUT/disco/tests" Sources/LibraryModel.swift Sources/I18n.swift "$OUT/disco/main.swift"
"$OUT/disco/tests"

mkdir "$OUT/ordenar"
cp scripts/tests/GridOrderTests.swift "$OUT/ordenar/main.swift"
"$SWIFT" -o "$OUT/ordenar/tests" Sources/LibraryModel.swift Sources/I18n.swift "$OUT/ordenar/main.swift"
"$OUT/ordenar/tests"

mkdir "$OUT/sync"
cp scripts/tests/SyncModelTests.swift "$OUT/sync/main.swift"
"$SWIFT" -o "$OUT/sync/tests" Sources/SyncModel.swift "$OUT/sync/main.swift"
"$OUT/sync/tests" ../../shared/library

mkdir "$OUT/sync-carpetas"
cp scripts/tests/SyncCarpetasTests.swift "$OUT/sync-carpetas/main.swift"
"$SWIFT" -o "$OUT/sync-carpetas/tests" Sources/LibraryModel.swift Sources/I18n.swift Sources/SyncModel.swift "$OUT/sync-carpetas/main.swift"
"$OUT/sync-carpetas/tests"

mkdir "$OUT/errores"
cp scripts/tests/ErroresCuentaTests.swift "$OUT/errores/main.swift"
"$SWIFT" -o "$OUT/errores/tests" Sources/CuentaErrores.swift Sources/I18n.swift "$OUT/errores/main.swift"
"$OUT/errores/tests" ../../docs/spec/cuenta.md

mkdir "$OUT/estado-sync"
cp scripts/tests/EstadoSyncTests.swift "$OUT/estado-sync/main.swift"
"$SWIFT" -o "$OUT/estado-sync/tests" Sources/SyncVista.swift Sources/I18n.swift "$OUT/estado-sync/main.swift"
"$OUT/estado-sync/tests"
