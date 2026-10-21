#!/usr/bin/env node
// Firma de publicaciones (fase de seguridad S4, x.1.1). Si alguien entra en la web, en Cloudflare o en GitHub, podría
// cambiar version.json y mandar a todas las apps a un APK o una fuente de AltStore falsos. Con esto, las apps sólo
// ofrecen lo firmado con la clave de publicación, que vive **fuera de línea** (USB cifrado + copia en Proton Pass),
// nunca en el repo ni en este PC de forma permanente.
//
//   node tools/publicar/firmar.mjs clave --dir /run/media/…/USB      crea la clave (una vez) y enseña la pública
//   node tools/publicar/firmar.mjs firmar --clave /…/publicar-ed25519.pem public/version.json public/altstore.json
//   node tools/publicar/firmar.mjs comprobar --publica <base64> public/version.json
//
// Cada archivo firmado queda junto a su `.sig`: base64 de Ed25519 sobre los **bytes exactos** del archivo (después de
// firmar no se puede tocar ni un espacio). La pública (32 bytes en base64) va en `Updates.PUBLISH_KEY` de las apps.
import { createPrivateKey, createPublicKey, generateKeyPairSync, sign, verify } from "node:crypto";
import { chmodSync, existsSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const NAME = "publicar-ed25519.pem";

const arg = (name) => {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : undefined;
};

/** 32 bytes en bruto de la pública, en base64 (lo que llevan las apps). */
export function publicKeyB64(key) {
  const der = createPublicKey(key).export({ type: "spki", format: "der" });
  return der.subarray(der.length - 32).toString("base64");
}

export function signBytes(priv, bytes) {
  return sign(null, bytes, priv).toString("base64");
}

/** La pública en bruto (base64) a un objeto de clave de Node. */
export function publicFromB64(b64) {
  const prefix = Buffer.from("302a300506032b6570032100", "hex"); // SPKI de Ed25519
  return createPublicKey({ key: Buffer.concat([prefix, Buffer.from(b64, "base64")]), format: "der", type: "spki" });
}

export function verifyBytes(publicB64, bytes, sigB64) {
  try {
    return verify(null, bytes, publicFromB64(publicB64), Buffer.from(sigB64.trim(), "base64"));
  } catch {
    return false;
  }
}

function insideRepo(path) {
  const real = existsSync(path) ? realpathSync(path) : resolve(path);
  return real === REPO || real.startsWith(REPO + "/");
}

function main() {
  const cmd = process.argv[2];
  if (cmd === "clave") {
    const dir = arg("dir");
    if (!dir || !existsSync(dir)) throw new Error("Falta --dir con la carpeta del USB (tiene que existir).");
    if (insideRepo(dir)) throw new Error("La clave no puede ir dentro del repo.");
    const path = join(dir, NAME);
    if (existsSync(path)) {
      console.log(`Ya hay clave en ${path}. Pública: ${publicKeyB64(createPrivateKey(readFileSync(path)))}`);
      return;
    }
    const { privateKey } = generateKeyPairSync("ed25519");
    writeFileSync(path, privateKey.export({ type: "pkcs8", format: "pem" }), { mode: 0o600 });
    chmodSync(path, 0o600);
    console.log(`Clave creada en ${path} (600). Guarda una copia en Proton Pass y desenchufa el USB al acabar.`);
    console.log(`Pública (va en Updates.PUBLISH_KEY de las dos apps): ${publicKeyB64(privateKey)}`);
    return;
  }
  if (cmd === "firmar") {
    const keyPath = arg("clave");
    if (!keyPath || !existsSync(keyPath)) throw new Error("Falta --clave con la ruta del .pem (en el USB).");
    if (insideRepo(keyPath)) throw new Error("La clave no puede estar dentro del repo.");
    const priv = createPrivateKey(readFileSync(keyPath));
    const targets = process.argv.slice(3).filter((a, i, all) => !a.startsWith("--") && all[i - 1] !== "--clave");
    if (targets.length === 0) throw new Error("Di qué archivos firmar.");
    for (const f of targets) {
      const sig = signBytes(priv, readFileSync(f));
      writeFileSync(`${f}.sig`, sig + "\n");
      console.log(`✅ ${f}.sig`);
    }
    return;
  }
  if (cmd === "comprobar") {
    const pub = arg("publica");
    if (!pub) throw new Error("Falta --publica <base64>.");
    const targets = process.argv.slice(3).filter((a, i, all) => !a.startsWith("--") && all[i - 1] !== "--publica");
    let ok = true;
    for (const f of targets) {
      const good = existsSync(`${f}.sig`) && verifyBytes(pub, readFileSync(f), readFileSync(`${f}.sig`, "utf8"));
      console.log(`${good ? "✅" : "❌"} ${f}`);
      ok &&= good;
    }
    process.exit(ok ? 0 : 1);
  }
  console.log("Uso: firmar.mjs clave --dir <USB> | firmar --clave <pem> <archivos…> | comprobar --publica <b64> <archivos…>");
  process.exit(1);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (e) {
    console.error(`❌ ${e.message}`);
    process.exit(1);
  }
}
