// Tickets de soporte y sugerencias (Cierre 1.0; lo pidió Toxbox). Cada reporte o sugerencia que llega a Discord
// abre un ticket numerado. Desde Discord:
//   /msg ticket:<abierto, autocompletado> texto:<…> tipo:<mensaje|fiesta|en-ello>   → aviso SÓLO a esa persona
//   /rp ticket:<n> accion:<o|c>   o = abrir (hilo propio en Discord y aviso «abierta» con un check), c = cerrar
// La app de quien lo envió recoge sus avisos con GET /mensajes?device=<id anónimo de la instalación>; aquí sólo se
// guarda su resumen (SHA-256), nunca el id, y sin correo.
import { hashId } from "./spam.js";

export const TIPOS = {
  abierto: "Abrimos tu incidencia",
  mensaje: "Respuesta de Pear Music",
  fiesta: "¡Solucionado! Gracias",
  "en-ello": "Estamos en ello",
};
const KEEP_MESSAGES = 50;
const TTL = 180 * 86_400; // 6 meses

const getJSON = async (env, k, def) => {
  const v = await env.RATE.get(k);
  return v ? JSON.parse(v) : def;
};
const putJSON = (env, k, v, ttl = TTL) => env.RATE.put(k, JSON.stringify(v), { expirationTtl: ttl });

/** Número nuevo (1, 2, 3…). */
export async function nextTicket(env) {
  const n = parseInt((await env.RATE.get("ticket:seq")) ?? "0", 10) + 1;
  await env.RATE.put("ticket:seq", String(n));
  return n;
}

export async function saveTicket(env, n, { kind, deviceId, text, platform }) {
  const t = { n, kind, device: await hashId(deviceId), summary: text.trim().replace(/\s+/g, " ").slice(0, 80), platform, status: "nuevo", at: new Date().toISOString() };
  await putJSON(env, `t:${n}`, t);
  const open = await getJSON(env, "tickets:open", []);
  open.unshift({ n, kind, summary: t.summary });
  await putJSON(env, "tickets:open", open.slice(0, 200));
  return t;
}

/** Aviso para la persona del ticket. */
export async function notify(env, ticket, tipo, text) {
  const key = `msgs:${ticket.device}`;
  const list = await getJSON(env, key, []);
  const m = { id: crypto.randomUUID(), ticket: ticket.n, kind: ticket.kind, tipo, title: TIPOS[tipo] ?? TIPOS.mensaje, text: String(text ?? "").slice(0, 2000), at: new Date().toISOString() };
  list.unshift(m);
  await putJSON(env, key, list.slice(0, KEEP_MESSAGES));
  return m;
}

/** GET /mensajes?device=…: los avisos de esa instalación (sólo los suyos). */
export async function messagesFor(env, deviceId) {
  if (typeof deviceId !== "string" || deviceId.length < 8 || deviceId.length > 100) return null;
  return getJSON(env, `msgs:${await hashId(deviceId)}`, []);
}

// MARK: Discord

const json = (body) => new Response(JSON.stringify(body), { headers: { "content-type": "application/json; charset=utf-8" } });
const ephemeral = (content) => json({ type: 4, data: { content, flags: 64, allowed_mentions: { parse: [] } } });
const hex = (s) => new Uint8Array(String(s).match(/../g)?.map((h) => parseInt(h, 16)) ?? []);

async function signed(env, request, body) {
  try {
    const key = await crypto.subtle.importKey("raw", hex(env.DISCORD_PUBLIC_KEY), { name: "Ed25519" }, false, ["verify"]);
    const ts = request.headers.get("x-signature-timestamp") ?? "";
    return await crypto.subtle.verify({ name: "Ed25519" }, key, hex(request.headers.get("x-signature-ed25519") ?? ""), new TextEncoder().encode(ts + body));
  } catch {
    return false;
  }
}

