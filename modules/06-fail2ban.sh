#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Install fail2ban with an sshd jail that reads the systemd journal"

apt_install fail2ban python3-systemd

sync_content /etc/fail2ban/jail.local 644 < <(render "$CONFIG_DIR/fail2ban/jail.local" \
  IGNORE_IP="${FAIL2BAN_IGNORE_IP:-127.0.0.1/8 ::1}" \
  BAN_TIME="${FAIL2BAN_BAN_TIME:-1h}" \
  MAX_RETRY="${FAIL2BAN_MAX_RETRY:-5}")

if ! has_systemd; then
  warn "systemd is not running, so the fail2ban service was not started."
  exit 0
fi

if [[ $DRY_RUN == 0 ]] && command -v fail2ban-client >/dev/null 2>&1; then
  if ! test_output="$(fail2ban-client -t 2>&1)"; then
    printf '%s\n' "$test_output" >&2
    die "fail2ban-client -t rejected the configuration."
  fi
fi

if systemctl is-enabled --quiet fail2ban 2>/dev/null; then
  ok "fail2ban is enabled at boot."
else
  run systemctl enable fail2ban
  changed "enabled fail2ban at boot"
fi

if ! systemctl is-active --quiet fail2ban 2>/dev/null; then
  run systemctl start fail2ban
  changed "started fail2ban"
elif [[ $FILE_CHANGED == 1 ]]; then
  restart_service fail2ban
else
  ok "fail2ban is running."
fi
