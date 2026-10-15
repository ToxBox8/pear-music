#!/usr/bin/env node
// Prepara los secretos del botón de pánico (Fase 4) en el PC de Toxbox, sin que pasen por ningún chat:
//   node scripts/preparar-secretos.mjs
// 1. Pide la contraseña (sin eco) y sube su hash PBKDF2 como PANIC_PASSWORD.
// 2. Crea un secreto TOTP nuevo, lo sube como TOTP_SECRET y enseña el enlace otpauth:// (y el QR, si está
//    `qrencode`) para la app de autenticación. Escanéalo y borra la terminal.
// 3. Crea un ADMIN_TOKEN aleatorio, lo sube y lo guarda en ~/.config/pear-music/estado.env (600) para estado.mjs.
// Necesita `npx wrangler login` hecho en esta carpeta.
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, readFileSync, readSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { hashPassword } from "../src/totp.js";

const URL_ESTADO = "https://pear-music-estado.8toxbox8-69a.workers.dev";

function put(name, value) {
  const r = spawnSync("npx", ["wrangler", "secret", "put", name], { input: value, stdio: ["pipe", "inherit", "inherit"] });
  if (r.status !== 0) throw new Error(`No se pudo subir ${name}`);
}

function askHidden(q) {
  process.stdout.write(q);
  spawnSync("stty", ["-echo"], { stdio: "inherit" });
  const buf = Buffer.alloc(256);
  const n = readSync(0, buf, 0, buf.length);
  spawnSync("stty", ["echo"], { stdio: "inherit" });
  process.stdout.write("\n");
  return buf.subarray(0, n).toString("utf8").replace(/\r?\n$/, "");
}

function base32(bytes) {
  const a = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = 0, value = 0, out = "";
  for (const b of bytes) {
    value = (value << 8) | b; bits += 8;
    while (bits >= 5) { out += a[(value >>> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits > 0) out += a[(value << (5 - bits)) & 31];
  return out;
}

const pass = askHidden("Contraseña del botón de pánico (12+ caracteres): ");
if (pass.length < 12) { console.error("Demasiado corta."); process.exit(1); }
if (askHidden("Repítela: ") !== pass) { console.error("No coinciden."); process.exit(1); }
put("PANIC_PASSWORD", await hashPassword(pass));

const totp = base32(randomBytes(20));
put("TOTP_SECRET", totp);
const uri = `otpauth://totp/Pear%20Music:panico?secret=${totp}&issuer=Pear%20Music&algorithm=SHA1&digits=6&period=30`;
console.log(`\nAñade esto a tu app de autenticación y luego borra la terminal (clear):\n${uri}\n`);
spawnSync("qrencode", ["-t", "ANSIUTF8", uri], { stdio: "inherit" });

const token = randomBytes(32).toString("base64url");
put("ADMIN_TOKEN", token);
const envFile = join(homedir(), ".config", "pear-music", "estado.env");
const keep = existsSync(envFile) ? readFileSync(envFile, "utf8").split("\n").filter((l) => l && !/^ESTADO_(URL|ADMIN)=/.test(l)) : [];
writeFileSync(envFile, [...keep, `ESTADO_URL=${URL_ESTADO}`, `ESTADO_ADMIN=${token}`].join("\n") + "\n", { mode: 0o600 });
console.log(`ADMIN_TOKEN guardado en ${envFile} (600).`);
