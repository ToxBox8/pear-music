#!/bin/sh
# Lista de comprobación antes de publicar una versión (docs/RELEASING.md › «Antes de publicar»).
#
#   scripts/prepublicar.sh android [ruta/al/app-release.apk]
#   scripts/prepublicar.sh ios
#
# No publica nada: sólo comprueba y dice qué falta. Sale con 1 si algo falla.
set -u
cd "$(dirname "$0")/.."
plat="${1:-}"
fail=0
ok()  { printf '  ✅ %s\n' "$1"; }
bad() { printf '  ❌ %s\n' "$1"; fail=1; }
warn(){ printf '  ⚠️  %s\n' "$1"; }

case "$plat" in
android)
    version=$(sed -n 's/.*versionName = "\(.*\)".*/\1/p' apps/android/app/build.gradle.kts)
    code=$(sed -n 's/.*versionCode = \([0-9]*\).*/\1/p' apps/android/app/build.gradle.kts)
    tag="android-v$version"
    echo "Android $version (versionCode $code)"
    ;;
ios)
    version=$(sed -n 's/.*CFBundleShortVersionString: *"\{0,1\}\([0-9.]*\)"\{0,1\}.*/\1/p' apps/ios/project.yml | head -1)
    build=$(sed -n 's/.*CFBundleVersion: *"\{0,1\}\([0-9]*\)"\{0,1\}.*/\1/p' apps/ios/project.yml | head -1)
    tag="ios-v$version"
    echo "iOS $version (build $build)"
    ;;
*) echo "Uso: $0 android|ios [apk]" >&2; exit 2 ;;
esac

# 1. Versión nueva: la etiqueta no puede existir ya.
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null || git ls-remote --tags origin "$tag" 2>/dev/null | grep -q .; then
    bad "La etiqueta $tag ya existe: sube la versión."
else
    ok "La etiqueta $tag es nueva."
fi

# 2. CHANGELOG con una sección para esta versión.
if grep -q "^### \[$version\]" CHANGELOG.md; then ok "CHANGELOG tiene [$version]."; else bad "Falta «### [$version]» en CHANGELOG.md."; fi
if grep -q "^### \[$version\] — sin publicar" CHANGELOG.md; then warn "En CHANGELOG [$version] pone «sin publicar»: cambia la fecha al publicar."; fi

# 3. Tokens de diseño generados al día.
if python3 shared/design/gen_tokens.py --check >/dev/null 2>&1; then ok "Tokens de diseño al día."; else bad "Tokens desactualizados: python3 shared/design/gen_tokens.py"; fi

# 4. Nada de secretos en lo que se ha subido desde la última etiqueta de esta plataforma.
last=$(git tag -l "${tag%v*}v*" --sort=-v:refname | head -1)
range="${last:+$last..}HEAD"
files=$(git diff --name-only $range 2>/dev/null)
if printf '%s\n' "$files" | grep -Eiq '(\.env$|\.jks$|\.keystore$|\.p12$|\.mobileprovision$|CONTRASEÑAS|secrets?\.)'; then
    bad "Hay archivos con pinta de secreto en $range:"; printf '%s\n' "$files" | grep -Ei '(\.env$|\.jks$|\.keystore$|\.p12$|CONTRASEÑAS|secrets?\.)' | sed 's/^/       /'
elif git diff $range 2>/dev/null | grep -Eq '^\+.*(discord(app)?\.com/api/webhooks/|-----BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16})'; then
    bad "Hay algo con pinta de clave o webhook en los cambios de $range."
else
    ok "Sin secretos en los cambios desde ${last:-el principio}."
fi

# 5. Android: APK firmado con la clave de siempre y con la versión correcta.
if [ "$plat" = android ]; then
    apk="${2:-apps/android/app/build/outputs/apk/usr/release/app-usr-release.apk}"
    if [ ! -f "$apk" ]; then
        warn "No hay APK en $apk (compila con assembleUsrRelease o pásalo como segundo argumento)."
    else
        bt=$(ls -d "$HOME"/Android/Sdk/build-tools/* 2>/dev/null | sort -V | tail -1)
        if [ -n "$bt" ] && "$bt/apksigner" verify --print-certs "$apk" 2>/dev/null | grep -q "SHA-256 digest: 9a38c4d7"; then
            ok "APK firmado con la clave de publicación (9a38c4d7…)."
        else
            bad "El APK no está firmado con la clave de publicación (o no se encuentra apksigner)."
        fi
        if [ -n "$bt" ] && "$bt/aapt2" dump badging "$apk" 2>/dev/null | grep -q "versionName='$version'"; then ok "El APK es la versión $version."; else bad "El APK no es la versión $version."; fi
        if unzip -p "$apk" 'classes*.dex' 2>/dev/null | grep -aq "discord.com/api/webhooks"; then bad "El APK contiene una URL de webhook de Discord."; else ok "El APK no lleva el webhook de Discord."; fi
    fi
fi

# 6. iOS: sintaxis comprobada (el .ipa lo hace la CI).
if [ "$plat" = ios ]; then
    if apps/ios/scripts/check-linux.sh >/dev/null 2>&1; then ok "Sintaxis de iOS correcta (check-linux.sh)."; else bad "Errores de sintaxis en iOS: apps/ios/scripts/check-linux.sh"; fi
fi

# 7. Web: la versión tiene su entrada en «Novedades» (src/config/changelog.ts de libremusic-landing).
web="${LANDING:-../libremusic-landing}/src/config/changelog.ts"
if [ ! -f "$web" ]; then
    warn "No encuentro la web en ${web%/src/*} (ponla al lado o usa LANDING=ruta): añade la versión a su changelog.ts."
elif grep -A1 "platform: \"$plat\"" "$web" | grep -q "version: \"$version\""; then
    ok "La web tiene $version en Novedades."
else
    bad "Falta $version en Novedades de la web: añádela arriba en src/config/changelog.ts (y quítala de «upcoming»), luego bun scripts/gen-feeds.ts."
fi

echo
if [ $fail -eq 0 ]; then echo "Todo listo para etiquetar $tag."; else echo "Hay cosas que arreglar antes de publicar."; fi
exit $fail
