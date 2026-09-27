#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Set the hostname and make it survive cloud-init on reboot"

name="${NEW_HOSTNAME:-}"

if [[ -z $name ]]; then
  ok "NEW_HOSTNAME is empty, keeping '$(hostname)'."
  exit 0
fi
[[ $name =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || die "NEW_HOSTNAME '$name' is not a valid hostname."

if [[ $(cat /etc/hostname 2>/dev/null) == "$name" && $(hostname) == "$name" ]]; then
  ok "Hostname is $name."
elif has_systemd && ! in_container; then
  run hostnamectl set-hostname "$name"
  changed "hostname set to $name"
else
  run hostname "$name"
  tmp="$(mktemp)"
  printf '%s\n' "$name" >"$tmp"
  write_in_place /etc/hostname "$tmp"
  rm -f "$tmp"
  changed "hostname set to $name"
fi

hosts_line="$(printf '127.0.1.1\t%s' "$name")"
if grep -qxF "$hosts_line" /etc/hosts; then
  ok "/etc/hosts resolves $name."
else
  tmp="$(mktemp)"
  if grep -q '^127\.0\.1\.1[[:space:]]' /etc/hosts; then
    sed "s/^127\.0\.1\.1[[:space:]].*/$hosts_line/" /etc/hosts >"$tmp"
  else
    cat /etc/hosts >"$tmp"
    printf '%s\n' "$hosts_line" >>"$tmp"
  fi
  write_in_place /etc/hosts "$tmp"
  rm -f "$tmp"
  changed "mapped 127.0.1.1 to $name in /etc/hosts"
fi

cloud_cfg=/etc/cloud/cloud.cfg
if [[ ! -f $cloud_cfg ]]; then
  ok "cloud-init is not installed, nothing can revert the hostname."
elif grep -qE '^preserve_hostname:[[:space:]]*true' "$cloud_cfg"; then
  ok "cloud-init preserves the hostname."
elif grep -q '^preserve_hostname:' "$cloud_cfg"; then
  run sed -i 's/^preserve_hostname:.*/preserve_hostname: true/' "$cloud_cfg"
  changed "set preserve_hostname: true in $cloud_cfg"
else
  append_line "$cloud_cfg" "preserve_hostname: true"
  changed "added preserve_hostname: true to $cloud_cfg"
fi
