#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Install Caddy reverse proxy with automatic HTTPS and hardened headers"

if is_installed caddy; then
  ok "Caddy is installed."
else
  run install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/caddy.asc ]]; then
    run curl -fsSL 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' -o /etc/apt/keyrings/caddy.asc
    run chmod a+r /etc/apt/keyrings/caddy.asc
  fi
  echo "deb [signed-by=/etc/apt/keyrings/caddy.asc] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" > /tmp/caddy.list
  sync_file /tmp/caddy.list /etc/apt/sources.list.d/caddy-stable.list 644
  rm -f /tmp/caddy.list
  run apt_get update -qq
  apt_install caddy
fi

sync_file "$CONFIG_DIR/caddy/Caddyfile" /etc/caddy/Caddyfile 644

if [[ $DRY_RUN == 0 ]] && command -v caddy >/dev/null 2>&1; then
  caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 || die "Caddyfile validation failed."
fi

if has_systemd; then
  if systemctl is-enabled --quiet caddy 2>/dev/null; then
    ok "Caddy is enabled at boot."
  else
    run systemctl enable caddy
    changed "enabled caddy service"
  fi
  if [[ $FILE_CHANGED == 1 ]]; then
    restart_service caddy
  elif systemctl is-active --quiet caddy 2>/dev/null; then
    ok "Caddy is running."
  else
    run systemctl start caddy
    changed "started caddy"
  fi
fi
