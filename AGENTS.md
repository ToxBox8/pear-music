# AGENTS.md

Guía para cualquier persona o agente (Claude Code, Codex…) que trabaje en este repositorio: dónde está cada cosa, cómo se organiza y qué reglas seguir. El qué y el porqué de la app están en [`CONTEXT.md`](CONTEXT.md); el historial de decisiones, en [`DECISIONS.md`](DECISIONS.md).

## Documentos vivos (léelos primero, mantenlos al día)

`AGENTS.md`, `CONTEXT.md` y `DECISIONS.md` son lo **primero que debe leer cualquier IA o persona** antes de tocar el proyecto (Claude Code carga `AGENTS.md` y `CONTEXT.md` desde `CLAUDE.md`; de `DECISIONS.md` busca sólo la entrada que necesita, y el código lo explora con el grafo de graphify, `graphify-out/`). Son la memoria del proyecto, así que forman parte de cada cambio:

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
├─ CLAUDE.md                               Hace que Claude Code cargue AGENTS y CONTEXT, y use el grafo
├─ graphify-out/                           Grafo de conocimiento del código y los docs (local, no va en git)
├─ AGENTS.md · CONTEXT.md · DECISIONS.md   Documentos vivos: leer primero, mantener al día
├─ README.md · CHANGELOG.md                Presentación y cambios por versión
├─ apps/
│  ├─ ios/                                 App iOS (SwiftUI, iOS 16+), proyecto XcodeGen
│  │  ├─ project.yml                       Versión, Info.plist, permisos
│  │  ├─ scripts/screenshots.sh            Capturas en el simulador del iPhone 16 (CI)
│  │  ├─ scripts/check-linux.sh            Comprueba la sintaxis de iOS en Linux (Swift de swift.org)
│  │  ├─ Config/                           Usr/Pref/Dev.xcconfig: bundle id, nombre y canal de cada variante
│  │  └─ Sources/                          Todo el código Swift (sin subcarpetas)
│  └─ android/                             App Android (Kotlin + Compose + Media3, API 26+)
│     ├─ gradle/libs.versions.toml         Versiones de dependencias
│     ├─ scripts/bench.sh                  Mide arranque, fluidez y Descubrir en un móvil
│     ├─ scripts/smoke.sh                  Prueba rápida en el móvil: instala, abre pantallas, capturas y cierres
│     ├─ scripts/variante.sh               Compila usr/pref/dev; pref y dev se instalan por adb (nunca se publican)
│     └─ app/
│        ├─ build.gradle.kts               versionName / versionCode
│        └─ src/main/java/app/libremusic/  Código Kotlin por capas (ver abajo)
├─ scripts/prepublicar.sh                  Lista de comprobación antes de publicar (versión, CHANGELOG, secretos, firma)
├─ scripts/activar-discord.sh              Activa las apps de Discord de soporte y pánico con ~/.config/pear-music/discord-*.env
├─ scripts/web-1.0.py                      Lo llama ../lanzar-1.0.sh: pone la 1.0/2.0 en downloads.ts, changelog.ts y altstore.json
├─ scripts/web-x.1.1.py                    Lo llama ../lanzar-x.1.1.sh: pone la 1.2/2.2 (textos de la versión) en la web
├─ services/soporte/                       Worker de Cloudflare: reportes de errores → Discord, rechazos y apelaciones (README con el despliegue)
├─ services/api/                           Worker pear-music-api: cuenta opcional, biblioteca cifrada y telemetría (D1; README)
├─ services/web-antigua/                   Worker «libremusic-landing»: redirige la dirección antigua de la web a la nueva (301/308)
├─ services/estado/                        Worker pear-music-estado: kill switch firmado y botón de pánico (README, scripts de Discord y secretos)
├─ tools/estado/estado.mjs                 PC de Toxbox: clave Ed25519, lotes prefirmados y publicar estados
├─ tools/i18n/                             extraer.py (textos → L("…") y catálogo) y construir.py (<idioma>.json a las dos apps)
├─ shared/i18n/                            Catálogo de idiomas: es.json (claves), src/orden.txt y src/<idioma>.txt (traducciones)
├─ shared/design/                          Diseño común a las dos apps
│  ├─ tokens.json                          Fuente única de colores, temas, radios y letra
│  ├─ gen_tokens.py                        Genera Tokens.swift y Tokens.kt
│  ├─ render_icon.py · AppIcon*.svg        Iconos: AppIcon-Encendido (el de Pear Music) y AppIcon (logo antiguo, sólo historia de la marca)
│  ├─ render_variant_icons.py              Iconos de Pear Dev y Pear Pref (Android por flavor e iOS AppIcon-Dev/-Pref)
│  ├─ compare_shots.py                     Hoja de capturas iOS | Android
│  └─ Inter-LICENSE.txt                    Licencia de la letra de Android
├─ docs/
│  ├─ ARCHITECTURE.md                      Arquitectura y equivalencias iOS ↔ Android
│  ├─ JAM_PROTOCOL.md                      Protocolo del Jam (v1 iOS, v2 multiplataforma)
│  ├─ LIBRARY_FORMAT.md                    Formato library.json (exportar/importar)
│  ├─ PARIDAD.md                           Comparación iOS ↔ Android y diferencias que quedan
│  ├─ RENDIMIENTO.md                       Cómo se mide el rendimiento en Android y resultados
│  ├─ RELEASING.md                         Versionado, firma y publicación
│  ├─ FLAVORS.md                           Las tres variantes (usr, pref, dev): qué lleva cada una y cómo se compila
│  ├─ TELEMETRIA.md                        Qué envía la telemetría opcional, para qué y cómo se retira
│  ├─ adr/                                 Decisiones de arquitectura (0001: cuenta, telemetría y actualizaciones)
│  ├─ SEGURIDAD.md                         Revisión de seguridad y privacidad: datos, arreglos y lo que queda
│  ├─ RUNBOOK-INCIDENTES.md                Qué hacer en un incidente: niveles, pánico, comunicar, recuperar, lote y clave
│  ├─ AVISOS-ALCANCE.md                    Discord frente a FCM/APNs para avisos y kill switch (Fase 4.2)
│  ├─ contexto.md                          Relevo entre sesiones: dónde estamos, bloqueos y siguiente paso
│  ├─ plan.md                              Prompt maestro de Toxbox, orden actual y reglas de pruebas
│  ├─ pendiente-decision.md                Preguntas abiertas del plan con propuestas
│  ├─ publicar/                            Para hacer público el código: análisis legal, LICENSE (GPL-3.0), README, SECURITY, lista
│  ├─ RELEVO-0.9.2.md                      Relevo de la otra sesión (se publicó como Android 0.9.4)
│  ├─ SIGUIENTE-SESION.md                  Prompt para retomar: contexto, reglas, revisión con skills y pruebas por cable
│  ├─ futuro.md                            Lo que falta: pruebas con cable, tests, bloqueos (skills, CI) y funciones pendientes
│  └─ pruebas/                             Capturas y mediciones de cada fase (faseN, v0.8.1-*)
└─ .github/workflows/
   ├─ ios.yml                              .ipa sin firmar y capturas del simulador (macOS; sólo master/monorepo, versiones o a mano)
   ├─ ios-sintaxis.yml                     Sintaxis de Swift en Linux en cualquier rama (barato)
   ├─ android.yml                          Tests, capturas de pantalla y APK (Linux)
   └─ release.yml                          GitHub Release al crear ios-v* / android-v*
