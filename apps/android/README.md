# LibreMusic para Android

App nativa en **Kotlin + Jetpack Compose + Media3**. Paquete `app.libremusic` (las builds de depuración usan `app.libremusic.debug` y pueden convivir con la de release).

Estado: **Fase 1 (MVP)**: buscar, escuchar en segundo plano, cola y favoritos. Deep link `libremusic://jam/CÓDIGO` preparado para el Jam. La hoja de ruta está en `docs/ARCHITECTURE.md`.

## Requisitos

- JDK 17
- Android SDK (plataforma 35). En Arch: `android-sdk-cmdline-tools-latest` (AUR) o Android Studio
- Gradle 8.11 (la CI usa `gradle/actions/setup-gradle`)

## Compilar e instalar

```bash
cd apps/android
gradle testDebugUnitTest         # tests
gradle assembleDebug             # APK de depuración
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Sin entorno local: cada push que toque `apps/android/` lanza el workflow **Android** en GitHub Actions. El APK queda como artefacto `LibreMusic-android`.

## Estructura

```
app/src/main/java/app/libremusic/
├─ AppActivity.kt             Entrada y deep links (en el manifiesto, un activity-alias por icono de la app)
├─ ui/                        Compose (HomeScreen, theme/)
├─ playback/PlaybackService   MediaSessionService + ExoPlayer
└─ jam/JamLink                Código/enlace del Jam (compatible con iOS)
app/src/test/                 Tests unitarios (JVM)
```

## Firma y publicación

Ver `docs/RELEASING.md`. Nunca subas `*.jks` ni contraseñas al repositorio: van en los secretos de GitHub.
