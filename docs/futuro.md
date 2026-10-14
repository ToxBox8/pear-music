# Futuro — lo que falta y lo que no se ha podido hacer

Última actualización: 2026-10-13. Lo hecho está en `CHANGELOG.md`, `DECISIONS.md` y `docs/contexto.md`; aquí sólo
lo pendiente, con el motivo y el siguiente paso. Al terminar algo, se quita de aquí y se apunta en `DECISIONS.md`.

## 1. Probar con cable (lo más urgente)

Probado el 13-10 por la noche (`docs/pruebas/v0.9.0-manual`): letra, temporizador con la app cerrada, estadísticas,
radio infinita, ecualizador (se aplica) y atajos. Falta lo de abajo que necesita a Toxbox: widget, copia a Drive,
TalkBack/letra grande, oír fundido y ecualizador, «al acabar la canción» con la pantalla apagada y lo de 0.8.1.

### Android (Nothing Phone (2) por USB)

1. `adb devices` debe enseñar **un** móvil como `device` (si sale vacío o `unauthorized`, se para y se apunta).
2. `cd apps/android && gradle assembleDebug && scripts/smoke.sh` → capturas en `docs/pruebas/smoke-AAAA-MM-DD`
   y aviso si hay cierres (`adb logcat -b crash`).
3. A mano, una por una (cada carpeta `docs/pruebas/v0.9.0-*` dice qué mirar):
   - Temporizador: 5 min con la app cerrada; baja el volumen y para. «Al acabar la canción» con la pantalla apagada.
   - Letras: la línea cambia a tiempo; tocar una línea salta; sin conexión en una descargada.
   - Fundido y ecualizador: con auriculares y con el altavoz; sigue tras cambiar de canción y cerrar la app.
   - Radio infinita: poner una sola canción y dejar que acabe la cola (sin repetidas).
   - Estadísticas: escuchar 30 s y ver que suma, también con la app cerrada.
   - Copia automática: elegir una carpeta de Drive; aparece `PearMusic-copia-AAAA-MM-DD.json`; importarla.
   - Widget: añadirlo; cambia con la canción; anterior / play / siguiente con la app cerrada.
   - Atajos: mantener pulsado el icono (con el icono violeta también).
   - TalkBack: recorrer reproductor y Ajustes; letra del sistema al máximo.
   - Lo de 0.8.1 que quedó sin probar: Tus álbumes, Ajustes nuevos, colores de la portada, informar de un error,
     importar de Spotify/SimpMusic, icono.
4. Medir fluidez con `scripts/bench.sh` y comparar con `docs/RENDIMIENTO.md` (letras y estadísticas añaden trabajo).

### iOS (iPhone por cable)

1. Compilar el `.ipa`: **ya compila** en el repo público (`pear-music`, rama `ios-compila`, ver `docs/contexto.md`).
   El de prueba está en `~/Documentos/code/libremusic/ipa/PearMusic-ios-1.4.0-prueba.ipa`.
2. Instalar con AltStore/SideStore y repetir la lista de Android (sin ecualizador ni widget), más:
   atajos de Siri («Mezcla mis favoritas en Pear Music»), VoiceOver y Texto más grande.
3. Corregir los errores de compilación que salgan (se esperan algunos: hay mucho código de iOS escrito sin compilar).

## 2. Tests y depuración que faltan

- iOS no tiene tests: añadir un target de tests (`project.yml`) para la lógica común con Android (`Matcher`,
  `TabOrder`, `Lyrics.parseLRC`, `Fade`, `PlayStats`, `Releases.pick`, `AutoBackup.toPrune`) — los mismos casos que
  los tests de Android, para que las dos apps no se separen.
- Android: tests de interfaz en un móvil de verdad (Compose UI tests / Macrobenchmark) para el reproductor y el widget.
- Capturas de iOS de las pantallas 16–26 (`-screenshotScenario`) para la hoja de paridad.
- Depurar en el móvil: `adb logcat` con el filtro de la app durante una sesión larga (fugas del temporizador,
  del fundido y del contador de escuchas, que van en el servicio).

## 3. Bloqueos externos

| Qué | Por qué no se hizo | Qué hace falta |
|---|---|---|
| ~~Skills de terceros~~ | Instaladas por Toxbox y usadas el 13-10 (noche) | — |
| **Skills de terceros (antes)** (`avdlee/swiftui-agent-skill@swiftui-expert-skill`, `twostraws/swiftui-agent-skill@swiftui-pro`, `wshobson/agents@mobile-android-design`, `momentic-ai/skills@momentic-mobile-test`) | El sistema de permisos de Claude Code bloquea `npx skills add` aunque Toxbox dé permiso | Toxbox las instala con `! npx skills add <paquete> -s <skill> -g -a claude-code -y` (o añade la regla `Bash(npx skills add:*)`); después, **revisar todo el código con ellas** (lo pidió Toxbox) |
| Compilar iOS | Cuota del repo privado agotada | **Resuelto** con las Actions gratis del repo público `pear-music` (rama `ios-compila`) |
| ~~Worker de soporte + Discord~~ | **Desplegado** el 13-10 (noche) | — |
| Integrar en la rama principal | Decisión de Toxbox | `plan-0.8.0` → `ideas-0.9.0` → `monorepo`/`master` |

## 4. Funciones pendientes

- **Widget de iOS** (WidgetKit + App Group). Necesita compilar y firmar; con AltStore/SideStore los App Groups
  funcionan, pero hay que probarlo.
- **Ecualizador en iOS**: sólo pasando a AVAudioEngine con descarga propia (HLS no deja procesar el audio). Mientras,
  Toxbox tiene que aceptar la diferencia o quitarlo de Android.
- **Sin cortes en iOS** (`AVQueuePlayer` para preparar la siguiente canción).
- **Avisos de lanzamientos** como notificación (WorkManager / BGTaskScheduler); hoy sólo es una estantería en Inicio.
- **Crossfade solapado** de verdad (dos reproductores), si el fundido corto se queda corto.
- **CarPlay completo**: imposible sin la App Store (permiso `carplay-audio`). Se queda con Ahora suena y los mandos.
- ~~Subir Android a 0.9.0~~: publicado como **0.9.1** (versionCode 11) el 13-10.

## 5. Web (libremusic-landing)

Ver la sección «Ideas para la web» de `README.md` en ese repo. Pendiente de la sesión de Toxbox: los secretos de las
notificaciones de nuevas versiones (claves VAPID) y conectar el aviso con las GitHub Releases.
