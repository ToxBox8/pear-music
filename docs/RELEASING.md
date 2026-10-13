# Publicar versiones

Cada app se versiona por separado con [SemVer](https://semver.org/lang/es/). Las etiquetas llevan prefijo de plataforma para que una release de iOS no dispare la de Android y viceversa.

| Plataforma | Dónde está la versión | Etiqueta | Binario en la Release |
|---|---|---|---|
| iOS | `apps/ios/project.yml` → `CFBundleShortVersionString` (versión) y `CFBundleVersion` (build, entero que siempre sube) | `ios-vX.Y.Z` | `LibreMusic-ios-X.Y.Z.ipa` |
| Android | `apps/android/app/build.gradle.kts` → `versionName` y `versionCode` (entero que siempre sube) | `android-vX.Y.Z` | `LibreMusic-android-X.Y.Z.apk` |

## Antes de publicar

`scripts/prepublicar.sh android [apk]` o `scripts/prepublicar.sh ios` comprueba, sin publicar nada:

1. Que la etiqueta (`android-vX` / `ios-vX`) es nueva, es decir, que se ha subido la versión.
2. Que `CHANGELOG.md` tiene su sección (y avisa si aún pone «sin publicar»).
3. Que los tokens de diseño están generados.
4. Que en los cambios desde la última versión no hay archivos ni textos con pinta de secreto (keystores, `.env`, `CONTRASEÑAS`, webhooks de Discord, claves privadas, tokens de GitHub o AWS).
5. Android: que el APK está firmado con la clave de publicación (SHA-256 `9a38c4d7…`), que es la versión del código y que no lleva la URL del webhook.
6. iOS: que la sintaxis es correcta (`apps/ios/scripts/check-linux.sh`).

Para probar en el móvil antes de publicar: `apps/android/scripts/smoke.sh` (instala la versión de pruebas, abre Inicio, Descubrir y Buscar, guarda capturas y busca cierres; se para si no hay un móvil autorizado o si está bloqueado).

## Pasos

1. Actualiza la versión en el archivo de la tabla y añade la entrada en `CHANGELOG.md` (mueve «Sin publicar» a la versión con fecha).
2. Commit en la rama principal: `git commit -am "iOS 1.1.0"`.
3. Etiqueta y sube:
   ```bash
   git tag ios-v1.1.0        # o android-v0.1.0
   git push origin master --tags
   ```
4. El workflow **Release** compila con el mismo workflow de CI de esa plataforma y crea la GitHub Release `iOS 1.1.0` / `Android 0.1.0` con el binario y su SHA-256.
5. Actualiza la web de descarga (repo `libremusic-landing`): copia el binario a `public/downloads/` como `LibreMusic.ipa` / `LibreMusic.apk` (este repo es privado, así que los assets de la Release no se pueden enlazar) y actualiza versión, tamaño y SHA-256 en `src/config/downloads.ts`; para iOS, añade la versión a `public/altstore.json` y quita las que apunten a un archivo que ya no existe. Al hacer push a `main`, Cloudflare Workers Builds publica la web sola.

Si sólo quieres publicar una plataforma, sube sólo su etiqueta. Las etiquetas también lanzan la CI normal de las dos apps; se puede cancelar, la Release compila por su cuenta.

## Si la CI no funciona (Android)

Pasó con 0.8.1 (cuota de Actions agotada). El APK se compila y se firma en local con la misma clave:

```bash
export ANDROID_KEYSTORE_PATH=…/firma-android/libremusic-release.jks
export ANDROID_KEY_ALIAS=… ANDROID_KEYSTORE_PASSWORD=… ANDROID_KEY_PASSWORD=…   # de tu gestor de contraseñas
cd apps/android && gradle assembleRelease
apksigner verify --print-certs app/build/outputs/apk/release/app-release.apk   # SHA-256 9a38c4d7…
cp app/build/outputs/apk/release/app-release.apk LibreMusic-android-X.Y.Z.apk && sha256sum LibreMusic-android-X.Y.Z.apk > SHA256SUMS.txt
git tag -a android-vX.Y.Z -m "Android X.Y.Z" && git push origin android-vX.Y.Z
gh release create android-vX.Y.Z LibreMusic-android-X.Y.Z.apk SHA256SUMS.txt --title "Android X.Y.Z" --notes-file notas.md
```

No exportes las contraseñas en un archivo del repo ni las escribas en el historial de la terminal. iOS no tiene
alternativa local (hace falta macOS).

## Firma

### iOS
El `.ipa` se compila **sin firmar** (`CODE_SIGNING_ALLOWED=NO`). Lo firma cada usuario con su Apple ID al instalarlo con AltStore, SideStore o Sideloadly. No hay claves que guardar.

### Android
Los APK publicados deben firmarse **siempre con la misma clave**; si se pierde, nadie podrá actualizar sobre su instalación.

1. Genera la clave una sola vez en tu ordenador (no en el repo):
   ```bash
   keytool -genkeypair -v -keystore libremusic-release.jks -alias libremusic \
     -keyalg RSA -keysize 4096 -validity 10000
   ```
2. Guarda una copia de `libremusic-release.jks` y sus contraseñas en un gestor de contraseñas.
3. En GitHub → *Settings → Secrets and variables → Actions* crea:
   - `ANDROID_KEYSTORE_BASE64` → salida de `base64 -w0 libremusic-release.jks`
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEY_ALIAS` → `libremusic`
   - `ANDROID_KEY_PASSWORD`

Sin esos secretos la CI firma con una clave de depuración temporal: el APK sirve para probar, pero **no** para publicar (cada build tendría una firma distinta).

`.gitignore` bloquea `*.jks`, `*.keystore` y `keystore.properties` para que la clave nunca acabe en el repositorio.

## Canales de distribución

- **Web** (`libremusic-landing`): canal principal para usuarios.
- **GitHub Releases**: archivo histórico de todas las versiones.
- **Obtainium** (Android): puede seguir las Releases filtrando por la etiqueta `android-v`.
- **AltStore / SideStore** (iOS): fuente `altstore.json` publicada en la web.
- **Google Play / App Store**: no disponibles (sus políticas no admiten clientes no oficiales de YouTube).
