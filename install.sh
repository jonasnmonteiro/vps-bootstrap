#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run with sudo or as root: curl ... | sudo bash" >&2; exit 1; }

REPO_URL="${REPO_URL:-https://github.com/vps-bootstrap/vps-bootstrap/archive/refs/heads/main.tar.gz}"
TMP_DIR="$(mktemp -d /tmp/vps-bootstrap-XXXXXX)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

command -v curl >/dev/null 2>&1 || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates tar; }

curl -fsSL "$REPO_URL" | tar -xz -C "$TMP_DIR" --strip-components=1

cd "$TMP_DIR"

if [[ -t 0 ]]; then
  ./bootstrap.sh "$@"
elif [[ -e /dev/tty ]]; then
  exec < /dev/tty
  ./bootstrap.sh "$@"
else
  ./bootstrap.sh --auto "$@"
fi