/** Llamada a la API de Discord con el token del bot (secreto DISCORD_BOT_TOKEN); sin token no hace nada. */
async function bot(env, method, path, body) {
  if (!env.DISCORD_BOT_TOKEN) return null;
  const r = await fetch(`https://discord.com/api/v10${path}`, {
    method,
    headers: { authorization: `Bot ${env.DISCORD_BOT_TOKEN}`, "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  return r.ok ? r.json().catch(() => ({})) : null;
}

const option = (i, name) => i.data?.options?.find((o) => o.name === name);

export async function discord(env, request) {
  const raw = await request.text();
  if (!(await signed(env, request, raw))) return new Response("Firma no válida", { status: 401 });
  const i = JSON.parse(raw);
  if (i.type === 1) return json({ type: 1 });
  const roles = i.member?.roles ?? [];
  if (env.DISCORD_ADMIN_ROLE && !roles.includes(env.DISCORD_ADMIN_ROLE)) return ephemeral("Sólo para el rol de soporte.");

  // Autocompletar: los tickets abiertos que coinciden con lo escrito.
  if (i.type === 4) {
    const typed = String(option(i, "ticket")?.value ?? "").toLowerCase();
    const open = await getJSON(env, "tickets:open", []);
    const choices = open
      .filter((t) => !typed || String(t.n).startsWith(typed.replace("#", "")) || t.summary.toLowerCase().includes(typed))
      .slice(0, 25)
      .map((t) => ({ name: `#${t.n} · ${t.kind === "sugerencia" ? "💡" : "🐞"} ${t.summary}`.slice(0, 100), value: t.n }));
    return json({ type: 8, data: { choices } });
  }

  if (i.type !== 2) return ephemeral("Comando desconocido.");
  const n = Number(option(i, "ticket")?.value);
  const ticket = await getJSON(env, `t:${n}`, null);
  if (!ticket) return ephemeral(`No existe el ticket #${n}.`);

  if (i.data.name === "msg") {
    const text = String(option(i, "texto")?.value ?? "").trim();
    let tipo = option(i, "tipo")?.value ?? "mensaje";
    // También vale escribirlo en el texto: «fiesta» (solucionado) o «estamos en ello».
    if (!option(i, "tipo") && /^fiesta\b/i.test(text)) tipo = "fiesta";
    if (!option(i, "tipo") && /^estamos en ello/i.test(text)) tipo = "en-ello";
    if (ticket.status === "cerrado") return ephemeral(`El ticket #${n} está cerrado.`);
    await notify(env, ticket, tipo, text);
    if (ticket.thread) await bot(env, "POST", `/channels/${ticket.thread}/messages`, { content: `**${TIPOS[tipo]}** (enviado a la persona): ${text}`.slice(0, 2000), allowed_mentions: { parse: [] } });
    return ephemeral(`✅ Enviado al ticket #${n} como «${TIPOS[tipo]}». Sólo lo ve esa persona.`);
  }

  if (i.data.name === "rp") {
    const accion = option(i, "accion")?.value;
    if (accion === "o") {
      ticket.status = "abierto";
      // Hilo propio para tenerlo localizado (necesita el bot en el servidor y DISCORD_TICKETS_CHANNEL).
      if (!ticket.thread && env.DISCORD_TICKETS_CHANNEL) {
        const th = await bot(env, "POST", `/channels/${env.DISCORD_TICKETS_CHANNEL}/threads`, { name: `Ticket #${n} · ${ticket.summary}`.slice(0, 100), type: 11, auto_archive_duration: 10080 });
        if (th?.id) {
          ticket.thread = th.id;
          await bot(env, "POST", `/channels/${th.id}/messages`, { content: `${ticket.kind === "sugerencia" ? "💡 Sugerencia" : "🐞 Error"} #${n} (${ticket.platform}): ${ticket.summary}`, allowed_mentions: { parse: [] } });
        }
      }
      await putJSON(env, `t:${n}`, ticket);
      await notify(env, ticket, "abierto", option(i, "texto")?.value ?? "Hemos abierto tu incidencia y la estamos mirando. Te avisaremos aquí.");
      return ephemeral(`📂 Ticket #${n} abierto${ticket.thread ? ` en <#${ticket.thread}>` : ""}. La persona ve el aviso con un check.`);
    }
    if (accion === "c") {
      ticket.status = "cerrado";
      await putJSON(env, `t:${n}`, ticket);
      const open = await getJSON(env, "tickets:open", []);
      await putJSON(env, "tickets:open", open.filter((t) => t.n !== n));
      if (ticket.thread) await bot(env, "PATCH", `/channels/${ticket.thread}`, { archived: true, locked: true });
      return ephemeral(`🔒 Ticket #${n} cerrado.`);
    }
    return ephemeral("Acción: o (abrir) o c (cerrar).");
  }
  return ephemeral("Comando desconocido.");
}
