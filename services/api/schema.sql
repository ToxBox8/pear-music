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
