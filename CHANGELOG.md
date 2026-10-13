# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/). Cada app se versiona por separado con [SemVer](https://semver.org/lang/es/) y etiquetas `ios-vX.Y.Z` / `android-vX.Y.Z` (ver `docs/RELEASING.md`).

## iOS

### [1.4.0] — 2026-10-13 (build 6)
- La app se llama ahora **Pear Music**. Es la misma app: se actualiza encima y conserva la biblioteca, las descargas y los ajustes.
- Accesibilidad: con letra grande ya caben todos los botones del reproductor (antes la cola se salía de la pantalla); los interruptores y los botones de reproducción se leen bien con el lector de pantalla.
- Buscar: cada canción de los resultados tiene «⋯» para abrir su menú con un toque (tocar la fila sigue reproduciéndola).
- Atajos de Siri y de la app Atajos: «Mezcla mis favoritas en Pear Music», lo descargado, Descubrir y Buscar.
- Importar: las canciones que no se añaden quedan en la playlist («Sin añadir») para buscarlas otra vez más tarde y elegir la versión buena.
- Inicio: «Novedades de tus artistas», con lo que han sacado este año los artistas que más escuchas.
- Copia automática de la biblioteca (Ajustes › Biblioteca): una al día en la carpeta que elijas (Drive, Nextcloud, iCloud…), guardando las 7 últimas.
- Estadísticas en Tu música: lo que más escuchas y tus artistas este mes, este año o siempre. Se guardan sólo en el móvil.
- Radio infinita: cuando se acaba la cola (con el bucle apagado) siguen canciones parecidas a la última. Se puede apagar en Ajustes › Reproducción.
- Fundido entre canciones (Ajustes › Reproducción): No, 3, 6 o 10 s. La canción baja al final y la siguiente entra suavemente.
- Letras: «Letra» junto a «Cola» en el reproductor (o «Ver letra» en el «⋯»). Si está sincronizada, la línea que suena se resalta y se sigue sola; tocar una línea salta a ese momento. Vienen de LRCLIB (gratis, sin cuenta) y se guardan para verlas sin conexión.
- Temporizador para dormir (la luna junto al título del reproductor): para la música a los 5–90 minutos, bajando el volumen los últimos 12 segundos, o al acabar la canción. Sigue contando con la app cerrada.
- Icono nuevo por defecto: vuelve el original de encendido en lila sobre negro. El violeta sigue disponible en Ajustes › Aspecto › Icono de la app.
- Ajustes reorganizados: Aspecto, Reproducción, Descargas, Biblioteca y Ayuda y soporte, con buscador, el valor de cada opción debajo de su nombre, «Restablecer» por sección y Avanzado plegado.
- Guía inicial de tres pasos (tema, colores y descargas) en instalaciones nuevas; se puede volver a ver en Ayuda y soporte.
- Orden de pestañas a tu gusto (Descubrir primero por defecto); la app se abre en la última pestaña que usaste.
- Colores de la portada con presets Sutil, Equilibrado e Intenso y dos barras (exageración y opacidad); el texto siempre se lee bien.
- Tus álbumes: los álbumes que añades o descargas desde su página, en Tu música, con buscador.
- Informar de un error (el escarabajo de Ajustes): correo, texto y capturas, con borradores.
- Importar de Spotify (enlace público o CSV de Exportify) y de SimpMusic (su copia .backup). Lo dudoso se revisa a mano antes de crear la playlist; tolerancia de duración en Avanzado.
- «Descargar todo» se puede pausar, reanudar y cancelar.
- Menú de canción en el reproductor («⋯») y en la cola (mantener pulsada una fila).
- El bucle está en los controles del reproductor, junto a la AirPlay y la cola.
- Buscador en Playlists y Artistas: filtra mientras se escribe, sin importar mayúsculas ni acentos, con botón para borrar y aviso si no hay coincidencias.
- Buscar enseña artistas, álbumes y canciones en secciones separadas y busca mientras se escribe (no hace falta pulsar Buscar; da igual mayúsculas y acentos). Mensaje claro si no hay resultados.
- Página de artista: canciones más escuchadas, álbumes y singles/EP.
- Los álbumes se pueden descargar enteros (sólo ese álbum) con progreso y «Detener»; con todo descargado, tocar «Disponible sin conexión» ofrece quitar las descargas, con confirmación (también en playlists y Favoritos).
- Bucle de tres estados (no / repetir lista / repetir canción). Se guarda entre sesiones y también se cambia desde la pantalla de bloqueo o CarPlay si el sistema lo muestra.
- Si el audio falla, se pide un identificador de visitante nuevo y se reintenta una vez; además, el identificador caduca a los 3 días. Uno viejo hacía que YouTube diera URLs que luego rechazaba (visto en Android: «Response code: 403» y no sonaba nada).

