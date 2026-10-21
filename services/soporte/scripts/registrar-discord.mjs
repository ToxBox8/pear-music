#!/usr/bin/env node
// Registra /msg y /rp (tickets de soporte, Cierre 1.0) y /sugerencias y /reportes (listados, x.1.1) en la aplicación de Discord «Pear Music · soporte». Lo
// ejecuta Toxbox; el token del bot sólo vive en su terminal.
//
//   DISCORD_APP_ID=… DISCORD_GUILD_ID=… DISCORD_BOT_TOKEN=… node scripts/registrar-discord.mjs
//
// Es otra aplicación que la del botón de pánico: cada aplicación de Discord tiene una sola URL de interacciones
// (ésta apunta a https://libremusic-soporte.8toxbox8-69a.workers.dev/discord).
const { DISCORD_APP_ID: app, DISCORD_GUILD_ID: guild, DISCORD_BOT_TOKEN: token } = process.env;
if (!app || !guild || !token) {
  console.error("Faltan DISCORD_APP_ID, DISCORD_GUILD_ID o DISCORD_BOT_TOKEN (variables de entorno).");
  process.exit(1);
}
const ticket = { type: 4, name: "ticket", description: "Ticket abierto", required: true, autocomplete: true };
export const COMMANDS = [
  {
    name: "msg", description: "Contestar a quien abrió un ticket (sólo lo ve esa persona)", type: 1,
    default_member_permissions: "0", contexts: [0],
    options: [
      ticket,
      { type: 3, name: "texto", description: "Lo que le llega como aviso", required: true, max_length: 2000 },
      { type: 3, name: "tipo", description: "Icono del aviso", required: false, choices: [
        { name: "💬 Mensaje", value: "mensaje" },
        { name: "🎉 Fiesta: solucionado, gracias", value: "fiesta" },
        { name: ">_ Estamos en ello", value: "en-ello" },
      ] },
    ],
  },
  {
    name: "rp", description: "Abrir (o) o cerrar (c) un ticket", type: 1,
    default_member_permissions: "0", contexts: [0],
    options: [
      ticket,
      { type: 3, name: "accion", description: "o = abrir (hilo propio y aviso ✓), c = cerrar", required: true, choices: [
        { name: "o · abrir", value: "o" }, { name: "c · cerrar", value: "c" },
      ] },
      { type: 3, name: "texto", description: "Mensaje al abrir (opcional)", required: false, max_length: 2000 },
    ],
  },
  // Listados (2.1 de x.1.1): sólo los ve quien los pide, 20 por página con ◀ ▶.
  ...[["sugerencias", "Listar sugerencias (sólo lo ves tú)"], ["reportes", "Listar reportes de errores (sólo lo ves tú)"]].map(([name, description]) => ({
    name, description, type: 1, default_member_permissions: "0", contexts: [0],
    options: [
      { type: 3, name: "estado", description: "Abiertas (por defecto), cerradas o todas", required: false, choices: [
        { name: "abiertas", value: "abiertas" }, { name: "cerradas", value: "cerradas" }, { name: "todas", value: "todas" },
      ] },
      { type: 4, name: "desde", description: "Sólo los de los últimos N días", required: false, min_value: 1, max_value: 365 },
    ],
  })),
];
const r = await fetch(`https://discord.com/api/v10/applications/${app}/guilds/${guild}/commands`, {
  method: "PUT", headers: { authorization: `Bot ${token}`, "content-type": "application/json" }, body: JSON.stringify(COMMANDS),
});
console.log(r.ok ? "Comandos /msg, /rp, /sugerencias y /reportes registrados." : `Discord respondió ${r.status}: ${await r.text()}`);
process.exit(r.ok ? 0 : 1);
