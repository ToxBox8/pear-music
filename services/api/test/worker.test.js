import { test } from "node:test";
import assert from "node:assert/strict";
import { handle, cleanup, LIMITS } from "../src/worker.js";
import { fakeEnv, req } from "./fakes.js";

async function login(env, email = "ana@correo.es") {
  assert.equal((await handle(req("POST", "/v1/cuenta/codigo", { email }), env)).status, 200);
  const code = env.sent.at(-1).subject.match(/\d{6}/)[0];
  const r = await handle(req("POST", "/v1/cuenta/entrar", { email, code }), env);
  assert.equal(r.status, 200);
  return r.json();
}
const bearer = (t) => ({ authorization: `Bearer ${t}` });

test("cuenta: código al correo, entrar y el correo nunca en claro en la base", async () => {
  const env = fakeEnv();
  const { token, created, hasLibrary } = await login(env);
  assert.match(token, /^[a-f0-9]{64}$/);
  assert.equal(created, true);
  assert.equal(hasLibrary, false);
  const dump = JSON.stringify(env.DB.raw.prepare("SELECT * FROM accounts").all()) + JSON.stringify(env.DB.raw.prepare("SELECT * FROM sessions").all());
  assert.ok(!dump.includes("ana@correo.es"), "el correo no puede estar en claro");
  assert.ok(!dump.includes(token), "el token no puede estar en claro");
  const me = await (await handle(req("GET", "/v1/cuenta", undefined, bearer(token)), env)).json();
  assert.equal(me.email, "ana@correo.es");
  // Segunda vez: misma cuenta.
  assert.equal((await login(env)).created, false);
});

test("cuenta: código erróneo cuenta intentos y caduca a los 5", async () => {
  const env = fakeEnv();
  await handle(req("POST", "/v1/cuenta/codigo", { email: "b@correo.es" }), env);
  const good = env.sent.at(-1).subject.match(/\d{6}/)[0];
  const bad = good === "000000" ? "111111" : "000000";
  for (let i = 0; i < LIMITS.codeTries; i++) {
    assert.equal((await handle(req("POST", "/v1/cuenta/entrar", { email: "b@correo.es", code: bad }), env)).status, 400);
  }
  const r = await handle(req("POST", "/v1/cuenta/entrar", { email: "b@correo.es", code: good }), env);
  assert.equal(r.status, 400, "tras 5 fallos ni el bueno vale");
});

test("cuenta: código caducado", async () => {
  const env = fakeEnv();
  const t0 = Date.now();
  await handle(req("POST", "/v1/cuenta/codigo", { email: "c@correo.es" }), env, t0);
  const code = env.sent.at(-1).subject.match(/\d{6}/)[0];
  const r = await handle(req("POST", "/v1/cuenta/entrar", { email: "c@correo.es", code }), env, t0 + LIMITS.codeTtlMs + 1);
  assert.equal(r.status, 400);
});

test("cuenta: límite de códigos por correo", async () => {
  const env = fakeEnv();
  for (let i = 0; i < LIMITS.codesPerEmailPerHour; i++) {
    assert.equal((await handle(req("POST", "/v1/cuenta/codigo", { email: "d@correo.es" }), env)).status, 200);
  }
  assert.equal((await handle(req("POST", "/v1/cuenta/codigo", { email: "d@correo.es" }), env)).status, 429);
});

test("cuenta: sin remitente configurado, 503 (las apps esconden la cuenta)", async () => {
  const env = { ...fakeEnv(), MAIL_FROM: "" };
  assert.equal((await handle(req("POST", "/v1/cuenta/codigo", { email: "e@correo.es" }), env)).status, 503);
});

test("biblioteca: blob opaco, versiones y conflicto entre móviles", async () => {
  const env = fakeEnv();
  const { token } = await login(env);
  const put = (blob, baseVersion) => handle(req("PUT", "/v1/cuenta/biblioteca", { blob, baseVersion }, bearer(token)), env);
  assert.equal((await handle(req("GET", "/v1/cuenta/biblioteca", undefined, bearer(token)), env)).status, 404);
  assert.deepEqual(await (await put("QUJD", 0)).json(), { version: 1 });
  const stale = await put("REVG", 0);
  assert.equal(stale.status, 409);
  assert.equal((await stale.json()).version, 1);
  assert.equal((await put("REVG", 1)).status, 200);
  const got = await (await handle(req("GET", "/v1/cuenta/biblioteca", undefined, bearer(token)), env)).json();
  assert.equal(got.blob, "REVG");
  assert.equal(got.version, 2);
  assert.equal((await put("no es base64!", 2)).status, 400);
});

