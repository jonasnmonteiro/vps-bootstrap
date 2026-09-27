#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Install Caddy reverse proxy with automatic HTTPS and hardened headers"

if is_installed caddy; then
  ok "Caddy is installed."
else
  apt_install debian-keyring debian-archive-keyring apt-transport-https
  if [[ ! -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg ]]; then
    run curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  fi
  if [[ ! -f /etc/apt/sources.list.d/caddy-stable.list ]]; then
    run curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    run apt_get update -qq
  fi
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
