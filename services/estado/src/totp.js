// TOTP (RFC 6238: HMAC-SHA1, 30 s, 6 cifras) y contraseña (PBKDF2-SHA256), con Web Crypto (Workers y Node).

const enc = new TextEncoder();

export function base32Decode(s) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const clean = String(s).toUpperCase().replace(/[^A-Z2-7]/g, "");
  let bits = 0, value = 0;
  const out = [];
  for (const ch of clean) {
    value = (value << 5) | alphabet.indexOf(ch);
    bits += 5;
    if (bits >= 8) { out.push((value >>> (bits - 8)) & 255); bits -= 8; }
  }
  return new Uint8Array(out);
}

export async function totpAt(secretB32, step) {
  const key = await crypto.subtle.importKey("raw", base32Decode(secretB32), { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  const msg = new Uint8Array(8);
  let s = step;
  for (let i = 7; i >= 0; i--) { msg[i] = s & 255; s = Math.floor(s / 256); }
  const h = new Uint8Array(await crypto.subtle.sign("HMAC", key, msg));
  const o = h[19] & 15;
  const n = ((h[o] & 127) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return String(n % 1_000_000).padStart(6, "0");
}

/** El paso (ventana de 30 s) en que vale el código, con ±1 de margen; null si no vale. */
export async function totpStep(secretB32, code, now = Date.now()) {
  if (!/^\d{6}$/.test(String(code ?? ""))) return null;
  const step = Math.floor(now / 30_000);
  for (const d of [0, -1, 1]) if ((await totpAt(secretB32, step + d)) === code) return step + d;
  return null;
}

/** «salt:hash» en base64, PBKDF2-SHA256 con 100 000 iteraciones (el máximo de Workers). */
export async function hashPassword(password, saltB64) {
  const salt = saltB64 ? Uint8Array.from(atob(saltB64), (c) => c.charCodeAt(0)) : crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveBits"]);
  const bits = new Uint8Array(await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations: 100_000 }, key, 256));
  const b64 = (u) => btoa(String.fromCharCode(...u));
  return `${b64(salt)}:${b64(bits)}`;
}

export async function checkPassword(password, stored) {
  const [salt, hash] = String(stored ?? "").split(":");
  if (!salt || !hash || typeof password !== "string" || password.length > 200) return false;
  const again = (await hashPassword(password, salt)).split(":")[1];
  if (again.length !== hash.length) return false;
  let diff = 0;
  for (let i = 0; i < hash.length; i++) diff |= again.charCodeAt(i) ^ hash.charCodeAt(i);
  return diff === 0;
}
