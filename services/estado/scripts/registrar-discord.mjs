#!/usr/bin/env node
// Registra el comando /panico en la aplicación de Discord de Pear Music (Fase 4). Lo ejecuta Toxbox, una vez y
// cada vez que cambie el comando. El token del bot sólo vive en su terminal: no se guarda en ningún archivo.
//
//   DISCORD_APP_ID=… DISCORD_GUILD_ID=… DISCORD_BOT_TOKEN=… node scripts/registrar-discord.mjs
//
// Se registra en el servidor (guild), no global: aparece al momento y sólo allí. Además el Worker comprueba el
// rol y el canal de administración, así que aunque alguien vea el comando no puede usarlo.
const { DISCORD_APP_ID: app, DISCORD_GUILD_ID: guild, DISCORD_BOT_TOKEN: token } = process.env;
if (!app || !guild || !token) {
  console.error("Faltan DISCORD_APP_ID, DISCORD_GUILD_ID o DISCORD_BOT_TOKEN (variables de entorno).");
  process.exit(1);
}

export const COMMAND = {
  name: "panico",
  description: "Botón de pánico de Pear Music (pide contraseña y código TOTP)",
  type: 1,
  default_member_permissions: "0", // oculto salvo a administradores del servidor
  contexts: [0], // sólo en servidores, nunca por mensaje directo
  options: [{
    type: 3, name: "accion", description: "Qué hacer", required: true,
    choices: [
      { name: "0 · Normal (resolver el incidente)", value: "0" },
      { name: "1 · Aviso (banner 24 h)", value: "1" },
      { name: "2 · Modo seguro", value: "2" },
      { name: "3 · Bloqueo total (pedir)", value: "3" },
      { name: "Confirmar bloqueo total (a los 10 min, otro código)", value: "confirmar" },
      { name: "Cancelar bloqueo pendiente", value: "cancelar" },
    ],
  }],
};

const r = await fetch(`https://discord.com/api/v10/applications/${app}/guilds/${guild}/commands`, {
  method: "PUT", // sustituye la lista entera: deja sólo /panico
  headers: { authorization: `Bot ${token}`, "content-type": "application/json" },
  body: JSON.stringify([COMMAND]),
});
console.log(r.ok ? "Comando /panico registrado." : `Discord respondió ${r.status}: ${await r.text()}`);
process.exit(r.ok ? 0 : 1);
