# Arquitectura

Dos apps nativas independientes que comparten **especificaciones**, no código: modelos de datos, protocolo del Jam, formato de exportación de biblioteca y diseño.

## iOS (`apps/ios`)

SwiftUI, proyecto generado con XcodeGen (`project.yml`). Archivos principales en `Sources/`:

| Área | Archivos |
|---|---|
| Datos (YouTube Music / InnerTube) | `Client.swift`, `Auth.swift` |
| Reproducción | `Player.swift`, `AirPlayer.swift` |
| Biblioteca y persistencia | `Store.swift`, `LibraryViews.swift`, `LibraryV11.swift` |
| Descubrir (reels) | `Reels.swift` |
| Jam | `Jam.swift` (v1 MultipeerConnectivity + integración v2), `JamNet.swift` (v2), `JamViews.swift` |
| Temas y UI | `Theme.swift`, `Backdrops.swift`, `Deck.swift`, `Kitchen.swift`, `HomeView.swift`, `Images.swift`, `Settings.swift` |
| Apple Music (importar) | `AppleMusic.swift` |

## Android (`apps/android`)

Kotlin + Jetpack Compose + Media3. Paquete `app.libremusic`. Estructura por capas pensada para modularizar (y, más adelante, compartir lógica con Kotlin Multiplatform):

```
app/src/main/java/app/libremusic/
├─ MainActivity.kt          Entrada, deep links libremusic://
├─ ui/                      Pantallas y tema (Compose)
├─ playback/                PlaybackService (MediaLibraryService + ExoPlayer), BrowseTree (Android Auto), StreamResolver, MediaGraph
├─ reels/                   Descubrir (ReelsViewModel, ReelClip)
├─ jam/                     Jam v2: JamProtocol, JamService (NSD + TCP), JamScreen (código y QR)
├─ data/                    YTClient (InnerTube), Song, Library (favoritos, playlists, recientes)
├─ download/                LibreDownloadService + Downloads (Media3 DownloadManager)
└─ LibreMusicApplication.kt Inicialización
```

## Equivalencias iOS → Android

| iOS | Android |
|---|---|
| AVPlayer + AVAudioSession | Media3 ExoPlayer + AudioAttributes (USAGE_MEDIA) |
| MPNowPlayingInfoCenter / MPRemoteCommandCenter | MediaSession en `MediaSessionService` |
| Descargas .m4a | Media3 DownloadManager |
| Store (favoritos, playlists) | Room + DataStore |
| MultipeerConnectivity (Jam v1) + Network.framework (v2) | Protocolo abierto v2 sobre NsdManager + TCP (`docs/JAM_PROTOCOL.md`) |
| QR | ZXing |
| AirPlay | Google Cast (variante aparte) |
| MusicKit (importar Apple Music) | Enlace público de Apple Music (`AppleMusic.kt`) + copia JSON de la biblioteca |
| AirPlay (selector) | Panel de salida de audio del sistema |

## Diseño compartido

Las dos apps se ven igual. iOS es la referencia y Android la copia pantalla a pantalla.

- `shared/design/tokens.json` es la fuente de colores (marca violeta `#8B5CF6`), temas, radios, tamaños de letra, paletas de playlist y colores de Air. `python3 shared/design/gen_tokens.py` genera `apps/ios/Sources/Tokens.swift` y `apps/android/.../ui/theme/Tokens.kt`; la CI de las dos apps falla si no están al día.
- `shared/design/render_icon.py` dibuja el icono (el mismo diseño que `AppIcon.svg`) y lo exporta a iOS y Android.

### Diferencias aceptadas

Lo único que puede ser distinto entre las dos apps, porque no se puede igualar por licencia o por el sistema. `docs/PARIDAD.md` lo detalla pantalla a pantalla.

