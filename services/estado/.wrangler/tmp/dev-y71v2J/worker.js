var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/totp.js
var enc = new TextEncoder();
function base32Decode(s) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const clean = String(s).toUpperCase().replace(/[^A-Z2-7]/g, "");
  let bits = 0, value = 0;
  const out = [];
  for (const ch of clean) {
    value = value << 5 | alphabet.indexOf(ch);
    bits += 5;
    if (bits >= 8) {
      out.push(value >>> bits - 8 & 255);
      bits -= 8;
    }
  }
  return new Uint8Array(out);
}
__name(base32Decode, "base32Decode");
async function totpAt(secretB32, step) {
  const key = await crypto.subtle.importKey("raw", base32Decode(secretB32), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const msg = new Uint8Array(8);
  let s = step;
  for (let i = 7; i >= 0; i--) {
    msg[i] = s & 255;
    s = Math.floor(s / 256);
  }
  const h = new Uint8Array(await crypto.subtle.sign("HMAC", key, msg));
  const o = h[19] & 15;
  const n = (h[o] & 127) << 24 | h[o + 1] << 16 | h[o + 2] << 8 | h[o + 3];
  return String(n % 1e6).padStart(6, "0");
}
__name(totpAt, "totpAt");
async function totpStep(secretB32, code, now = Date.now()) {
  if (!/^\d{6}$/.test(String(code ?? ""))) return null;
  const step = Math.floor(now / 3e4);
  for (const d of [0, -1, 1]) if (await totpAt(secretB32, step + d) === code) return step + d;
  return null;
}
__name(totpStep, "totpStep");
async function hashPassword(password, saltB64) {
  const salt = saltB64 ? Uint8Array.from(atob(saltB64), (c) => c.charCodeAt(0)) : crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = new Uint8Array(await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations: 1e5 }, key, 256));
  const b642 = /* @__PURE__ */ __name((u) => btoa(String.fromCharCode(...u)), "b64");
  return `${b642(salt)}:${b642(bits)}`;
}
__name(hashPassword, "hashPassword");
async function checkPassword(password, stored) {
  const [salt, hash] = String(stored ?? "").split(":");
  if (!salt || !hash || typeof password !== "string" || password.length > 200) return false;
  const again = (await hashPassword(password, salt)).split(":")[1];
  if (again.length !== hash.length) return false;
  let diff = 0;
  for (let i = 0; i < hash.length; i++) diff |= again.charCodeAt(i) ^ hash.charCodeAt(i);
  return diff === 0;
}
__name(checkPassword, "checkPassword");

