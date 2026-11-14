# Casos comunes de `library.json`

Copias de la biblioteca que leen los tests de las dos apps para comprobar que salen **iguales** (formato en
`docs/LIBRARY_FORMAT.md`):

| Archivo | Qué prueba |
|---|---|
| `antigua-sin-carpetas.json` | Una copia de antes de las carpetas (iOS 2.2 / Android 1.2 / 3.0.0-beta.1): se lee igual y todo queda sin carpeta. |
| `carpetas.json` | Carpetas en 3 niveles; un álbum con `folder` (no va en carpetas: se ignora). |
| `carpetas-rotas.json` | Huérfana, ciclo, carpeta que es su propio padre, 4.º nivel, id repetido, sin id, nombre vacío, tipos raros. |
| `esperado.json` | Lo que tiene que salir de cada una. |

- iOS: `apps/ios/scripts/test-linux.sh` (`scripts/tests/LibraryFoldersTests.swift`, en Linux).
- Android: `PlaylistFoldersTest` (`gradle testUsrDebugUnitTest --tests '*PlaylistFoldersTest'`).

Si cambias una regla, cambia aquí el caso y su resultado: las dos apps tienen que seguir pasando.
