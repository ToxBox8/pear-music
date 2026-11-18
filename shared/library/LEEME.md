# Casos comunes de `library.json`

Copias de la biblioteca que leen los tests de las dos apps para comprobar que salen **iguales** (formato en
`docs/LIBRARY_FORMAT.md`):

| Archivo | Qué prueba |
|---|---|
| `antigua-sin-carpetas.json` | Una copia de antes de las carpetas (iOS 2.2 / Android 1.2 / 3.0.0-beta.1): se lee igual y todo queda sin carpeta. |
| `carpetas.json` | Carpetas en 3 niveles; un álbum con `folder` (no va en carpetas: se ignora). |
| `carpetas-rotas.json` | Huérfana, ciclo, carpeta que es su propio padre, 4.º nivel, id repetido, sin id, nombre vacío, tipos raros. |
| `carpetas-albumes.json` | Carpetas de álbumes (`albumFolders`, T15): dos árboles, un álbum en una carpeta de playlists y una playlist en una de álbumes, id repetido entre las dos listas, 4.º nivel, `albumOrder` con `folder:` y con una clave huérfana. |
| `carpetas-iconos.json` | Icono y color de carpeta (T16): icono conocido con y sin `tint`, desconocido, `tint` 8, −1, `3.0`, `"3"` y `2.5`, `icon` numérico y vacío, `covers` con el id de una carpeta. |
| `esperado.json` | Lo que tiene que salir de cada una (los dos árboles de carpetas, iconos y colores guardados y pintados, la carpeta de cada playlist y, en la de álbumes, las claves `folder:` que valen y el orden de «Tus álbumes»). |
| `seguidos.json` | Artistas seguidos (3.0): repetido, sin `browseId`, id vacío o que no es texto, nombre vacío, `since` y foto de otro tipo. |
| `esperado-seguidos.json` | Los seguidos que tienen que salir de cada copia, en orden. |
| `sync-unir.json` | Unir dos versiones de la biblioteca entre móviles (`docs/spec/sync.md` §5): 14 casos con su entrada, su resultado y su aviso. Los escribe `node tools/spec/generar-sync.mjs` con la referencia `tools/spec/sync.mjs`; hoy sólo los pasa JS (`node --test tools/spec/vectores.test.mjs`); las dos apps, desde el 2-D. |

- iOS: `apps/ios/scripts/test-linux.sh` (`scripts/tests/LibraryFoldersTests.swift`, en Linux).
- Android: `PlaylistFoldersTest` (`gradle testUsrDebugUnitTest --tests '*PlaylistFoldersTest'`).
- Seguidos: `scripts/tests/FollowedArtistsTests.swift` (iOS, en el mismo `test-linux.sh`) y `FollowedArtistsTest` (Android).

Si cambias una regla, cambia aquí el caso y su resultado: las dos apps tienen que seguir pasando.
