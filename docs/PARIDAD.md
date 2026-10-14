# Paridad visual iOS ↔ Android

Comparación de las 15 capturas de `ScreenshotTest` (Android, rama `screenshots`) con las mismas pantallas en el
simulador del iPhone 16 (iOS, rama `screenshots-ios`). Los dos lados usan los mismos datos de ejemplo: 6 canciones,
3 playlists y «Blinding Lights» en pausa en 1:14 de 3:20.

```sh
python3 shared/design/compare_shots.py --out /tmp/paridad   # hoja.png + una vista por pareja con los píxeles distintos
```

## Estado

Sólo quedan diferencias aceptadas (las de `docs/ARCHITECTURE.md`, «Diseño compartido») y desplazamientos de 1–3 pt
que vienen de la letra: Inter tiene otras métricas que SF Pro, así que algunas líneas parten en otro sitio y los
bloques de texto largos miden un poco más o menos.

| Pantalla | Qué cambia | Por qué se acepta |
|---|---|---|
| Todas | Barra de estado (hora, batería) sólo en iOS | La dibuja el sistema; `ScreenshotTest` reserva su hueco (59 pt) |
| Todas | Letra Inter en lugar de SF Pro; algunos textos parten línea en otro sitio | Licencia de SF Pro |
| Todas | Glifos Material en lugar de SF Symbols (mismo tamaño, otro dibujo; p. ej. «Artistas») | Licencia de SF Symbols |
| Barras de pestañas, «Cerrar», hojas | El cristal líquido de iOS 26 refracta el fondo; Android usa un velo translúcido con la misma forma, o su propio cristal líquido si se activa en Aspecto (los botones de dentro de una pantalla no refractan) | Efecto del sistema |
| Deslizar entre pestañas | iOS cambia al soltar; Android enseña la pestaña vecina mientras se arrastra | `TabView` de SwiftUI no deja dibujar la vecina |
| Colores de la portada | Mismos presets, barras y contraste mínimo; el tinte de Android se calcula con HSV y el de iOS con HSB | Cada sistema tiene su espacio de color |
| Icono de la app | Android cambia de `activity-alias` (el lanzador tarda unos segundos y puede quitar el acceso directo); iOS usa iconos alternativos y enseña un aviso del sistema | APIs de cada sistema |
| Ajustes › Aspecto | «Cristal líquido» sólo en Android | El cristal de iOS 26 lo da el sistema |
| 07 Ajustes | «AirPlay» con su selector (iOS) / «Salida de audio» con chevron (Android); versión de la app | AirPlay sólo existe en Apple |
| 09–13 Reproductores | Icono de AirPlay / icono de Cast | AirPlay → salida de audio del sistema |
| 12 Air | Casilla «iPhone» / «Este móvil» | Nombre de la salida de audio de cada sistema |
| 14 Jam | «…en la misma WiFi o con el Bluetooth activado» / «…en la misma WiFi» | iOS también conecta por MultipeerConnectivity (Bluetooth); Android sólo por la red local (protocolo v2) |
| 15 Importar | Sección «Desde la app Música de este iPhone» sólo en iOS; el pie dice «la app Música» / «Apple Music» | MusicKit sólo existe en iOS; cada sistema llama así a la app |
| 15 Importar | «(también el de Android)» / «(también el de iOS)» en el pie de la copia | Cada app nombra a la otra |

## Pendiente en iOS (Android 0.9.4, 2026-10-14)

Hecho primero en Android porque Toxbox lo pidió para probarlo en su móvil; estado en iOS:

| Qué | Android | iOS |
|---|---|---|
| Ajustes arriba o en la barra (Aspecto › Ajustes; `settingsTop.classic` / `settingsTop.simpmusic`) | Hecho | Hecho (falta probarlo en un iPhone) |
| Igualar el volumen (`normalize`) | Hecho (`loudnessDb` de YouTube) | Falta (AVPlayer: `volume` por canción) |
| Resolver por adelantado la siguiente canción | Hecho (`Prefetch`) | Falta comprobar si `Player.swift` ya lo hace |
| Barra que sigue al dedo al deslizar entre pestañas | Hecho (`TabPager`) | No aplica: `TabView` cambia al soltar (diferencia aceptada) |
| Avisos: campana con no leídos, pantalla y notificación (48 h, una vez) | Hecho (WorkManager cada 15 min) | Hecho (`BGAppRefreshTask`, cuando iOS deja; falta probarlo en un iPhone) |

## Revisión del 2026-10-13 (Android 0.8.1 · iOS 1.4.0)

Lo nuevo se hizo igual en las dos apps (mismos textos, ajustes y formatos). Android: tests y capturas Roborazzi
(`ScreenshotTest` 16–22); iOS sin compilar (CI parada), así que la comparación con capturas de iOS queda pendiente.

| Qué | Antes | Ahora |
|---|---|---|
| Bucle | No existía | Botón de tres estados en la fila de controles del reproductor; en Android además en la notificación |
| Menú de canción | No había en el reproductor ni en la cola | «⋯» junto al título y mantener pulsada una fila de la cola |
| Tus álbumes | No existía | Fila en Tu música y cuadrícula con buscador |
| Ajustes | Apariencia / Audio y descargas / Acerca de | Aspecto, Reproducción, Descargas, Biblioteca, Ayuda y soporte, Avanzado; buscador, Restablecer, guía inicial |
| Pestañas | Orden fijo | Ordenables, Descubrir primero, abre en la última usada |
| Soporte | No existía | Escarabajo en Ajustes, formulario con borradores |
| Importar | Apple Music y copia | También Spotify (enlace, CSV) y SimpMusic, con revisión |
| Icono | Violeta | Encendido original por defecto; el violeta, elegible |
| Menú de canción con música (Android) | Fallaba la mitad de las veces | Sale siempre (el gesto ya no se reinicia al redibujar) |
| Casete y vinilo en horizontal (Android) | Barra de estado encima | Sin barras del sistema, como iOS |

