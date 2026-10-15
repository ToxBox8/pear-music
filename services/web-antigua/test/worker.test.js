import { test } from "node:test";
import assert from "node:assert/strict";
import worker, { NEW_ORIGIN } from "../src/worker.js";

test("redirige con la misma ruta y consulta", async () => {
  const r = await worker.fetch(new Request("https://libremusic-landing.8toxbox8-69a.workers.dev/downloads/LibreMusic.apk?v=1.0.0"));
  assert.equal(r.status, 301);
  assert.equal(r.headers.get("location"), `${NEW_ORIGIN}/downloads/LibreMusic.apk?v=1.0.0`);
});

test("POST conserva el método (308)", async () => {
  const r = await worker.fetch(new Request("https://x/api/algo", { method: "POST", body: "{}" }));
  assert.equal(r.status, 308);
});