```

La web de descarga vive en otro repo: `ToxBox8/libremusic-landing`, publicada en el Worker `pearmusic-by-toxbox`
(https://pearmusic-by-toxbox.8toxbox8-69a.workers.dev desde el 15-10-2026). La dirección antigua
(`libremusic-landing.8toxbox8-69a.workers.dev`) la ocupa `services/web-antigua`, que lo redirige todo a la nueva.

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
| Variante (`Channel`), registro (`Logs`), exportar y borrar datos (`UserData`), cifrado local (`SecureBox`); pantallas Tus datos y Administración | `UserData.swift`, `DataViews.swift` |
| Cuenta opcional y biblioteca cifrada; `AccountPitch` | `Account.swift`, `AccountView.swift` |
| Bienvenida (en `AppSettings.swift`), recorrido, historias y primeros pasos | `Intro.swift` |
| Telemetría, aviso de versión nueva, filtro local del soporte, ficha del dispositivo e instalaciones activas | `Telemetry.swift`, `Updates.swift`, `SupportFilter.swift`, `Ficha.swift` |
| Importar de Apple Music; `Matcher` (emparejado con confianza) | `AppleMusic.swift` |
| Importar de Spotify (enlace y CSV de Exportify) y SimpMusic (`.backup`), emparejado de listas e importaciones a medias | `ExternalImport.swift` |
| Modo de capturas (`-screenshotScenario`) | `Screenshots.swift` |
| Avisos (campana de Inicio, pantalla, `BGAppRefreshTask` y notificaciones) | `Avisos.swift` |

## Android (`apps/android/app/src/main/java/app/libremusic`)

| Carpeta | Contenido | Equivale en iOS a |
|---|---|---|
| `ui/LibreMusicApp.kt`, `ui/Nav.kt`, `ui/TabPager.kt` | Raíz, pestañas, pilas de navegación, hojas, avisos; `TabPager`: deslizar entre pestañas (sigue al dedo, muelle con la velocidad, las barras lo siguen) | `LibreMusicApp.swift` |
| `ui/Home.kt` | Inicio, búsqueda, álbumes | `HomeView.swift` |
| `ui/Search.kt` | Resultados de búsqueda y página de artista | `SearchViews.swift` |
| `ui/Library.kt`, `ui/Songs.kt`, `ui/Stats.kt` | Biblioteca 1.1, filas de canción, editor, importar, estadísticas | `LibraryV11.swift`, `LibraryViews.swift` |
| `ui/Player.kt`, `ui/LyricsView.kt`, `ui/Decks.kt`, `ui/AirPlayer.kt` | Reproductor, letra, casete, vinilo, Air | `LibreMusicApp.swift`, `Deck.swift`, `Kitchen.swift`, `AirPlayer.swift` |
| `ui/SettingsScreens.kt`, `ui/Onboarding.kt`, `ui/Support.kt` | Ajustes y formularios; guía inicial; informar de un error | `AppSettings.swift`, `Settings.swift`, `Support.swift` |
| `I18n.kt`, `ui/LanguagePicker.kt` | Idiomas: `L()`, idioma elegido y selector con banderas | `I18n.swift`, `LanguagePicker.swift` |
| `ui/DataScreens.kt`, `data/UserData.kt`, `data/Logs.kt`, `data/SecureBox.kt` | Tus datos (exportar .zip, borrar todo, telemetría), Administración (sólo dev), registro sin datos personales, cifrado local | `DataViews.swift`, `UserData.swift` |
| `data/Account.kt`, `ui/AccountScreens.kt` | Cuenta opcional, biblioteca cifrada y `AccountPitch` | `Account.swift`, `AccountView.swift` |
| `ui/Onboarding.kt`, `ui/Tour.kt`, `ui/Stories.kt`, `ui/FirstSteps.kt` | Bienvenida, recorrido sobre la app, historias y primeros pasos | `AppSettings.swift` (`OnboardingView`), `Intro.swift` |
| `data/Discography.kt`, `ui/Search.kt` (`DiscographyScreen`) | Discografía completa (YouTube Music + MusicBrainz) | `Discography.swift`, `SearchViews.swift` (`DiscographyView`) |
| `playback/Widgets.kt`, `playback/NowPlayingWidget.kt`, `ui/PersonalizationScreen.kt` | Widgets (Ahora suena pequeño y grande, accesos rápidos, playlist fijada, recientes) y Ajustes › Widgets | — (iOS aún sin widgets) |
| `data/Incident.kt` (`Incident`, `Panic`) | Estado firmado (kill switch, niveles 0–3) y botón de pánico de Pear Dev | `Incident.swift` |
| `data/Telemetry.kt`, `data/PanelKey.kt`, `data/Updates.kt`, `data/SupportFilter.kt`, `data/Ficha.kt` | Telemetría con consentimiento (resumen semanal; `PanelKey`: llave del panel por USB, sólo dev), aviso de versión nueva (APK verificado), filtro local del soporte | `Telemetry.swift`, `Updates.swift`, `SupportFilter.swift` |
| `ui/Kitchen.kt` | Componentes comunes | `Kitchen.swift`, `Images.swift` |
| `avisos/`, `ui/Avisos.kt` | Avisos de Pear Music (canal privado de Discord → `/api/avisos` de la web): `AvisosRepo` (descarga, copia guardada, vistos, regla de 48 h sin repetir), `AvisosWorker` (WorkManager cada 15 min, notificaciones), campana `AvisosBell` en Inicio y pantalla `AvisosScreen` | `Avisos.swift` |
| `ui/simpbar/` | Barra inferior estilo SimpMusic (opción `barStyle`), copiada de Open Menus: vidrio de Kyant, gota arrastrable, Buscar aparte, plegado 2.2.0 | Barra de pestañas de iOS 26 (`tabBarMinimizeBehavior`) |
| `ui/Glass.kt` | Cristal líquido opcional (capa grabada + desenfoque + shader AGSL de refracción, gota de la barra de pestañas, pulsación con rebote) | El cristal de iOS 26 lo da el sistema |
| `ui/theme/` | `Theme.kt` (temas y Prefs), `Backdrops.kt`, `Type.kt` (Inter), `SfIcons.kt`, `Tokens.kt` (**generado**) | `Theme.swift`, `Backdrops.swift` |
| `ui/*ViewModel.kt` | Estado de reproductor, biblioteca e inicio | objetos `@EnvironmentObject` |
| `playback/` | `PlaybackService` (Media3), `Tracks.kt` (resuelve el audio), `BrowseTree` (Android Auto), `SleepTimer` (temporizador para dormir), `Fade.kt` (fundido entre canciones y `VolumeMix`), `Eq.kt` (ecualizador, sólo Android), `AutoRadio` (radio infinita), `AudioTuning.kt` (búfer de audio, `Prefetch` de las siguientes URLs, `Normalizer`: igualar el volumen), `PlayCounter` (cuenta escuchas), `NowPlayingWidget` (widget de la pantalla de inicio), `LastQueue` (última cola para retomar con la app cerrada) | `Player.swift` |
| `data/` | `YTClient`, `Song`, `Library` (library.json), `AppleMusic.kt` (y `Matcher`), `ExternalImport.kt` (Spotify, Exportify, SimpMusic, `ImportMatcher`, `ImportJob`), `TabOrder`, `Support` (borradores y envío), `AppIcon` (migra el antiguo icono violeta), `Lyrics` (letras de LRCLIB), `PlayStats` (estadísticas, `stats.json`), `AutoBackup` (copia diaria a una carpeta), `Releases` (novedades de tus artistas), `PendingImports` («Sin añadir» de las importaciones), `AppShortcuts` (atajos del icono) | `Client.swift`, `Store.swift`, `AppleMusic.swift` |
| `download/` | Descargas con Media3 DownloadManager | `DownloadStore` en `Store.swift` |
| `reels/`, `jam/` | Descubrir y Jam | `Reels.swift`, `Jam*.swift` |

Tests en `app/src/test`: lógica (YTClient, `Matcher`, descargas, Jam, biblioteca, reels) y `ui/ScreenshotTest.kt` (capturas de pantalla en vertical; `LandscapeShotTest`, los reproductores y el inicio en horizontal, `h*.png`; `LargeTextShotTest`, letra al 150 %, `t*.png`; `WidgetShotTest`, el widget, `w1_widget.png`).

## Cómo trabajar

- **Compilar:** no hace falta Mac. Cada push que toca `apps/android` lanza su workflow; el de iOS en macOS sólo se lanza solo en `master`/`monorepo` (los minutos de macOS cuentan ×10), en las versiones o a mano, y en las demás ramas `ios-sintaxis.yml` comprueba la sintaxis en Linux. El .ipa y el APK salen como artefactos.
- **Errores de Android:** la CI los publica como anotaciones: `gh api repos/ToxBox8/libremusic/check-runs/<job>/annotations`.
- **Capturas:** `ScreenshotTest` (Android) dibuja 26 pantallas con el tamaño y los márgenes seguros del iPhone 16 y la CI las sube a la rama `screenshots`; `ios.yml` hace en el simulador (`-screenshotScenario`) las 15 primeras y las sube a `screenshots-ios` (de la 16 a la 22 —Tus álbumes, Aspecto, colores, pestañas, guía, informar de un error, icono— aún no tienen escenario en iOS). `python3 shared/design/compare_shots.py --out /tmp/paridad` genera la hoja iOS | Android. Antes de integrar un cambio de interfaz, compara y deja `docs/PARIDAD.md` al día.
- **Android en local (opcional):** con Gradle 9.4.0, JDK 21 y el SDK de Android, `gradle testUsrDebugUnitTest --tests '*ScreenshotTest'` deja las capturas en `app/build/shots/` en un par de minutos.
- **Probar en un móvil Android:** `gradle assembleUsrDebug` instala `app.libremusic.debug` (o `scripts/variante.sh dev|pref`) al lado de la app normal; los cierres se leen con `adb logcat -b crash -d`. Para medir fluidez, la variante `perf` y `scripts/bench.sh` (ver `docs/RENDIMIENTO.md`); compara con la tabla antes de integrar cambios que afecten a la fluidez.
- **Compilar iOS sin gastar cuota:** el repo privado se queda sin minutos de macOS; el público `ToxBox8/pear-music` los tiene gratis. Rama `ios-compila` con sólo `apps/ios` (commit con `ToxBox8@users.noreply.github.com`, nunca el historial de este repo) y `gh workflow run ios.yml -R ToxBox8/pear-music --ref ios-compila`; pasos en `docs/contexto.md`.
- **Errores de iOS:** también salen como anotaciones (los dos `xcodebuild` de `ios.yml`). Sin Mac ni CI, `apps/ios/scripts/check-linux.sh` comprueba al menos la sintaxis con Swift para Linux (los tipos de SwiftUI no, porque sólo existen en Apple).
- **Diseño:** nunca escribas colores, radios o tamaños de marca a mano. Cámbialos en `shared/design/tokens.json` y ejecuta `python3 shared/design/gen_tokens.py`. La CI falla si `Tokens.swift` o `Tokens.kt` no están al día.
- **Icono:** uno solo, `AppIcon-Encendido.svg` (en Android, vector `drawable/ic_launcher_power.xml`; en iOS, `AppIcon.appiconset`). `render_icon.py` copia su PNG a iOS y al logo de Acerca de, y dibuja el logo antiguo (`AppIcon.svg`, violeta) sólo para la historia de la marca del README y la web. No se vuelven a añadir iconos alternativos en las apps.
- **Variantes:** usr (pública), pref y dev (sólo el móvil de Toxbox, por adb; nunca se publican). Todo en `docs/FLAVORS.md`; las diferencias van por banderas (`BuildConfig.CHANNEL`/`ADMIN_TOOLS`/`VERBOSE_LOGS`, `Channel` en iOS), nunca con código duplicado. Registra con `Logs`, nunca con `Log`/`print`, y sin datos personales.
- **Ramas:** `monorepo` es la rama de trabajo; usa ramas propias para cambios grandes y no integres sin la CI en verde.
- **Versiones:** sube la versión y anota el cambio en `CHANGELOG.md` en el mismo commit (ver `docs/RELEASING.md`).
- **Decisiones:** cuando se tome una decisión de producto o de diseño, añádela con fecha a `DECISIONS.md`.

## Convenciones

- **Idiomas:** todo texto visible va dentro de `L("…")` (Kotlin y Swift; `{0}` para datos, nunca concatenar frases). Tras añadir textos: `python3 tools/i18n/extraer.py`, traducir las líneas nuevas del final de `shared/i18n/src/orden.txt` en cada `<idioma>.txt` y `python3 tools/i18n/construir.py`. No uses `L()` para claves, nombres de recursos, cabeceras HTTP ni atajos de Siri (App Intents exige literales).

- Textos de la interfaz, comentarios y mensajes de commit **en español**.
- Textos de iOS con icono (`Label(…, systemImage:)`): el extractor salta esas líneas, así que se escriben ya con `L("…")`.
- Mismos nombres de ajustes en las dos apps (`theme`, `appearance`, `deck`, `searchPlacement`, `playlistSort`, `playlistOrder`, `smartPlacement`, `artworkColorsPlayer`, `artworkColorsApp`, `artworkIntensity`, `artworkOpacity`, `tabOrder`, `lastTab`, `onboarded`, `repeatMode`, `matchTolerance`, `crossfade`, `autoplay`, `scramble`, `quality`; `barStyle`, `barRestoreIdle`, `showDiscover`; `liquidGlass`, `equalizer` y, por ahora, `normalize` sólo en Android), mismo `library.json` y mismo protocolo del Jam.
- Animaciones con la curva «ui ease out» `cubic-bezier(0.23, 1, 0.32, 1)` y respeto a «Reducir movimiento».
- Botones de al menos 44 pt/dp de área táctil y textos que crecen con el tamaño de letra del sistema.
- Los commits terminan con las líneas de coautoría de Claude cuando los hace Claude.