### [1.3.1] — 2026-10-12 (build 5)
- Importar de Apple Music elige la versión correcta de cada canción: se comparan título, etiquetas de versión (directo, remix, acústica, sped up…), artista, álbum y duración. Antes «Canción (Live)» y «Canción» contaban como iguales y podía colarse otra versión o un karaoke.
- Las canciones que YouTube no deja reproducir sin cuenta se buscan en otra subida de la misma canción (reproducir y descargar). Se quitan los clientes IOS (ya no da audio) y ANDROID_VR (sus URLs fallaban con 403 a los pocos segundos y la canción se cortaba).
- Si no hay alternativa, el error lo explica (suele ser contenido «para niños», que YouTube no sirve sin cuenta).
- Descubrir: la hora, la batería y la cabecera ya no se mezclan con el feed; mientras está abierto, la app pasa a modo oscuro como en Android.
- Audio y descargas: la calidad de streaming son dos filas con marca (Máxima / Ahorro de datos), como en Android, en vez de un menú.
- «Descargar todo» pertenece a su lista: una playlist que comparte canciones con la que se está descargando ya no dice «Descargando… · Detener», y su «Detener» no para la otra.
- Las descargas en bloque piden a iOS unos minutos más al salir de la app y se reanudan solas al volver.
- Deslizar a los lados cambia de pestaña (en todas, también Descubrir). Los carruseles y las filas con «Quitar» tienen prioridad, y dentro de una pantalla abierta deslizar a la derecha sigue siendo «atrás».
- «Añadir a playlist» muestra la portada de cada playlist.
- Reproductor Air: el selector y el anillo de puntos avanzan en cada fotograma, sin tirones cada medio segundo.
- Playlists: ordenar por nombre A-Z o Z-A y «A mano», arrastrando también Descargadas y Favoritos (Biblioteca › ⇅ › A mano, o Ajustes › Apariencia › Biblioteca).
- Opción para mostrar Descargadas y Favoritos con su portada grande en Playlists o como filas en «Tu música».
- «Colores de la carátula» (Ajustes › Apariencia): al sonar una canción, el reproductor (fondo de carátula desenfocada y controles) y/o el resto de la app (acento y un tinte en fondos y menús) toman colores de su portada, encima del tema.

