#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Lock the password of the default cloud image account"

account="${CLOUD_ACCOUNT:-ubuntu}"

if ! id "$account" >/dev/null 2>&1; then
  ok "No '$account' account on this system."
  exit 0
fi

status="$(passwd -S "$account" | awk '{print $2}')"

if [[ $status != P ]]; then
  ok "Password of '$account' is already locked or empty (status $status)."
elif [[ $account == "${ADMIN_USER:-}" ]]; then
  warn "'$account' is the admin user, so its password stays usable for sudo."
else
  run passwd -l "$account"
  changed "locked the password of $account"
fi

if grep -rqs "^$account .*NOPASSWD" /etc/sudoers.d/; then
  warn "'$account' has passwordless sudo in /etc/sudoers.d. Keep its SSH keys under control."
fi