// src/worker.js
var RULES = {
  cooldownMs: 5 * 6e4,
  // entre cambios de estado
  lockConfirmMs: 10 * 6e4,
  // nivel 3: segundo TOTP pasados 10 min
  pendingTtlMs: 60 * 6e4,
  // la petición de nivel 3 caduca en 1 h
  failsPerHour: 5,
  auditKeep: 200
};
var LEVELS = { 0: "Normal", 1: "Aviso", 2: "Modo seguro", 3: "Bloqueo total" };
var json = /* @__PURE__ */ __name((status, body, headers = {}) => new Response(body === null ? null : JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers }
}), "json");
var b64 = /* @__PURE__ */ __name((s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0)), "b64");
var hex = /* @__PURE__ */ __name((s) => new Uint8Array(String(s).match(/../g).map((h) => parseInt(h, 16))), "hex");
async function verifyEnvelope(env, e) {
  try {
    const key = await crypto.subtle.importKey("raw", b64(env.PUBLIC_KEY), { name: "Ed25519" }, false, ["verify"]);
    const ok = await crypto.subtle.verify({ name: "Ed25519" }, key, b64(e.sig), new TextEncoder().encode(e.payload));
    return ok ? JSON.parse(e.payload) : null;
  } catch {
    return null;
  }
}
__name(verifyEnvelope, "verifyEnvelope");
async function getJSON(env, k, def = null) {
  const v = await env.ESTADO.get(k);
  return v ? JSON.parse(v) : def;
}
__name(getJSON, "getJSON");
var putJSON = /* @__PURE__ */ __name((env, k, v) => env.ESTADO.put(k, JSON.stringify(v)), "putJSON");
async function audit(env, entry, now) {
  const list = await getJSON(env, "audit", []);
  list.unshift({ at: new Date(now).toISOString(), ...entry });
  await putJSON(env, "audit", list.slice(0, RULES.auditKeep));
  if (env.ALERT_WEBHOOK) {
    const text = `\u{1F6A8} P\xE1nico \xB7 ${entry.action}${entry.level != null ? ` \xB7 nivel ${entry.level} (${LEVELS[entry.level]})` : ""} \xB7 v\xEDa ${entry.via}${entry.who ? ` (${entry.who})` : ""}${entry.ok === false ? " \xB7 RECHAZADO" : ""}${entry.note ? ` \xB7 ${entry.note}` : ""}`;
    await fetch(env.ALERT_WEBHOOK, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ content: text, allowed_mentions: { parse: [] } }) }).catch(() => {
    });
  }
}
__name(audit, "audit");
async function authenticate(env, body, now) {
  const hourKey = `fails:${Math.floor(now / 36e5)}`;
  const fails = parseInt(await env.ESTADO.get(hourKey) ?? "0", 10);
  if (fails >= RULES.failsPerHour) return { error: json(429, { error: "Demasiados intentos fallidos. Espera una hora." }) };
  const step = await checkPassword(body?.password, env.PANIC_PASSWORD) ? await totpStep(env.TOTP_SECRET, body?.totp, now) : null;
  if (step == null) {
    await env.ESTADO.put(hourKey, String(fails + 1), { expirationTtl: 3700 });
    return { error: json(401, { error: "Contrase\xF1a o c\xF3digo incorrectos." }), failed: true };
  }
  return { step };
}
__name(authenticate, "authenticate");
async function publishLevel(env, level, now) {
  const batch = await getJSON(env, "batch");
  if (!batch || batch.expiresAt * 1e3 < now) return { error: "No hay estados prefirmados vigentes: renueva el lote desde el PC." };
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
__name(publishLevel, "publishLevel");
async function panic(env, { action, level, password, totp, via, who }, now = Date.now()) {
  const auth = await authenticate(env, { password, totp }, now);
  if (auth.error) {
    if (auth.failed) await audit(env, { action: action ?? "activar", level, via, who, ok: false, note: "credenciales" }, now);
    return auth.error;
  }
  if (action === "cancelar") {
    await env.ESTADO.delete("pending3");
    await audit(env, { action: "cancelar bloqueo", via, who }, now);
    return json(200, { ok: true, message: "Petici\xF3n de bloqueo cancelada." });
  }
  if (action === "confirmar") {
    const pending = await getJSON(env, "pending3");
    if (!pending || now - pending.requestedAt > RULES.pendingTtlMs) return json(404, { error: "No hay ning\xFAn bloqueo pendiente (o caduc\xF3)." });
    if (now - pending.requestedAt < RULES.lockConfirmMs) {
      return json(425, { error: `A\xFAn no: el bloqueo se confirma a partir de ${new Date(pending.requestedAt + RULES.lockConfirmMs).toISOString()}.` });
    }
    if (auth.step === pending.step) return json(400, { error: "Usa un c\xF3digo nuevo, distinto del de la petici\xF3n." });
    const r2 = await publishLevel(env, 3, now);
    await env.ESTADO.delete("pending3");
    await audit(env, { action: "confirmar bloqueo", level: 3, via, who, ok: !r2.error, note: r2.error }, now);
    return r2.error ? json(409, { error: r2.error }) : json(200, { ok: true, level: 3, left: r2.left });
  }
  if (![0, 1, 2, 3].includes(level)) return json(400, { error: "Nivel no v\xE1lido." });
  const last = parseInt(await env.ESTADO.get("lastChange") ?? "0", 10);
  if (now - last < RULES.cooldownMs) return json(429, { error: "Hace muy poco del \xFAltimo cambio. Espera unos minutos." });
  if (level === 3) {
    await putJSON(env, "pending3", { requestedAt: now, step: auth.step, via, who });
    await audit(env, { action: "pedir bloqueo", level: 3, via, who, note: "confirmar en 10 min con otro c\xF3digo" }, now);
    return json(202, { pending: true, confirmAfter: new Date(now + RULES.lockConfirmMs).toISOString() });
  }
  const r = await publishLevel(env, level, now);
  await audit(env, { action: "activar", level, via, who, ok: !r.error, note: r.error }, now);
  return r.error ? json(409, { error: r.error }) : json(200, { ok: true, level, left: r.left });
}
__name(panic, "panic");
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
__name(discordSigned, "discordSigned");
var ephemeral = /* @__PURE__ */ __name((content) => json(200, { type: 4, data: { content, flags: 64 } }), "ephemeral");
async function discord(env, request, now = Date.now()) {
  const raw = await request.text();
  if (!await discordSigned(env, request, raw)) return new Response("Firma no v\xE1lida", { status: 401 });
  const i = JSON.parse(raw);
  if (i.type === 1) return json(200, { type: 1 });
  const roles = i.member?.roles ?? [];
  const who = i.member?.user?.username ?? "?";
  if (i.channel_id !== env.DISCORD_ADMIN_CHANNEL || !roles.includes(env.DISCORD_ADMIN_ROLE)) {
    await audit(env, { action: "discord sin permiso", via: "discord", who, ok: false }, now);
    return ephemeral("Este comando s\xF3lo se puede usar en el canal de administraci\xF3n y con el rol de administraci\xF3n.");
  }
  if (i.type === 2 && i.data?.name === "panico") {
    const choice = i.data.options?.find((o) => o.name === "accion")?.value ?? "1";
    return json(200, {
      type: 9,
      data: {
        custom_id: `panico:${choice}`,
        title: choice === "confirmar" ? "Confirmar bloqueo total" : choice === "cancelar" ? "Cancelar bloqueo" : `P\xE1nico: ${LEVELS[choice] ?? "?"}`,
        components: [
          { type: 1, components: [{ type: 4, custom_id: "password", label: "Contrase\xF1a", style: 1, min_length: 8, max_length: 200, required: true }] },
          { type: 1, components: [{ type: 4, custom_id: "totp", label: "C\xF3digo de 6 cifras (app de autenticaci\xF3n)", style: 1, min_length: 6, max_length: 6, required: true }] }
        ]
      }
    });
  }
  if (i.type === 5 && String(i.data?.custom_id).startsWith("panico:")) {
    const choice = i.data.custom_id.slice(7);
    const field = /* @__PURE__ */ __name((id) => i.data.components.flatMap((r2) => r2.components).find((c) => c.custom_id === id)?.value, "field");
    const action = ["confirmar", "cancelar"].includes(choice) ? choice : "activar";
    const r = await panic(env, { action, level: Number(choice), password: field("password"), totp: field("totp"), via: "discord", who }, now);
    const body = await r.json();
    return ephemeral(body.error ? `\u274C ${body.error}` : body.pending ? `\u23F3 Bloqueo pedido. Conf\xEDrmalo con /panico accion:confirmar a partir de ${body.confirmAfter} (con otro c\xF3digo).` : `\u2705 Hecho. Quedan ${body.left ?? "?"} cambios en el lote.`);
  }
  return ephemeral("Comando desconocido.");
}
__name(discord, "discord");
async function handle(request, env, now = Date.now()) {
  const url = new URL(request.url);
  const route = `${request.method} ${url.pathname}`;
  if (route === "GET /estado") {
    const current = await getJSON(env, "current");
    return current ? json(200, current, { "cache-control": "public, max-age=60" }) : json(204, null);
  }
  if (route === "POST /discord") return discord(env, request, now);
  if (route === "POST /panico" || route === "POST /panico/confirmar" || route === "POST /panico/cancelar") {
    let body;
    try {
      body = await request.json();
    } catch {
      return json(400, { error: "JSON mal formado." });
    }
    const action = url.pathname.endsWith("confirmar") ? "confirmar" : url.pathname.endsWith("cancelar") ? "cancelar" : "activar";
    return panic(env, { ...body, action, via: "pear-dev" }, now);
  }
  if (route === "POST /panico/info") {
    let body;
    try {
      body = await request.json();
    } catch {
      return json(400, { error: "JSON mal formado." });
    }
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
      audit: (await getJSON(env, "audit", [])).slice(0, 20)
    });
  }
  if (route === "POST /admin/lote" || route === "POST /admin/publicar") {
    if (!env.ADMIN_TOKEN || request.headers.get("authorization") !== `Bearer ${env.ADMIN_TOKEN}`) return json(401, { error: "No autorizado." });
    const body = await request.json();
    const envelopes = route.endsWith("lote") ? (body.slots ?? []).flat() : [body];
    for (const e of envelopes) if (!await verifyEnvelope(env, e)) return json(400, { error: "Hay un estado mal firmado: no se ha guardado nada." });
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
__name(handle, "handle");
var worker_default = { fetch: /* @__PURE__ */ __name((request, env) => handle(request, env), "fetch") };

// ../../../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/middleware/middleware-ensure-req-body-drained.ts
var drainBody = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } finally {
    try {
      if (request.body !== null && !request.bodyUsed) {
        const reader = request.body.getReader();
        while (!(await reader.read()).done) {
        }
      }
    } catch (e) {
      console.error("Failed to drain the unused request body.", e);
    }
  }
}, "drainBody");
var middleware_ensure_req_body_drained_default = drainBody;

