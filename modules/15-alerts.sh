#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Configure Telegram webhook notifications for fail2ban bans and security alerts"

bot_token="${TELEGRAM_BOT_TOKEN:-}"
chat_id="${TELEGRAM_CHAT_ID:-}"

if [[ -z $bot_token || -z $chat_id ]]; then
  ok "TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set. Skipping Telegram notification hook."
  exit 0
fi

sync_content /etc/fail2ban/action.d/telegram.conf 644 < <(render "$CONFIG_DIR/fail2ban/telegram.conf" \
  TELEGRAM_BOT_TOKEN="$bot_token" \
  TELEGRAM_CHAT_ID="$chat_id")

sync_content /usr/local/bin/notify-telegram 755 < <(render "$CONFIG_DIR/alerts/notify-telegram" \
  TELEGRAM_BOT_TOKEN="$bot_token" \
  TELEGRAM_CHAT_ID="$chat_id")

if [[ -f /etc/fail2ban/jail.local ]]; then
  if grep -q 'action = %(action_)s telegram' /etc/fail2ban/jail.local; then
    ok "Telegram action already configured in jail.local."
  elif grep -q 'action = ' /etc/fail2ban/jail.local; then
    run sed -i 's/^action = .*/action = %(action_)s telegram/' /etc/fail2ban/jail.local
    changed "enabled telegram action in /etc/fail2ban/jail.local"
    restart_service fail2ban
  else
    append_line /etc/fail2ban/jail.local "action = %(action_)s telegram"
    changed "added telegram action to /etc/fail2ban/jail.local"
    restart_service fail2ban
  fi
fi
