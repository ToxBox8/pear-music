// D1 y KV de mentira para los tests (D1 sobre el SQLite de Node, con el esquema real).
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";

export function fakeD1() {
  const db = new DatabaseSync(":memory:");
  db.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
  const stmt = (sql, args = []) => ({
    bind: (...a) => stmt(sql, a),
    first: async (col) => {
      const row = db.prepare(sql).get(...args);
      return row === undefined ? null : col ? row[col] : { ...row };
    },
    run: async () => db.prepare(sql).run(...args),
    all: async () => ({ results: db.prepare(sql).all(...args) }),
  });
  return { prepare: (sql) => stmt(sql), batch: async (list) => Promise.all(list.map((s) => s.run())), raw: db };
}

export function fakeKV() {
  const m = new Map();
  return { get: async (k) => m.get(k) ?? null, put: async (k, v) => void m.set(k, v), map: m };
}

export function fakeEnv() {
  const sent = [];
  return {
    DB: fakeD1(),
    RATE: fakeKV(),
    EMAIL: { send: async (msg) => void sent.push(msg) },
    MAIL_FROM: "hola@pear.example",
    EMAIL_KEY: btoa(String.fromCharCode(...new Uint8Array(32).fill(7))),
    EMAIL_HMAC: "secreto-de-pruebas-muy-largo",
    sent,
  };
}

export const req = (method, path, body, headers = {}) =>
  new Request(`https://api.test${path}`, {
    method,
    headers: { "content-type": "application/json", ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
