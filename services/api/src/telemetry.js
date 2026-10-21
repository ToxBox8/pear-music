// Telemetría (ADR 0001, docs/TELEMETRIA.md). Lista cerrada de campos: cualquier otro hace que se rechace el
// informe entero, así una versión de la app no puede mandar de más sin que se note.

export const FIELDS = {
  install: (v) => typeof v === "string" && /^[a-f0-9]{32,64}$/.test(v),
  platform: (v) => v === "ios" || v === "android",
  channel: (v) => v === "usr" || v === "pref" || v === "dev",
  app_version: (v) => typeof v === "string" && /^[0-9A-Za-z.+-]{1,32}$/.test(v),
  os_version: (v) => v == null || (typeof v === "string" && v.length <= 32),
  device_model: (v) => v == null || (typeof v === "string" && v.length <= 64),
  week: (v) => typeof v === "string" && /^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$/.test(v),
  // «forzado» (2.12 de x.1.1): la semana en curso, porque el panel lo pidió.
  kind: (v) => v === "semanal" || v === "manual" || v === "forzado",
  sessions: (v) => v == null || (Number.isInteger(v) && v >= 0 && v < 10_000),
  startup_ms: (v) => v == null || (Number.isInteger(v) && v >= 0 && v < 120_000),
  fps_median: (v) => v == null || (typeof v === "number" && v >= 0 && v <= 240),
  jank_percent: (v) => v == null || (typeof v === "number" && v >= 0 && v <= 100),
  memory_mb: (v) => v == null || (Number.isInteger(v) && v >= 0 && v < 65_536),
  session_minutes: (v) => v == null || (Number.isInteger(v) && v >= 0 && v < 1_440),
};

// Fase 4b: un informe por semana (agregado en el móvil) o uno «manual» desde Pear Dev con los campos que elija
// Toxbox; por eso sólo lo mínimo es obligatorio.
const REQUIRED = ["install", "platform", "channel", "app_version", "week", "kind"];

/** null si vale, o el motivo del rechazo. */
export function telemetryProblem(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return "Informe mal formado.";
  for (const key of Object.keys(body)) if (!(key in FIELDS)) return `Campo no permitido: ${key}`;
  for (const key of REQUIRED) if (body[key] == null) return `Falta ${key}`;
  for (const [key, ok] of Object.entries(FIELDS)) if (!ok(body[key])) return `Valor no válido en ${key}`;
  return null;
}

export const RETENTION_DAYS = 90;

// MARK: Panel (Fase 4b). Sólo con una llave firmada por Pear Dev, que la da por el cable USB (adb forward):
// `Authorization: Panel <payload base64url>.<firma base64url>`, payload {"exp": ms, "n": "…"}, Ed25519 con la clave
// pública PANEL_PUBLIC_KEY. Caduca en 5 min; sin el móvil enchufado no hay llave.

const b64u = (s) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), (c) => c.charCodeAt(0));
export const PANEL_MAX_MS = 10 * 60_000;

export async function panelAuthorized(env, header, now = Date.now()) {
  try {
    if (!env.PANEL_PUBLIC_KEY || !header?.startsWith("Panel ")) return false;
    const [payload, sig] = header.slice(6).trim().split(".");
    const key = await crypto.subtle.importKey("raw", b64u(env.PANEL_PUBLIC_KEY), { name: "Ed25519" }, false, ["verify"]);
    if (!(await crypto.subtle.verify({ name: "Ed25519" }, key, b64u(sig), b64u(payload)))) return false;
    const { exp } = JSON.parse(new TextDecoder().decode(b64u(payload)));
    return Number.isFinite(exp) && exp > now && exp - now <= PANEL_MAX_MS;
  } catch {
    return false;
  }
}

/** Resumen para el panel: por semana, versión y modelo, y los últimos informes (sin el identificador). */
export async function panelSummary(db) {
  const all = async (sql) => (await db.prepare(sql).all()).results;
  const avg = "round(avg(startup_ms)) AS startup_ms, round(avg(fps_median), 1) AS fps, round(avg(jank_percent), 1) AS jank, round(avg(memory_mb)) AS memory_mb";
  return {
    weeks: await all(`SELECT week, count(DISTINCT install) AS installs, count(*) AS reports, sum(platform = 'android') AS android, sum(platform = 'ios') AS ios, sum(sessions) AS sessions, ${avg}, round(avg(session_minutes)) AS minutes FROM telemetry GROUP BY week ORDER BY week DESC LIMIT 12`),
    versions: await all("SELECT platform, channel, app_version, count(DISTINCT install) AS installs FROM telemetry GROUP BY platform, channel, app_version ORDER BY installs DESC LIMIT 30"),
    devices: await all(`SELECT platform, device_model, count(DISTINCT install) AS installs, ${avg} FROM telemetry WHERE device_model IS NOT NULL GROUP BY platform, device_model ORDER BY installs DESC LIMIT 20`),
    latest: await all("SELECT received, kind, week, platform, channel, app_version, os_version, device_model, sessions, startup_ms, fps_median, jank_percent, memory_mb, session_minutes FROM telemetry ORDER BY received DESC LIMIT 30"),
    // Órdenes del panel y cuántas apps han respondido a cada «forzar» (2.12 de x.1.1).
    ordenes: await all("SELECT o.id, o.kind, o.at, o.borradas, (SELECT count(*) FROM telemetry t WHERE o.kind = 'forzar' AND t.kind = 'forzado' AND t.received >= o.at) AS respuestas FROM ordenes o ORDER BY o.at DESC LIMIT 10"),
  };
}

/** Entre dos «forzar», al menos esto (para no tirar del panel sin querer). */
export const FORZAR_EVERY_MS = 10 * 60_000;
/** Las apps atienden un «forzar» durante una semana (lo ven en su latido diario). */
export const ORDEN_TTL_MS = 7 * 86_400_000;

/** El último «forzar» vigente, o null. */
export async function ordenVigente(db, now) {
  return db.prepare("SELECT id FROM ordenes WHERE kind = 'forzar' AND at > ? ORDER BY at DESC LIMIT 1").bind(now - ORDEN_TTL_MS).first("id");
}
