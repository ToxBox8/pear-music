# Formato de la biblioteca (`library.json`)

Formato común de iOS y Android para guardar y exportar la biblioteca. Las dos apps lo usan como archivo interno (iOS: `Documents/library.json`) y en **Biblioteca → + → Importar playlist → Copia de la biblioteca** («Importar copia» y «Exportar copia»).

```json
{
  "favorites": [Song, …],
  "playlists": [
    { "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "name": "Viaje", "songs": [Song, …], "icon": "car.fill", "tint": 3 },
    { "id": "…", "name": "Currents", "songs": [Song, …], "tint": 5,
      "album": { "browseId": "MPREb_…", "artist": "Tame Impala", "year": "2015" } }
  ],
  "recents": [Song, …],
  "covers": { "E621E1F8-…": "base64 del JPEG (≤ 700 px)" },
  "playlistOrder": ["E621E1F8-…", "…"],
  "playlistSort": "manual",
  "albumOrder": ["5F0C…", "…"],
  "albumSort": "custom",
  "musicOrder": ["playlists", "songs", "albums", "artists", "favorites", "downloads", "recents", "stats"]
}
```

`Song`:

```json
{ "id": "videoId", "title": "Título", "artist": "Artista", "thumbnail": "https://…" }
```

## Reglas

- `id` de playlist: UUID en mayúsculas (como `UUID().uuidString` de Swift).
- Campos opcionales (`thumbnail`, `icon`, `tint`, `recents`, `album`): pueden faltar o ser `null`.
- `album` (desde 0.8.1): la lista es un álbum guardado o descargado desde su página. Sale en **Tu música ›
  Tus álbumes** y no en Playlists. `artist` y `year` son opcionales. Las versiones anteriores lo ignoran y lo
  muestran como una playlist más.
- `icon` es un SF Symbol de iOS; Android lo conserva aunque no lo muestre.
- `pinned: true` (desde Android 1.0 / iOS 2.0): la playlist o el álbum está fijado arriba en Biblioteca e Inicio
  («Fijados»). Si falta, no lo está.
- `recents`: como mucho 40, el más reciente primero.
- **Importar = unir**: se añaden favoritas y playlists que no existan (por `id`); nunca se borra nada.
- `albumOrder` y `albumSort` (desde x.1.1, opcionales): el orden propio de «Tus álbumes» (ids, como `playlistOrder`)
  y si está en uso (`custom`) o no (`recent`). Al importar se unen igual que `playlistOrder`. Las copias viejas, sin
  estos campos, se leen igual.
- `musicOrder` (desde Android 1.0 / iOS 2.0, opcional; `playlists` desde x.1.1): orden de las carpetas de «Tu música»; sólo se escribe si no es el de fábrica y al importar se adopta si el móvil no tenía uno propio.
- `covers`, `playlistOrder` y `playlistSort` (desde Android 1.0 / iOS 2.0): las portadas propias de las playlists y su
  orden manual, que antes se perdían al pasar la copia a otro móvil. Al importar, la portada se pone sólo donde no
  haya una propia; el orden se une (el del móvil se respeta y lo nuevo va detrás) y, si el móvil no tenía orden
  propio, se adopta el de la copia junto con `playlistSort`. La copia en la nube de la cuenta lleva portadas sólo
  si caben en su límite de 2 MB. Las versiones anteriores ignoran estos campos.
- Implementaciones: `Library` en `apps/ios/Sources/Store.swift` y `LibraryData` en `apps/android/.../data/Library.kt` (con tests de compatibilidad).

## Compartir una playlist con un QR (x.1.1)

Sin servidor. El QR (y el enlace de «Compartir enlace») es `libremusic://playlist?v=1&d=<datos>`:

- `datos` = JSON `{"n": "Atardecer", "i": "<id1><id2>…", "ic": "sun.max.fill", "t": 3}` comprimido con **deflate sin
  cabecera** (RFC 1951) y en **base64url sin relleno**.
- `i`: los ids de YouTube **seguidos** (11 caracteres cada uno, `[A-Za-z0-9_-]`), en el orden de la playlist. Como
  mucho **150** (≈1800 caracteres, un QR que se lee desde otra pantalla). `n` como mucho 100 caracteres; `ic` y `t`
  opcionales (icono y color).
- Al importar, el título, el artista y la carátula se piden a YouTube Music (`music/get_queue`, de 50 en 50); lo que
  no esté se queda fuera y se avisa. Si ya hay una playlist con ese nombre: «Atardecer (2)».
- Una foto propia no viaja (no cabe); la hoja lo dice. Listas más largas o con foto: con el servidor (después de la
  mudanza, fase de seguridad).
- Al descomprimir hay tope (64 KB): unos datos manipulados no pueden inflarse.
- Implementaciones: `PlaylistShare` (Kotlin, con `PlaylistShareTest`) y `PlaylistShare` (Swift).

