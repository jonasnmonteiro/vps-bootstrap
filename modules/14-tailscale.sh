#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Install Tailscale zero-trust VPN and enable tailscaled daemon"

auth_key="${TAILSCALE_AUTH_KEY:-}"
hostname="${NEW_HOSTNAME:-}"

if is_installed tailscale; then
  ok "Tailscale is installed."
else
  run install -m 0755 -d /usr/share/keyrings
  if [[ ! -f /usr/share/keyrings/tailscale-archive-keyring.gpg ]]; then
    run curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  fi
  if [[ ! -f /etc/apt/sources.list.d/tailscale.list ]]; then
    run curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list
    run apt_get update -qq
  fi
  apt_install tailscale
fi

if has_systemd; then
  if systemctl is-enabled --quiet tailscaled 2>/dev/null; then
    ok "tailscaled service is enabled."
  else
    run systemctl enable tailscaled
    changed "enabled tailscaled service"
  fi
  if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
    run systemctl start tailscaled
    changed "started tailscaled"
  else
    ok "tailscaled is running."
  fi
fi

if [[ -n $auth_key ]]; then
  args=(--auth-key="$auth_key" --ssh)
  [[ -n $hostname ]] && args+=(--hostname="$hostname")
  run tailscale up "${args[@]}"
  changed "connected node to tailnet"
elif [[ $DRY_RUN == 0 ]] && command -v tailscale >/dev/null 2>&1; then
  if tailscale status >/dev/null 2>&1; then
    ok "Tailscale is authenticated and connected."
  else
    warn "Tailscale installed but not logged in. Run 'sudo tailscale up' or set TAILSCALE_AUTH_KEY in .env."
  fi
fi
