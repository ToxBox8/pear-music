# Estado: kill switch firmado y botón de pánico (Fase 4)

Worker de Cloudflare `pear-music-estado`, **aparte** de la web y del repo público. Sirve el estado de incidencias
que leen las apps y deja publicar, con contraseña + TOTP, los estados que el PC de Toxbox ya firmó. Qué hacer en un
incidente: [`docs/RUNBOOK-INCIDENTES.md`](../../docs/RUNBOOK-INCIDENTES.md).

```
PC de Toxbox (clave privada Ed25519)
  └─ tools/estado/estado.mjs lote ──POST /admin/lote (ADMIN_TOKEN)──▶ Worker (KV: lote prefirmado)
Pear Dev (panel de pánico) ──POST /panico (contraseña + TOTP)──▶ Worker publica el siguiente sobre del lote
Discord /panico (rol + canal de administración, modal) ──POST /discord──▶ igual
Apps (al abrir; Android cada 15 min) ──GET /estado──▶ { payload, sig } → verifican con la clave pública
```

- **El Worker no tiene la clave privada**: no puede inventar un estado ni cambiar un mensaje, sólo publicar uno
  de los sobres firmados en el PC. Si alguien entra en Cloudflare, lo peor que puede hacer es publicar uno de esos
  estados (o borrar el KV, y entonces las apps siguen normal).
- **Las apps fallan en abierto**: sin red, sin estado (204), con firma mala o caducado, siguen como estaban. Nunca
  aceptan un contador menor que el último que vieron (anti-rollback).
- **Niveles**: 0 normal · 1 aviso (banner, caduca solo a las 24 h) · 2 modo seguro (se apagan actualizaciones,
  búsqueda remota, soporte, telemetría y cuenta) · 3 bloqueo total (pantalla de mantenimiento).
- **Reglas** (`RULES` en `src/worker.js`): 5 min entre cambios; nivel 3 en dos pasos (pedir y confirmar entre 10 min
  y 1 h después con **otro** código); 5 fallos de credenciales en una hora bloquean hasta la hora siguiente; cada
  acción (y cada intento rechazado) queda en la auditoría (200 entradas) y se avisa al canal de administración.

## Rutas

| Ruta | Quién | Qué |
|---|---|---|
| `GET /estado` | apps | sobre firmado vigente, o 204 si no hay ninguno |
| `POST /panico` `{level, password, totp}` | Pear Dev | publica el nivel 0–2, o pide el 3 (202) |
| `POST /panico/confirmar` · `/panico/cancelar` | Pear Dev | confirma o cancela el bloqueo pedido |
| `POST /panico/info` `{password, totp}` | Pear Dev | nivel, bloqueo pendiente, cambios que quedan, caducidad del lote y auditoría |
| `POST /discord` | Discord | interacciones del comando `/panico` (firma Ed25519 de Discord) |
| `POST /admin/lote` · `/admin/publicar` | PC | sube un lote prefirmado o un estado firmado a mano (`Bearer ADMIN_TOKEN`) |

## Desplegar (lo hace Toxbox, una vez)

Nada de esto pasa por un chat: los secretos se escriben en la terminal y van directos a Cloudflare.

1. **Cloudflare** (en esta carpeta):
   ```bash
   npx wrangler login --device                  # el login normal falla en este PC
   npx wrangler kv namespace create ESTADO      # copia el id en wrangler.toml (sustituye «PENDIENTE»)
   npx wrangler deploy
   ```
2. **Secretos del pánico**: `node scripts/preparar-secretos.mjs`. Pide la contraseña (sin eco, 12+ caracteres) y
   sube su hash (`PANIC_PASSWORD`), crea el secreto TOTP (`TOTP_SECRET`) y te enseña el QR para la app de
   autenticación (haz `clear` después), y crea `ADMIN_TOKEN` y lo guarda en `~/.config/pear-music/estado.env`.
3. **Alertas**: webhook del canal de administración de Discord → `npx wrangler secret put ALERT_WEBHOOK`.
4. **Discord** (opcional, para `/panico` desde el móvil sin Pear Dev):
   1. [Portal de desarrolladores](https://discord.com/developers/applications) › *New Application* › copia la
      *Public Key* → `npx wrangler secret put DISCORD_PUBLIC_KEY`.
   2. *Interactions Endpoint URL*: `https://pear-music-estado.8toxbox8-69a.workers.dev/discord` (Discord la prueba
      al guardar; el Worker tiene que estar desplegado y con la clave del paso anterior).
   3. Invita la aplicación a tu servidor con el permiso `applications.commands`.
   4. En `wrangler.toml`, `DISCORD_ADMIN_ROLE` y `DISCORD_ADMIN_CHANNEL` con los id del rol y del canal privado
      (Discord › Ajustes › Avanzado › Modo desarrollador › clic derecho › *Copiar ID*) y `npx wrangler deploy`.
   5. Registra el comando, con el token del bot sólo en tu terminal:
      ```bash
      DISCORD_APP_ID=… DISCORD_GUILD_ID=… DISCORD_BOT_TOKEN=… node scripts/registrar-discord.mjs
      ```
5. **Primer lote**: `node tools/estado/estado.mjs lote` (desde la raíz del repo). Comprueba con
   `node tools/estado/estado.mjs ver` (sin nada publicado aún, sale vacío: es lo correcto).
6. **Prueba de humo** (en el móvil de pruebas, con Pear Dev): panel de pánico › *Ver estado* (tiene que enseñar 20
   cambios), nivel 1, ver el banner en la app pública, nivel 0. Queda en la auditoría.

Si el subdominio de workers.dev no es `8toxbox8-69a`, cambia la URL en `Incident.kt` (Android), `Incident.swift`
(iOS), `scripts/preparar-secretos.mjs` y este README.

## Estado

**Desplegado el 15-10-2026** (KV `ESTADO` = `013da6ec…`). Hecho: pasos 1 y 5 (`ADMIN_TOKEN` en
`~/.config/pear-music/estado.env`, primer lote de 20 cambios válido 30 días: **renovarlo antes del 14-11**). Sin
estado publicado `/estado` responde 204 y las apps siguen normal. Pasos 3 y 4 hechos el mismo día (app «Pear Music panico» 1560290517122687078, `/panico`
registrado, rol Admin Pear y canal privado #panico con el webhook de alertas; datos en
`~/.config/pear-music/discord-panico.env`). Falta (Toxbox): paso 2, `node scripts/preparar-secretos.mjs` (contraseña y TOTP).

## Probar sin desplegar

`npm test` (Node 20+): TOTP con los vectores del RFC 6238, contraseña, firmas, anti-rollback, reglas del nivel 3,
bloqueo por fallos y Discord, con un KV falso.
