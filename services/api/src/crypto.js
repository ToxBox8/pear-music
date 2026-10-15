// Criptografía del servidor con Web Crypto (la misma API en Workers y en Node, para los tests).
// Secretos: EMAIL_KEY (AES-256 en base64) y EMAIL_HMAC (texto largo aleatorio). Nunca en el repo.

const enc = new TextEncoder();
const b64 = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)));
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const hex = (bytes) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");

export const normalizeEmail = (email) => String(email ?? "").trim().toLowerCase();

export async function sha256(text) {
  return hex(await crypto.subtle.digest("SHA-256", enc.encode(text)));
}

/** HMAC del correo: para buscar la cuenta sin guardar el correo en claro. */
export async function emailMac(env, email) {
  const key = await crypto.subtle.importKey("raw", enc.encode(env.EMAIL_HMAC), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", key, enc.encode(normalizeEmail(email))));
}

async function aesKey(env) {
  return crypto.subtle.importKey("raw", unb64(env.EMAIL_KEY), "AES-GCM", false, ["encrypt", "decrypt"]);
}

/** Correo cifrado (AES-GCM, IV aleatorio): «iv.cifrado» en base64. */
export async function encryptEmail(env, email) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await aesKey(env), enc.encode(normalizeEmail(email)));
  return `${b64(iv)}.${b64(ct)}`;
}

export async function decryptEmail(env, stored) {
  const [iv, ct] = stored.split(".");
  const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: unb64(iv) }, await aesKey(env), unb64(ct));
  return new TextDecoder().decode(plain);
}

/** Token o identificador aleatorio de 256 bits, en hexadecimal. */
export const randomToken = () => hex(crypto.getRandomValues(new Uint8Array(32)));

/** Código de 6 cifras sin sesgo (rechazo de muestras). */
export function randomCode() {
  const buf = new Uint32Array(1);
  do crypto.getRandomValues(buf);
  while (buf[0] >= 4_294_000_000);
  return String(buf[0] % 1_000_000).padStart(6, "0");
}

/** Comparación en tiempo constante de dos cadenas hexadecimales del mismo tamaño. */
export function sameHex(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
