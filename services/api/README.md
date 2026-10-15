# pear-music-api

Worker de la cuenta opcional, la biblioteca cifrada y la telemetría (ADR `docs/adr/0001-cuenta-telemetria-actualizaciones.md`,
campos de telemetría en `docs/TELEMETRIA.md`).

**Desplegado el 14-10-2026 sin correo** (Fase 4b): D1 `pear-music` en Europa occidental, KV `pear-music-api-rate`,
secretos `EMAIL_KEY`/`EMAIL_HMAC` (copia en `~/.config/pear-music/api-secretos.env`, 600: **guárdala en tu gestor**).
La telemetría y el panel funcionan; las cuentas siguen «muy pronto» hasta que haya dominio (`MAIL_FROM`).

## Probar

```bash
npm test          # node --test, con D1 sobre el SQLite de Node y KV/correo de mentira
```

## Activar las cuentas (cuando haya dominio)

Ya están hechos los pasos 2–5; falta el 1 y volver a desplegar.

1. Dar de alta el dominio en Cloudflare Email Service (`npx wrangler email sending enable tudominio.es`) y poner
   `MAIL_FROM = "hola@tudominio.es"` en `wrangler.toml`.
2. Base de datos en Europa occidental (lo dice la política de privacidad):
   `npx wrangler d1 create pear-music --location weur` → pegar el id; `npx wrangler d1 execute pear-music --remote --file schema.sql`.
3. `npx wrangler kv namespace create RATE` → pegar el id.
4. Secretos (nunca en el repo):
   `openssl rand -base64 32 | npx wrangler secret put EMAIL_KEY` y `openssl rand -hex 32 | npx wrangler secret put EMAIL_HMAC`.
   **Perder `EMAIL_KEY` deja ilegibles los correos guardados** (habría que volver a entrar con código): guárdala también fuera.
5. `npx wrangler deploy`. Comprobar `curl https://pear-music-api.<cuenta>.workers.dev/v1/cuenta/disponible` → `{"available":true}`.

Hasta entonces las apps enseñan «Las cuentas estarán disponibles muy pronto».

## Panel de telemetría (Fase 4b)

`GET /v1/telemetria/panel` sólo con `Authorization: Panel <payload>.<firma>` firmada por Pear Dev (Ed25519, ≤ 10 min)
y CORS sólo para `PANEL_ORIGIN`. La clave pública va en `PANEL_PUBLIC_KEY` (`wrangler.toml`): Pear Dev › Administración
› «Copiar clave pública». Cómo se usa: `docs/TELEMETRIA.md`.
