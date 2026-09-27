#!/usr/bin/env bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$REPO_ROOT/configs"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
CHANGED=0
FILE_CHANGED=0

if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  C_BLUE=$'\033[1;34m' C_GREEN=$'\033[1;32m' C_YELLOW=$'\033[1;33m' C_RED=$'\033[1;31m' C_RESET=$'\033[0m'
else
  C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_RESET=''
fi

log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
fail() { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()  { fail "$*"; exit 1; }
describe() { log "$(basename "$0" .sh): $*"; }

refuse() {
  if [[ $DRY_RUN == 1 ]]; then
    warn "$* (a real run would stop here)"
  else
    die "$*"
  fi
}

ask() {
  local reply
  read -rp "$1 [y/N] " reply
  [[ $reply =~ ^[yY]$ ]]
}

run() {
  if [[ $DRY_RUN == 1 ]]; then
    printf '   [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

changed() {
  CHANGED=1
  if [[ $DRY_RUN == 1 ]]; then
    printf '   [would change] %s\n' "$*"
  else
    printf '   [changed] %s\n' "$*"
  fi
  if [[ -n ${CHANGES_FILE:-} ]]; then
    printf '%s: %s\n' "$(basename "$0" .sh)" "$*" >>"$CHANGES_FILE"
  fi
}

load_env() {
  local file="$REPO_ROOT/.env" key value
  [[ -f $file ]] || return 0
  while IFS='=' read -r key value || [[ -n $key ]]; do
    [[ $key =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
    [[ -n ${!key+x} ]] && continue
    value="${value%\"}"
    value="${value#\"}"
    export "$key=$value"
  done <"$file"
}

same_timezone() {
  [[ $(readlink -f "/usr/share/zoneinfo/$1") == "$(readlink -f "/usr/share/zoneinfo/$2")" ]]
}

has_systemd() { [[ -d /run/systemd/system ]]; }

in_container() { systemd-detect-virt --container --quiet 2>/dev/null; }

restart_service() {
  if has_systemd; then
    run systemctl restart "$1"
  else
    warn "systemd is not running, so $1 was not restarted."
  fi
}

apt_get() {
  DEBIAN_FRONTEND=noninteractive apt-get -y -q \
    -o DPkg::Lock::Timeout=600 \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    "$@"
}

is_installed() {
  [[ $(dpkg-query -W -f='${Status}' "$1" 2>/dev/null) == "install ok installed" ]]
}

apt_install() {
  local pkg missing=()
  for pkg in "$@"; do
    is_installed "$pkg" || missing+=("$pkg")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "Already installed: $*"
    return 0
  fi
  run apt_get install "${missing[@]}"
  changed "installed ${missing[*]}"
}

render() {
  local template=$1 pair
  local args=()
  shift
  for pair in "$@"; do
    args+=(-e "s|@${pair%%=*}@|${pair#*=}|g")
  done
  sed "${args[@]}" "$template"
}

sync_file() {
  local src=$1 dest=$2 mode=${3:-644}
  FILE_CHANGED=0
  if cmp -s "$src" "$dest" && [[ $(stat -c '%a %U' "$dest") == "$mode root" ]]; then
    ok "Up to date: $dest"
    return 0
  fi
  run install -D -m "$mode" -o root -g root "$src" "$dest"
  FILE_CHANGED=1
  changed "wrote $dest"
}

sync_content() {
  local dest=$1 mode=${2:-644} tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  sync_file "$tmp" "$dest" "$mode"
  rm -f "$tmp"
}

append_line() {
  local file=$1 line=$2
  if [[ $DRY_RUN == 1 ]]; then
    printf '   [dry-run] append "%s" to %s\n' "$line" "$file"
  else
    printf '%s\n' "$line" >>"$file"
  fi
}

write_in_place() {
  local file=$1 tmp=$2
  if [[ $DRY_RUN == 1 ]]; then
    printf '   [dry-run] rewrite %s\n' "$file"
  else
    cat "$tmp" >"$file"
  fi
}

load_env
