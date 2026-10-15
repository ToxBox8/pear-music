// Fichas de dispositivo y recuento de instalaciones activas (15-10-2026, lo pidió Toxbox). Docs: docs/TELEMETRIA.md.
// Igual que la telemetría: lista cerrada de campos; cualquier otro rechaza la petición entera.

const hex = (min, max) => (v) => typeof v === "string" && new RegExp(`^[a-f0-9]{${min},${max}}$`).test(v);
const COMMON = {
  platform: (v) => v === "ios" || v === "android",
  channel: (v) => v === "usr" || v === "pref" || v === "dev",
  app_version: (v) => typeof v === "string" && /^[0-9A-Za-z.+-]{1,32}$/.test(v),
};

export const FICHA_FIELDS = {
  ...COMMON,
  ficha: hex(64, 64),
  os_version: (v) => v == null || (typeof v === "string" && v.length <= 32),
  device_model: (v) => v == null || (typeof v === "string" && v.length <= 64),
  install: (v) => v == null || hex(32, 64)(v),
  ticket: (v) => Number.isInteger(v) && v > 0 && v < 10_000_000,
  kind: (v) => v === "error" || v === "sugerencia",
};
const FICHA_REQUIRED = ["ficha", "platform", "channel", "app_version", "ticket", "kind"];

function problem(body, fields, required) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return "Petición mal formada.";
  for (const key of Object.keys(body)) if (!(key in fields)) return `Campo no permitido: ${key}`;
  for (const key of required) if (body[key] == null) return `Falta ${key}`;
  for (const [key, ok] of Object.entries(fields)) if (!ok(body[key])) return `Valor no válido en ${key}`;
  return null;
}

export const fichaProblem = (body) => problem(body, FICHA_FIELDS, FICHA_REQUIRED);

const DECISION = (v) => v === "si" || v === "no";
export const DECISION_FIELDS = { ...COMMON, decision: DECISION, antes: (v) => v == null || DECISION(v) };
export const decisionProblem = (body) => problem(body, DECISION_FIELDS, [...Object.keys(COMMON), "decision"]);

/** Suma la decisión y, si cambió, resta la anterior (sin bajar de cero). */
export async function countDecision(db, b) {
  const stmts = [
    db.prepare(
      "INSERT INTO decisiones (platform, channel, decision, n) VALUES (?, ?, ?, 1) " +
      "ON CONFLICT (platform, channel, decision) DO UPDATE SET n = n + 1",
    ).bind(b.platform, b.channel, b.decision),
  ];
  if (b.antes && b.antes !== b.decision) {
    stmts.push(db.prepare("UPDATE decisiones SET n = max(n - 1, 0) WHERE platform = ? AND channel = ? AND decision = ?")
      .bind(b.platform, b.channel, b.antes));
  }
  await db.batch(stmts);
}
export const activoProblem = (body) => problem(body, COMMON, Object.keys(COMMON));

export const FICHA_RETENTION_DAYS = 180;
export const ACTIVOS_RETENTION_DAYS = 400;
const MAX_TICKETS = 50;

/** Crea o pone al día la ficha y le añade el ticket. */
export async function saveFicha(db, b, now) {
  const old = await db.prepare("SELECT tickets, first_seen FROM fichas WHERE id = ?").bind(b.ficha).first();
  const tickets = old ? JSON.parse(old.tickets) : [];
  if (!tickets.some((t) => t.n === b.ticket)) tickets.push({ n: b.ticket, kind: b.kind, at: now });
  await db.prepare(
    "INSERT OR REPLACE INTO fichas (id, platform, channel, app_version, os_version, device_model, install, tickets, first_seen, last_seen) " +
    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
  ).bind(b.ficha, b.platform, b.channel, b.app_version, b.os_version ?? null, b.device_model ?? null, b.install ?? null,
    JSON.stringify(tickets.slice(-MAX_TICKETS)), old?.first_seen ?? now, now).run();
}

export const today = (now) => new Date(now).toISOString().slice(0, 10);

export async function countActivo(db, b, now) {
  await db.prepare(
    "INSERT INTO activos (day, platform, channel, app_version, n) VALUES (?, ?, ?, ?, 1) " +
    "ON CONFLICT (day, platform, channel, app_version) DO UPDATE SET n = n + 1",
  ).bind(today(now), b.platform, b.channel, b.app_version).run();
}

/** Para el panel: activos de los últimos 30 días, el reparto del último día y las fichas (sin el id de telemetría). */
export async function dispositivos(db, now) {
  const all = async (sql, ...args) => (await db.prepare(sql).bind(...args).all()).results;
  const desde = today(now - 30 * 86_400_000);
  const fichas = await all(
    "SELECT substr(f.id, 1, 10) AS id, f.platform, f.channel, f.app_version, f.os_version, f.device_model, f.tickets, " +
    "f.first_seen, f.last_seen, (f.install IS NOT NULL) AS telemetria, t.week, t.startup_ms, t.fps_median, t.jank_percent, t.memory_mb " +
    "FROM fichas f LEFT JOIN telemetry t ON t.rowid = (SELECT rowid FROM telemetry WHERE install = f.install ORDER BY received DESC LIMIT 1) " +
    "ORDER BY f.last_seen DESC LIMIT 500",
  );
  // Historial de telemetría de cada perfil que la tiene (12 últimos informes), sin el identificador.
  const historial = await all(
    "SELECT substr(f.id, 1, 10) AS id, t.received, t.week, t.kind, t.app_version, t.sessions, t.startup_ms, t.fps_median, " +
    "t.jank_percent, t.memory_mb, t.session_minutes FROM fichas f JOIN telemetry t ON t.install = f.install " +
    "ORDER BY t.received DESC LIMIT 2000",
  );
  const porFicha = {};
  for (const h of historial) {
    const { id, ...rest } = h;
    (porFicha[id] ??= []).length < 12 && porFicha[id].push(rest);
  }
  return {
    activosPorDia: await all(
      "SELECT day, sum(n) AS total, sum(CASE WHEN platform = 'android' THEN n ELSE 0 END) AS android, " +
      "sum(CASE WHEN platform = 'ios' THEN n ELSE 0 END) AS ios FROM activos WHERE day >= ? GROUP BY day ORDER BY day DESC", desde),
    activosHoy: await all(
      "SELECT platform, channel, app_version, n FROM activos WHERE day = (SELECT max(day) FROM activos) ORDER BY n DESC"),
    fichas: fichas.map((f) => ({ ...f, telemetria: !!f.telemetria, tickets: JSON.parse(f.tickets), historial: porFicha[f.id] ?? [] })),
    decisiones: await all("SELECT platform, channel, decision, n FROM decisiones ORDER BY platform, channel, decision"),
  };
}
