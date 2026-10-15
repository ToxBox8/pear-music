# ADR 0001 — Cuenta opcional, telemetría y avisos de actualización (Fase 2)

- **Estado:** aceptado (14-10-2026)
- **Decide:** Toxbox (opciones elegidas en la sesión del 14-10); propuesta técnica de Claude.

## Contexto

Hasta la 0.9.5 / 1.4.1 Pear Music no tiene servidor propio con datos de usuarios: sólo el Worker de soporte
(reportes → Discord) y la web (avisos, versiones). La Fase 2 pide:

1. Una **cuenta opcional** que ayude a mejorar la app, sin perder nada si no se crea.
2. **Telemetría** (dispositivo, FPS, rendimiento) con consentimiento **separado** de la cuenta, retirable, y
   documentando exactamente qué se envía. Sin consentimiento, nada.
3. **Avisos de actualización** con novedades, «Descargar» y «Recordarme mañana»; que la descarga no rompa la
   instalación existente ni pierda la música descargada.
4. Soporte más robusto contra tickets no genuinos.

Restricciones: RGPD (responsable en España), proyecto de una persona, sin presupuesto, todo ya está en
Cloudflare (Workers, KV) y GitHub.

## Decisión

### Un Worker nuevo, `pear-music-api` (`services/api`), con D1

| Ruta | Qué hace | Autenticación |
|---|---|---|
| `POST /v1/cuenta/codigo` | Manda un código de 6 cifras al correo (caduca en 10 min, 5 intentos). | — |
| `POST /v1/cuenta/entrar` | Cambia correo + código por un token de sesión. | — |
| `GET/PUT /v1/cuenta/biblioteca` | Guarda y devuelve la biblioteca **cifrada en el móvil** (blob opaco, ≤ 2 MB, con versión para no pisar cambios). | Bearer |
| `GET /v1/cuenta` · `DELETE /v1/cuenta` | Ver qué hay guardado · borrar la cuenta y todo lo suyo al momento. | Bearer |
| `POST /v1/telemetria` | Un informe de rendimiento por sesión. Rechaza campos que no estén en la lista. | Identificador de instalación aleatorio |

- **Correo:** se guarda cifrado (AES-GCM con un secreto del Worker) y se busca por un HMAC; nunca en claro en la
  base de datos. Se usa sólo para entrar.
- **Biblioteca cifrada de extremo a extremo** (lo pidió Toxbox: «que esté cifrado por seguridad de los
  usuarios»): cada cuenta tiene una **clave de cifrado aleatoria de 256 bits** que se crea en el primer móvil y
  se enseña una vez como **clave de recuperación** (24 caracteres). El servidor nunca la ve; para usar la cuenta
  en otro móvil hay que escribirla. Sin ella, nadie (ni Toxbox) puede leer la biblioteca guardada.
- **Sesiones:** token aleatorio de 256 bits; en el servidor sólo su SHA-256. En el móvil, en `SecureBox`.
- **Telemetría:** tabla aparte, **sin relación con la cuenta** (otro identificador, aleatorio, que se renueva al
  retirar el consentimiento). Se borra a los 90 días (cron diario). Campos exactos en `docs/TELEMETRIA.md`.

### Avisos de actualización desde la web

Las apps leen `https://…/version.json` (ya existía; ahora con título, novedades y, en Android, APK + SHA-256).

- **Android:** «Descargar» baja el APK con `DownloadManager`, **comprueba el SHA-256** y abre el instalador del
  sistema. Al ser el mismo paquete y la misma firma, Android **actualiza encima**: biblioteca, ajustes y
  canciones descargadas se conservan. Si el hash no cuadra, no se instala.
- **iOS:** una app no puede instalarse sola. «Descargar» abre la fuente de AltStore (o SideStore), que actualiza
  encima conservando los datos; si no hay ninguna, la guía de la web.
- **«Recordarme mañana»:** guarda la versión y la hora; vuelve a salir pasadas 24 h. Al abrir, como mucho una
  comprobación cada 6 h.

## Alternativas descartadas

| Alternativa | Por qué no |
|---|---|
| Firebase Auth / Supabase | Otro proveedor y otro encargado de tratamiento (RGPD); datos fuera de Cloudflare. |
| Contraseñas | Hay que guardarlas, recuperarlas y protegerlas; un código al correo es más simple y seguro. |
| Cifrar la biblioteca con una clave derivada de la contraseña | No hay contraseña; y una clave aleatoria es más fuerte que cualquier contraseña humana. |
| Telemetría con un SDK (Firebase, Sentry) | SDK de terceros en la app, más datos de los necesarios y otro encargado. |
| Google Play In-App Updates | La app no está en Google Play. |

## Consecuencias

- **Coste:** D1 y Workers en el plan gratuito sobran para este volumen.
- **Hace falta para desplegar:** crear la base D1, los secretos (`EMAIL_KEY`, `EMAIL_HMAC`) y **un remitente de
  correo**. El envío de correo de Cloudflare necesita un **dominio propio** en Cloudflare; `workers.dev` no
  sirve. Hasta tenerlo, la cuenta queda desactivada en las apps (el resto funciona).
- **Perder la clave de recuperación** = no poder leer la biblioteca guardada en la nube (la del móvil sigue
  intacta). Se avisa claramente al crearla.
- El **botón de pánico** no va aquí: es la Fase 4 (estado firmado con Ed25519), y este Worker lo respetará.
