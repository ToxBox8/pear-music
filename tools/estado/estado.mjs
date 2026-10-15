#!/usr/bin/env node
// Herramienta del PC de Toxbox para el estado firmado de Pear Music (Fase 4, docs/RUNBOOK-INCIDENTES.md).
// La clave privada Ed25519 vive SÓLO aquí: ~/.config/pear-music/estado-ed25519.pem (permisos 600). Nunca en el repo,
// en las apps, en Discord ni en Cloudflare. El Worker «pear-music-estado» sólo publica lo que se firma aquí.
//
//   node tools/estado/estado.mjs clave                       crea la clave (si no existe) y enseña la pública
//   node tools/estado/estado.mjs lote [--dias 30]            firma un lote de estados prefirmados y lo sube
//   node tools/estado/estado.mjs publicar --nivel N --mensaje "…" [--horas 24]   firma uno concreto y lo publica ya
//   node tools/estado/estado.mjs ver                         estado publicado ahora
//
// Config en ~/.config/pear-music/estado.env: ESTADO_URL=https://… y ESTADO_ADMIN=<token de subida> (600).
import { createPrivateKey, createPublicKey, generateKeyPairSync, sign } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const DIR = join(homedir(), ".config", "pear-music");
const KEY = join(DIR, "estado-ed25519.pem");
const COUNTER = join(DIR, "estado-contador");

/** Mensajes fijos de cada nivel (los prefirmados no pueden llevar un texto concreto). */
export const MESSAGES = {
  0: "",
  1: "Estamos investigando un problema. Puede que algo no funcione bien un rato.",
  2: "Modo seguro: hemos desactivado algunas funciones mientras resolvemos un problema. Tu música descargada sigue funcionando.",
  3: "Pear Music está en mantenimiento por un incidente. Te avisaremos en cuanto esté resuelto.",
};
/** El aviso (nivel 1) caduca solo a las 24 h de verlo; los demás, hasta que se publique otro. */
const TTL = { 0: null, 1: 24, 2: null, 3: null };
const SLOTS = 20; // cambios de estado posibles por lote

function env() {
  const f = join(DIR, "estado.env");
  if (!existsSync(f)) return {};
  return Object.fromEntries(readFileSync(f, "utf8").split("\n").filter((l) => l.includes("=")).map((l) => [l.slice(0, l.indexOf("=")).trim(), l.slice(l.indexOf("=") + 1).trim()]));
}

function privateKey() {
  if (!existsSync(KEY)) throw new Error("No hay clave: ejecuta primero «clave».");
  return createPrivateKey(readFileSync(KEY));
}

/** Clave pública en base64 (32 bytes en bruto): la que llevan las apps. */
export function publicKeyB64(priv) {
  const der = createPublicKey(priv).export({ type: "spki", format: "der" });
  return der.subarray(der.length - 32).toString("base64");
}

function nextCounter(n = 1) {
  const cur = existsSync(COUNTER) ? parseInt(readFileSync(COUNTER, "utf8"), 10) || 0 : 0;
  writeFileSync(COUNTER, String(cur + n));
  return cur + 1;
}

/** Sobre firmado: { payload: "<JSON exacto>", sig: base64(Ed25519(payload)) }. */
export function envelope(priv, { level, counter, issuedAt, expiresAt, message, ttlHours }) {
  const payload = JSON.stringify({ v: 1, level, counter, issuedAt, expiresAt, ttlHours, message });
  return { payload, sig: sign(null, Buffer.from(payload, "utf8"), priv).toString("base64") };
}

async function upload(path, body) {
  const { ESTADO_URL, ESTADO_ADMIN } = env();
  if (!ESTADO_URL || !ESTADO_ADMIN) throw new Error(`Falta ESTADO_URL o ESTADO_ADMIN en ${join(DIR, "estado.env")}`);
  const r = await fetch(new URL(path, ESTADO_URL), {
    method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${ESTADO_ADMIN}` }, body: JSON.stringify(body),
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`El Worker respondió ${r.status}: ${text}`);
  return text;
}

const arg = (name, def) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : def;
};

async function main() {
  const cmd = process.argv[2];
  mkdirSync(DIR, { recursive: true, mode: 0o700 });
  if (cmd === "clave") {
    if (!existsSync(KEY)) {
      const { privateKey: k } = generateKeyPairSync("ed25519");
      writeFileSync(KEY, k.export({ type: "pkcs8", format: "pem" }), { mode: 0o600 });
      chmodSync(KEY, 0o600);
      console.log(`Clave creada en ${KEY} (600). GUÁRDALA también en tu gestor de contraseñas: sin ella no se pueden firmar estados nuevos.`);
    }
    console.log(`Clave pública (va en las apps): ${publicKeyB64(privateKey())}`);
  } else if (cmd === "lote") {
    const priv = privateKey();
    const days = Number(arg("dias", "30"));
    const now = Math.floor(Date.now() / 1000);
    const base = nextCounter(SLOTS * 4);
    // Hueco i: un sobre por nivel con contadores base+4i…base+4i+3. Cada cambio gasta un hueco entero.
    const slots = [];
    for (let i = 0; i < SLOTS; i++) {
      slots.push([0, 1, 2, 3].map((level) =>
        envelope(priv, { level, counter: base + i * 4 + level, issuedAt: now, expiresAt: now + days * 86400, message: MESSAGES[level], ttlHours: TTL[level] })));
    }
    console.log(await upload("/admin/lote", { slots, expiresAt: now + days * 86400 }));
    console.log(`Lote de ${SLOTS} cambios, válido ${days} días. Renuévalo antes de que caduque.`);
  } else if (cmd === "publicar") {
    const priv = privateKey();
    const level = Number(arg("nivel"));
    if (![0, 1, 2, 3].includes(level)) throw new Error("--nivel 0 (normal), 1 (aviso), 2 (modo seguro) o 3 (bloqueo)");
    const now = Math.floor(Date.now() / 1000);
    const hours = Number(arg("horas", level === 1 ? "24" : "720"));
    const env1 = envelope(priv, { level, counter: nextCounter(), issuedAt: now, expiresAt: now + hours * 3600, message: arg("mensaje", MESSAGES[level]), ttlHours: level === 1 ? hours : null });
    console.log(await upload("/admin/publicar", env1));
  } else if (cmd === "ver") {
    const { ESTADO_URL } = env();
    console.log(await (await fetch(new URL("/estado", ESTADO_URL))).text());
  } else {
    console.log(readFileSync(new URL(import.meta.url)).toString().split("\n").slice(1, 10).join("\n"));
  }
}

if (import.meta.url === `file://${process.argv[1]}`) main().catch((e) => { console.error(e.message); process.exit(1); });
