# CONTEXT.md

Qué es LibreMusic, para qué sirve y cómo funciona. Para la organización del código, ver [`AGENTS.md`](AGENTS.md); para el historial de decisiones, [`DECISIONS.md`](DECISIONS.md).

## Qué es

**Pear Music** (hasta octubre de 2026, LibreMusic; el código y los identificadores siguen usando `libremusic`) es un **cliente de música libre y sin anuncios** para iPhone y Android que reproduce el catálogo de **YouTube Music** sin cuenta, sin publicidad y con reproducción en segundo plano y descargas.

Es un cliente **no oficial**: no está afiliado a YouTube ni a Google, usa una API no oficial (InnerTube) que puede dejar de funcionar, y **no se distribuye en la App Store ni en Google Play**:

- **iOS:** `.ipa` sin firmar que cada usuario instala con AltStore, SideStore o Sideloadly.
- **Android:** APK firmado, desde la web, GitHub Releases u Obtainium.

La web de descarga es `ToxBox8/libremusic-landing`.

## Para qué sirve

- Escuchar cualquier canción de YouTube Music gratis, sin anuncios y con la pantalla apagada.
- Guardar favoritos y playlists propias, y descargar canciones para escucharlas sin conexión.
- Descubrir música nueva en un feed de fragmentos (como los reels).
- Hacer una playlist entre varias personas que están juntas (Jam), entre iPhone y Android.
- Traerse playlists de Apple Music.
- Personalizar el aspecto con temas y reproductores con personalidad (casete, vinilo, Air).

## Pantallas

| Pestaña | Qué hay |
|---|---|
| **Inicio** | Saludo según la hora, buscador arriba (o pestaña aparte), «Escuchado recientemente», «Para ti» (radio de lo último que escuchaste), «Novedades de tus artistas» (lanzamientos de este año de los 8 artistas que más escuchas), tus playlists y las estanterías de YouTube Music. Los álbumes y playlists públicas se abren y se pueden guardar en la biblioteca. |
| **Descubrir** | Feed vertical a pantalla completa. Cada canción suena 30 s desde la zona del estribillo, en bucle. Desliza para la siguiente, doble toque para «Me gusta», y «Escuchar completa» la pasa al reproductor. Sale de las radios de tus favoritas y recientes. |
| **Biblioteca** | Carrusel de playlists con Descargadas y Favoritos (o, si se elige, como filas en «Tu música»), ordenado por recientes, nombre A-Z/Z-A, tamaño o a mano; debajo, en «Tu música», Tus álbumes (los guardados o descargados desde su página, en cuadrícula con buscador), Canciones, Artistas, Recientes y Estadísticas (lo más escuchado este mes, este año o siempre, en `stats.json`, sólo en el móvil). Cada lista tiene un anillo de puntos con lo descargado, filtros, «Descargar todo» y un editor (nombre, foto, icono y color). |
| **Ajustes** | Buscador arriba y cinco secciones con su valor debajo: Aspecto (tema, reproductor, colores de la portada con presets y barras, orden de pestañas y, sólo en Android, cristal líquido), Reproducción (calidad, seguir con canciones parecidas, ecualizador —sólo Android—, fundido entre canciones, AirPlay/salida), Descargas (canciones, espacio, borrar), Biblioteca (orden de playlists, Descargadas/Favoritos, dónde va Buscar, copia automática, eliminar playlists) y Ayuda y soporte (avisos, informar de un error, guía inicial, Tus datos —exportar todo en un .zip o borrarlo todo— y Acerca de); Avanzado plegado. «Restablecer» por sección. El escarabajo de arriba a la derecha abre «Informar de un error»: correo, texto y hasta 4 capturas que llegan a un canal privado de Discord a través de un Worker de Cloudflare (`services/soporte`), con borradores. |