// ../../../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/middleware/middleware-miniflare3-json-error.ts
function reduceError(e) {
  return {
    name: e?.name,
    message: e?.message ?? String(e),
    stack: e?.stack,
    cause: e?.cause === void 0 ? void 0 : reduceError(e.cause)
  };
}
__name(reduceError, "reduceError");
var jsonError = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } catch (e) {
    const error = reduceError(e);
    const body = JSON.stringify(error);
    const headers = {
      "Content-Type": "application/json",
      "MF-Experimental-Error-Stack": "true"
    };
    const encoded = encodeURIComponent(body);
    if (encoded.length <= 8192) {
      headers["MF-Experimental-Error-Stack-Payload"] = encoded;
    }
    return new Response(body, { status: 500, headers });
  }
}, "jsonError");
var middleware_miniflare3_json_error_default = jsonError;

// .wrangler/tmp/bundle-Tfy76p/middleware-insertion-facade.js
var __INTERNAL_WRANGLER_MIDDLEWARE__ = [
  middleware_ensure_req_body_drained_default,
  middleware_miniflare3_json_error_default
];
var middleware_insertion_facade_default = worker_default;

// ../../../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/middleware/common.ts
var __facade_middleware__ = [];
function __facade_register__(...args) {
  __facade_middleware__.push(...args.flat());
}
__name(__facade_register__, "__facade_register__");
function __facade_invokeChain__(request, env, ctx, dispatch, middlewareChain) {
  const [head, ...tail] = middlewareChain;
  const middlewareCtx = {
    dispatch,
    next(newRequest, newEnv) {
      return __facade_invokeChain__(newRequest, newEnv, ctx, dispatch, tail);
    }
  };
  return head(request, env, ctx, middlewareCtx);
}
__name(__facade_invokeChain__, "__facade_invokeChain__");
function __facade_invoke__(request, env, ctx, dispatch, finalMiddleware) {
  return __facade_invokeChain__(request, env, ctx, dispatch, [
    ...__facade_middleware__,
    finalMiddleware
  ]);
}
__name(__facade_invoke__, "__facade_invoke__");

