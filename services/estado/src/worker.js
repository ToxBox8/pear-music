// Worker «pear-music-estado» (Fase 4): sirve el estado firmado (Ed25519) que leen las apps y deja publicar los
// estados PREFIRMADOS en el PC de Toxbox desde Pear Dev o Discord con contraseña + TOTP. No tiene la clave
// privada: no puede inventar un estado, sólo publicar uno firmado. Runbook: docs/RUNBOOK-INCIDENTES.md.
//
// Bindings: KV (ESTADO). Variables: PUBLIC_KEY (base64), DISCORD_ADMIN_ROLE, DISCORD_ADMIN_CHANNEL.
// Secretos: ADMIN_TOKEN (subida desde el PC), PANIC_PASSWORD (salt:hash de PBKDF2), TOTP_SECRET (base32),
// ALERT_WEBHOOK (canal de administración), DISCORD_PUBLIC_KEY (hex, de la aplicación de Discord).
import { checkPassword, totpStep } from "./totp.js";

export const RULES = {
  cooldownMs: 5 * 60_000, // entre cambios de estado
  lockConfirmMs: 10 * 60_000, // nivel 3: segundo TOTP pasados 10 min
  pendingTtlMs: 60 * 60_000, // la petición de nivel 3 caduca en 1 h
  failsPerHour: 5,
  auditKeep: 200,
};
export const LEVELS = { 0: "Normal", 1: "Aviso", 2: "Modo seguro", 3: "Bloqueo total" };

const json = (status, body, headers = {}) =>
  new Response(body === null ? null : JSON.stringify(body), {
    status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });

const b64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const hex = (s) => new Uint8Array(String(s).match(/../g).map((h) => parseInt(h, 16)));

/** ¿Está bien firmado por la clave del PC? Devuelve el contenido o null. */
export async function verifyEnvelope(env, e) {
  try {
    const key = await crypto.subtle.importKey("raw", b64(env.PUBLIC_KEY), { name: "Ed25519" }, false, ["verify"]);
    const ok = await crypto.subtle.verify({ name: "Ed25519" }, key, b64(e.sig), new TextEncoder().encode(e.payload));
    return ok ? JSON.parse(e.payload) : null;
  } catch {
    return null;
  }
}

async function getJSON(env, k, def = null) {
  const v = await env.ESTADO.get(k);
  return v ? JSON.parse(v) : def;
}
const putJSON = (env, k, v) => env.ESTADO.put(k, JSON.stringify(v));

async function audit(env, entry, now) {
  const list = await getJSON(env, "audit", []);
  list.unshift({ at: new Date(now).toISOString(), ...entry });
  await putJSON(env, "audit", list.slice(0, RULES.auditKeep));
  if (env.ALERT_WEBHOOK) {
    const text = `🚨 Pánico · ${entry.action}${entry.level != null ? ` · nivel ${entry.level} (${LEVELS[entry.level]})` : ""} · vía ${entry.via}${entry.who ? ` (${entry.who})` : ""}${entry.ok === false ? " · RECHAZADO" : ""}${entry.note ? ` · ${entry.note}` : ""}`;
    await fetch(env.ALERT_WEBHOOK, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ content: text, allowed_mentions: { parse: [] } }) }).catch(() => {});
  }
}

/** Contraseña + TOTP, con bloqueo tras 5 fallos en una hora. Devuelve el paso TOTP o un error. */
async function authenticate(env, body, now) {
  const hourKey = `fails:${Math.floor(now / 3_600_000)}`;
  const fails = parseInt((await env.ESTADO.get(hourKey)) ?? "0", 10);
  if (fails >= RULES.failsPerHour) return { error: json(429, { error: "Demasiados intentos fallidos. Espera una hora." }) };
  const step = (await checkPassword(body?.password, env.PANIC_PASSWORD)) ? await totpStep(env.TOTP_SECRET, body?.totp, now) : null;
  if (step == null) {
    await env.ESTADO.put(hourKey, String(fails + 1), { expirationTtl: 3700 });
    return { error: json(401, { error: "Contraseña o código incorrectos." }), failed: true };
  }
  return { step };
}

/** Publica el siguiente sobre prefirmado de ese nivel (contador mayor que el publicado). */
async function publishLevel(env, level, now) {
  const batch = await getJSON(env, "batch");
  if (!batch || batch.expiresAt * 1000 < now) return { error: "No hay estados prefirmados vigentes: renueva el lote desde el PC." };
  const current = await getJSON(env, "current");
  const curCounter = current ? JSON.parse(current.payload).counter : 0;
  for (const slot of batch.slots) {
    const e = slot[level];
    const p = JSON.parse(e.payload);
    if (p.counter > curCounter) {
      await putJSON(env, "current", e);
      await env.ESTADO.put("lastChange", String(now));
      const left = batch.slots.filter((s) => JSON.parse(s[0].payload).counter > p.counter).length;
      return { published: p, left };
    }
  }
  return { error: "Se han gastado todos los cambios del lote: renueva el lote desde el PC." };
}

