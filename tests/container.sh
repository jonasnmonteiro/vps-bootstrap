#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE="${IMAGE:-vps-bootstrap-test}"
BASE_IMAGE="${BASE_IMAGE:-ubuntu:24.04}"
NAME="${NAME:-vps-bootstrap-test}"
TARGET=/opt/vps-bootstrap
SETTINGS=(-e ADMIN_USER=deploy -e NEW_HOSTNAME=vps-test)

FAILURES=0
step() { printf '\n==> %s\n' "$*"; }
pass() { printf '[PASS] %s\n' "$*"; }
flunk() { printf '[FAIL] %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
in_box() { docker exec "${SETTINGS[@]}" "$NAME" "$@"; }

cleanup() {
  if [[ -z ${KEEP:-} ]]; then
    docker rm -f "$NAME" >/dev/null 2>&1 || true
  else
    printf 'Container kept. Open a shell with: docker exec -it %s bash\n' "$NAME"
  fi
}
trap cleanup EXIT

if [[ -z ${SKIP_BUILD:-} ]]; then
  step "Building $IMAGE from $BASE_IMAGE"
  docker build --quiet --build-arg BASE_IMAGE="$BASE_IMAGE" -t "$IMAGE" tests/container >/dev/null
fi

step "Starting a systemd container"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /run/lock \
  "$IMAGE" >/dev/null
for _ in $(seq 1 60); do
  state="$(docker exec "$NAME" systemctl is-system-running 2>/dev/null || true)"
  [[ $state == running || $state == degraded ]] && break
  sleep 1
done
printf 'systemd state: %s\n' "$state"

step "Copying the project and simulating a fresh cloud image"
docker exec "$NAME" mkdir -p "$TARGET"
tar -c --exclude=.git . | docker exec -i "$NAME" tar -x -C "$TARGET"
in_box bash "$TARGET/tests/fixtures/cloud-image.sh"
effective="$(in_box sshd -T 2>&1 || true)"
if grep -qx 'passwordauthentication yes' <<<"$effective"; then
  pass "fixture reproduces the cloud-init trap: password login is on"
else
  flunk "fixture did not enable password login: $(head -3 <<<"$effective")"
fi

step "Dry run must not change anything"
in_box "$TARGET/bootstrap.sh" --auto --dry-run
if in_box test ! -e /etc/ssh/sshd_config.d/00-hardening.conf && ! in_box id deploy >/dev/null 2>&1; then
  pass "dry run left the system untouched"
else
  flunk "dry run changed the system"
fi

step "First run"
if in_box "$TARGET/bootstrap.sh" --auto; then
  pass "first run finished and verification passed"
else
  flunk "first run failed"
fi

step "Second run must change nothing"
second="$(in_box "$TARGET/bootstrap.sh" --auto 2>&1)" || true
printf '%s\n' "$second" | tail -25
if grep -q "No changes needed" <<<"$second"; then
  pass "second run was a no-op (idempotent)"
else
  flunk "second run made changes"
fi

step "Login behaviour"
ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5)
if in_box ssh "${ssh_opts[@]}" -i /root/test_key deploy@127.0.0.1 true 2>/dev/null; then
  pass "admin user logs in with the key"
else
  flunk "admin user cannot log in with the key"
fi
if in_box ssh "${ssh_opts[@]}" -i /root/test_key root@127.0.0.1 true 2>/dev/null; then
  pass "root logs in with the key (prohibit-password)"
else
  flunk "root cannot log in with the key"
fi
denied="$(in_box ssh "${ssh_opts[@]}" -o PubkeyAuthentication=no -o IdentitiesOnly=yes deploy@127.0.0.1 true 2>&1 || true)"
if grep -q 'Permission denied (publickey)' <<<"$denied"; then
  pass "password login is refused: $(grep -o 'Permission denied (publickey)' <<<"$denied")"
else
  flunk "server still offers another method: $denied"
fi
if in_box passwd -S ubuntu | awk '{exit $2 == "L" ? 0 : 1}'; then
  pass "cloud image account password is locked"
else
  flunk "cloud image account password is still usable"
fi

printf '\n'
if [[ $FAILURES -eq 0 ]]; then
  printf 'All container tests passed.\n'
else
  printf '%d container test(s) failed.\n' "$FAILURES"
  exit 1
fi
