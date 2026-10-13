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
  "recents": [Song, …]
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
- `recents`: como mucho 40, el más reciente primero.
- **Importar = unir**: se añaden favoritas y playlists que no existan (por `id`); nunca se borra nada.
- Implementaciones: `Library` en `apps/ios/Sources/Store.swift` y `LibraryData` en `apps/android/.../data/Library.kt` (con tests de compatibilidad).
