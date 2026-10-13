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
  globalThis.fetch = async (url, init) => { sent.push({ url, body: init.body }); return new Response(null, { status: 204 }); };
});

const jpeg = (n) => { const b = new Uint8Array(n); b.set([0xff, 0xd8, 0xff]); return b; };
function report(extra = {}, photos = []) {
  const f = new FormData();
  const fields = { email: "ana@example.com", text: "La app se cierra al abrir la cola", platform: "ios",
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
  assert.equal(payload.embeds[0].title, "Reporte desde iOS 1.4.0");
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

test("límite de 5 por dispositivo y hora", async () => {
  for (let i = 0; i < 5; i++) assert.equal((await worker.fetch(report(), env)).status, 200);
  const res = await worker.fetch(report(), env);
  assert.equal(res.status, 429);
  assert.match((await res.json()).error, /una hora/);
  assert.equal(sent.length, 5);
});

test("si Discord falla, la app recibe un error (y guarda el borrador)", async () => {
  globalThis.fetch = async () => new Response("", { status: 500 });
  assert.equal((await worker.fetch(report(), env)).status, 502);
});