La barra inferior puede ser la clásica o **estilo SimpMusic** (Ajustes › Aspecto › Barra inferior): cápsula con las pestañas y una gota que se arrastra, Buscar en un círculo aparte (Inicio no lleva buscador) y al bajar por una lista se pliega en un círculo junto al mini reproductor. **Ajustes** puede ir en la barra o arriba en Inicio junto al Jam (Aspecto › Ajustes; por defecto en la barra con la clásica y arriba con la estilo SimpMusic). Deslizar a los lados cambia de pestaña siguiendo al dedo, y la barra se mueve a la vez.

**Avisos:** la campana de Inicio (junto al Jam, con un número de no leídos) abre los avisos de Pear Music, los mismos que la web en `/avisos`. Salen de un canal privado de Discord (el bot del Worker de la web los lee), se bajan cada vez que se abre la app y, con «Notificar en el móvil», llegan como notificación: sólo los de las últimas 48 h y una vez cada uno (Android cada 15 min; iOS cuando el sistema deja). También en Ajustes › Ayuda y soporte › Avisos.

Las pestañas se ordenan en Ajustes › Aspecto › Pestañas (por defecto Descubrir, Inicio, Biblioteca, Ajustes) y la app se abre en la última usada. La primera vez sale la **bienvenida**: bienvenida, privacidad (condiciones obligatorias y telemetría opcional, por separado y sin marcar; la cuenta, opcional), tema, colores y descargas; después un recorrido sobre la app real (foco sobre cada sección), unas historias a pantalla completa y la tarjeta «Primeros pasos» en Inicio. Quien ya tenía la app sólo ve la privacidad, una vez.

**Fase 3:** la página de un artista tiene «Ver todo» con su discografía completa (YouTube Music y, atenuado, lo que sólo conoce MusicBrainz); tocar un artista en Tu música › Artistas (A-Z/Z-A) o en la cabecera de un álbum abre su perfil. Descubrir se puede quitar (Aspecto › Pestañas). Los álbumes y playlists se pueden **fijar** arriba en Biblioteca e Inicio. En Android hay cinco widgets (Ahora suena pequeño y grande, Accesos rápidos, Playlist fijada y Recientes) que se configuran en **Ajustes › Widgets**.

**Cuenta (opcional):** Ajustes › Cuenta. Entrar con un código al correo; la biblioteca se guarda en la nube cifrada con una clave de recuperación que sólo tiene el usuario (`services/api`, aún sin desplegar). **Versión nueva:** al abrir, como mucho cada 6 h, la app lee `version.json` de la web y ofrece «Descargar» (Android: APK verificado, con el progreso en el aviso, e instalado encima con un toque en el
instalador del sistema; iOS: AltStore/SideStore) o «Recordarme mañana».

**Incidentes (Fase 4):** al abrirse (y en Android cada 15 min) la app lee un estado firmado con Ed25519 del Worker `pear-music-estado` (`services/estado`): 0 normal, 1 aviso (banner 24 h), 2 modo seguro (sin actualizaciones salvo las marcadas como arreglo, sin búsqueda remota, soporte, telemetría ni cuenta; la música descargada sigue), 3 mantenimiento. Falla en abierto. Se cambia desde Pear Dev o `/panico` en Discord con contraseña + TOTP; la clave privada sólo está en el PC de Toxbox. Qué hacer: `docs/RUNBOOK-INCIDENTES.md`.

**Idiomas (Cierre 1.0):** español, català, valencià, galego, euskara, English y Esperanto (bienvenida y Ajustes › Idioma, con banderas). Los textos van en español dentro de `L("…")` y el catálogo común está en `shared/i18n/` (`tools/i18n/`).

**Tickets y sugerencias:** cada reporte o sugerencia (Ayuda y soporte › Buzón de sugerencias, o la carta de Ajustes) tiene número; Toxbox contesta desde Discord con `/msg` y la respuesta sale sólo a esa persona en la campana (`services/soporte`).

