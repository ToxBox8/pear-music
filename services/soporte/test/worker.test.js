// El Worker entero con un KV y un Discord falsos: así se prueba sin desplegar ni gastar el webhook.
import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/worker.js";

let sent;
const kv = new Map();
const env = {
  DISCORD_WEBHOOK: "https://discord.example/webhook",
  RATE: { get: async (k) => kv.get(k) ?? null, put: async (k, v) => void kv.set(k, v) },
};
beforeEach(() => {
  sent = [];
  kv.clear();
  globalThis.fetch = async (url, init) => {
    if (String(url).startsWith("https://cloudflare-dns.com/")) {
      // El dominio «nadie.invalid» no existe; el resto tiene MX.
      const nx = String(url).includes("nadie.invalid");
      return Response.json(nx ? { Status: 3 } : { Status: 0, Answer: [{ data: "10 mx.ejemplo" }] });
    }
    sent.push({ url, body: init.body });
    return new Response(null, { status: 204 });
  };
});

const jpeg = (n) => { const b = new Uint8Array(n); b.set([0xff, 0xd8, 0xff]); return b; };
function report(extra = {}, photos = []) {
  const f = new FormData();
  const fields = { email: "ana@gmail.com", text: "La app se cierra al abrir la cola", platform: "ios",
    appVersion: "1.4.0", os: "iOS 26.1", model: "iPhone16,1", deviceId: "dev-1", ...extra };
  for (const [k, v] of Object.entries(fields)) f.append(k, v);
  photos.forEach((p, i) => f.append(`photo${i}`, new Blob([p.bytes], { type: p.type ?? "image/jpeg" }), `f${i}.jpg`));
  return new Request("https://w.example/report", { method: "POST", body: f, headers: { "cf-connecting-ip": "1.2.3.4" } });
}

test("sin fotos llega a Discord", async () => {
  const res = await worker.fetch(report(), env);
  assert.equal(res.status, 200);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].url, env.DISCORD_WEBHOOK);
  const payload = JSON.parse(sent[0].body.get("payload_json"));
  assert.equal(payload.embeds[0].title, "Reporte #1 desde iOS 1.4.0");
});

test("con dos fotos las adjunta", async () => {
  const res = await worker.fetch(report({}, [{ bytes: jpeg(500) }, { bytes: jpeg(800) }]), env);
  assert.equal(res.status, 200);
  assert.ok(sent[0].body.get("files[0]"));
  assert.ok(sent[0].body.get("files[1]"));
});

test("rechaza un PNG y un archivo grande", async () => {
  assert.equal((await worker.fetch(report({}, [{ bytes: jpeg(10), type: "image/png" }]), env)).status, 415);
  assert.equal((await worker.fetch(report({}, [{ bytes: jpeg(1_600_000) }]), env)).status, 400);
  assert.equal(sent.length, 0);
});

test("uno por hora por dispositivo y por correo; tres por IP", async () => {
  assert.equal((await worker.fetch(report(), env)).status, 200);
  const otra = await worker.fetch(report(), env);
  assert.equal(otra.status, 429);
  assert.match((await otra.json()).error, /una hora/);
  // Otro móvil con el mismo correo: también espera.
  assert.equal((await worker.fetch(report({ deviceId: "dev-2" }), env)).status, 429);
  // Otro móvil y otro correo desde la misma IP: hasta 3.
  assert.equal((await worker.fetch(report({ deviceId: "dev-3", email: "luis@gmail.com" }), env)).status, 200);
  assert.equal((await worker.fetch(report({ deviceId: "dev-4", email: "eva@gmail.com" }), env)).status, 200);
  assert.equal((await worker.fetch(report({ deviceId: "dev-5", email: "rosa@gmail.com" }), env)).status, 429);
  assert.equal(sent.length, 3);
});

test("los contadores no guardan la IP, el correo ni el id del móvil", async () => {
  await worker.fetch(report(), env);
  const keys = [...kv.keys()].join(" ");
  assert.ok(!keys.includes("1.2.3.4") && !keys.includes("ana@gmail.com") && !keys.includes("dev-1"));
});

test("dominio que no existe", async () => {
  const res = await worker.fetch(report({ email: "ana@nadie.invalid" }), env);
  assert.equal(res.status, 400);
  assert.match((await res.json()).error, /no existe/);
});

test("si Discord falla no cuenta para el límite", async () => {
  globalThis.fetch = async (url) => String(url).startsWith("https://cloudflare-dns.com/")
    ? Response.json({ Status: 0, Answer: [{}] }) : new Response("", { status: 500 });
  assert.equal((await worker.fetch(report(), env)).status, 502);
  // Sólo avanza el contador de tickets; ningún límite cuenta y no queda ticket guardado.
  assert.deepEqual([...kv.keys()], ["ticket:seq"]);
});

test("si Discord falla, la app recibe un error (y guarda el borrador)", async () => {
  globalThis.fetch = async (url) => String(url).startsWith("https://cloudflare-dns.com/")
    ? Response.json({ Status: 0, Answer: [{}] }) : new Response("", { status: 500 });
  assert.equal((await worker.fetch(report(), env)).status, 502);
});

test("insultos: se rechaza con motivo, se registra sin el texto y se puede apelar una vez", async () => {
  const res = await worker.fetch(report({ text: "eres un gilipollas, la app no va" }), env);
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.match(body.error, /insultos/);
  assert.equal(body.canAppeal, true);
  const stored = kv.get(`deny:${body.denialId}`);
  assert.ok(stored && !stored.includes("gilipollas") && !stored.includes("dev-1"), "el registro no guarda el texto ni el id");
  const appeal = (extra = {}) => worker.fetch(new Request("https://w.example/appeal", {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ denialId: body.denialId, deviceId: "dev-1", email: "ana@gmail.com",
      text: "Perdón, estaba enfadado: la app se cierra al abrir la cola cada vez.", ...extra }),
  }), env);
  assert.equal((await appeal({ deviceId: "otro" })).status, 403);
  assert.equal((await appeal()).status, 200);
  assert.match(sent.at(-1).body, /Apelación/);
  assert.equal((await appeal()).status, 409);
});

test("una palabrota suelta de frustración no se rechaza", async () => {
  assert.equal((await worker.fetch(report({ text: "Esto es una mierda, la app se cierra al abrir la cola" }), env)).status, 200);
});

test("el mismo reporte repetido desde el mismo móvil al día siguiente de la hora se rechaza", async () => {
  assert.equal((await worker.fetch(report(), env)).status, 200);
  // Pasada la hora (se vacían los contadores por hora), el mismo texto sigue rechazado durante 24 h.
  for (const k of [...kv.keys()]) if (k.startsWith("rl:")) kv.delete(k);
  const res = await worker.fetch(report(), env);
  assert.equal(res.status, 400);
  assert.match((await res.json()).error, /mismo reporte/);
});