// .wrangler/tmp/bundle-Tfy76p/middleware-loader.entry.ts
var __Facade_ScheduledController__ = class ___Facade_ScheduledController__ {
  constructor(scheduledTime, cron, noRetry) {
    this.scheduledTime = scheduledTime;
    this.cron = cron;
    this.#noRetry = noRetry;
  }
  scheduledTime;
  cron;
  static {
    __name(this, "__Facade_ScheduledController__");
  }
  #noRetry;
  noRetry() {
    if (!(this instanceof ___Facade_ScheduledController__)) {
      throw new TypeError("Illegal invocation");
    }
    this.#noRetry();
  }
};
function wrapExportedHandler(worker) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return worker;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  const fetchDispatcher = /* @__PURE__ */ __name(function(request, env, ctx) {
    if (worker.fetch === void 0) {
      throw new Error("Handler does not export a fetch() function.");
    }
    return worker.fetch(request, env, ctx);
  }, "fetchDispatcher");
  return {
    ...worker,
    fetch(request, env, ctx) {
      const dispatcher = /* @__PURE__ */ __name(function(type, init) {
        if (type === "scheduled" && worker.scheduled !== void 0) {
          const controller = new __Facade_ScheduledController__(
            Date.now(),
            init.cron ?? "",
            () => {
            }
          );
          return worker.scheduled(controller, env, ctx);
        }
      }, "dispatcher");
      return __facade_invoke__(request, env, ctx, dispatcher, fetchDispatcher);
    }
  };
}
__name(wrapExportedHandler, "wrapExportedHandler");
function wrapWorkerEntrypoint(klass) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return klass;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  return class extends klass {
    #fetchDispatcher = /* @__PURE__ */ __name((request, env, ctx) => {
      this.env = env;
      this.ctx = ctx;
      if (super.fetch === void 0) {
        throw new Error("Entrypoint class does not define a fetch() function.");
      }
      return super.fetch(request);
    }, "#fetchDispatcher");
    #dispatcher = /* @__PURE__ */ __name((type, init) => {
      if (type === "scheduled" && super.scheduled !== void 0) {
        const controller = new __Facade_ScheduledController__(
          Date.now(),
          init.cron ?? "",
          () => {
          }
        );
        return super.scheduled(controller);
      }
    }, "#dispatcher");
    fetch(request) {
      return __facade_invoke__(
        request,
        this.env,
        this.ctx,
        this.#dispatcher,
        this.#fetchDispatcher
      );
    }
  };
}
__name(wrapWorkerEntrypoint, "wrapWorkerEntrypoint");
var WRAPPED_ENTRY;
if (typeof middleware_insertion_facade_default === "object") {
  WRAPPED_ENTRY = wrapExportedHandler(middleware_insertion_facade_default);
} else if (typeof middleware_insertion_facade_default === "function") {
  WRAPPED_ENTRY = wrapWorkerEntrypoint(middleware_insertion_facade_default);
}
var middleware_loader_entry_default = WRAPPED_ENTRY;
export {
  LEVELS,
  RULES,
  __INTERNAL_WRANGLER_MIDDLEWARE__,
  middleware_loader_entry_default as default,
  discord,
  handle,
  panic,
  verifyEnvelope
};
//# sourceMappingURL=worker.js.map
