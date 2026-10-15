import { test } from "node:test";
import assert from "node:assert/strict";
import { totpAt, hashPassword, checkPassword } from "../src/totp.js";

// RFC 6238, apéndice B (SHA-1, clave «12345678901234567890»), últimas 6 cifras.
test("TOTP: vectores del RFC 6238", async () => {
  const secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"; // base32 de «12345678901234567890»
  assert.equal(await totpAt(secret, Math.floor(59 / 30)), "287082");
  assert.equal(await totpAt(secret, Math.floor(1111111109 / 30)), "081804");
  assert.equal(await totpAt(secret, Math.floor(1234567890 / 30)), "005924");
  assert.equal(await totpAt(secret, Math.floor(2000000000 / 30)), "279037");
});

test("contraseña: PBKDF2 con sal, se comprueba sin guardarla", async () => {
  const stored = await hashPassword("una frase larga de verdad");
  assert.ok(!stored.includes("una frase"));
  assert.equal(await checkPassword("una frase larga de verdad", stored), true);
  assert.equal(await checkPassword("otra", stored), false);
});
