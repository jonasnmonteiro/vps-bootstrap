#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Keep the journal across reboots, with a fixed size limit"

restart=0

if [[ -d /var/log/journal ]]; then
  ok "Persistent journal directory exists."
else
  run install -d /var/log/journal
  run systemd-tmpfiles --create --prefix /var/log/journal
  changed "created /var/log/journal"
  restart=1
fi

sync_content /etc/systemd/journald.conf.d/00-limit.conf 644 < <(render "$CONFIG_DIR/journald/00-limit.conf" \
  MAX_USE="${JOURNAL_MAX_USE:-500M}")
[[ $FILE_CHANGED == 0 ]] || restart=1

if [[ $restart == 1 ]]; then
  restart_service systemd-journald
fi
