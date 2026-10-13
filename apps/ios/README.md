# LibreMusic (cliente no oficial de YouTube Music)

Compilación en la nube (GitHub Actions) + instalación desde Linux.

## 1. Compilar
La CI del monorepo compila esta app sin Mac (ver `docs/RELEASING.md`):
1. Cada push que toque `apps/ios/` lanza el workflow **iOS** en la pestaña **Actions** (~3-5 min).
2. Descarga el artefacto `LibreMusic-ios` (zip con `LibreMusic-ios-<versión>.ipa`, sin firmar, y su SHA-256).
3. Las versiones publicadas (etiqueta `ios-vX.Y.Z`) quedan en **Releases**.

## 2. Instalar desde Arch
    sudo pacman -S libimobiledevice usbmuxd
    sudo systemctl enable --now usbmuxd
Conecta el iPhone, desbloquéalo y pulsa "Confiar". Activa **Ajustes → Privacidad y seguridad → Modo desarrollador** (reinicia).
Firma e instala el .ipa con tu Apple ID usando **Sideloader** (github.com/Dadoum/Sideloader) o **AltServer-Linux**.
Primera vez: Ajustes → General → VPN y gestión de dispositivos → Confiar. Con Apple ID gratis caduca a los 7 días: repite el paso.

## Biblioteca «Nueva 1.1» y tema Aire
- Ajustes → Biblioteca → Diseño → **Nueva 1.1**: playlists arriba en carrusel (con *Descargadas* y *Favoritos* como listas), filtros Todas / Descargadas / Favoritas, «Descargar todo» y botones de favorito y descarga en cada canción.
- Ajustes → Apariencia → **Aire**: copia de *Air OS* (Geex Arts): papel gris claro, Helvetica Neue negra y anillo de puntos (los puntos negros son lo descargado de la lista).
- Reproductor **Air** (Ajustes → Reproductor, o toca la miniatura del mini reproductor): disco esmerilado con la carátula, anillo de puntos que se oscurece al avanzar (arrástralo para saltar), selector holográfico, rueda de iPod (toca arriba para la cola, gira el borde para avanzar 30 s por vuelta), botón «x1» de velocidad, casilla de salida de audio/AirPlay y corona de descarga.

## Ajustes → Apariencia
- Todo lo visual está junto: **Tema**, **Reproductor**, **Biblioteca** y **Buscar**.
- Buscar: por defecto es una barra fija arriba en Inicio; en Apariencia → Buscar se puede volver a la pestaña aparte.

## Descubrir (reels)
- Pestaña **Descubrir**: feed vertical a pantalla completa. Cada canción suena 30 s desde la zona del estribillo, en bucle, con la carátula animada.
- Desliza arriba/abajo para cambiar, toca para pausar, doble toque para «Me gusta». «Escuchar completa» la pasa al reproductor con el resto del feed como cola.
- Sale de la radio de tus favoritos y lo último que has escuchado (o del inicio si aún no hay nada). No muestra lo que ya tienes en favoritos.

## Jam con amigos
- Biblioteca → **+** → *Jam con amigos* (o el botón de personas en Inicio).
- Quien lo crea recibe un código de 6 caracteres y un QR. Los demás lo escriben o lo escanean (también con la cámara del iPhone, abre `libremusic://jam/CÓDIGO`).
- Sin servidor: funciona entre móviles cercanos (misma WiFi o Bluetooth), hasta 8 personas, con la app abierta. Cada canción muestra quién la añadió.
- *Guardar como playlist* deja una copia en tu biblioteca. Si el anfitrión termina o se pierde la conexión, la lista se conserva para guardarla.
- La primera vez iOS pide permiso de **red local** (y de cámara para escanear).

## Limitaciones
- No publicable en App Store. API no oficial de YouTube: puede romperse.
- Sin login ni letras. Favoritos/playlists locales. Descargas en .m4a dentro de la app.