**Telemetría (Fase 4b):** con consentimiento, un resumen por semana a `pear-music-api` (desplegado el 14-10, sin correo). Pear Dev no envía sola: sólo «Enviar ahora», eligiendo campos, y dar una llave por USB para el panel escondido de la web (`/panel-t`), que sin el móvil de Toxbox conectado no existe (`docs/TELEMETRIA.md`).

Sobre las pestañas flota el **mini reproductor**: tocarlo abre el reproductor y mantenerlo pulsado deja elegir el tipo de reproductor.

### Reproductores

- **Normal:** carátula, título con «⋯» (menú de canción) y la luna del temporizador para dormir (5–90 min con bajada de volumen, o al acabar la canción), progreso, controles, favorito, descarga, salida de audio, bucle (no / lista / canción) y cola. El botón de la cola cambia la carátula por un panel «Cola | Letra»; la letra (de LRCLIB) se sincroniza con la canción y se guarda para verla sin conexión. En la cola, mantener pulsada una fila abre el menú de canción.
- **Casete:** réplica del «Cassette Audio Player» de The Kitchen (dqnamo). Las bobinas se giran con el dedo para avanzar o rebobinar.
- **Vinilo:** tocadiscos a 33⅓ con la carátula como galleta. Se puede «scratchear» el disco o mover el brazo.
- **Air:** inspirado en Air OS de Geex Arts. Papel plateado, anillo de puntos del progreso, selector holográfico, rueda del iPod, velocidad y salida de audio.

Con el móvil en horizontal, el casete y el vinilo ocupan toda la pantalla.

### Temas

Cuatro temas, en las dos apps:

| Tema | Aspecto |
|---|---|
| **Cristal** (por defecto) | Luz difusa con los colores de la carátula; respeta claro/oscuro. |
| **Aire** | Plata con grotesco negro; siempre claro. |
| **Neón** | Rejilla synthwave; siempre oscuro. |
| **Sistema** | Sin efectos. |

La marca es violeta `#8B5CF6`. El icono, en las dos apps y en la web, es el de encendido (lila `#A78BFA` sobre `#07070A`). El violeta con nota y bobina es el logo antiguo de LibreMusic: ya no va en las apps, sólo en el README y la web como evolución de la marca.

### Variantes

Del mismo código salen tres apps (`docs/FLAVORS.md`): **Pear Music** (usr, la pública), **Pear Pref** (la de Toxbox) y **Pear Dev** (pruebas, con Ajustes › Ayuda y soporte › Administración: canal, registro y botón de pánico). Pref y Dev sólo se instalan en el móvil de Toxbox y nunca se publican.

## Cómo funciona

### Música (YouTube Music / InnerTube)

- Búsqueda, sugerencias, inicio (`FEmusic_home`), álbumes y playlists públicas, y radios (`next` con `RDAMVM<id>`) con el cliente web `WEB_REMIX`, sin sesión.
- El audio se pide con el cliente `VISIONOS`, el único que hoy (2026-10) da URLs directas sin «PO token». Android elige Opus (~160 kbps) y, si no hay, AAC; iOS, el AAC de más calidad (AVPlayer no reproduce Opus). Con «Ahorro de datos», el de menos. Si YouTube no deja reproducir esa subida (sobre todo contenido «para niños»), se busca otra subida de la misma canción y se recuerda mientras la app está abierta.
- El `visitorData` se guarda, porque sin él YouTube responde «confirma que no eres un bot».
- Las URLs caducan (unas 6 h); Android las cachea 3 h.

### Reproducción

