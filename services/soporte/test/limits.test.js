import { test } from "node:test";
import assert from "node:assert/strict";
import { LIMITS, checkReport, discordPayload, isJpeg, rateKey, validEmail } from "../src/limits.js";

const jpeg = (n) => { const b = new Uint8Array(n); b.set([0xff, 0xd8, 0xff]); return b; };
const ok = { email: "ana@gmail.com", text: "La cola se vacía sola al cambiar de canción", platform: "android",
  appVersion: "0.8.1", os: "Android 16", model: "A065", deviceId: "3f2a9c1e-0000", photos: [] };

test("correo", () => {
  assert.ok(validEmail("ana@gmail.com"));
  assert.ok(!validEmail("ana@example"));
  assert.ok(!validEmail("ana@example.com"));
  assert.ok(!validEmail("ana example.com"));
});

test("un reporte normal vale, con y sin fotos", () => {
  assert.equal(checkReport(ok), null);
  assert.equal(checkReport({ ...ok, photos: [jpeg(1000), jpeg(2000)] }), null);
});

test("rechaza texto corto, plataforma rara, demasiadas fotos, fotos grandes o que no son JPEG", () => {
  assert.match(checkReport({ ...ok, text: "mal" }), /más/);
  assert.match(checkReport({ ...ok, platform: "web" }), /Plataforma/);
  assert.match(checkReport({ ...ok, photos: Array(5).fill(jpeg(10)) }), /Como mucho 4/);
  assert.match(checkReport({ ...ok, photos: [jpeg(LIMITS.maxPhotoBytes + 1)] }), /demasiado grande/);
  assert.match(checkReport({ ...ok, photos: [new Uint8Array([0x89, 0x50, 0x4e, 0x47])] }), /JPEG/);
});

test("JPEG por sus bytes", () => {
  assert.ok(isJpeg(jpeg(4)));
  assert.ok(!isJpeg(new Uint8Array([0x47, 0x49, 0x46, 0x38])));
});

test("contador por hora", () => {
  assert.equal(rateKey("dev", "x", 3_600_000 * 10 + 5), "rl:dev:x:10");
});

test("mensaje de Discord sin menciones y con los datos", () => {
  const p = discordPayload({ ...ok, text: "@everyone se cuelga" });
  assert.deepEqual(p.allowed_mentions, { parse: [] });
  assert.equal(p.embeds[0].title, "Reporte desde Android 0.8.1");
  assert.equal(p.embeds[0].fields[0].value, "ana@gmail.com");
});