/** El corazón del botón de pánico, igual para Pear Dev y Discord. */
export async function panic(env, { action, level, password, totp, via, who }, now = Date.now()) {
  const auth = await authenticate(env, { password, totp }, now);
  if (auth.error) {
    if (auth.failed) await audit(env, { action: action ?? "activar", level, via, who, ok: false, note: "credenciales" }, now);
    return auth.error;
  }
  if (action === "cancelar") {
    await env.ESTADO.delete("pending3");
    await audit(env, { action: "cancelar bloqueo", via, who }, now);
    return json(200, { ok: true, message: "Petición de bloqueo cancelada." });
  }
  if (action === "confirmar") {
    const pending = await getJSON(env, "pending3");
    if (!pending || now - pending.requestedAt > RULES.pendingTtlMs) return json(404, { error: "No hay ningún bloqueo pendiente (o caducó)." });
    if (now - pending.requestedAt < RULES.lockConfirmMs) {
      return json(425, { error: `Aún no: el bloqueo se confirma a partir de ${new Date(pending.requestedAt + RULES.lockConfirmMs).toISOString()}.` });
    }
    if (auth.step === pending.step) return json(400, { error: "Usa un código nuevo, distinto del de la petición." });
    const r = await publishLevel(env, 3, now);
    await env.ESTADO.delete("pending3");
    await audit(env, { action: "confirmar bloqueo", level: 3, via, who, ok: !r.error, note: r.error }, now);
    return r.error ? json(409, { error: r.error }) : json(200, { ok: true, level: 3, left: r.left });
  }
  if (![0, 1, 2, 3].includes(level)) return json(400, { error: "Nivel no válido." });
  const last = parseInt((await env.ESTADO.get("lastChange")) ?? "0", 10);
  if (now - last < RULES.cooldownMs) return json(429, { error: "Hace muy poco del último cambio. Espera unos minutos." });
  if (level === 3) {
    await putJSON(env, "pending3", { requestedAt: now, step: auth.step, via, who });
    await audit(env, { action: "pedir bloqueo", level: 3, via, who, note: "confirmar en 10 min con otro código" }, now);
    return json(202, { pending: true, confirmAfter: new Date(now + RULES.lockConfirmMs).toISOString() });
  }
  const r = await publishLevel(env, level, now);
  await audit(env, { action: "activar", level, via, who, ok: !r.error, note: r.error }, now);
  return r.error ? json(409, { error: r.error }) : json(200, { ok: true, level, left: r.left });
}

// MARK: Discord (comando /panico, sólo rol de administración y canal privado; contraseña y código en un modal)

async function discordSigned(env, request, body) {
  try {
    const key = await crypto.subtle.importKey("raw", hex(env.DISCORD_PUBLIC_KEY), { name: "Ed25519" }, false, ["verify"]);
    const sig = hex(request.headers.get("x-signature-ed25519") ?? "");
    const ts = request.headers.get("x-signature-timestamp") ?? "";
    return await crypto.subtle.verify({ name: "Ed25519" }, key, sig, new TextEncoder().encode(ts + body));
  } catch {
    return false;
  }
}

const ephemeral = (content) => json(200, { type: 4, data: { content, flags: 64 } });

