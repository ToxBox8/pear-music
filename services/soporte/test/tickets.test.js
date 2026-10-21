// Tickets (Cierre 1.0): reporte → ticket, /rp o (aviso con check), /msg con tipos, autocompletar, sólo a esa
// persona, /rp c y sugerencias a su canal. Discord falso y firmas Ed25519 de verdad.
import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/worker.js";

const kv = new Map();
let sent;
const keys = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]);
const pubHex = Buffer.from(await crypto.subtle.exportKey("raw", keys.publicKey)).toString("hex");
const env = {
  DISCORD_WEBHOOK: "https://discord.example/soporte",
  DISCORD_WEBHOOK_SUGERENCIAS: "https://discord.example/sugerencias",
  DISCORD_PUBLIC_KEY: pubHex,
  DISCORD_ADMIN_ROLE: "rol-admin",
  RATE: { get: async (k) => kv.get(k) ?? null, put: async (k, v) => void kv.set(k, v) },
};
beforeEach(() => {
  kv.clear();
  sent = [];
  globalThis.fetch = async (url, init) => {
    if (String(url).startsWith("https://cloudflare-dns.com/")) return Response.json({ Status: 0, Answer: [{ data: "10 mx" }] });
    sent.push({ url: String(url), body: init?.body });
    return new Response(null, { status: 204 });
  };
});

function report(extra = {}) {
  const f = new FormData();
  const fields = { email: "ana@gmail.com", text: "La app se cierra al abrir la cola", platform: "android",
    appVersion: "1.0.0", os: "Android 16", model: "A065", deviceId: "instalacion-ana-1234", ...extra };
  for (const [k, v] of Object.entries(fields)) f.append(k, v);
  return new Request("https://w.example/report", { method: "POST", body: f, headers: { "cf-connecting-ip": `1.2.3.${Math.random() * 200 | 0}` } });
}
async function slash(body, roles = ["rol-admin"]) {
  const raw = JSON.stringify({ member: { roles, user: { username: "toxbox" } }, ...body });
  const ts = "1800000000";
  const sig = Buffer.from(await crypto.subtle.sign({ name: "Ed25519" }, keys.privateKey, new TextEncoder().encode(ts + raw))).toString("hex");
  return worker.fetch(new Request("https://w.example/discord", { method: "POST", body: raw, headers: { "x-signature-ed25519": sig, "x-signature-timestamp": ts } }), env);
}
const mensajes = async (device) => (await (await worker.fetch(new Request(`https://w.example/mensajes?device=${device}`), env)).json()).mensajes;

