#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Set the clock to UTC and keep it synchronized over NTP"

timezone="${TIMEZONE:-UTC}"

[[ -f /usr/share/zoneinfo/$timezone ]] || die "Unknown TIMEZONE '$timezone'."

if ! has_systemd; then
  warn "systemd is not running, so timedatectl is unavailable. Skipping."
  exit 0
fi

current="$(timedatectl show --property=Timezone --value)"
if same_timezone "$current" "$timezone"; then
  ok "Timezone is $timezone."
else
  run timedatectl set-timezone "$timezone"
  changed "timezone $current -> $timezone"
fi

if in_container; then
  warn "Running inside a container: the host owns the clock, NTP is not configured here."
  exit 0
fi

if [[ $(timedatectl show --property=NTP --value) == yes ]]; then
  ok "NTP synchronization is enabled."
else
  if ! is_installed systemd-timesyncd && ! is_installed chrony; then
    apt_install systemd-timesyncd
  fi
  run timedatectl set-ntp true
  changed "enabled NTP synchronization"
fi