- **iOS:** AVPlayer + AVAudioSession, con Ahora suena, controles de la pantalla de bloqueo y AirPlay.
- **Android:** Media3 ExoPlayer en un `MediaLibraryService` con notificación multimedia y Android Auto (Favoritas, Descargadas, Recientes y Playlists). Las canciones se identifican como `libremusic://track/<videoId>` y se resuelven a la URL real justo antes de sonar.
- Atajos: en Android, al mantener pulsado el icono (mezclar favoritas o descargadas, Descubrir, Buscar); en iOS, los mismos como atajos de Siri (App Intents).
- Android tiene un widget «Ahora suena» (4×1) que actualiza el servicio y manda teclas multimedia; con la app cerrada enseña la última canción y «reproducir» retoma la última cola (`LastQueue`, `onPlaybackResumption`). iOS aún no tiene widget.
- Android prepara la URL de las dos siguientes canciones mientras suena la actual (sin silencios entre canciones), guarda hasta 2 min por delante y iguala el volumen entre canciones con la sonoridad de YouTube (`normalize`).
- Una canción suelta completa la cola con su radio, y al empezar la última canción de la cola (bucle apagado) se añaden 20 parecidas (radio infinita, ajuste `autoplay`).

### Biblioteca y descargas

- La biblioteca (favoritos, playlists, recientes) se guarda en `library.json` con el **mismo formato en las dos apps** (`docs/LIBRARY_FORMAT.md`). Se puede exportar e importar, y copiar sola una vez al día a una carpeta (`PearMusic-copia-AAAA-MM-DD.json`, las 7 últimas).
- Las fotos de portada van en `covers/<id>.jpg`, reducidas a 700 px.
- **iOS** descarga `.m4a` a `Documents/Downloads`. **Android** usa el DownloadManager de Media3 con la caché indexada por videoId.
- Las descargas siempre usan la máxima calidad.

### Jam

- Playlist compartida en la misma red con un código de 6 caracteres o un QR (`libremusic://jam/CÓDIGO`).
- Protocolo **v2** abierto: el anfitrión anuncia `_lm-jam2._tcp` por Bonjour/NSD con el código en el TXT, y los invitados se conectan por TCP con JSON por líneas. Hasta 16 personas.
- iOS mantiene además la v1 (MultipeerConnectivity) entre iPhones.
- Especificación completa en `docs/JAM_PROTOCOL.md`.

### Importar playlists

- **Spotify por enlace** (las dos apps): la página de inserción pública trae título, artistas, duración y si es explícita (hasta ~100 canciones). **CSV de Exportify**: todas las canciones, con álbum e ISRC.
- **SimpMusic**: su copia `.backup` (ZIP con su base SQLite); las canciones ya son de YouTube Music y llegan exactas. Se eligen qué playlists traer.
- Lo que no viene de YouTube Music se empareja (ISRC primero; título, versión, artista, álbum y duración con tolerancia configurable) y se clasifica en bien / para revisar / no encontrada; lo dudoso se elige a mano entre candidatos. Se puede continuar una importación cortada. Las que no se añaden quedan en la playlist como «Sin añadir» (`import_pending.json`) para volver a buscarlas. Importar nunca descarga.

### Importar de Apple Music

- **Por enlace público** (las dos apps): se lee el JSON de la página y cada pista se busca en YouTube Music, 4 a la vez. Entre los resultados se elige el de más puntos (`Matcher`): título, etiquetas de versión, artista, álbum y duración; si ninguno encaja, la pista se salta.
- **Desde la app Música del iPhone** (sólo iOS).
- **Copia de la biblioteca** (las dos apps): «Importar copia» y «Exportar copia» de `library.json` en la misma hoja. Importar une sin borrar.

### Diseño compartido

- `shared/design/tokens.json` genera los colores, temas, radios y tamaños de las dos apps.
- iOS usa SF Pro y SF Symbols; Android usa Inter e iconos Material redondeados, porque las fuentes e iconos de Apple sólo se pueden usar en sus sistemas.

## Estado

| App | Versión | Estado |
|---|---|---|
| iOS | 1.4.1 (publicada) | Referencia de diseño. Publicada el 14-10 desde el repo público (`ToxBox8/pear-music`, release `ios-v1.4.1`, compilada por su CI), en la web y en la fuente de AltStore. Falta probarla en un iPhone. |
| Android | 0.9.5 (publicada) | Misma interfaz que iOS (`docs/PARIDAD.md`). Publicada el 14-10 en GitHub Releases (`android-v0.9.5`; por la tarde, tras la 0.9.4 de la mañana; firmada en local con la clave de siempre) y en la web. Probada en un Nothing Phone (2) con Android 16 (`docs/pruebas/v0.9.0-manual`). |