test("cuenta: sin token o con token falso, 401", async () => {
  const env = fakeEnv();
  assert.equal((await handle(req("GET", "/v1/cuenta"), env)).status, 401);
  assert.equal((await handle(req("GET", "/v1/cuenta", undefined, bearer("a".repeat(64))), env)).status, 401);
});

test("borrar la cuenta lo borra todo y el token deja de valer", async () => {
  const env = fakeEnv();
  const { token } = await login(env);
  await handle(req("PUT", "/v1/cuenta/biblioteca", { blob: "QUJD", baseVersion: 0 }, bearer(token)), env);
  assert.equal((await handle(req("DELETE", "/v1/cuenta", undefined, bearer(token)), env)).status, 200);
  for (const t of ["accounts", "sessions", "libraries"]) {
    assert.equal(env.DB.raw.prepare(`SELECT count(*) AS n FROM ${t}`).get().n, 0, t);
  }
  assert.equal((await handle(req("GET", "/v1/cuenta", undefined, bearer(token)), env)).status, 401);
});

const report = {
  install: "a".repeat(32), platform: "android", channel: "usr", app_version: "1.0.0",
  os_version: "16", device_model: "A065", week: "2026-W42", kind: "semanal", sessions: 9, startup_ms: 640, fps_median: 59.8, jank_percent: 1.9, memory_mb: 210, session_minutes: 12,
};

test("telemetría: acepta la lista exacta de campos y nada más", async () => {
  const env = fakeEnv();
  assert.equal((await handle(req("POST", "/v1/telemetria", report), env)).status, 202);
  assert.equal((await handle(req("POST", "/v1/telemetria", { ...report, email: "x@y.es" }), env)).status, 400);
  assert.equal((await handle(req("POST", "/v1/telemetria", { ...report, platform: "windows" }), env)).status, 400);
  const { platform, ...sinPlataforma } = report;
  assert.equal((await handle(req("POST", "/v1/telemetria", sinPlataforma), env)).status, 400);
});

test("telemetría: semana y tipo obligatorios; el envío manual puede omitir campos", async () => {
  const env = fakeEnv();
  const { week, ...sinSemana } = report;
  assert.equal((await handle(req("POST", "/v1/telemetria", sinSemana), env)).status, 400);
  assert.equal((await handle(req("POST", "/v1/telemetria", { ...report, week: "2026-42" }), env)).status, 400);
  assert.equal((await handle(req("POST", "/v1/telemetria", { ...report, kind: "diario" }), env)).status, 400);
  const manual = { install: report.install, platform: "android", channel: "dev", app_version: "1.0.0", week: "2026-W42", kind: "manual", fps_median: 60 };
  assert.equal((await handle(req("POST", "/v1/telemetria", manual), env)).status, 202);
});

test("panel: sólo con llave de Pear Dev firmada y sin caducar", async () => {
  const env = fakeEnv();
  const { publicKey, privateKey } = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  env.PANEL_PUBLIC_KEY = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey("raw", publicKey))));
  env.PANEL_ORIGIN = "https://web.test";
  const b64u = (u) => btoa(String.fromCharCode(...u)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const llave = async (exp) => {
    const payload = new TextEncoder().encode(JSON.stringify({ exp, n: "abc" }));
    return `Panel ${b64u(payload)}.${b64u(new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, privateKey, payload)))}`;
  };
  const now = Date.now();
  await handle(req("POST", "/v1/telemetria", report), env, now);
  const panel = (auth) => handle(req("GET", "/v1/telemetria/panel", undefined, auth ? { authorization: auth } : {}), env, now);
  assert.equal((await panel()).status, 401);
  assert.equal((await panel(await llave(now - 1))).status, 401, "caducada");
  assert.equal((await panel(await llave(now + 60 * 60_000))).status, 401, "demasiado larga");
  const otra = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  const payload = new TextEncoder().encode(JSON.stringify({ exp: now + 60_000 }));
  const falsa = `Panel ${b64u(payload)}.${b64u(new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, otra.privateKey, payload)))}`;
  assert.equal((await panel(falsa)).status, 401, "otra clave");
  const ok = await panel(await llave(now + 5 * 60_000));
  assert.equal(ok.status, 200);
  assert.equal(ok.headers.get("access-control-allow-origin"), "https://web.test");
  const data = await ok.json();
  assert.equal(data.weeks[0].week, "2026-W42");
  assert.equal(data.weeks[0].installs, 1);
  assert.ok(!JSON.stringify(data).includes(report.install), "el panel no enseña identificadores");
  assert.equal((await handle(req("OPTIONS", "/v1/telemetria/panel"), env, now)).status, 204);
});

