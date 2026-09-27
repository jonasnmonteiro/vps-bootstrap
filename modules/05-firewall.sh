#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Enable UFW: deny incoming, allow outgoing, open only the listed ports"

read -ra ports <<<"${UFW_ALLOW:-22/tcp 80/tcp 443/tcp}"

printf '%s\n' "${ports[@]}" | grep -qxE '22(/tcp)?' \
  || die "UFW_ALLOW must include 22/tcp. Enabling the firewall without it cuts your own session."

apt_install ufw

if ! command -v ufw >/dev/null 2>&1; then
  run sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
  run ufw default deny incoming
  run ufw default allow outgoing
  for port in "${ports[@]}"; do run ufw allow "$port"; done
  run ufw --force enable
  exit 0
fi

if grep -qx 'IPV6=yes' /etc/default/ufw; then
  ok "UFW manages IPv6 as well."
else
  run sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
  changed "set IPV6=yes in /etc/default/ufw"
fi

grep -qx 'DEFAULT_INPUT_POLICY="DROP"' /etc/default/ufw || { run ufw default deny incoming; changed "default policy: deny incoming"; }
grep -qx 'DEFAULT_OUTPUT_POLICY="ACCEPT"' /etc/default/ufw || { run ufw default allow outgoing; changed "default policy: allow outgoing"; }

added="$(ufw show added 2>/dev/null)"
for port in "${ports[@]}"; do
  if grep -qx "ufw allow $port" <<<"$added"; then
    ok "Rule present: allow $port"
  else
    run ufw allow "$port"
    changed "allowed $port"
  fi
done

if ufw status | grep -qx 'Status: active'; then
  ok "UFW is active."
  if [[ $CHANGED == 1 ]]; then
    run ufw reload
  fi
else
  run ufw --force enable
  changed "enabled UFW"
fi
