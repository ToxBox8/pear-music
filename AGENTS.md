# AGENTS.md

Guía para cualquier persona o agente (Claude Code, Codex…) que trabaje en este repositorio: dónde está cada cosa, cómo se organiza y qué reglas seguir. El qué y el porqué de la app están en [`CONTEXT.md`](CONTEXT.md); el historial de decisiones, en [`DECISIONS.md`](DECISIONS.md).

## Documentos vivos (léelos primero, mantenlos al día)

`AGENTS.md`, `CONTEXT.md` y `DECISIONS.md` son lo **primero que debe leer cualquier IA o persona** antes de tocar el proyecto (Claude Code los carga desde `CLAUDE.md`). Son la memoria del proyecto, así que forman parte de cada cambio:

| Si el cambio… | Actualiza |
|---|---|
| mueve, crea o borra archivos o carpetas, o cambia cómo se compila, prueba o publica | `AGENTS.md` (mapa, tablas, «Cómo trabajar») |
| cambia lo que hace la app, sus pantallas, temas, reproductores, funcionamiento interno o versión | `CONTEXT.md` |
| es una decisión de producto, diseño o técnica (qué se elige, qué se descarta y por qué) | `DECISIONS.md`: entrada nueva arriba, con fecha AAAA-MM-DD y el motivo. Nunca se borran entradas antiguas; si algo se revierte, se añade una entrada nueva. |

Reglas:

1. Se actualizan en el **mismo commit** que el cambio, no después.
2. Si el cambio no afecta a ninguno, no se tocan.
3. Si lo que dicen los documentos no coincide con el código, gana el código: corrige el documento y apúntalo en el commit.
4. Las decisiones que toma Toxbox se anotan como suyas («Lo decidió Toxbox»).

## Regla principal

