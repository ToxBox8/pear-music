# Rendimiento (Android)

Mediciones en un móvil real para comparar antes y después de cada cambio. Las capturas no sirven
para esto: la versión debug de Compose es varias veces más lenta que la publicada.

## Cómo se mide

1. `gradle assemblePerf` → `app/build/outputs/apk/perf/app-perf.apk`: igual que la release (R8, sin
   depuración) pero con la clave de depuración y el id `app.libremusic.perf`, así que se instala al
   lado de la app normal sin tocarla.
2. `apps/android/scripts/bench.sh "<etiqueta>" [all|nav]` con el móvil por USB y sin tocarlo:
   - **Arranque:** `am start -W` tres veces (la primera en frío).
   - **Fluidez entre menús:** `dumpsys gfxinfo` tras un recorrido fijo (cambiar de pestaña 9 veces,
     6 desplazamientos en Inicio, abrir y cerrar dos playlists y Apariencia).
   - **Descubrir:** el registro `LMPerf` (`adb logcat -s LMPerf`) da `reel_start_ms`, el tiempo desde
     que se elige un fragmento hasta que suena; se pasan 6 fragmentos.
3. La pantalla del móvil cambia sola entre 60, 90 y 120 Hz: se compara el tiempo por fotograma
   (percentiles) y los fotogramas con tirón («Janky frames»), no los FPS sueltos.

## Resultados

Nothing Phone (2), Android 16, pantalla de 120 Hz (presupuesto de 8,3 ms por fotograma).

| Fecha | Versión | Cristal | Arranque frío / templado | Fotograma p50 / p90 / p99 | Tirones | Descubrir (inicio del fragmento) |
|---|---|---|---|---|---|---|
| 2026-10-12 | 0.7.1 (`2c67137`) | No | 569 ms / ~190 ms | 12 / 19 / 21 ms | 0,52 % (12 de 2308) | 2,16–2,37 s (media 2,27 s) |
| 2026-10-12 | 0.7.1 (`2c67137`) | Sí (pantalla a 90 Hz) | — | 13 / 16 / 20 ms | 0,26 % (6 de 2317) | — |
| 2026-10-12 | Fase 1 + navegación nueva, sin caché del cristal | Sí | ~240 ms | 15 / 20 / 27 ms | 0,57 % | 0,48–0,79 s |
| 2026-10-12 | Fase 2 (pila tipo iOS, deslizar pestañas) | No (90 Hz) | — | 10 / 14 / 23 ms | 0,49 % | — |
| 2026-10-12 | Fase 2 + efecto y sombra del cristal en caché | Sí | ~250 ms | 12 / 15 / 29 ms | 0,67 % | 0,51–1,67 s (mediana 0,84 s) |
| 2026-10-12 | Fase 4 (Descubrir con precarga, relojes leídos al dibujar) | Sí (90 Hz) | ~270 ms | 12 / 15 / 24 ms | 0,53 % | 0,21–0,77 s (mediana 0,36 s) |
| 2026-10-13 | Plan 0.8.0, paso 0: 0.7.1 (`306b509`), referencia | No (120 Hz) | 293 ms / ~245 ms | 16 / 20 / 31 ms | 0,53 % (12 de 2265) | No sonaba (403); tras borrar los datos, 0,46–0,62 s |
| 2026-10-13 | Plan 0.8.0, Fase 1 | No (90 Hz) | 252 ms (templado) | 9 / 13 / 21 ms | 0,60 % (14 de ~2270) | 0,33–0,73 s (un pico de 1,95 s) |
| 2026-10-13 | Plan 0.8.0, Fase 1 | Sí, modo claro (90 Hz) | — | 9 / 14 / 30–38 ms | 0,96–1,19 % | — |

La mejora de Descubrir (de ~2,3 s a ~0,35 s) viene de pedir el audio con `Range` (ver «Descargas»), de pedir por adelantado las URLs de los dos fragmentos siguientes, de cargar directamente desde el estribillo (la duración llega con la URL) y de empezar con 0,5 s de audio en vez de 2,5 s.

La pantalla cambia sola entre 90 y 120 Hz y, a 120 Hz, los percentiles salen 2–3 ms más altos con el mismo trabajo; para comparar, lo más estable es el porcentaje de fotogramas con tirón (~0,5 % en todas las mediciones).

iOS no se puede medir desde esta máquina (no hay Mac ni Instruments); se compara a ojo.

### Descargas

Velocidad de la carpeta de descargas (`du` cada 5–10 s) con 2 descargas a la vez:

| Fecha | Cambio | Velocidad |
|---|---|---|
| 2026-10-12 | Antes (petición sin `Range`) | ~64 KB/s en total; una canción tardaba ~2 min |
| 2026-10-12 | Con `Range: bytes=0-` | ~10 MB/s; 51 canciones en ~30 s |