Pendientes y fases en `docs/ARCHITECTURE.md` y `CHANGELOG.md`.

### Prompt maestro (2026-10-13, Toxbox) — Android 0.8.1 / iOS 1.4.0

Toxbox mandó un prompt maestro (copiado en `docs/plan.md`) y aceptó las propuestas de `docs/pendiente-decision.md`. Todas las fases están hechas en las dos apps; lo publicado es Android 0.8.1. Estado del relevo entre sesiones en `docs/contexto.md`; pruebas en `docs/pruebas/`.

| Fase | Qué | Estado |
|---|---|---|
| 1 | Menú de canción que fallaba con música (Android) y menú también en el reproductor («⋯») y en la cola | Hecho; el arreglo, medido en el móvil (12/12) |
| 2 | Bucle de tres estados, en la fila de controles del reproductor, notificación y pantalla de bloqueo | Hecho; probado en el móvil |
| 2A | Buscar artistas y álbumes, página de artista, descargar álbumes; Pausar / Reanudar / Cancelar en «Descargar todo» | Hecho |
| 2B | Buscador local (`LocalSearch`) en Playlists, Artistas y Tus álbumes | Hecho |
| 2C | «Tus álbumes» en Tu música (álbumes guardados o descargados desde su página) | Hecho |
| 3 | Orden de pestañas; la app se abre en la última usada | Hecho |
| 4 | Ajustes por intención, buscador, Restablecer, guía inicial | Hecho |
| 4B | Colores de la portada con presets y dos barras, contraste garantizado | Hecho |
| 4C | Informar de un error → Worker de Cloudflare → Discord | Hecho y desplegado (13-10); reportes en el servidor privado «Pear Music · soporte» |
| 2D | Importar de Spotify (enlace o CSV de Exportify) y SimpMusic; emparejado con revisión | Hecho; prueba real 20/20 |
| 5 | Icono original de encendido por defecto, icono elegible, versión y release | Android 0.8.1 publicado; iOS 1.4.0 espera a la CI |

Pendiente de probar: en el móvil, todo lo de después del bucle (se desconectó a las 07:43 del 13-10); iOS entero desde «Tus álbumes» (la CI de GitHub no arranca: cuota agotada).

### Plan 0.8.0 anterior (rama `plan-0.8.0`, sustituido por el prompt maestro)

Plan de 13 fases de Toxbox (bugs, navegación, paridad, reproductor, biblioteca, orden de pestañas, Ajustes, colores de portada, previsualizaciones, álbumes, importar de Spotify/SimpMusic, soporte y versión). Muchas cosas de las fases 1–6 ya se hicieron el 2026-10-12; en cada fase se comprueba en el móvil y sólo se toca lo que sigue fallando.

**Fase 1 (bugs de datos y estabilidad) — hecha**
- Hecho: arreglo del 403 al reproducir (Android e iOS); barras del sistema ocultas con casete/vinilo en horizontal; barra inferior centrada en horizontal; más área táctil en el mini reproductor.
- Comprobado sin cambios: «Descargar playlist» sólo descarga esa lista y sigue en segundo plano; tema Cristal sin el cuadrado; reproductor Normal y Air en horizontal; vinilo girando.
- Pendiente de validación visual: si el «cuadrado blanco» que vio Toxbox es la tarjeta de cristal detrás de los controles del reproductor (la misma que iOS, `glassCard`).
- Dudas para Toxbox: qué botones le fallan exactamente (los medidos responden siempre); con cristal líquido en modo claro, el mini reproductor y el botón del Jam se ven demasiado transparentes (se mira en la Fase 3).
