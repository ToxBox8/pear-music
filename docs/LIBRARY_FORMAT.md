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
  "musicOrder": ["songs", "albums", "artists", "favorites", "downloads", "recents", "stats"]
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
- `musicOrder` (desde Android 1.0 / iOS 2.0, opcional): orden de las carpetas de «Tu música»; sólo se escribe si no es el de fábrica y al importar se adopta si el móvil no tenía uno propio.
- `covers`, `playlistOrder` y `playlistSort` (desde Android 1.0 / iOS 2.0): las portadas propias de las playlists y su
  orden manual, que antes se perdían al pasar la copia a otro móvil. Al importar, la portada se pone sólo donde no
  haya una propia; el orden se une (el del móvil se respeta y lo nuevo va detrás) y, si el móvil no tenía orden
  propio, se adopta el de la copia junto con `playlistSort`. La copia en la nube de la cuenta lleva portadas sólo
  si caben en su límite de 2 MB. Las versiones anteriores ignoran estos campos.
- Implementaciones: `Library` en `apps/ios/Sources/Store.swift` y `LibraryData` en `apps/android/.../data/Library.kt` (con tests de compatibilidad).
