#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Install security updates automatically, never reboot automatically"

apt_install unattended-upgrades
sync_file "$CONFIG_DIR/apt/20auto-upgrades" /etc/apt/apt.conf.d/20auto-upgrades 644
sync_file "$CONFIG_DIR/apt/99local-upgrades" /etc/apt/apt.conf.d/99local-upgrades 644
