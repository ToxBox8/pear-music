// Worker «pear-music-api» (ADR 0001): cuenta opcional con código al correo, biblioteca cifrada en el móvil
// (el servidor sólo guarda un blob que no puede leer) y telemetría con consentimiento.
// Bindings: DB (D1), RATE (KV), EMAIL (send_email). Secretos: EMAIL_KEY, EMAIL_HMAC. Variables: MAIL_FROM,
// PANEL_PUBLIC_KEY (llave de Pear Dev para el panel de telemetría) y PANEL_ORIGIN (la web).
import {
  decryptEmail, emailMac, encryptEmail, normalizeEmail, randomCode, randomToken, sameHex, sha256,
} from "./crypto.js";
import { FORZAR_EVERY_MS, RETENTION_DAYS, ordenVigente, panelAuthorized, panelSummary, telemetryProblem } from "./telemetry.js";
import {
  ACTIVOS_RETENTION_DAYS, FICHA_RETENTION_DAYS, activoProblem, countActivo, countDecision, decisionProblem, dispositivos,
  fichaProblem, saveFicha, today,
} from "./fichas.js";

export const LIMITS = {
  codeTtlMs: 10 * 60_000,
  codeTries: 5,
  codesPerEmailPerHour: 3,
  codesPerIpPerHour: 10,
  telemetryPerInstallPerHour: 6,
  fichasPerDevicePerHour: 10,
  activosPerIpPerHour: 30,
  libraryMaxBytes: 2_000_000, // base64 del blob cifrado
  bodyMaxBytes: 2_100_000,
};

const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,190}\.[a-z]{2,24}$/i;

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

/** Contador por hora en KV; true si ya se pasó del límite (y si no, lo sube). */
async function limited(env, key, max, now) {
  const k = `rl:${key}:${Math.floor(now / 3_600_000)}`;
  const n = parseInt((await env.RATE.get(k)) ?? "0", 10);
  if (n >= max) return true;
  await env.RATE.put(k, String(n + 1), { expirationTtl: 3700 });
  return false;
}

async function readJson(request) {
  const length = parseInt(request.headers.get("content-length") ?? "0", 10);
  if (length > LIMITS.bodyMaxBytes) return { error: json(413, { error: "Demasiado grande." }) };
  try {
    return { body: await request.json() };
  } catch {
    return { error: json(400, { error: "JSON mal formado." }) };
  }
}

