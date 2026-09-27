#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

NAME="${NAME:-vps-bootstrap-test}"
TARGET=/home/ubuntu/vps-bootstrap
SETTINGS=(ADMIN_USER=ubuntu NEW_HOSTNAME=vps-test)

FAILURES=0
step() { printf '\n==> %s\n' "$*"; }
pass() { printf '[PASS] %s\n' "$*"; }
flunk() { printf '[FAIL] %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
in_vm() { multipass exec "$NAME" -- sudo env "${SETTINGS[@]}" "$@"; }

command -v multipass >/dev/null 2>&1 || { echo "multipass is not installed: brew install --cask multipass" >&2; exit 1; }

cleanup() {
  if [[ -z ${KEEP:-} ]]; then
    multipass delete --purge "$NAME" >/dev/null 2>&1 || true
  else
    printf 'VM kept. Open a shell with: multipass shell %s\n' "$NAME"
  fi
}
trap cleanup EXIT

step "Launching a fresh Ubuntu 24.04 VM"
multipass delete --purge "$NAME" >/dev/null 2>&1 || true
multipass launch 24.04 --name "$NAME" --cpus 2 --memory 2G --disk 10G

step "Copying the project"
tar -c --exclude=.git . | multipass exec "$NAME" -- bash -c "mkdir -p $TARGET && tar -x -C $TARGET"

step "Dry run"
in_vm "$TARGET/bootstrap.sh" --auto --dry-run

step "First run"
if in_vm "$TARGET/bootstrap.sh" --auto; then
  pass "first run finished and verification passed"
else
  flunk "first run failed"
fi

step "Second run must change nothing"
second="$(in_vm "$TARGET/bootstrap.sh" --auto 2>&1)" || true
printf '%s\n' "$second" | tail -40
if grep -q "No changes needed" <<<"$second"; then
  pass "second run was a no-op (idempotent)"
else
  flunk "second run made changes"
fi

step "Rebooting to prove persistence"
multipass restart "$NAME"
if in_vm "$TARGET/checks/verify.sh"; then
  pass "every check still passes after the reboot"
else
  flunk "a check failed after the reboot"
fi

step "Login behaviour from this machine"
ip="$(multipass info "$NAME" --format csv | awk -F, 'NR==2 {print $3}')"
denied="$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
  -o PubkeyAuthentication=no -o IdentitiesOnly=yes -o ConnectTimeout=5 "ubuntu@$ip" true 2>&1 || true)"
if grep -q 'Permission denied (publickey)' <<<"$denied"; then
  pass "password login is refused from outside"
else
  flunk "server still offers another method: $denied"
fi
for port in 22 80 443 8080; do
  if nc -z -w 3 "$ip" "$port" 2>/dev/null; then
    printf '       port %s answers\n' "$port"
  else
    printf '       port %s does not answer\n' "$port"
  fi
done

printf '\n'
if [[ $FAILURES -eq 0 ]]; then
  printf 'All VM tests passed.\n'
else
  printf '%d VM test(s) failed.\n' "$FAILURES"
  exit 1
fi
