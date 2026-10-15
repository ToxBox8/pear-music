import { test } from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, sign as nodeSign } from "node:crypto";
import { handle, RULES } from "../src/worker.js";
import { hashPassword, totpAt } from "../src/totp.js";
import { envelope, publicKeyB64, MESSAGES } from "../../../tools/estado/estado.mjs";

const SECRET = "JBSWY3DPEHPK3PXP";
const { privateKey } = generateKeyPairSync("ed25519");
const discordKeys = generateKeyPairSync("ed25519");
const discordPubHex = Buffer.from(discordKeys.publicKey.export({ type: "spki", format: "der" })).subarray(-32).toString("hex");

function kv() {
  const m = new Map();
  return { get: async (k) => m.get(k) ?? null, put: async (k, v) => void m.set(k, v), delete: async (k) => void m.delete(k), m };
}
async function env() {
  return {
    ESTADO: kv(), PUBLIC_KEY: publicKeyB64(privateKey), ADMIN_TOKEN: "subida",
    PANIC_PASSWORD: await hashPassword("contraseña larga"), TOTP_SECRET: SECRET,
    DISCORD_PUBLIC_KEY: discordPubHex, DISCORD_ADMIN_ROLE: "rol-admin", DISCORD_ADMIN_CHANNEL: "canal-admin",
  };
}
const post = (path, body, headers = {}) => new Request(`https://e.test${path}`, { method: "POST", headers: { "content-type": "application/json", ...headers }, body: JSON.stringify(body) });
const T0 = 1_800_000_000_000;
const code = (now) => totpAt(SECRET, Math.floor(now / 30_000));

function batch(base = 1) {
  const slots = [];
  for (let i = 0; i < 3; i++) slots.push([0, 1, 2, 3].map((level) => envelope(privateKey, { level, counter: base + i * 4 + level, issuedAt: 1, expiresAt: 4_000_000_000, message: MESSAGES[level], ttlHours: level === 1 ? 24 : null })));
  return { slots, expiresAt: 4_000_000_000 };
}

test("sin estado publicado: 204 (las apps siguen normal)", async () => {
  assert.equal((await handle(new Request("https://e.test/estado"), await env())).status, 204);
});

test("el PC sube un lote firmado; uno mal firmado o sin token, rechazado", async () => {
  const e = await env();
  assert.equal((await handle(post("/admin/lote", batch()), e)).status, 401);
  const bad = batch();
  bad.slots[0][2] = { ...bad.slots[0][2], payload: bad.slots[0][2].payload.replace('"level":2', '"level":3') };
  assert.equal((await handle(post("/admin/lote", bad, { authorization: "Bearer subida" }), e)).status, 400);
  assert.equal((await handle(post("/admin/lote", batch(), { authorization: "Bearer subida" }), e)).status, 200);
});

test("activar modo seguro con contraseña y TOTP publica el prefirmado; luego hay enfriamiento", async () => {
  const e = await env();
  await handle(post("/admin/lote", batch(), { authorization: "Bearer subida" }), e);
  assert.equal((await handle(post("/panico", { level: 2, password: "contraseña larga", totp: "000000" }), e, T0)).status, 401);
  const ok = await handle(post("/panico", { level: 2, password: "contraseña larga", totp: await code(T0) }), e, T0);
  assert.equal(ok.status, 200);
  const st = await (await handle(new Request("https://e.test/estado"), e)).json();
  assert.equal(JSON.parse(st.payload).level, 2);
  const again = await handle(post("/panico", { level: 0, password: "contraseña larga", totp: await code(T0 + 60_000) }), e, T0 + 60_000);
  assert.equal(again.status, 429, "enfriamiento");
  const later = T0 + RULES.cooldownMs + 1;
  assert.equal((await handle(post("/panico", { level: 0, password: "contraseña larga", totp: await code(later) }), e, later)).status, 200);
  const back = await (await handle(new Request("https://e.test/estado"), e)).json();
  assert.equal(JSON.parse(back.payload).level, 0);
  assert.ok(JSON.parse(back.payload).counter > JSON.parse(st.payload).counter, "el contador siempre sube");
});