test("telemetría: retirar el consentimiento borra lo de esa instalación", async () => {
  const env = fakeEnv();
  await handle(req("POST", "/v1/telemetria", report), env);
  await handle(req("POST", "/v1/telemetria", { ...report, install: "b".repeat(32) }), env);
  assert.equal((await handle(req("DELETE", "/v1/telemetria", { install: report.install }), env)).status, 200);
  assert.equal(env.DB.raw.prepare("SELECT count(*) AS n FROM telemetry").get().n, 1);
});

test("limpieza: telemetría de más de 90 días fuera", async () => {
  const env = fakeEnv();
  const now = Date.now();
  await handle(req("POST", "/v1/telemetria", report), env, now - 91 * 86_400_000);
  await handle(req("POST", "/v1/telemetria", { ...report, install: "c".repeat(32) }), env, now);
  await cleanup(env, now);
  assert.equal(env.DB.raw.prepare("SELECT count(*) AS n FROM telemetry").get().n, 1);
});

test("disponible: sólo con remitente configurado", async () => {
  assert.equal((await (await handle(req("GET", "/v1/cuenta/disponible"), fakeEnv())).json()).available, true);
  assert.equal((await (await handle(req("GET", "/v1/cuenta/disponible"), { ...fakeEnv(), MAIL_FROM: "" })).json()).available, false);
});

const ficha = {
  ficha: "f".repeat(64), platform: "android", channel: "usr", app_version: "1.0.1",
  os_version: "Android 16", device_model: "Nothing A065", ticket: 12, kind: "error",
};

test("ficha: se crea con el reporte, suma tickets y rechaza campos de más", async () => {
  const env = fakeEnv();
  const now = Date.now();
  assert.equal((await handle(req("POST", "/v1/ficha", ficha), env, now)).status, 202);
  assert.equal((await handle(req("POST", "/v1/ficha", { ...ficha, ticket: 13, kind: "sugerencia" }), env, now + 1)).status, 202);
  assert.equal((await handle(req("POST", "/v1/ficha", { ...ficha, ticket: 13 }), env, now + 2)).status, 202, "repetido no duplica");
  const row = env.DB.raw.prepare("SELECT * FROM fichas").get();
  assert.deepEqual(JSON.parse(row.tickets).map((t) => t.n), [12, 13]);
  assert.equal(row.first_seen, now);
  assert.equal(row.install, null, "sin telemetría no hay id de telemetría");
  assert.equal((await handle(req("POST", "/v1/ficha", { ...ficha, email: "x@y.es" }), env)).status, 400);
  assert.equal((await handle(req("POST", "/v1/ficha", { ...ficha, ficha: "corto" }), env)).status, 400);
  assert.equal((await handle(req("POST", "/v1/ficha", { ...ficha, kind: "otro" }), env)).status, 400);
});

