// Worker «libremusic-soporte»: POST /report (multipart/form-data; kind=sugerencia para el buzón) → canal privado
// de Discord con un ticket numerado, POST /appeal (apelar un rechazo), POST /discord (comandos /msg y /rp) y
// GET /mensajes (los avisos de cada instalación; src/tickets.js). Capas contra tickets no genuinos: la app valida antes de enviar; aquí, reglas de
// contenido (spam.js), límites por hora, repetición en 24 h y registro de cada rechazo para poder apelarlo.
// La URL del webhook sólo vive en el secreto DISCORD_WEBHOOK (npx wrangler secret put DISCORD_WEBHOOK);
// nunca en el repositorio ni en las apps.
import { LIMITS, checkReport, discordPayload, rateKey } from "./limits.js";
import { domainReceivesMail, hashId, textFingerprint } from "./spam.js";
import { discord, messagesFor, nextTicket, saveTicket } from "./tickets.js";

const json = (status, body) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8" } });

/** Contadores de la hora: se miran antes de enviar y sólo suben si el reporte llega a Discord. */
async function count(env, key) {
  return parseInt((await env.RATE.get(key)) ?? "0", 10);
}
async function bump(env, key, n) {
  await env.RATE.put(key, String(n + 1), { expirationTtl: 3700 });
}

/**
 * Rechazo por el contenido: se registra 30 días (motivo, móvil resumido y huella del texto; nunca el texto ni
 * el correo) y se devuelve un `denialId` para que la app ofrezca reformular o apelar.
 */
async function deny(env, reason, deviceId, text) {
  const denialId = crypto.randomUUID();
  const record = { reason, device: await hashId(deviceId || "?"), text: await textFingerprint(text), at: new Date().toISOString() };
  await env.RATE.put(`deny:${denialId}`, JSON.stringify(record), { expirationTtl: LIMITS.denialTtlSeconds });
  return json(400, { error: reason, denialId, canAppeal: true });
}