test("bloqueo total: pedir, confirmar a los 10 min con otro código", async () => {
  const e = await env();
  await handle(post("/admin/lote", batch(), { authorization: "Bearer subida" }), e);
  const pend = await handle(post("/panico", { level: 3, password: "contraseña larga", totp: await code(T0) }), e, T0);
  assert.equal(pend.status, 202);
  assert.equal((await handle(new Request("https://e.test/estado"), e)).status, 204, "aún no se publica");
  const early = T0 + 5 * 60_000;
  assert.equal((await handle(post("/panico/confirmar", { password: "contraseña larga", totp: await code(early) }), e, early)).status, 425);
  const t = T0 + RULES.lockConfirmMs + 1000;
  assert.equal((await handle(post("/panico/confirmar", { password: "contraseña larga", totp: await code(t) }), e, t)).status, 200);
  const st = await (await handle(new Request("https://e.test/estado"), e)).json();
  assert.equal(JSON.parse(st.payload).level, 3);
});

test("bloqueo tras 5 fallos en una hora", async () => {
  const e = await env();
  for (let i = 0; i < RULES.failsPerHour; i++) await handle(post("/panico", { level: 1, password: "mal", totp: "123456" }), e, T0);
  const r = await handle(post("/panico", { level: 1, password: "contraseña larga", totp: await code(T0) }), e, T0);
  assert.equal(r.status, 429);
});

test("anti-rollback: el PC no puede publicar un contador viejo", async () => {
  const e = await env();
  const h = { authorization: "Bearer subida" };
  const ten = envelope(privateKey, { level: 1, counter: 10, issuedAt: 1, expiresAt: 4_000_000_000, message: "x", ttlHours: 24 });
  const five = envelope(privateKey, { level: 0, counter: 5, issuedAt: 1, expiresAt: 4_000_000_000, message: "", ttlHours: null });
  assert.equal((await handle(post("/admin/publicar", ten, h), e)).status, 200);
  assert.equal((await handle(post("/admin/publicar", five, h), e)).status, 409);
});

function discordReq(body, signWith = discordKeys.privateKey) {
  const raw = JSON.stringify(body);
  const ts = "1800000000";
  const sig = nodeSign(null, Buffer.from(ts + raw), signWith).toString("hex");
  return new Request("https://e.test/discord", { method: "POST", headers: { "x-signature-ed25519": sig, "x-signature-timestamp": ts }, body: raw });
}

test("Discord: firma, rol y canal; el comando abre un modal y el modal activa", async () => {
  const e = await env();
  await handle(post("/admin/lote", batch(), { authorization: "Bearer subida" }), e);
  assert.equal((await handle(discordReq({ type: 1 }, generateKeyPairSync("ed25519").privateKey), e)).status, 401);
  assert.deepEqual(await (await handle(discordReq({ type: 1 }), e)).json(), { type: 1 });
  const noRole = await (await handle(discordReq({ type: 2, channel_id: "canal-admin", member: { roles: [] }, data: { name: "panico" } }), e)).json();
  assert.match(noRole.data.content, /rol de administración/);
  const member = { roles: ["rol-admin"], user: { username: "toxbox" } };
  const modal = await (await handle(discordReq({ type: 2, channel_id: "canal-admin", member, data: { name: "panico", options: [{ name: "accion", value: "1" }] } }), e)).json();
  assert.equal(modal.type, 9);
  const fields = (pw, t) => [{ components: [{ custom_id: "password", value: pw }] }, { components: [{ custom_id: "totp", value: t }] }];
  const done = await (await handle(discordReq({ type: 5, channel_id: "canal-admin", member, data: { custom_id: "panico:1", components: fields("contraseña larga", await code(T0)) } }), e, T0)).json();
  assert.match(done.data.content, /Hecho/);
  assert.equal(done.data.flags, 64, "respuesta sólo para quien lo usa");
  const audit = JSON.parse(e.ESTADO.m.get("audit"));
  assert.equal(audit[0].via, "discord");
  assert.ok(!JSON.stringify(audit).includes("contraseña larga"), "la contraseña nunca se guarda");
});