test("un reporte abre el ticket #1 y el título lo lleva", async () => {
  const r = await worker.fetch(report(), env);
  assert.deepEqual(await r.json(), { ok: true, ticket: 1 });
  const payload = JSON.parse(sent.at(-1).body.get("payload_json"));
  assert.match(payload.embeds[0].title, /#1/);
});

test("sugerencias: a su canal y con su ticket", async () => {
  const r = await worker.fetch(report({ kind: "sugerencia", text: "Me gustaría poder ordenar por artista" }), env);
  assert.equal((await r.json()).ticket, 1);
  assert.equal(sent.at(-1).url, env.DISCORD_WEBHOOK_SUGERENCIAS);
  assert.match(JSON.parse(sent.at(-1).body.get("payload_json")).embeds[0].title, /Sugerencia #1/);
});

test("autocompletar, abrir, mensajes por tipo y sólo para esa persona", async () => {
  await worker.fetch(report(), env);
  await worker.fetch(report({ deviceId: "instalacion-otro-5678", email: "luis@gmail.com", text: "No suena nada en el coche" }), env);
  const ac = await (await slash({ type: 4, data: { name: "msg", options: [{ name: "ticket", value: "", focused: true }] } })).json();
  assert.equal(ac.type, 8);
  assert.deepEqual(ac.data.choices.map((c) => c.value), [2, 1]);

  const o = await (await slash({ type: 2, data: { name: "rp", options: [{ name: "ticket", value: 1 }, { name: "accion", value: "o" }] } })).json();
  assert.match(o.data.content, /abierto/);
  await slash({ type: 2, data: { name: "msg", options: [{ name: "ticket", value: 1 }, { name: "texto", value: "¿Qué móvil tienes?" }] } });
  await slash({ type: 2, data: { name: "msg", options: [{ name: "ticket", value: 1 }, { name: "texto", value: "estamos en ello, ya lo vemos" }] } });
  await slash({ type: 2, data: { name: "msg", options: [{ name: "ticket", value: 1 }, { name: "texto", value: "Arreglado en la 1.0.1" }, { name: "tipo", value: "fiesta" }] } });

  const ana = await mensajes("instalacion-ana-1234");
  assert.deepEqual(ana.map((m) => m.tipo), ["fiesta", "en-ello", "mensaje", "abierto"]);
  assert.ok(ana.every((m) => m.ticket === 1));
  // 1.12 de x.1.1: el aviso de «abierto» sin texto va como plantilla (la app lo traduce); con texto, no.
  const abierto = ana.find((m) => m.tipo === "abierto");
  assert.equal(abierto.plantilla, "abierto");
  assert.match(abierto.text, /Hemos abierto tu incidencia/);
  assert.ok(ana.filter((m) => m.tipo !== "abierto").every((m) => m.plantilla === undefined));
  assert.deepEqual(await mensajes("instalacion-otro-5678"), [], "a la otra persona no le llega nada");
  assert.ok(![...kv.values()].some((v) => String(v).includes("instalacion-ana-1234")), "no se guarda el id en claro");
  assert.ok(![...kv.values()].some((v) => String(v).includes("ana@gmail.com")), "ni el correo");
});

test("cerrar lo quita del autocompletado y ya no admite mensajes", async () => {
  await worker.fetch(report(), env);
  await slash({ type: 2, data: { name: "rp", options: [{ name: "ticket", value: 1 }, { name: "accion", value: "c" }] } });
  const ac = await (await slash({ type: 4, data: { name: "msg", options: [{ name: "ticket", value: "", focused: true }] } })).json();
  assert.equal(ac.data.choices.length, 0);
  const m = await (await slash({ type: 2, data: { name: "msg", options: [{ name: "ticket", value: 1 }, { name: "texto", value: "hola" }] } })).json();
  assert.match(m.data.content, /cerrado/);
});

test("sin el rol o con firma falsa, nada", async () => {
  await worker.fetch(report(), env);
  const r = await (await slash({ type: 2, data: { name: "msg", options: [{ name: "ticket", value: 1 }, { name: "texto", value: "x" }] } }, ["otro"])).json();
  assert.match(r.data.content, /Sólo/);
  const bad = await worker.fetch(new Request("https://w.example/discord", { method: "POST", body: "{}", headers: { "x-signature-ed25519": "00", "x-signature-timestamp": "1" } }), env);
  assert.equal(bad.status, 401);
  assert.deepEqual(await mensajes("instalacion-ana-1234"), []);
});

// 2.1 y 2.8 de x.1.1: listados con autor (sin correo ni id en claro), filtros, páginas y canal propio de reportes.
test("/reportes y /sugerencias: autor enmascarado, filtros y páginas", async () => {
  for (let k = 0; k < 23; k++) await worker.fetch(report({ email: `ana${k}@gmail.com`, deviceId: `instalacion-${k}-abcd`, text: `Fallo número ${k} al abrir la cola` }), env);
  await worker.fetch(report({ kind: "sugerencia", email: "luis@gmail.com", deviceId: "instalacion-sug-9999", text: "Modo karaoke con la letra grande" }), env);

  const rep = await (await slash({ type: 2, data: { name: "reportes", options: [] } })).json();
  assert.equal(rep.data.flags, 64, "sólo lo ve quien lo pide");
  assert.match(rep.data.content, /🐞 Reportes abiertas · 23 · página 1\/2/);
  assert.match(rep.data.content, /an…@gmail\.com · disp\. [0-9A-F]{4}/);
  assert.match(rep.data.content, /android 1\.0\.0/);
  assert.ok(!rep.data.content.includes("ana@gmail.com"));
  assert.equal(rep.data.content.split("\n").length, 21, "título y 20 filas");

  const next = rep.data.components[0].components[1];
  const p2 = await (await slash({ type: 3, data: { custom_id: next.custom_id } })).json();
  assert.equal(p2.type, 7, "cambia el mismo mensaje");
  assert.match(p2.data.content, /página 2\/2/);

  const sug = await (await slash({ type: 2, data: { name: "sugerencias", options: [] } })).json();
  assert.match(sug.data.content, /💡 Sugerencias abiertas · 1/);
  assert.match(sug.data.content, /karaoke/);

  await slash({ type: 2, data: { name: "rp", options: [{ name: "ticket", value: 24 }, { name: "accion", value: "c" }] } });
  const closed = await (await slash({ type: 2, data: { name: "sugerencias", options: [{ name: "estado", value: "cerradas" }] } })).json();
  assert.match(closed.data.content, /cerradas · 1/);
  const open = await (await slash({ type: 2, data: { name: "sugerencias", options: [] } })).json();
  assert.match(open.data.content, /abiertas · 0/);
});

test("los reportes van a #reportes si hay webhook", async () => {
  const withReports = { ...env, DISCORD_WEBHOOK_REPORTES: "https://discord.example/reportes" };
  await worker.fetch(report(), withReports);
  assert.equal(sent.at(-1).url, "https://discord.example/reportes");
});

test("los tickets de antes del índice también salen (anónimos)", async () => {
  kv.set("ticket:seq", "1");
  kv.set("t:1", JSON.stringify({ n: 1, kind: "error", device: "ab12cd", summary: "Ticket viejo", platform: "ios", status: "abierto", at: "2026-10-15T10:00:00.000Z" }));
  const r = await (await slash({ type: 2, data: { name: "reportes", options: [] } })).json();
  assert.match(r.data.content, /#1\*\* · 2026-10-15 · anónimo · disp\. AB12 · Ticket viejo · ios/);
});