## Revisión del 2026-10-12 (iOS 1.3.1 · Android 0.7.1)

Probado en un Nothing Phone (2) con Android 16 y comparado con el código de iOS (sin iPhone conectado; iOS sólo se compila en la CI).

| Qué | Antes | Ahora |
|---|---|---|
| Inicio al bajar | En Android el saludo, el Jam y el buscador se iban con la lista | Como iOS: el saludo se encoge a la barra y el Jam y el buscador quedan fijos |
| Icono del Jam | «Groups» (tres personas) | Dibujo propio igual a `person.2.wave.2` |
| Menú de una canción | Lista sin vista previa; submenús con «Atrás» | Como iOS: fondo desenfocado, la fila elevada, submenús en el sitio; portadas en «Añadir a playlist» (también en iOS) |
| Atrás | Fundido de 420 ms, sin gesto | Animación de UINavigationController que sigue al dedo y gesto atrás del sistema conectado |
| Calidad de streaming (iOS) | Menú desplegable | Dos filas con marca, como Android |
| Descubrir (iOS) | Hora y batería en negro sobre el feed | Modo oscuro mientras está a la vista, como Android |
| Reproductor en horizontal (Android) | Normal sin carátula; Air desbordado | Dos columnas (`LandscapeShotTest`) |
| Orden de playlists | Recientes, nombre, tamaño | También Z-A y a mano (con Descargadas y Favoritos), y opción de mover Descargadas y Favoritos a «Tu música» |

## Diferencias corregidas en la revisión anterior

Todas se arreglaron en Android salvo las marcadas como iOS.

| Pantalla | Qué cambiaba | Dónde se arregla |
|---|---|---|
| Todas | Contenido 59 pt más arriba: Robolectric no tiene barras del sistema | `ScreenshotTest.IPhoneInsets` |
| Todas | Barra de pestañas a 8 pt del borde en vez de 21; iconos pequeños; píldora de selección estrecha | `LibreMusicApp.kt` (`TabBar`) |
| Todas | Mini reproductor de 56 pt en vez de 48; botones con otra separación | `Player.kt` (`MiniPlayerAccessory`), `IconTap(box=)` |
| Todas | Material fino (`.ultraThinMaterial`) casi blanco: los círculos de «+» y de las filas no se veían en Cristal | `Backdrops.kt` (`material`) |
| 05 Sistema | Fondo gris agrupado en la biblioteca (iOS: blanco fuera de los formularios) | `ThemeBackdrop(grouped =)` |
| 01–05 Biblioteca | «+» en negro (iOS: color del tema); «Playlists» 3 pt más bajo; textos «Importar playlist» | `Library.kt` |
| 06, 08 | Barra de navegación de 52 pt (iOS 44) y chevron pequeño; cabecera de la colección 16 pt más arriba | `Nav.kt` (`NavBar`), `CollectionDetail` |
| 01–06 | Glifos de Descargadas/Favoritos más pequeños y sin sombra; iconos de Reproducir/Aleatorio y de descarga pequeños | `SmartCover`, `PillButton`, `DownloadGlyphButton` |
| 07, 08, 15 | Filas de 44 pt (iOS 26: 52, o 58 con icono de color); una tarjeta por sección en vez de una por fila; cabeceras en mayúsculas; título grande y separaciones | `SettingsScreens.kt` (`FormSection`, `FormRow`, `FormCustomRow`), token `radius.formGroup` |
| 08 Temas | Segmentado rectangular y oscuro; vista previa de Aire con las cintas sin desenfocar | `Segmented`, `AirPaper` (desenfoque real de 40 pt) |
| 09, 13 | Controles pegados al título en vez de abajo; pulgar redondo (iOS 26: cápsula); iconos pequeños; sombra de la carátula con un anillo | `PlayerScreen`, `Scrubber`, `Modifier.dropShadow` |
| 10 Casete | Tiempos 1:14 / 3:20 recortados por el interlineado de los textos monoespaciados; casete 7 pt más arriba | `Decks.kt` (`tightLine`), huecos de 14 pt en `PlayerScreen` |
| 11 Vinilo | Glifos de las teclas pequeños | `DeckKey`, START·STOP |
| 12 Air | Cabecera 16 pt más baja; asa que iOS no tiene; reflejo holográfico azul (iOS: rojo-amarillo); borde visible en la carátula desenfocada del disco (bug); iconos de la rueda pequeños | `AirPlayer.kt`, `Sheet` |
| 14 Jam | «Crear Jam» y «Unirme» parecían activos sin nombre (sólo se atenuaba el texto); «Cerrar» sin cápsula | `PillButton`, `tactile(dimWhenDisabled =)`, `ToolbarCapsule` |
| 15 Importar | Botones grandes en vez de `.bordered`; «⚠︎» como icono; asa que iOS no tiene | `CapsuleButton`, `ImportScreen` |
| 15 Importar (iOS) | No tenía «Importar copia / Exportar copia» | `LibraryViews.swift` (`ImportView`), `Store.swift` |
| 15 Importar (iOS) | El marcador «https://music.apple.com/…» salía en azul como un enlace (bug: Markdown) | `LibraryViews.swift` |