/** La cuenta del token «Bearer», o null. */
async function session(env, request) {
  const auth = request.headers.get("authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!/^[a-f0-9]{64}$/.test(token)) return null;
  return env.DB.prepare("SELECT account_id FROM sessions WHERE token_hash = ?").bind(await sha256(token)).first("account_id");
}

async function sendCode(env, email, code) {
  await env.EMAIL.send({
    to: email,
    from: { email: env.MAIL_FROM, name: "Pear Music" },
    subject: `Tu código de Pear Music: ${code}`,
    text: `Tu código para entrar en Pear Music es ${code}.\n\nCaduca en 10 minutos. Si no lo has pedido tú, ignora este correo: nadie puede entrar sin él.`,
    html: `<p>Tu código para entrar en Pear Music es</p><p style="font-size:28px;font-weight:700;letter-spacing:4px">${code}</p><p>Caduca en 10 minutos. Si no lo has pedido tú, ignora este correo: nadie puede entrar sin él.</p>`,
  });
}

export async function handle(request, env, now = Date.now()) {
  const url = new URL(request.url);
  const route = `${request.method} ${url.pathname}`;
  const ip = request.headers.get("cf-connecting-ip") ?? "0";

  // Las apps sólo enseñan «Crear cuenta» si el servidor puede mandar el código (hay remitente configurado).
  if (route === "GET /v1/cuenta/disponible") return json(200, { available: !!(env.EMAIL && env.MAIL_FROM) });

  if (route === "POST /v1/cuenta/codigo") {
    if (!env.EMAIL || !env.MAIL_FROM) return json(503, { error: "Las cuentas aún no están disponibles." });
    const { body, error } = await readJson(request);
    if (error) return error;
    const email = normalizeEmail(body?.email);
    if (!EMAIL.test(email)) return json(400, { error: "El correo no es válido." });
    const mac = await emailMac(env, email);
    if ((await limited(env, `code:ip:${await sha256(ip)}`, LIMITS.codesPerIpPerHour, now)) ||
        (await limited(env, `code:mail:${mac}`, LIMITS.codesPerEmailPerHour, now))) {
      return json(429, { error: "Has pedido muchos códigos. Prueba dentro de una hora." });
    }
    const code = randomCode();
    await env.DB.prepare(
      "INSERT INTO codes (email_mac, code_hash, expires, tries) VALUES (?, ?, ?, 0) " +
      "ON CONFLICT(email_mac) DO UPDATE SET code_hash = excluded.code_hash, expires = excluded.expires, tries = 0",
    ).bind(mac, await sha256(`${mac}:${code}`), now + LIMITS.codeTtlMs).run();
    try {
      await sendCode(env, email, code);
    } catch {
      return json(502, { error: "No se pudo mandar el correo. Prueba más tarde." });
    }
    return json(200, { ok: true });
  }

  if (route === "POST /v1/cuenta/entrar") {
    const { body, error } = await readJson(request);
    if (error) return error;
    const email = normalizeEmail(body?.email);
    const code = String(body?.code ?? "");
    if (!EMAIL.test(email) || !/^\d{6}$/.test(code)) return json(400, { error: "Correo o código no válidos." });
    const mac = await emailMac(env, email);
    const row = await env.DB.prepare("SELECT code_hash, expires, tries FROM codes WHERE email_mac = ?").bind(mac).first();
    if (!row || row.expires < now || row.tries >= LIMITS.codeTries) {
      return json(400, { error: "El código ha caducado. Pide otro." });
    }
    if (!sameHex(row.code_hash, await sha256(`${mac}:${code}`))) {
      await env.DB.prepare("UPDATE codes SET tries = tries + 1 WHERE email_mac = ?").bind(mac).run();
      return json(400, { error: "El código no es correcto." });
    }
    await env.DB.prepare("DELETE FROM codes WHERE email_mac = ?").bind(mac).run();
    let id = await env.DB.prepare("SELECT id FROM accounts WHERE email_mac = ?").bind(mac).first("id");
    const created = !id;
    if (!id) {
      id = randomToken().slice(0, 32);
      await env.DB.prepare("INSERT INTO accounts (id, email_mac, email_enc, created) VALUES (?, ?, ?, ?)")
        .bind(id, mac, await encryptEmail(env, email), now).run();
    }
    const token = randomToken();
    await env.DB.prepare("INSERT INTO sessions (token_hash, account_id, created) VALUES (?, ?, ?)")
      .bind(await sha256(token), id, now).run();
    const hasLibrary = !!(await env.DB.prepare("SELECT 1 AS x FROM libraries WHERE account_id = ?").bind(id).first("x"));
    return json(200, { token, created, hasLibrary });
  }

  if (url.pathname.startsWith("/v1/cuenta")) {
    const account = await session(env, request);
    if (!account) return json(401, { error: "Vuelve a entrar en tu cuenta." });

    if (route === "GET /v1/cuenta") {
      const a = await env.DB.prepare("SELECT email_enc, created FROM accounts WHERE id = ?").bind(account).first();
      const lib = await env.DB.prepare("SELECT version, updated, length(blob) AS size FROM libraries WHERE account_id = ?").bind(account).first();
      return json(200, { email: await decryptEmail(env, a.email_enc), created: a.created, library: lib ?? null });
    }
    if (route === "GET /v1/cuenta/biblioteca") {
      const lib = await env.DB.prepare("SELECT blob, version, updated FROM libraries WHERE account_id = ?").bind(account).first();
      return lib ? json(200, lib) : json(404, { error: "No hay biblioteca guardada." });
    }
    if (route === "PUT /v1/cuenta/biblioteca") {
      const { body, error } = await readJson(request);
      if (error) return error;
      const blob = body?.blob;
      const base = Number.isInteger(body?.baseVersion) ? body.baseVersion : 0;
      if (typeof blob !== "string" || blob.length > LIMITS.libraryMaxBytes || !/^[A-Za-z0-9+/=]+$/.test(blob)) {
        return json(400, { error: "Biblioteca no válida." });
      }
      const current = (await env.DB.prepare("SELECT version FROM libraries WHERE account_id = ?").bind(account).first("version")) ?? 0;
      if (current !== base) return json(409, { error: "Hay una versión más nueva en otro móvil.", version: current });
      await env.DB.prepare(
        "INSERT INTO libraries (account_id, blob, version, updated) VALUES (?, ?, ?, ?) " +
        "ON CONFLICT(account_id) DO UPDATE SET blob = excluded.blob, version = excluded.version, updated = excluded.updated",
      ).bind(account, blob, current + 1, now).run();
      return json(200, { version: current + 1 });
    }
    if (route === "DELETE /v1/cuenta") {
      // Borrado inmediato de todo (RGPD, art. 17). D1 aplica ON DELETE CASCADE sólo con foreign_keys, así que
      // se borra explícito.
      await env.DB.batch([
        env.DB.prepare("DELETE FROM libraries WHERE account_id = ?").bind(account),
        env.DB.prepare("DELETE FROM sessions WHERE account_id = ?").bind(account),
        env.DB.prepare("DELETE FROM accounts WHERE id = ?").bind(account),
      ]);
      return json(200, { ok: true });
    }
    if (route === "POST /v1/cuenta/salir") {
      const token = request.headers.get("authorization").slice(7).trim();
      await env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(await sha256(token)).run();
      return json(200, { ok: true });
    }
    return json(404, { error: "No encontrado." });
  }

  if (route === "POST /v1/telemetria") {
    const { body, error } = await readJson(request);
    if (error) return error;
    const problem = telemetryProblem(body);
    if (problem) return json(400, { error: problem });
    if (await limited(env, `tel:${body.install}`, LIMITS.telemetryPerInstallPerHour, now)) return json(429, { error: "Demasiados informes." });
    await env.DB.prepare(
      "INSERT INTO telemetry (received, install, platform, channel, app_version, os_version, device_model, week, kind, sessions, startup_ms, fps_median, jank_percent, memory_mb, session_minutes) " +
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    ).bind(now, body.install, body.platform, body.channel, body.app_version, body.os_version ?? null, body.device_model ?? null,
      body.week, body.kind, body.sessions ?? null, body.startup_ms ?? null, body.fps_median ?? null, body.jank_percent ?? null, body.memory_mb ?? null, body.session_minutes ?? null).run();
    return json(202, { ok: true });
  }

  // Ficha del dispositivo: la app la manda al enviar un reporte o una sugerencia (el formulario lo avisa).
  if (route === "POST /v1/ficha") {
    const { body, error } = await readJson(request);
    if (error) return error;
    const problem = fichaProblem(body);
    if (problem) return json(400, { error: problem });
    if (await limited(env, `ficha:${body.ficha}`, LIMITS.fichasPerDevicePerHour, now)) return json(429, { error: "Demasiadas fichas." });
    await saveFicha(env.DB, body, now);
    return json(202, { ok: true });
  }

  // Instalaciones activas: cada app avisa una vez al día. Sólo se suma uno al contador; no se guarda nada más.
  if (route === "POST /v1/activo") {
    const { body, error } = await readJson(request);
    if (error) return error;
    const problem = activoProblem(body);
    if (problem) return json(400, { error: problem });
    if (await limited(env, `act:${request.headers.get("cf-connecting-ip") ?? "?"}`, LIMITS.activosPerIpPerHour, now)) return json(429, { error: "Demasiadas peticiones." });
    await countActivo(env.DB, body, now);
    // Si el panel ha pedido el resumen de esta semana, la app lo ve aquí (y sólo lo manda con consentimiento).
    return json(202, { ok: true, orden: await ordenVigente(env.DB, now) });
  }

  // Decisión sobre la telemetría (sí/no): sólo contadores, sin identificadores.
  if (route === "POST /v1/consentimiento") {
    const { body, error } = await readJson(request);
    if (error) return error;
    const problem = decisionProblem(body);
    if (problem) return json(400, { error: problem });
    if (await limited(env, `dec:${request.headers.get("cf-connecting-ip") ?? "?"}`, LIMITS.activosPerIpPerHour, now)) return json(429, { error: "Demasiadas peticiones." });
    await countDecision(env.DB, body);
    return json(202, { ok: true });
  }

  // Órdenes del panel (2.12 y 2.12.1 de x.1.1), con la misma llave que el panel: desde la web o desde Pear Dev.
  if (url.pathname === "/v1/telemetria/forzar" || url.pathname === "/v1/telemetria/reset") {
    const cors = {
      "access-control-allow-origin": env.PANEL_ORIGIN ?? "",
      "access-control-allow-headers": "authorization, content-type",
      "access-control-allow-methods": "POST",
      vary: "origin",
    };
    const out = async () => {
      if (request.method === "OPTIONS") return new Response(null, { status: 204 });
      if (request.method !== "POST") return json(405, { error: "Método no permitido." });
      if (await limited(env, `panel:${request.headers.get("cf-connecting-ip") ?? "?"}`, 60, now)) return json(429, { error: "Demasiadas peticiones." });
      if (!(await panelAuthorized(env, request.headers.get("authorization"), now))) return json(401, { error: "Conecta el móvil por USB y abre Pear Dev." });
      if (url.pathname.endsWith("/forzar")) {
        const last = await env.DB.prepare("SELECT at FROM ordenes WHERE kind = 'forzar' ORDER BY at DESC LIMIT 1").first("at");
        if (last && now - last < FORZAR_EVERY_MS) return json(429, { error: "Ya se pidió hace poco. Espera unos minutos." });
        const id = randomToken().slice(0, 16);
        await env.DB.prepare("INSERT INTO ordenes (id, kind, at) VALUES (?, 'forzar', ?)").bind(id, now).run();
        return json(200, { id, at: now });
      }
      // Reset: doble confirmación (la web y Pear Dev preguntan dos veces y mandan la palabra). Nunca toca las fichas.
      const { body, error } = await readJson(request);
      if (error) return error;
      if (body?.confirmar !== "BORRAR") return json(400, { error: "Falta confirmar." });
      const n = (await env.DB.prepare("SELECT count(*) AS n FROM telemetry").first("n")) ?? 0;
      await env.DB.batch([
        env.DB.prepare("DELETE FROM telemetry"),
        env.DB.prepare("INSERT INTO ordenes (id, kind, at, borradas) VALUES (?, 'reset', ?, ?)").bind(randomToken().slice(0, 16), now, n),
      ]);
      return json(200, { ok: true, borradas: n });
    };
    const r = await out();
    for (const [k, v] of Object.entries(cors)) r.headers.set(k, v);
    return r;
  }

  // Panel de telemetría (Fase 4b): sólo desde la web y con la llave que Pear Dev da por el cable.
  if (url.pathname === "/v1/telemetria/panel") {
    const cors = {
      "access-control-allow-origin": env.PANEL_ORIGIN ?? "",
      "access-control-allow-headers": "authorization",
      "access-control-allow-methods": "GET",
      vary: "origin",
    };
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (request.method !== "GET") return json(405, { error: "Método no permitido." });
    if (await limited(env, `panel:${request.headers.get("cf-connecting-ip") ?? "?"}`, 60, now)) return json(429, { error: "Demasiadas peticiones." });
    const ok = await panelAuthorized(env, request.headers.get("authorization"), now);
    const r = ok ? json(200, { ...(await panelSummary(env.DB)), dispositivos: await dispositivos(env.DB, now) }) : json(401, { error: "Conecta el móvil por USB y abre Pear Dev." });
    for (const [k, v] of Object.entries(cors)) r.headers.set(k, v);
    return r;
  }

  if (route === "DELETE /v1/telemetria") {
    // Retirar el consentimiento: la app manda su identificador y se borra todo lo suyo.
    const { body, error } = await readJson(request);
    if (error) return error;
    if (typeof body?.install !== "string" || !/^[a-f0-9]{32,64}$/.test(body.install)) return json(400, { error: "Identificador no válido." });
    await env.DB.batch([
      env.DB.prepare("DELETE FROM telemetry WHERE install = ?").bind(body.install),
      env.DB.prepare("UPDATE fichas SET install = NULL WHERE install = ?").bind(body.install),
    ]);
    return json(200, { ok: true });
  }

  return json(404, { error: "No encontrado." });
}

/** Limpieza diaria (cron): telemetría de más de 90 días y códigos caducados. */
export async function cleanup(env, now = Date.now()) {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM telemetry WHERE received < ?").bind(now - RETENTION_DAYS * 86_400_000),
    env.DB.prepare("DELETE FROM codes WHERE expires < ?").bind(now),
    env.DB.prepare("DELETE FROM fichas WHERE last_seen < ?").bind(now - FICHA_RETENTION_DAYS * 86_400_000),
    env.DB.prepare("DELETE FROM activos WHERE day < ?").bind(today(now - ACTIVOS_RETENTION_DAYS * 86_400_000)),
  ]);
}

export default {
  fetch: (request, env) => handle(request, env),
  scheduled: (_event, env, ctx) => ctx.waitUntil(cleanup(env)),
};