test("ficha + telemetría: el panel las une sin enseñar el id; retirarla las separa", async () => {
  const env = fakeEnv();
  const { publicKey, privateKey } = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  env.PANEL_PUBLIC_KEY = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey("raw", publicKey))));
  const b64u = (u) => btoa(String.fromCharCode(...u)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const now = Date.now();
  const payload = new TextEncoder().encode(JSON.stringify({ exp: now + 60_000 }));
  const auth = `Panel ${b64u(payload)}.${b64u(new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, privateKey, payload)))}`;
  await handle(req("POST", "/v1/telemetria", report), env, now);
  await handle(req("POST", "/v1/ficha", { ...ficha, install: report.install }), env, now);
  await handle(req("POST", "/v1/activo", { platform: "android", channel: "usr", app_version: "1.0.1" }), env, now);
  await handle(req("POST", "/v1/activo", { platform: "ios", channel: "usr", app_version: "2.0.1" }), env, now);
  const panel = async () => (await handle(req("GET", "/v1/telemetria/panel", undefined, { authorization: auth }), env, now)).json();
  const data = await panel();
  const [f] = data.dispositivos.fichas;
  assert.equal(f.telemetria, true);
  assert.equal(f.week, report.week);
  assert.equal(f.tickets[0].n, 12);
  assert.equal(f.id.length, 10);
  assert.equal(data.dispositivos.activosPorDia[0].total, 2);
  assert.equal(data.dispositivos.activosPorDia[0].ios, 1);
  assert.ok(!JSON.stringify(data).includes(report.install), "el panel no enseña el id de telemetría");
  await handle(req("DELETE", "/v1/telemetria", { install: report.install }), env, now);
  assert.equal((await panel()).dispositivos.fichas[0].telemetria, false);
});

test("activos: sólo un contador, sin identificadores", async () => {
  const env = fakeEnv();
  const a = { platform: "android", channel: "usr", app_version: "1.0.0" };
  for (let i = 0; i < 3; i++) assert.equal((await handle(req("POST", "/v1/activo", a), env)).status, 202);
  assert.equal(env.DB.raw.prepare("SELECT n FROM activos").get().n, 3);
  assert.deepEqual(Object.keys(env.DB.raw.prepare("SELECT * FROM activos").get()).sort(), ["app_version", "channel", "day", "n", "platform"]);
  assert.equal((await handle(req("POST", "/v1/activo", { ...a, install: "a".repeat(32) }), env)).status, 400);
});

test("limpieza: fichas sin reportes en 180 días fuera", async () => {
  const env = fakeEnv();
  const now = Date.now();
  await handle(req("POST", "/v1/ficha", ficha), env, now - 181 * 86_400_000);
  await handle(req("POST", "/v1/ficha", { ...ficha, ficha: "e".repeat(64) }), env, now);
  await cleanup(env, now);
  assert.equal(env.DB.raw.prepare("SELECT count(*) AS n FROM fichas").get().n, 1);
});

test("decisiones: cuenta sí y no, y un cambio mueve el contador", async () => {
  const env = fakeEnv();
  const base = { platform: "android", channel: "usr", app_version: "1.0.1" };
  await handle(req("POST", "/v1/consentimiento", { ...base, decision: "no" }), env);
  await handle(req("POST", "/v1/consentimiento", { ...base, decision: "no" }), env);
  await handle(req("POST", "/v1/consentimiento", { ...base, decision: "si", antes: "no" }), env);
  const n = (d) => env.DB.raw.prepare("SELECT n FROM decisiones WHERE decision = ?").get(d).n;
  assert.equal(n("no"), 1);
  assert.equal(n("si"), 1);
  assert.equal((await handle(req("POST", "/v1/consentimiento", { ...base, decision: "quizá" }), env)).status, 400);
  assert.equal((await handle(req("POST", "/v1/consentimiento", { ...base, decision: "no", install: "a".repeat(32) }), env)).status, 400);
});

test("perfil: el historial de telemetría va con la ficha, sin el identificador", async () => {
  const env = fakeEnv();
  const { publicKey, privateKey } = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
  env.PANEL_PUBLIC_KEY = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.exportKey("raw", publicKey))));
  const b64u = (u) => btoa(String.fromCharCode(...u)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const now = Date.now();
  const payload = new TextEncoder().encode(JSON.stringify({ exp: now + 60_000 }));
  const auth = `Panel ${b64u(payload)}.${b64u(new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, privateKey, payload)))}`;
  await handle(req("POST", "/v1/telemetria", report), env, now - 1000);
  await handle(req("POST", "/v1/telemetria", { ...report, week: "2026-W43" }), env, now);
  await handle(req("POST", "/v1/ficha", { ...ficha, install: report.install }), env, now);
  const data = await (await handle(req("GET", "/v1/telemetria/panel", undefined, { authorization: auth }), env, now)).json();
  const [f] = data.dispositivos.fichas;
  assert.deepEqual(f.historial.map((h) => h.week), ["2026-W43", "2026-W42"]);
  assert.ok(!JSON.stringify(data).includes(report.install));
  assert.ok(Array.isArray(data.dispositivos.decisiones));
});
