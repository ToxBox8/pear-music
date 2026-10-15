# Soporte: reportes de errores → Discord (Fase 4C)

Worker de Cloudflare que recibe los reportes del botón del escarabajo (Ajustes, arriba a la derecha) y los
reenvía a un canal privado de Discord. Las apps **no llevan** la URL del webhook: sólo conocen la del Worker.

```
app ──POST multipart /report──▶ Worker (valida, limita) ──webhook──▶ canal privado de Discord
```

- **Qué envía la app:** `email`, `text`, `platform` (`ios`/`android`), `appVersion`, `os`, `model`, `deviceId`
  (UUID anónimo de la instalación) y hasta 4 fotos `photo0…photo3` (JPEG, reescaladas a 1600 px, sin EXIF).
- **Qué comprueba el Worker** (`src/limits.js`, mismos límites que las apps): correo válido, texto de 10 a 4000
  caracteres, ≤ 4 fotos, ≤ 1,5 MB cada una y ≤ 6,5 MB en total, que sean JPEG de verdad (por sus bytes), y
  1 reporte por hora por dispositivo y por correo y 3 por IP (Workers KV, con las claves en SHA-256: no se guarda la IP
  ni el correo). Además (`src/spam.js`): correos desechables, de prueba o de relleno, dominio sin MX (DNS sobre HTTPS a
  1.1.1.1) y texto sin sentido o con más de 2 enlaces. Responde `200 {ok}`, o `4xx/5xx {error}` con
  un texto que la app enseña tal cual.
- **Discord:** un mensaje con un embed (correo, sistema, modelo, versión y texto) y las fotos adjuntas, sin
  menciones (`allowed_mentions: []`). Los webhooks admiten 10 archivos y unos 8–10 MB por mensaje en un servidor
  sin mejoras; con 4 fotos de ≤ 1,5 MB queda margen.
- **Coste:** el plan gratuito de Workers (100 000 peticiones al día) y de KV basta; no hay servidor que mantener.

## Estado

Desplegado el 13-10-2026 en la cuenta de la web. KV `RATE` = `fa1cbcea…`. Los reportes van al servidor privado de Discord «Pear Music · soporte», canal `#soporte-pear-music`. Para volver a desplegar: `npx wrangler login --device` (el login normal falla) y `npx wrangler deploy`.

## Desplegar (lo hace Toxbox, una vez)

1. En Discord: canal privado › Editar canal › Integraciones › Webhooks › Nuevo webhook › *Copiar URL*.
   **No la pegues en ningún chat ni archivo.**
2. En esta carpeta:
   ```bash
   npx wrangler login                          # abre el navegador con tu cuenta de Cloudflare
   npx wrangler kv namespace create RATE       # copia el id que devuelve en wrangler.toml
   npx wrangler secret put DISCORD_WEBHOOK     # pega aquí la URL del paso 1
   npx wrangler deploy
   ```
3. Queda en `https://libremusic-soporte.8toxbox8-69a.workers.dev/report`, la URL que llevan las apps
   (`SupportClient` en iOS y Android). Si tu subdominio de workers.dev es otro, cámbiala en las dos.
4. Prueba: `curl -F email=tu@correo.com -F text="Prueba del soporte" -F platform=android -F deviceId=prueba https://libremusic-soporte.8toxbox8-69a.workers.dev/report`
   tiene que devolver `{"ok":true}` y aparecer en el canal.

## Probar sin desplegar

`npm test` (Node 20+): valida los límites y ejecuta el Worker entero con un KV y un Discord falsos.

## Tickets y buzón de sugerencias (Cierre 1.0)

Cada reporte o sugerencia (`kind=sugerencia`, desde Ayuda y soporte › Buzón de sugerencias) abre un ticket
numerado: la app recibe `{ok, ticket}` y el embed de Discord lleva «#n». Las sugerencias van a
`DISCORD_WEBHOOK_SUGERENCIAS` si existe (si no, al canal de soporte).

Desde Discord (aplicación propia «Pear Music · soporte»; la del pánico es otra, porque cada aplicación tiene una sola
URL de interacciones):

- `/msg ticket:<autocompleta los abiertos> texto:<…> [tipo]`: le llega **sólo a esa persona** como aviso en la
  campana. Tipos: 💬 mensaje (por defecto), 🎉 `fiesta` (solucionado, gracias; también si el texto empieza por
  «fiesta») y `>_` `en-ello` (o si empieza por «estamos en ello»).
- `/rp ticket:<n> accion:o` abre el ticket: hilo propio en `DISCORD_TICKETS_CHANNEL` y aviso «Abrimos tu
  incidencia» con un check. `accion:c` lo cierra (archiva el hilo y ya no admite mensajes).

La app pide sus avisos con `GET /mensajes?device=<id anónimo>` sólo si ya envió algo desde ese móvil. Aquí se guarda
el resumen SHA-256 del id, nunca el id ni el correo (6 meses).

Activarlo (Toxbox, una vez):
1. Portal de desarrolladores de Discord › nueva aplicación «Pear Music · soporte» › *Public Key* →
   `npx wrangler secret put DISCORD_PUBLIC_KEY`; *Bot* › token → `npx wrangler secret put DISCORD_BOT_TOKEN`.
2. *Interactions Endpoint URL*: `https://libremusic-soporte.8toxbox8-69a.workers.dev/discord`.
3. Invitar el bot al servidor de soporte con `applications.commands` y permiso de crear hilos y escribir.
4. En `wrangler.toml` (`[vars]`): `DISCORD_ADMIN_ROLE` (id del rol) y `DISCORD_TICKETS_CHANNEL` (id del canal).
   Opcional: `npx wrangler secret put DISCORD_WEBHOOK_SUGERENCIAS` (webhook del canal de sugerencias).
5. `npx wrangler deploy` y `DISCORD_APP_ID=… DISCORD_GUILD_ID=… DISCORD_BOT_TOKEN=… node scripts/registrar-discord.mjs`.

Desplegado el 15-10-2026 (tickets y `/mensajes` ya funcionan; los comandos esperan a los pasos 1–5).
