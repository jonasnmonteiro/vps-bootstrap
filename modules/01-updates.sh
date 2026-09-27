#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Refresh package lists and apply every pending upgrade"

run apt_get -qq update
pending="$(apt-get -s full-upgrade 2>/dev/null | grep -c '^Inst ' || true)"
if [[ $pending -eq 0 ]]; then
  ok "All packages are up to date."
else
  run apt_get full-upgrade
  changed "upgraded $pending packages"
fi

if [[ -f /var/run/reboot-required ]]; then
  warn "A reboot is required to load new kernel or library versions. Reboot after this run."
fi
