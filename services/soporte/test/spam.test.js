// Filtros de correo inventado y texto sin sentido.
import { test } from "node:test";
import assert from "node:assert/strict";
import { domainReceivesMail, emailProblem, hashId, textProblem } from "../src/spam.js";

test("correos de verdad pasan", () => {
  for (const e of ["ana@gmail.com", "luis.perez+pear@outlook.es", "maria_g@protonmail.com", "j@uni.edu.es"]) {
    assert.equal(emailProblem(e), null, e);
  }
});

test("correos inventados, de prueba o desechables no", () => {
  for (const e of ["ana@example.com", "x@mailinator.com", "a@yopmail.com", "b@10minutemail.com", "test@gmail.com",
    "asdf@gmail.com", "prueba1@hotmail.com", "a@sub.guerrillamail.com", "ana@@gmail.com", "ana@gmail", ".ana@gmail.com",
    "ana..b@gmail.com", "ana@gmail.c"]) {
    assert.notEqual(emailProblem(e), null, e);
  }
});

test("textos normales pasan (castellano, inglés, con enlace y términos técnicos)", () => {
  for (const t of [
    "La app se cierra al abrir la cola con el reproductor Air.",
    "No suena nada al darle a reproducir en Android 16, la barra se queda en 0:00",
    "The lyrics don't scroll when I tap a line, iPhone 15 with iOS 26.1",
    "Al importar de Spotify https://open.spotify.com/playlist/abc se quedan 3 canciones sin añadir",
    "El widget no hace nada con la app cerrada. APK 0.9.1, Nothing Phone 2",
  ]) assert.equal(textProblem(t), null, t);
});

test("texto sin sentido o spam no", () => {
  for (const t of [
    "asdfghjkl qwertyuiop zxcvbnm",
    "aaaaaaaaaaaaaaaaa",
    "hola hola hola hola hola hola hola hola",
    "dfgdfg sdfsdf ghjghj fghfgh",
    "!!!!!!????......,,,,,",
    "1234567890 123456",
    "mira https://a.com https://b.com https://c.com",
    "jkjkjk lklklk",
  ]) assert.notEqual(textProblem(t), null, t);
});

test("DNS: con MX vale; dominio inexistente no; si el DNS falla deja pasar", async () => {
  const dns = (body, ok = true) => async () => ({ ok, status: ok ? 200 : 503, json: async () => body });
  assert.equal(await domainReceivesMail("gmail.com", dns({ Status: 0, Answer: [{}] })), true);
  assert.equal(await domainReceivesMail("nadie.invalid", dns({ Status: 3 })), false);
  assert.equal(await domainReceivesMail("x.com", dns({}, false)), true);
});

test("hash corto y estable, sin el valor original", async () => {
  const a = await hashId("1.2.3.4");
  assert.equal(a, await hashId(" 1.2.3.4 "));
  assert.match(a, /^[0-9a-f]{24}$/);
});