**Las dos apps tienen que ser iguales en todo.** iOS es la referencia: cada cambio se hace primero en iOS (`apps/ios`) y después se portea a Android (`apps/android`) con el mismo aspecto, los mismos textos y el mismo comportamiento. Las únicas diferencias admitidas están en la tabla «Diferencias aceptadas» de [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Mapa del repositorio

```
libremusic/
├─ CLAUDE.md                               Hace que Claude Code cargue los tres de abajo
├─ AGENTS.md · CONTEXT.md · DECISIONS.md   Documentos vivos: leer primero, mantener al día
├─ README.md · CHANGELOG.md                Presentación y cambios por versión
├─ apps/
│  ├─ ios/                                 App iOS (SwiftUI, iOS 16+), proyecto XcodeGen
│  │  ├─ project.yml                       Versión, Info.plist, permisos
│  │  ├─ scripts/screenshots.sh            Capturas en el simulador del iPhone 16 (CI)
│  │  ├─ scripts/check-linux.sh            Comprueba la sintaxis de iOS en Linux (Swift de swift.org)
│  │  └─ Sources/                          Todo el código Swift (sin subcarpetas)
│  └─ android/                             App Android (Kotlin + Compose + Media3, API 26+)
│     ├─ gradle/libs.versions.toml         Versiones de dependencias
│     ├─ scripts/bench.sh                  Mide arranque, fluidez y Descubrir en un móvil
│     ├─ scripts/smoke.sh                  Prueba rápida en el móvil: instala, abre pantallas, capturas y cierres
│     └─ app/
│        ├─ build.gradle.kts               versionName / versionCode
│        └─ src/main/java/app/libremusic/  Código Kotlin por capas (ver abajo)
├─ scripts/prepublicar.sh                  Lista de comprobación antes de publicar (versión, CHANGELOG, secretos, firma)
├─ services/soporte/                       Worker de Cloudflare: reportes de errores → Discord (README con el despliegue)
├─ shared/design/                          Diseño común a las dos apps
│  ├─ tokens.json                          Fuente única de colores, temas, radios y letra
│  ├─ gen_tokens.py                        Genera Tokens.swift y Tokens.kt
│  ├─ render_icon.py · AppIcon*.svg        Iconos: AppIcon-Encendido (por defecto) y el violeta (alternativo)
│  ├─ compare_shots.py                     Hoja de capturas iOS | Android
│  └─ Inter-LICENSE.txt                    Licencia de la letra de Android
├─ docs/
│  ├─ ARCHITECTURE.md                      Arquitectura y equivalencias iOS ↔ Android
│  ├─ JAM_PROTOCOL.md                      Protocolo del Jam (v1 iOS, v2 multiplataforma)
│  ├─ LIBRARY_FORMAT.md                    Formato library.json (exportar/importar)
│  ├─ PARIDAD.md                           Comparación iOS ↔ Android y diferencias que quedan
│  ├─ RENDIMIENTO.md                       Cómo se mide el rendimiento en Android y resultados
│  ├─ RELEASING.md                         Versionado, firma y publicación
│  ├─ contexto.md                          Relevo entre sesiones: dónde estamos, bloqueos y siguiente paso
│  ├─ plan.md                              Prompt maestro de Toxbox, orden actual y reglas de pruebas
│  ├─ pendiente-decision.md                Preguntas abiertas del plan con propuestas
│  ├─ publicar/                            Para hacer público el código: análisis legal, LICENSE (GPL-3.0), README, SECURITY, lista
│  ├─ SIGUIENTE-SESION.md                  Prompt para retomar: contexto, reglas, revisión con skills y pruebas por cable
│  ├─ futuro.md                            Lo que falta: pruebas con cable, tests, bloqueos (skills, CI) y funciones pendientes
│  └─ pruebas/                             Capturas y mediciones de cada fase (faseN, v0.8.1-*)
└─ .github/workflows/
   ├─ ios.yml                              .ipa sin firmar y capturas del simulador (macOS; sólo master/monorepo, versiones o a mano)
   ├─ ios-sintaxis.yml                     Sintaxis de Swift en Linux en cualquier rama (barato)
   ├─ android.yml                          Tests, capturas de pantalla y APK (Linux)
   └─ release.yml                          GitHub Release al crear ios-v* / android-v*
```

La web de descarga vive en otro repo: `ToxBox8/libremusic-landing`.

## iOS (`apps/ios/Sources`)

| Área | Archivos |
|---|---|
| Entrada, pestañas, mini reproductor, reproductor, cola | `LibreMusicApp.swift` |
| Datos de YouTube Music (InnerTube) e inicio de sesión | `Client.swift`, `Auth.swift` |
| Reproducción | `Player.swift` (AVPlayer, Ahora suena, AirPlay), `SleepTimer.swift` (temporizador para dormir), `Lyrics.swift` (letras de LRCLIB y su vista), `Fade.swift` (fundido entre canciones), `PlayStats.swift` (estadísticas y su pantalla), `AutoBackup.swift` (copia diaria a una carpeta), `Releases.swift` (novedades de tus artistas), `PendingImports.swift` («Sin añadir»), `AppShortcuts.swift` (atajos de Siri) |
| Biblioteca, playlists, descargas (persistencia) | `Store.swift` |
| Pantallas de biblioteca | `LibraryV11.swift` (la biblioteca), `LibraryViews.swift` (artistas, editor, importar) |
| Inicio y álbumes remotos | `HomeView.swift` |
| Resultados de búsqueda (artistas, álbumes, canciones) y página de artista | `SearchViews.swift` |
| Descubrir (reels) | `Reels.swift` |
| Jam | `Jam.swift`, `JamNet.swift` (v2), `JamViews.swift` |
| Temas y fondos | `Theme.swift`, `Backdrops.swift`, `Tokens.swift` (**generado**) |
| Componentes (botón táctil, scramble, casete…) | `Kitchen.swift` |
| Reproductores Casete/Vinilo, selector | `Deck.swift` |
| Reproductor Air | `AirPlayer.swift` |
| Carátulas y portadas | `Images.swift` |
| Ajustes | `AppSettings.swift` (pantalla principal, Aspecto, colores de la portada, pestañas, Reproducción, Descargas, Ayuda, guía inicial, `TabOrder`, Restablecer), `Settings.swift` (tema, reproductor, biblioteca, Acerca de, filas) |
| Informar de un error (formulario, borradores, envío) | `Support.swift` |
| Importar de Apple Music; `Matcher` (emparejado con confianza) | `AppleMusic.swift` |
| Importar de Spotify (enlace y CSV de Exportify) y SimpMusic (`.backup`), emparejado de listas e importaciones a medias | `ExternalImport.swift` |
| Modo de capturas (`-screenshotScenario`) | `Screenshots.swift` |

## Android (`apps/android/app/src/main/java/app/libremusic`)

| Carpeta | Contenido | Equivale en iOS a |
|---|---|---|
| `ui/LibreMusicApp.kt`, `ui/Nav.kt` | Raíz, pestañas, pilas de navegación, hojas, avisos | `LibreMusicApp.swift` |
| `ui/Home.kt` | Inicio, búsqueda, álbumes | `HomeView.swift` |
| `ui/Search.kt` | Resultados de búsqueda y página de artista | `SearchViews.swift` |
| `ui/Library.kt`, `ui/Songs.kt`, `ui/Stats.kt` | Biblioteca 1.1, filas de canción, editor, importar, estadísticas | `LibraryV11.swift`, `LibraryViews.swift` |
| `ui/Player.kt`, `ui/LyricsView.kt`, `ui/Decks.kt`, `ui/AirPlayer.kt` | Reproductor, letra, casete, vinilo, Air | `LibreMusicApp.swift`, `Deck.swift`, `Kitchen.swift`, `AirPlayer.swift` |
| `ui/SettingsScreens.kt`, `ui/Onboarding.kt`, `ui/Support.kt` | Ajustes y formularios; guía inicial; informar de un error | `AppSettings.swift`, `Settings.swift`, `Support.swift` |
| `ui/Kitchen.kt` | Componentes comunes | `Kitchen.swift`, `Images.swift` |
| `ui/Glass.kt` | Cristal líquido opcional (capa grabada + desenfoque + shader AGSL de refracción, gota de la barra de pestañas, pulsación con rebote) | El cristal de iOS 26 lo da el sistema |
| `ui/theme/` | `Theme.kt` (temas y Prefs), `Backdrops.kt`, `Type.kt` (Inter), `SfIcons.kt`, `Tokens.kt` (**generado**) | `Theme.swift`, `Backdrops.swift` |
| `ui/*ViewModel.kt` | Estado de reproductor, biblioteca e inicio | objetos `@EnvironmentObject` |
| `playback/` | `PlaybackService` (Media3), `Tracks.kt` (resuelve el audio), `BrowseTree` (Android Auto), `SleepTimer` (temporizador para dormir), `Fade.kt` (fundido entre canciones y `VolumeMix`), `Eq.kt` (ecualizador, sólo Android), `AutoRadio` (radio infinita), `PlayCounter` (cuenta escuchas), `NowPlayingWidget` (widget de la pantalla de inicio), `LastQueue` (última cola para retomar con la app cerrada) | `Player.swift` |
| `data/` | `YTClient`, `Song`, `Library` (library.json), `AppleMusic.kt` (y `Matcher`), `ExternalImport.kt` (Spotify, Exportify, SimpMusic, `ImportMatcher`, `ImportJob`), `TabOrder`, `Support` (borradores y envío), `AppIcon` (icono de la app), `Lyrics` (letras de LRCLIB), `PlayStats` (estadísticas, `stats.json`), `AutoBackup` (copia diaria a una carpeta), `Releases` (novedades de tus artistas), `PendingImports` («Sin añadir» de las importaciones), `AppShortcuts` (atajos del icono) | `Client.swift`, `Store.swift`, `AppleMusic.swift` |
| `download/` | Descargas con Media3 DownloadManager | `DownloadStore` en `Store.swift` |
| `reels/`, `jam/` | Descubrir y Jam | `Reels.swift`, `Jam*.swift` |

Tests en `app/src/test`: lógica (YTClient, `Matcher`, descargas, Jam, biblioteca, reels) y `ui/ScreenshotTest.kt` (capturas de pantalla en vertical; `LandscapeShotTest`, los reproductores y el inicio en horizontal, `h*.png`; `LargeTextShotTest`, letra al 150 %, `t*.png`; `WidgetShotTest`, el widget, `w1_widget.png`).

## Cómo trabajar

- **Compilar:** no hace falta Mac. Cada push que toca `apps/android` lanza su workflow; el de iOS en macOS sólo se lanza solo en `master`/`monorepo` (los minutos de macOS cuentan ×10), en las versiones o a mano, y en las demás ramas `ios-sintaxis.yml` comprueba la sintaxis en Linux. El .ipa y el APK salen como artefactos.
- **Errores de Android:** la CI los publica como anotaciones: `gh api repos/ToxBox8/libremusic/check-runs/<job>/annotations`.
- **Capturas:** `ScreenshotTest` (Android) dibuja 26 pantallas con el tamaño y los márgenes seguros del iPhone 16 y la CI las sube a la rama `screenshots`; `ios.yml` hace en el simulador (`-screenshotScenario`) las 15 primeras y las sube a `screenshots-ios` (de la 16 a la 22 —Tus álbumes, Aspecto, colores, pestañas, guía, informar de un error, icono— aún no tienen escenario en iOS). `python3 shared/design/compare_shots.py --out /tmp/paridad` genera la hoja iOS | Android. Antes de integrar un cambio de interfaz, compara y deja `docs/PARIDAD.md` al día.
- **Android en local (opcional):** con Gradle 8.11.1, JDK 17 y el SDK de Android, `gradle testDebugUnitTest --tests '*ScreenshotTest'` deja las capturas en `app/build/shots/` en un par de minutos.
- **Probar en un móvil Android:** `gradle assembleDebug` instala `app.libremusic.debug` al lado de la app normal; los cierres se leen con `adb logcat -b crash -d`. Para medir fluidez, la variante `perf` y `scripts/bench.sh` (ver `docs/RENDIMIENTO.md`); compara con la tabla antes de integrar cambios que afecten a la fluidez.
- **Compilar iOS sin gastar cuota:** el repo privado se queda sin minutos de macOS; el público `ToxBox8/pear-music` los tiene gratis. Rama `ios-compila` con sólo `apps/ios` (commit con `ToxBox8@users.noreply.github.com`, nunca el historial de este repo) y `gh workflow run ios.yml -R ToxBox8/pear-music --ref ios-compila`; pasos en `docs/contexto.md`.
- **Errores de iOS:** también salen como anotaciones (los dos `xcodebuild` de `ios.yml`). Sin Mac ni CI, `apps/ios/scripts/check-linux.sh` comprueba al menos la sintaxis con Swift para Linux (los tipos de SwiftUI no, porque sólo existen en Apple).
- **Diseño:** nunca escribas colores, radios o tamaños de marca a mano. Cámbialos en `shared/design/tokens.json` y ejecuta `python3 shared/design/gen_tokens.py`. La CI falla si `Tokens.swift` o `Tokens.kt` no están al día.
- **Icono:** el de por defecto es `AppIcon-Encendido.svg` (en Android, `drawable/ic_launcher_power.xml`); el violeta alternativo lo dibuja `render_icon.py` (y su SVG). Ejecuta `render_icon.py` tras cambiar cualquiera de los dos. Para añadir otro icono: un `activity-alias` en el manifiesto + `AppIcon.kt`, y un `.appiconset` + `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` en `project.yml`.
- **Ramas:** `monorepo` es la rama de trabajo; usa ramas propias para cambios grandes y no integres sin la CI en verde.
- **Versiones:** sube la versión y anota el cambio en `CHANGELOG.md` en el mismo commit (ver `docs/RELEASING.md`).
- **Decisiones:** cuando se tome una decisión de producto o de diseño, añádela con fecha a `DECISIONS.md`.

## Convenciones

- Textos de la interfaz, comentarios y mensajes de commit **en español**.
- Mismos nombres de ajustes en las dos apps (`theme`, `appearance`, `deck`, `searchPlacement`, `playlistSort`, `playlistOrder`, `smartPlacement`, `artworkColorsPlayer`, `artworkColorsApp`, `artworkIntensity`, `artworkOpacity`, `tabOrder`, `lastTab`, `onboarded`, `repeatMode`, `matchTolerance`, `crossfade`, `autoplay`, `scramble`, `quality`; `liquidGlass` y `equalizer` sólo en Android), mismo `library.json` y mismo protocolo del Jam.
- Animaciones con la curva «ui ease out» `cubic-bezier(0.23, 1, 0.32, 1)` y respeto a «Reducir movimiento».
- Botones de al menos 44 pt/dp de área táctil y textos que crecen con el tamaño de letra del sistema.
- Los commits terminan con las líneas de coautoría de Claude cuando los hace Claude.
