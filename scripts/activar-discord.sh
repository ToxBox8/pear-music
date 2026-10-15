#!/usr/bin/env bash
# Activa las dos aplicaciones de Discord de Pear Music con los datos guardados en ~/.config/pear-music (600):
#
#   discord-soporte.env  APP_ID, PUBLIC_KEY, BOT_TOKEN, ADMIN_ROLE, TICKETS_CHANNEL
#   discord-panico.env   APP_ID, PUBLIC_KEY, BOT_TOKEN, ADMIN_ROLE, ADMIN_CHANNEL, ALERT_WEBHOOK (opcional)
#
#   bash scripts/activar-discord.sh soporte|panico|todo
#
# Sube los secretos a su Worker (sin enseñarlos), pone los id en wrangler.toml, despliega y registra los comandos
# (/msg y /rp en soporte; /panico en el estado). Después hay que poner la Interactions Endpoint URL en el portal
# (Discord la prueba al guardar, por eso va después del despliegue).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CFG=~/.config/pear-music
GUILD=1559653765630533673

load() { # carga un .env sin exportar nada más
  local f="$CFG/discord-$1.env"
  [ -f "$f" ] || { echo "❌ Falta $f"; exit 1; }
  [ "$(stat -c %a "$f")" = 600 ] || chmod 600 "$f"
  unset APP_ID PUBLIC_KEY BOT_TOKEN ADMIN_ROLE TICKETS_CHANNEL ADMIN_CHANNEL ALERT_WEBHOOK
  # shellcheck disable=SC1090
  source "$f"
}

secret() { printf '%s' "$2" | npx wrangler secret put "$1" >/dev/null && echo "  · $1 subido"; }

setvar() { # setvar archivo CLAVE valor
  if grep -q "^$2 = " "$1"; then sed -i "s|^$2 = .*|$2 = \"$3\"|" "$1"
  else sed -i "/^\[vars\]/a $2 = \"$3\"" "$1"; fi
}

soporte() {
  load soporte
  cd "$ROOT/services/soporte"
  grep -q '^\[vars\]' wrangler.toml || printf '\n[vars]\n' >> wrangler.toml
  setvar wrangler.toml DISCORD_ADMIN_ROLE "$ADMIN_ROLE"
  setvar wrangler.toml DISCORD_TICKETS_CHANNEL "$TICKETS_CHANNEL"
  npm test --silent >/dev/null && echo "  · tests del soporte en verde"
  secret DISCORD_PUBLIC_KEY "$PUBLIC_KEY"
  secret DISCORD_BOT_TOKEN "$BOT_TOKEN"
  npx wrangler deploy >/dev/null && echo "  · libremusic-soporte desplegado"
  DISCORD_APP_ID=$APP_ID DISCORD_GUILD_ID=$GUILD DISCORD_BOT_TOKEN=$BOT_TOKEN node scripts/registrar-discord.mjs
  echo "✅ Soporte. Interactions Endpoint URL: https://libremusic-soporte.8toxbox8-69a.workers.dev/discord"
}

panico() {
  load panico
  cd "$ROOT/services/estado"
  setvar wrangler.toml DISCORD_ADMIN_ROLE "$ADMIN_ROLE"
  setvar wrangler.toml DISCORD_ADMIN_CHANNEL "$ADMIN_CHANNEL"
  npm test --silent >/dev/null && echo "  · tests del estado en verde"
  secret DISCORD_PUBLIC_KEY "$PUBLIC_KEY"
  [ -n "${ALERT_WEBHOOK:-}" ] && secret ALERT_WEBHOOK "$ALERT_WEBHOOK"
  npx wrangler deploy >/dev/null && echo "  · pear-music-estado desplegado"
  DISCORD_APP_ID=$APP_ID DISCORD_GUILD_ID=$GUILD DISCORD_BOT_TOKEN=$BOT_TOKEN node scripts/registrar-discord.mjs
  echo "✅ Pánico. Interactions Endpoint URL: https://pear-music-estado.8toxbox8-69a.workers.dev/discord"
  echo "   Falta (Toxbox, en su terminal): node scripts/preparar-secretos.mjs  (contraseña + TOTP)"
}

case "${1:-todo}" in
  soporte) soporte ;;
  panico) panico ;;
  todo) soporte; panico ;;
  *) echo "Uso: $0 soporte|panico|todo"; exit 1 ;;
esac