/** POST /appeal { denialId, deviceId, email, text }: llega a Discord marcado como apelación. */
async function appeal(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "Apelación mal formada." });
  }
  const raw = await env.RATE.get(`deny:${body?.denialId ?? ""}`);
  if (!raw) return json(404, { error: "Ese rechazo ya no existe (se guardan 30 días)." });
  const denial = JSON.parse(raw);
  if (denial.appealed) return json(409, { error: "Ya apelaste este rechazo. Te contestaremos al correo." });
  const device = await hashId(body.deviceId ?? "");
  if (device !== denial.device) return json(403, { error: "Sólo puede apelar el móvil que lo envió." });
  const text = String(body.text ?? "").trim();
  if (text.length < LIMITS.minAppealText || text.length > LIMITS.maxAppealText) {
    return json(400, { error: `Explica en ${LIMITS.minAppealText}–${LIMITS.maxAppealText} caracteres por qué es un reporte de verdad.` });
  }
  const key = `ap:${device}:${Math.floor(Date.now() / 86_400_000)}`;
  const n = await count(env, key);
  if (n >= LIMITS.appealsPerDevicePerDay) return json(429, { error: "Has apelado varias veces hoy. Prueba mañana." });
  const res = await fetch(env.DISCORD_WEBHOOK, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      username: "Pear Music · soporte",
      allowed_mentions: { parse: [] },
      embeds: [{
        title: "Apelación de un reporte rechazado",
        description: text.slice(0, 4000),
        color: 0xf59e0b,
        fields: [
          { name: "Motivo del rechazo", value: denial.reason.slice(0, 1024) },
          { name: "Correo", value: String(body.email ?? "—").trim().slice(0, 254) || "—", inline: true },
          { name: "Rechazo", value: `${body.denialId.slice(0, 8)} · ${denial.at}`, inline: true },
        ],
        timestamp: new Date().toISOString(),
      }],
    }),
  });
  if (!res.ok) return json(502, { error: "El servidor de soporte no responde. Prueba más tarde." });
  await env.RATE.put(`deny:${body.denialId}`, JSON.stringify({ ...denial, appealed: true }), { expirationTtl: LIMITS.denialTtlSeconds });
  await env.RATE.put(key, String(n + 1), { expirationTtl: 90_000 });
  return json(200, { ok: true });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/appeal" && request.method === "POST") return appeal(request, env);
    // Tickets (Cierre 1.0): comandos /msg y /rp de Discord, y los avisos de cada instalación.
    if (url.pathname === "/discord" && request.method === "POST") return discord(env, request);
    if (url.pathname === "/mensajes" && request.method === "GET") {
      const list = await messagesFor(env, url.searchParams.get("device"));
      return list ? json(200, { mensajes: list }) : json(400, { error: "Identificador no válido." });
    }
    if (url.pathname !== "/report") return json(404, { error: "No encontrado." });
    if (request.method !== "POST") return json(405, { error: "Usa POST." });
    const length = parseInt(request.headers.get("content-length") ?? "0", 10);
    if (length > LIMITS.maxTotalBytes + 200_000) return json(413, { error: "El reporte pesa demasiado." });

    let form;
    try {
      form = await request.formData();
    } catch {
      return json(400, { error: "Reporte mal formado." });
    }
    const photos = [];
    for (const [key, value] of form.entries()) {
      if (key.startsWith("photo") && typeof value === "object") {
        if (value.type !== "image/jpeg") return json(415, { error: "Sólo se admiten fotos JPEG." });
        photos.push(new Uint8Array(await value.arrayBuffer()));
      }
    }
    const report = {
      email: form.get("email") ?? "",
      text: form.get("text") ?? "",
      platform: form.get("platform") ?? "",
      appVersion: form.get("appVersion") ?? "",
      os: form.get("os") ?? "",
      model: form.get("model") ?? "",
      deviceId: form.get("deviceId") ?? "",
      // «sugerencia» desde el buzón de Ayuda y soporte; si no, un reporte de error.
      kind: form.get("kind") === "sugerencia" ? "sugerencia" : "error",
      photos,
    };
    const problem = checkReport(report);
    if (problem) return deny(env, problem, report.deviceId, report.text);

    const domain = report.email.trim().toLowerCase().split("@")[1];
    if (!(await domainReceivesMail(domain))) {
      return deny(env, "Ese correo no existe (su dominio no recibe correo). Revisa que esté bien escrito.", report.deviceId, report.text);
    }


    // Uno por hora por móvil y por correo; las claves llevan un resumen (hash), no la IP ni el correo.
    const ip = request.headers.get("cf-connecting-ip") ?? "0";
    const keys = [
      [rateKey("dev", await hashId(report.deviceId)), LIMITS.perDevicePerHour],
      [rateKey("mail", await hashId(report.email)), LIMITS.perEmailPerHour],
      [rateKey("ip", await hashId(ip)), LIMITS.perIpPerHour],
    ];
    const counts = await Promise.all(keys.map(([k]) => count(env, k)));
    if (counts.some((n, i) => n >= keys[i][1])) {
      return json(429, { error: "Ya has enviado un reporte hace poco. Puedes mandar otro dentro de una hora." });
    }

    // El mismo texto otra vez desde el mismo móvil en 24 h: ya lo tenemos.
    const seenKey = `seen:${await hashId(report.deviceId)}:${await textFingerprint(report.text)}`;
    if (await env.RATE.get(seenKey)) {
      return deny(env, "Ya nos mandaste este mismo reporte hoy. Si ha pasado algo nuevo, cuéntalo con otras palabras.", report.deviceId, report.text);
    }

    report.ticket = await nextTicket(env);
    const out = new FormData();
    out.append("payload_json", JSON.stringify(discordPayload(report)));
    photos.forEach((p, i) => out.append(`files[${i}]`, new Blob([p], { type: "image/jpeg" }), `foto-${i + 1}.jpg`));
    // Cada tipo a su canal (2.8 de x.1.1): #sugerencias (DISCORD_WEBHOOK_SUGERENCIAS) y #reportes
    // (DISCORD_WEBHOOK_REPORTES); si falta alguno, al de soporte de siempre.
    const hook = (report.kind === "sugerencia" ? env.DISCORD_WEBHOOK_SUGERENCIAS : env.DISCORD_WEBHOOK_REPORTES) || env.DISCORD_WEBHOOK;
    const res = await fetch(hook, { method: "POST", body: out });
    if (!res.ok) return json(502, { error: "El servidor de soporte no responde. Prueba más tarde." });
    await saveTicket(env, report.ticket, report);
    await Promise.all(keys.map(([k], i) => bump(env, k, counts[i])));
    await env.RATE.put(seenKey, "1", { expirationTtl: LIMITS.repeatWindowSeconds });
    return json(200, { ok: true, ticket: report.ticket });
  },
};
