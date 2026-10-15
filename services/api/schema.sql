-- Base D1 de pear-music-api (ADR 0001). Crear: npx wrangler d1 execute pear-music --file schema.sql
-- Ningún dato personal en claro: el correo va cifrado (email_enc) y se busca por HMAC (email_mac).

CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,               -- aleatorio
  email_mac TEXT NOT NULL UNIQUE,    -- HMAC-SHA256 del correo normalizado (para buscar)
  email_enc TEXT NOT NULL,           -- correo cifrado con AES-GCM (para poder mandar el código)
  created INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS codes (
  email_mac TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,           -- SHA-256 del código de 6 cifras
  expires INTEGER NOT NULL,
  tries INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,       -- SHA-256 del token; el token sólo lo tiene el móvil
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  created INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS libraries (
  account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  blob TEXT NOT NULL,                -- base64 de la biblioteca cifrada en el móvil (el servidor no puede leerla)
  version INTEGER NOT NULL,
  updated INTEGER NOT NULL
);

-- Telemetría: sin relación con las cuentas. Campos exactos en docs/TELEMETRIA.md. Se borra a los 90 días.
CREATE TABLE IF NOT EXISTS telemetry (
  received INTEGER NOT NULL,
  install TEXT NOT NULL,             -- identificador aleatorio de la instalación (se renueva al retirar el consentimiento)
  platform TEXT NOT NULL,
  channel TEXT NOT NULL,
  app_version TEXT NOT NULL,
  os_version TEXT,
  device_model TEXT,                 -- opcionales desde la Fase 4b (el envío manual de Pear Dev elige campos)
  week TEXT NOT NULL,                -- semana ISO del informe, «2026-W42» (Fase 4b: un informe por semana)
  kind TEXT NOT NULL,                -- «semanal» o «manual» (Pear Dev)
  sessions INTEGER,                  -- sesiones de esa semana
  startup_ms INTEGER,
  fps_median REAL,
  jank_percent REAL,
  memory_mb INTEGER,
  session_minutes INTEGER
);
CREATE INDEX IF NOT EXISTS telemetry_received ON telemetry(received);
CREATE INDEX IF NOT EXISTS telemetry_week ON telemetry(week);

-- Fichas de dispositivo (15-10-2026, lo pidió Toxbox): se crean al enviar un reporte o una sugerencia (el formulario
-- lo avisa). Para ver en el panel qué móvil tiene cada ticket y, si tiene la telemetría activada, cómo le va.
-- Se borran a los 180 días sin reportes nuevos.
CREATE TABLE IF NOT EXISTS fichas (
  id TEXT PRIMARY KEY,               -- SHA-256 del id anónimo del soporte (el mismo resumen que guarda libremusic-soporte)
  platform TEXT NOT NULL,
  channel TEXT NOT NULL,
  app_version TEXT NOT NULL,
  os_version TEXT,
  device_model TEXT,
  install TEXT,                      -- id de la telemetría, sólo si está activada en ese móvil (se quita al retirarla)
  tickets TEXT NOT NULL DEFAULT '[]',-- [{"n": 12, "kind": "error", "at": ms}], los 50 últimos
  first_seen INTEGER NOT NULL,
  last_seen INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS fichas_install ON fichas(install);

-- Instalaciones activas por día, versión y canal: sólo un contador (cada app avisa una vez al día), sin
-- identificadores ni IPs. Se borra a los 400 días.
CREATE TABLE IF NOT EXISTS activos (
  day TEXT NOT NULL,                 -- AAAA-MM-DD (UTC)
  platform TEXT NOT NULL,
  channel TEXT NOT NULL,
  app_version TEXT NOT NULL,
  n INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, platform, channel, app_version)
);

-- Decisiones sobre la telemetría (15-10-2026, lo pidió Toxbox: «cuántos han dicho que no»). Sólo contadores: cada
-- app manda su decisión al contestar (y, si cambia, la anterior para restarla). Sin identificadores ni IPs.
CREATE TABLE IF NOT EXISTS decisiones (
  platform TEXT NOT NULL,
  channel TEXT NOT NULL,
  decision TEXT NOT NULL,            -- «si» o «no»
  n INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (platform, channel, decision)
);
