// Worker «libremusic-soporte»: POST /report (multipart/form-data) → canal privado de Discord.
// La URL del webhook sólo vive en el secreto DISCORD_WEBHOOK (npx wrangler secret put DISCORD_WEBHOOK);
// nunca en el repositorio ni en las apps.
import { LIMITS, checkReport, discordPayload, rateKey } from "./limits.js";

const json = (status, body) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8" } });

async function bump(env, key, max) {
  const n = parseInt((await env.RATE.get(key)) ?? "0", 10);
  if (n >= max) return false;
  await env.RATE.put(key, String(n + 1), { expirationTtl: 3700 });
  return true;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
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
      photos,
    };
    const problem = checkReport(report);
    if (problem) return json(400, { error: problem });

    const ip = request.headers.get("cf-connecting-ip") ?? "0";
    if (!(await bump(env, rateKey("dev", report.deviceId), LIMITS.perDevicePerHour)) ||
        !(await bump(env, rateKey("ip", ip), LIMITS.perIpPerHour))) {
      return json(429, { error: "Has enviado muchos reportes seguidos. Prueba dentro de una hora." });
    }

    const out = new FormData();
    out.append("payload_json", JSON.stringify(discordPayload(report)));
    photos.forEach((p, i) => out.append(`files[${i}]`, new Blob([p], { type: "image/jpeg" }), `foto-${i + 1}.jpg`));
    const res = await fetch(env.DISCORD_WEBHOOK, { method: "POST", body: out });
    if (!res.ok) return json(502, { error: "El servidor de soporte no responde. Prueba más tarde." });
    return json(200, { ok: true });
  },
};