### [1.3.0] — 2026-10-12 (build 4)
- Marca en violeta (#8B5CF6), la misma que la web y Android; icono nuevo en violeta.
- Cuatro temas: Cristal (por defecto, respeta claro/oscuro), Aire, Neón y Sistema. Partículas, Holográfico, Wireframe, ASCII, Malla, Split-flap y Semitono se retiran y pasan a Cristal.
- Una sola biblioteca (la 1.1) y una sola fila de canción en toda la app; fuera el ajuste «Diseño».
- El mini reproductor ya no cambia de reproductor al tocar la carátula: tocar abre el reproductor y mantener pulsado deja elegir.
- La carátula del reproductor ya no cambia al casete al tocarla.
- La cola sólo muestra las asas de mover y borrar con «Editar».
- Los títulos con símbolos aleatorios sólo se animan en el reproductor grande.
- Plurales correctos («1 canción»), favorito con el color del tema, títulos grandes que crecen con el tamaño de texto del sistema.
- Tokens de diseño compartidos con Android (`shared/design/tokens.json` → `Tokens.swift`).
- «Importar copia» y «Exportar copia» de la biblioteca (`library.json`) en la hoja de Importar, como en Android.
- El marcador del enlace de Apple Music ya no sale en azul como un enlace.
- Modo de capturas (`-screenshotScenario`) para comparar con Android en la CI.

### 1.2.0 (build 3) — no se publicó por separado; incluida en 1.3.0
- Jam compatible con Android: protocolo abierto v2 (Bonjour `_lm-jam2._tcp` + TCP, `JamNet.swift`) junto al Jam actual por MultipeerConnectivity. El anfitrión anuncia los dos; al unirse se busca en los dos.
- Hasta 16 personas cuando se une gente por v2.
- Reorganización del repositorio en monorepo (`apps/ios`) y versión declarada en `project.yml`.

### [1.0.0] — 2026-10-11 (build 1)
- Primera versión distribuida desde la web (compilación «air-plata»): biblioteca Nueva 1.1, tema Aire en plata, reproductor Air, Descubrir (reels), Jam con amigos, Buscar en Inicio.

## Android

### [0.9.1] — 2026-10-13 (versionCode 11)
(Incluye todo lo preparado como 0.9.0, que no llegó a publicarse.)
- La app se llama ahora **Pear Music**. Es la misma app: se actualiza encima y conserva la biblioteca, las descargas y los ajustes.
- Accesibilidad: con letra grande ya caben todos los botones del reproductor (antes la cola se salía de la pantalla); los interruptores y los botones de reproducción se leen bien con el lector de pantalla.
- Buscar: cada canción de los resultados tiene «⋯» para abrir su menú con un toque (tocar la fila sigue reproduciéndola).
- Atajos al mantener pulsado el icono: mezclar favoritas, mezclar lo descargado, Descubrir y Buscar.
- Widget «Ahora suena» para la pantalla de inicio (4×1): carátula, título y anterior / reproducir / siguiente. Con la app cerrada sigue enseñando la última canción y «reproducir» la retoma donde se quedó (también desde los auriculares). Sólo en Android por ahora.
- Importar: las canciones que no se añaden quedan en la playlist («Sin añadir») para buscarlas otra vez más tarde y elegir la versión buena.
- Inicio: «Novedades de tus artistas», con lo que han sacado este año los artistas que más escuchas.
- Copia automática de la biblioteca (Ajustes › Biblioteca): una al día en la carpeta que elijas (Drive, Nextcloud, iCloud…), guardando las 7 últimas.
- Estadísticas en Tu música: lo que más escuchas y tus artistas este mes, este año o siempre. Se guardan sólo en el móvil.
- Radio infinita: cuando se acaba la cola (con el bucle apagado) siguen canciones parecidas a la última. Se puede apagar en Ajustes › Reproducción.
- Ecualizador (Ajustes › Reproducción): Más graves, Voces claras, Más agudos y Altavoz pequeño. Sólo en Android.
- Fundido entre canciones (Ajustes › Reproducción): No, 3, 6 o 10 s. La canción baja al final y la siguiente entra suavemente.
- Letras: «Letra» junto a «Cola» en el reproductor (o «Ver letra» en el «⋯»). Si está sincronizada, la línea que suena se resalta y se sigue sola; tocar una línea salta a ese momento. Vienen de LRCLIB (gratis, sin cuenta) y se guardan para verlas sin conexión.
- Temporizador para dormir (la luna junto al título del reproductor): para la música a los 5–90 minutos, bajando el volumen los últimos 12 segundos, o al acabar la canción. Sigue contando con la app cerrada.

### [0.8.1] — 2026-10-13 (versionCode 10)
- Icono nuevo por defecto: vuelve el original de encendido en lila sobre negro. El violeta sigue disponible en Ajustes › Aspecto › Icono de la app.
- Ajustes reorganizados: Aspecto, Reproducción, Descargas, Biblioteca y Ayuda y soporte, con buscador, el valor de cada opción debajo de su nombre, «Restablecer» por sección y Avanzado plegado.
- Guía inicial de tres pasos (tema, colores y descargas) en instalaciones nuevas; se puede volver a ver en Ayuda y soporte.
- Orden de pestañas a tu gusto (Descubrir primero por defecto); la app se abre en la última pestaña que usaste.
- Colores de la portada con presets Sutil, Equilibrado e Intenso y dos barras (exageración y opacidad); el texto siempre se lee bien.
- Tus álbumes: los álbumes que añades o descargas desde su página, en Tu música, con buscador.
- Informar de un error (el escarabajo de Ajustes): correo, texto y capturas, con borradores.
- Importar de Spotify (enlace público o CSV de Exportify) y de SimpMusic (su copia .backup). Lo dudoso se revisa a mano antes de crear la playlist; tolerancia de duración en Avanzado.
- «Descargar todo» se puede pausar, reanudar y cancelar.
- Menú de canción en el reproductor («⋯») y en la cola (mantener pulsada una fila).
- El bucle está en los controles del reproductor, junto a la salida de audio y la cola.

Incluye lo preparado para 0.8.0, que no llegó a publicarse:
- Buscador en Playlists y Artistas: filtra mientras se escribe, sin importar mayúsculas ni acentos, con botón para borrar y aviso si no hay coincidencias.
- Buscar enseña artistas, álbumes y canciones en secciones separadas y busca mientras se escribe (no hace falta pulsar Buscar; da igual mayúsculas y acentos). Mensaje claro si no hay resultados.
- Página de artista: canciones más escuchadas, álbumes y singles/EP.
- Los álbumes se pueden descargar enteros (sólo ese álbum) con progreso y «Detener»; con todo descargado, tocar «Disponible sin conexión» ofrece quitar las descargas, con confirmación (también en playlists y Favoritos).
- Bucle de tres estados (no / repetir lista / repetir canción), igual que iOS, también como botón en la notificación y la pantalla de bloqueo. Se guarda entre sesiones (también si se cambia con la app cerrada).
- El menú de una canción (pulsación larga) ya sale siempre: con música sonando fallaba la mitad de las veces porque el gesto se reiniciaba en cada redibujado de la pantalla. Afecta a todos los botones y filas con pulsación larga (Inicio, Buscar, Biblioteca, playlists, Jam, mini reproductor).
- Descubrir: un toque o doble toque justo cuando empieza a sonar el fragmento ya no se pierde.
- Arreglado «No se pudo reproducir: Response code 403»: si YouTube rechaza el audio, se pide un identificador de visitante y una URL nuevos y se reintenta una vez (al escuchar, en Descubrir y al descargar). El identificador caduca a los 3 días.
- Casete y vinilo en horizontal: se ocultan la barra de estado y la de navegación (asoman deslizando desde el borde), como en iOS. Antes la hora y los iconos se dibujaban encima del aparato.
- En horizontal, el mini reproductor y la barra de pestañas no pasan de 520 dp y quedan centrados (antes ocupaban todo el ancho y tapaban la lista).
- Mini reproductor: «Reproducir/Pausa» y «Siguiente» con más área táctil (44 y 40 dp), sin mover los iconos.

### [0.7.1] — 2026-10-12 (versionCode 8)
- Arreglado el cierre al reproducir: faltaba el permiso `WAKE_LOCK` que pide el reproductor para seguir sonando con la pantalla apagada.
- Cristal líquido de iOS 26 (opcional, Ajustes › Apariencia): la barra de pestañas, el mini reproductor, los botones redondos, los menús y los avisos refractan lo que hay detrás; la pestaña elegida se convierte en una gota que sigue al dedo y los botones crecen con rebote al pulsarlos.
- Los botones ya no vibran al pulsarlos.
- Descargas ~150 veces más rápidas (de ~64 KB/s a ~10 MB/s): se piden con `Range`, porque sin esa cabecera YouTube sirve el archivo a velocidad de reproducción. El inicio de cada canción también es más rápido.
- Las descargas pendientes se reanudan al abrir la app (antes la cola se quedaba parada si Android cerraba la app a medias).
- «Descargar todo» pertenece a su lista (mismo arreglo que iOS).
- Tema Cristal: la carátula del fondo ya no deja un cuadrado de bordes duros (blanco con carátulas claras). Descubrir: el fondo girado ya no deja ver las esquinas.
- Reproductor Normal y Air en horizontal: dos columnas (antes la carátula desaparecía y el disco de Air tapaba los controles).
- Navegación como en iOS: la pantalla nueva entra por la derecha y la anterior se aparta y se oscurece; para volver se arrastra hacia la derecha desde cualquier punto (sigue al dedo) y el gesto atrás de Android usa la misma animación. Al volver, cada pantalla conserva su desplazamiento.
- Deslizar a los lados cambia de pestaña, con la pestaña vecina asomando al arrastrar (como Instagram). Carruseles, filas con «Quitar» y el «atrás» de una pantalla abierta tienen prioridad.
- Cristal líquido más fluido: el efecto y la sombra se guardan en caché en vez de rehacerse en cada fotograma.
- Descubrir empieza a sonar en <1 s (antes ~2,3 s).
- Inicio como en iOS: al bajar, el saludo se encoge hasta la barra de arriba y el botón del Jam y el buscador se quedan fijos.
- Icono del Jam igual que el de iOS (dos personas con ondas), dibujado a mano.
- Menú contextual como el de iOS: el fondo se desenfoca y oscurece, la canción se eleva como vista previa, el menú sale de ahí con rebote y los submenús se abren en el sitio. «Añadir a playlist» muestra la portada de cada playlist y marca en las que ya está.
- Con cristal líquido, también el botón atrás es de cristal.
- El vinilo y las bobinas del casete vuelven a girar: el ángulo salía de la hora del sistema y, al pasarlo a Float, perdía la precisión (parecían parados). Ahora el reloj sólo cuenta mientras suena y se lee al dibujar, sin recomponer la pantalla en cada fotograma.
- Descubrir empieza a sonar en ~0,35 s: pide por adelantado las URLs de los dos fragmentos siguientes, carga directamente desde el estribillo y arranca con medio segundo de audio.
- Reproductor Air: el selector y los puntos avanzan en cada fotograma (antes, a saltos cada 0,5 s).
- Playlists: ordenar por nombre A-Z o Z-A y «A mano» arrastrando (también Descargadas y Favoritos), y opción para mostrar Descargadas y Favoritos en Playlists o en «Tu música». Igual que iOS.
- «Colores de la carátula» como en iOS (reproductor y/o resto de la app, también los menús).
- Tema Cristal: arreglado de verdad el cuadrado de bordes duros detrás del contenido (la capa con transparencia recortaba el desenfoque a su tamaño).
- Mismo emparejado de Apple Music y misma búsqueda de alternativas al reproducir que iOS 1.3.1.

### [0.7.0] — 2026-10-12 (versionCode 7)
- Primera versión publicada en GitHub Releases, firmada con la clave de publicación (las siguientes se podrán instalar encima).
- Interfaz rehecha para ser igual que la de iOS 1.3: mismos colores, tamaños y radios (tokens compartidos), letra Inter (la más parecida a SF Pro, que sólo se puede usar en Apple) e iconos redondeados.
- Pestañas Inicio, Descubrir, Biblioteca y Ajustes en una barra flotante, con el mini reproductor encima; «Buscar» en Inicio o como pestaña aparte.
- Inicio con «Escuchado recientemente», «Para ti», tus playlists y las estanterías de YouTube Music; álbumes y playlists públicas se abren y se guardan en la biblioteca.
- Biblioteca 1.1: carrusel de playlists con Descargadas y Favoritos, anillo de puntos de lo descargado, filtros, «Descargar todo», deslizar para quitar y editor de playlist (nombre, foto, icono y color).
- Cuatro temas (Cristal, Aire, Neón y Sistema) con sus fondos animados que toman los colores de la carátula, y claro/oscuro.
- Reproductor Normal, Casete, Vinilo y Air (rueda del iPod, velocidad, salida de audio); cola con «Editar»; casete y vinilo a pantalla completa en horizontal.
- Descubrir y el Jam con el mismo diseño que iOS.
- Importar una playlist de Apple Music por enlace, como en iOS; además, importar y exportar una copia de la biblioteca.
- «Ahorro de datos» funciona al escuchar en streaming.
- Icono igual que el de iOS.
- Paridad revisada captura a captura con iOS (`docs/PARIDAD.md`): barra de pestañas, mini reproductor, hojas, formularios de iOS 26, reproductor, casete, vinilo, Air y Jam con las mismas medidas; botones desactivados atenuados enteros; corregidos los tiempos recortados del casete y el borde de la carátula del disco de Air.

### 0.6.0 (versionCode 6) — no se publicó por separado; incluida en 0.7.0
- Fase 5a: Android Auto. El servicio de reproducción pasa a ser un `MediaLibraryService` con un árbol de navegación (Favoritas, Descargadas, Recientes y Playlists); al elegir una canción en el coche suena la carpeta entera desde ella.

### 0.5.0 (versionCode 5)
- Fase 4: Jam con amigos con el protocolo abierto v2 (`docs/JAM_PROTOCOL.md`): el anfitrión anuncia `_lm-jam._tcp` por NSD con el código en el TXT y los invitados se conectan por TCP (JSON por líneas).
- Crear un Jam o unirse con el código, escaneando el QR o abriendo `libremusic://jam/CÓDIGO`; hasta 16 personas, nombres únicos, «Añadir al Jam» en el menú de cada canción, reproducir la lista y guardarla como playlist (también si se corta la conexión).
- Servicio `_lm-jam2._tcp` (no choca con el Jam v1 de iOS); compatible con LibreMusic para iOS 1.2.0.

### 0.4.0 (versionCode 4)
- Fase 3: pestaña Descubrir. Feed vertical en el que cada canción suena 30 s desde la zona del estribillo, en bucle, con las mismas reglas que iOS (`ReelClip`).
- Sale de las radios de tus favoritas y recientes (o de una búsqueda si aún no hay), intercaladas y sin repetir favoritas; carga más al acercarse al final.
- Toca para pausar, doble toque para «Me gusta» y «Escuchar completa» pasa la canción al reproductor con el resto del feed como cola.

### 0.3.0 (versionCode 3)
- Fase 2: descargas para escuchar sin conexión (Media3 DownloadManager, en segundo plano con notificación de progreso), «Descargar todo» en Favoritas y playlists.
- Biblioteca: Favoritas, Descargadas, Playlists (crear, añadir, quitar, eliminar) y Recientes.
- Exportar/importar la biblioteca en el formato `library.json` de iOS (`docs/LIBRARY_FORMAT.md`); la importación une sin borrar.
- Migración automática de los favoritos de 0.2.0.
- Pendiente para una próxima versión: inicio de sesión opcional con la cuenta de YouTube Music.

### 0.2.0 (versionCode 2)
- Fase 1 (MVP): búsqueda con sugerencias, reproducción en segundo plano con notificación y pantalla de bloqueo, cola (a continuación, añadir, quitar, saltar), radio automática al reproducir una canción, favoritos guardados en el dispositivo y reproductor a pantalla completa.
- Cliente InnerTube portado de la app iOS (`Client.swift`) con la misma cadena de clientes VISIONOS → IOS → ANDROID_VR; la URL del audio se resuelve justo antes de reproducir y se guarda 3 h.
- Textos en español e inglés.

### 0.1.0
- Fase 0: esqueleto nativo (Kotlin + Jetpack Compose + Media3), servicio de reproducción en segundo plano, deep link `libremusic://jam/CÓDIGO` y CI de compilación.
