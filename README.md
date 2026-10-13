# LibreMusic

Cliente de música libre y sin cuenta para **iPhone** y **Android**: busca y escucha el catálogo público de YouTube
Music, guarda favoritos y playlists, descarga para escuchar sin conexión, letras sincronizadas, Jam entre móviles y
reproductores con personalidad (casete, vinilo, Air).

- **Web y descargas:** https://libremusic-landing.8toxbox8-69a.workers.dev
- **iOS:** `.ipa` sin firmar para AltStore, SideStore o Sideloadly. **Android:** APK firmado (también por Obtainium).

## Aviso legal

LibreMusic es un proyecto personal, gratuito y sin ánimo de lucro. **No está afiliado, patrocinado ni aprobado por
Google LLC, YouTube ni YouTube Music**; esos nombres son marcas de sus dueños y se usan sólo para decir con qué
catálogo es compatible. La app usa una interfaz no oficial que puede dejar de funcionar en cualquier momento.

Cada persona es responsable de cómo la usa y de respetar las condiciones de los servicios a los que accede y los
derechos de autor de la música. Las descargas son para escuchar sin conexión dentro de la app, no para redistribuir.

## Privacidad

Sin cuentas, sin anuncios, sin analíticas. La biblioteca, las estadísticas y las descargas se quedan en el móvil.
La app sólo habla con YouTube Music (búsquedas y audio), LRCLIB (letras), Apple Music o Spotify (al importar una
playlist pública) y, si mandas un reporte de error, con el servidor de soporte. Detalles en la web
(`/privacidad`).

## Código

Monorepo con las dos apps nativas: `apps/ios` (SwiftUI) y `apps/android` (Kotlin + Jetpack Compose + Media3).
Para contribuir, empieza por `AGENTS.md`, `CONTEXT.md` y `DECISIONS.md`.

## Licencia

[GPL-3.0](LICENSE). Puedes usar, estudiar, modificar y compartir el código; las versiones modificadas que
distribuyas tienen que seguir siendo GPL-3.0 y con su código disponible.