| Diferencia | iOS | Android | Motivo |
|---|---|---|---|
| Formato del audio | AAC 128 kbps (HLS o `audio/mp4`) | Opus ~160 kbps (WebM), AAC si no hay | AVPlayer no reproduce WebM/Opus; en Android Opus suena mejor al mismo tamaño |
| Letra | SF Pro | Inter (algún texto parte línea en otro sitio) | SF Pro sólo se puede usar en Apple |
| Iconos | SF Symbols | Material redondeados, al mismo tamaño de glifo (`SfIcons.kt` traduce los de `library.json`) | Licencia de SF Symbols |
| Salida de audio | AirPlay (fila en Ajustes, icono en el reproductor, «iPhone» en Air) | Panel de salida del sistema («Salida de audio», icono de Cast, «Este móvil») | AirPlay sólo existe en Apple |
| Importar | También desde la app Música del iPhone; el pie dice «la app Música» | Sólo por enlace; el pie dice «Apple Music» | MusicKit sólo existe en iOS; cada sistema llama así a la app |
| Jam | «…en la misma WiFi o con el Bluetooth activado» | «…en la misma WiFi» | iOS también conecta por MultipeerConnectivity; Android sólo por red local (protocolo v2) |
| Cristal líquido de iOS 26 | Refracta el fondo (barra de pestañas, botones de barra, hojas) | Por defecto, misma forma con un velo translúcido plano. Con «Cristal líquido» (Ajustes › Aspecto, Android 12+; refracción en 13+) se imita con `Glass.kt`; los botones que están dentro de una pantalla no refractan, sólo brillo y velo | Efecto del sistema; el ajuste sólo existe en Android |
| Deslizar entre pestañas | Cambia al soltar | La pestaña vecina asoma mientras se arrastra | `TabView` de SwiftUI no deja dibujar la vecina |
| Ecualizador (**propuesta**, falta que Toxbox la acepte) | No hay | Ajustes › Reproducción › Ecualizador (5 ajustes hechos) | iOS reproduce HLS con AVPlayer y no deja procesar su audio |
| Widget «Ahora suena» (**pendiente en iOS**) | Aún no (necesita una extensión de WidgetKit y un App Group) | Widget 4×1 (`NowPlayingWidget`) | Se hará en iOS cuando se pueda compilar y probar |
| Barra SimpMusic plegada (**por confirmar** con las capturas 37/38, x.1.1) | Al plegarse quedan la pestaña actual **y la lupa** | Sólo la pestaña actual | iOS 26 deja siempre visible la pestaña con `role: .search` al minimizar; sin ese rol, Buscar dejaría de ser un círculo aparte |
| Aspecto › Barra (x.1.1) | Estilo, Buscar y Pestañas | También «Cristal líquido» | En iOS 26 el cristal lo pone el sistema |
| «Buscar vuelve al parar» (**por confirmar**, x.1.1) | La barra del sistema no se despliega a mano: se cambia a `.never` tras 1,5 s quieta (iOS 18+) | Se despliega la barra propia | `tabBarMinimizeBehavior` no tiene «desplegar ahora» |
| Barras del sistema | Barra de estado de iOS | La de Android (`ScreenshotTest` sólo reserva su hueco) | Las dibuja cada sistema |

### Capturas y comparación

- `ScreenshotTest` (Android) dibuja las pantallas principales con el tamaño y los márgenes seguros de un iPhone 16 y la CI las publica en la rama `screenshots`. iOS hace las mismas capturas en el simulador del iPhone 16 (`-screenshotScenario <nombre>`, ver `Sources/Screenshots.swift` y `scripts/screenshots.sh`) y las publica en `screenshots-ios`.
- `python3 shared/design/compare_shots.py --out <carpeta>` genera la hoja iOS | Android; las diferencias que quedan se apuntan en `docs/PARIDAD.md`.

| iOS (SwiftUI) | Android (Compose) |
|---|---|
| `Theme.swift`, `Backdrops.swift` | `ui/theme/Theme.kt`, `Backdrops.kt`, `Type.kt` |
| `Kitchen.swift` (botón táctil, scramble, mantener para confirmar) | `ui/Kitchen.kt` |
| `LibreMusicApp.swift` (pestañas, mini reproductor, reproductor) | `ui/LibreMusicApp.kt`, `ui/Player.kt`, `ui/Nav.kt` |
| `HomeView.swift` | `ui/Home.kt` |
| `LibraryV11.swift`, `LibraryViews.swift` | `ui/Library.kt`, `ui/Songs.kt` |
| `Deck.swift`, `Kitchen.swift` (casete, vinilo) | `ui/Decks.kt` |
| `AirPlayer.swift` | `ui/AirPlayer.kt` |
| `Settings.swift` | `ui/SettingsScreens.kt` |
| `Reels.swift`, `JamViews.swift` | `reels/ReelsScreen.kt`, `jam/JamScreen.kt` |

## Hoja de ruta Android

| Fase | Contenido | Estado |
|---|---|---|
| 0 | Esqueleto, tema, servicio de reproducción, deep link, CI | Hecho |
| 1 | Búsqueda, reproducción en segundo plano, cola, favoritos (MVP) | Hecho |
| 2 | Descargas, playlists, importar/exportar biblioteca (login opcional: pendiente) | Hecho |
| 3 | Descubrir (reels) | Hecho |
| 4 | Jam v2 multiplataforma (Android 0.5 + iOS 1.2) | Hecho (falta prueba con dispositivos) |
| 5 | Android Auto (hecho), temas (Air, iPod), Cast | En curso |
| 6 | Interfaz igual que iOS 1.3 (0.7) | Hecho |
| 7 | Prompt maestro (0.8.1): álbumes, Ajustes nuevos, pestañas, colores, soporte, importar de Spotify/SimpMusic, icono | Hecho (falta desplegar el Worker de soporte y probar en el móvil) |