export async function discord(env, request, now = Date.now()) {
  const raw = await request.text();
  if (!(await discordSigned(env, request, raw))) return new Response("Firma no válida", { status: 401 });
  const i = JSON.parse(raw);
  if (i.type === 1) return json(200, { type: 1 });
  const roles = i.member?.roles ?? [];
  const who = i.member?.user?.username ?? "?";
  if (i.channel_id !== env.DISCORD_ADMIN_CHANNEL || !roles.includes(env.DISCORD_ADMIN_ROLE)) {
    await audit(env, { action: "discord sin permiso", via: "discord", who, ok: false }, now);
    return ephemeral("Este comando sólo se puede usar en el canal de administración y con el rol de administración.");
  }
  if (i.type === 2 && i.data?.name === "panico") {
    const choice = i.data.options?.find((o) => o.name === "accion")?.value ?? "1";
    return json(200, {
      type: 9,
      data: {
        custom_id: `panico:${choice}`,
        title: choice === "confirmar" ? "Confirmar bloqueo total" : choice === "cancelar" ? "Cancelar bloqueo" : `Pánico: ${LEVELS[choice] ?? "?"}`,
        components: [
          { type: 1, components: [{ type: 4, custom_id: "password", label: "Contraseña", style: 1, min_length: 8, max_length: 200, required: true }] },
          { type: 1, components: [{ type: 4, custom_id: "totp", label: "Código de 6 cifras (app de autenticación)", style: 1, min_length: 6, max_length: 6, required: true }] },
        ],
      },
    });
  }
  if (i.type === 5 && String(i.data?.custom_id).startsWith("panico:")) {
    const choice = i.data.custom_id.slice(7);
    const field = (id) => i.data.components.flatMap((r) => r.components).find((c) => c.custom_id === id)?.value;
    const action = ["confirmar", "cancelar"].includes(choice) ? choice : "activar";
    const r = await panic(env, { action, level: Number(choice), password: field("password"), totp: field("totp"), via: "discord", who }, now);
    const body = await r.json();
    return ephemeral(body.error ? `❌ ${body.error}` : body.pending ? `⏳ Bloqueo pedido. Confírmalo con /panico accion:confirmar a partir de ${body.confirmAfter} (con otro código).` : `✅ Hecho. Quedan ${body.left ?? "?"} cambios en el lote.`);
  }
  return ephemeral("Comando desconocido.");
}

// MARK: HTTP

export async function handle(request, env, now = Date.now()) {
  const url = new URL(request.url);
  const route = `${request.method} ${url.pathname}`;
  if (route === "GET /estado") {
    const current = await getJSON(env, "current");
    // Sin estado publicado: 204 y las apps siguen normal (fallan en abierto).
    return current ? json(200, current, { "cache-control": "public, max-age=60" }) : json(204, null);
  }
  if (route === "POST /discord") return discord(env, request, now);
  if (route === "POST /panico" || route === "POST /panico/confirmar" || route === "POST /panico/cancelar") {
    let body;
    try { body = await request.json(); } catch { return json(400, { error: "JSON mal formado." }); }
    const action = url.pathname.endsWith("confirmar") ? "confirmar" : url.pathname.endsWith("cancelar") ? "cancelar" : "activar";
    return panic(env, { ...body, action, via: "pear-dev" }, now);
  }
  if (route === "POST /panico/info") {
    let body;
    try { body = await request.json(); } catch { return json(400, { error: "JSON mal formado." }); }
    const auth = await authenticate(env, body, now);
    if (auth.error) return auth.error;
    const current = await getJSON(env, "current");
    const batch = await getJSON(env, "batch");
    const curCounter = current ? JSON.parse(current.payload).counter : 0;
    return json(200, {
      level: current ? JSON.parse(current.payload).level : 0,
      pending: await getJSON(env, "pending3"),
      batchExpiresAt: batch?.expiresAt ?? null,
      left: batch ? batch.slots.filter((s) => JSON.parse(s[0].payload).counter > curCounter).length : 0,
      audit: (await getJSON(env, "audit", [])).slice(0, 20),
    });
  }
  // Desde el PC (token de subida): sólo se aceptan sobres bien firmados por la clave del PC.
  if (route === "POST /admin/lote" || route === "POST /admin/publicar") {
    if (!env.ADMIN_TOKEN || request.headers.get("authorization") !== `Bearer ${env.ADMIN_TOKEN}`) return json(401, { error: "No autorizado." });
    const body = await request.json();
    const envelopes = route.endsWith("lote") ? (body.slots ?? []).flat() : [body];
    for (const e of envelopes) if (!(await verifyEnvelope(env, e))) return json(400, { error: "Hay un estado mal firmado: no se ha guardado nada." });
    if (route.endsWith("lote")) {
      await putJSON(env, "batch", { slots: body.slots, expiresAt: body.expiresAt });
      await audit(env, { action: "nuevo lote", via: "pc", note: `${body.slots.length} cambios` }, now);
      return json(200, { ok: true, slots: body.slots.length });
    }
    const p = JSON.parse(body.payload);
    const current = await getJSON(env, "current");
    if (current && JSON.parse(current.payload).counter >= p.counter) return json(409, { error: "Contador viejo: firma uno nuevo." });
    await putJSON(env, "current", body);
    await env.ESTADO.put("lastChange", String(now));
    await audit(env, { action: "publicar firmado", level: p.level, via: "pc" }, now);
    return json(200, { ok: true, level: p.level });
  }
  return json(404, { error: "No encontrado." });
}

export default { fetch: (request, env) => handle(request, env) };
