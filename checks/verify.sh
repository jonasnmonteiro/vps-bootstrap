#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "$0")/../lib/common.sh"

[[ $EUID -eq 0 ]] || die "Run with sudo: most checks read root-only state."

PASSED=0
FAILED=0
WARNED=0
SKIPPED=0

section() { printf '\n%s\n' "$1"; }
pass() { ok "$1"; PASSED=$((PASSED + 1)); }
flunk() { fail "$1"; FAILED=$((FAILED + 1)); }
advise() { warn "$1"; WARNED=$((WARNED + 1)); }
skip() { printf '[SKIP] %s\n' "$1"; SKIPPED=$((SKIPPED + 1)); }

check() {
  local description=$1
  shift
  if "$@" >/dev/null 2>&1; then pass "$description"; else flunk "$description"; fi
}

has() { command -v "$1" >/dev/null 2>&1; }

admin="${ADMIN_USER:-}"
permit_root="${SSH_PERMIT_ROOT_LOGIN:-prohibit-password}"
cloud_account="${CLOUD_ACCOUNT:-ubuntu}"
swappiness="${SWAPPINESS:-10}"
timezone="${TIMEZONE:-UTC}"
read -ra ports <<<"${UFW_ALLOW:-22/tcp 80/tcp 443/tcp}"

section "ACCESS"
[[ -d /run/sshd ]] || install -d -m 755 /run/sshd
check "sshd -t accepts the configuration" sshd -t
effective="$(sshd -T 2>/dev/null)"
check "sshd: passwordauthentication no" grep -qx "passwordauthentication no" <<<"$effective"
check "sshd: kbdinteractiveauthentication no" grep -qx "kbdinteractiveauthentication no" <<<"$effective"
check "sshd: pubkeyauthentication yes" grep -qx "pubkeyauthentication yes" <<<"$effective"
if [[ $permit_root == no ]]; then
  check "sshd: permitrootlogin no" grep -qx "permitrootlogin no" <<<"$effective"
else
  check "sshd: permitrootlogin prohibit-password" grep -qxE "permitrootlogin (prohibit-password|without-password)" <<<"$effective"
fi

if [[ -z $admin ]]; then
  skip "ADMIN_USER is not set, admin user checks skipped"
elif ! id "$admin" >/dev/null 2>&1; then
  flunk "admin user '$admin' exists"
else
  home="$(getent passwd "$admin" | cut -d: -f6)"
  check "admin user '$admin' is in the sudo group" bash -c "id -nG '$admin' | tr ' ' '\n' | grep -qx sudo"
  check "$home/.ssh/authorized_keys holds valid keys" ssh-keygen -lf "$home/.ssh/authorized_keys"
  check "$home/.ssh is 700 and owned by $admin" test "$(stat -c '%a %U' "$home/.ssh" 2>/dev/null)" == "700 $admin"
  check "authorized_keys is 600 and owned by $admin" test "$(stat -c '%a %U' "$home/.ssh/authorized_keys" 2>/dev/null)" == "600 $admin"
  check "$home is not writable by group or others" test $(( 8#$(stat -c '%a' "$home") & 8#022 )) -eq 0
fi

if id "$cloud_account" >/dev/null 2>&1 && [[ $cloud_account != "$admin" ]]; then
  check "password of '$cloud_account' is locked" test "$(passwd -S "$cloud_account" | awk '{print $2}')" != P
fi

section "NETWORK"
if has ufw; then
  status="$(ufw status verbose)"
  check "UFW is active" grep -qx "Status: active" <<<"$status"
  check "UFW denies incoming by default" grep -q "deny (incoming)" <<<"$status"
  for port in "${ports[@]}"; do
    check "UFW allows $port on IPv4" grep -qE "^$port +ALLOW IN" <<<"$status"
  done
  if [[ -e /proc/net/if_inet6 ]]; then
    for port in "${ports[@]}"; do
      check "UFW allows $port on IPv6" grep -qE "^$port \(v6\) +ALLOW IN" <<<"$status"
    done
  else
    skip "the kernel has no IPv6 support here, IPv6 rule checks skipped"
  fi
else
  flunk "UFW is installed"
fi

section "SYSTEM"
if has fail2ban-client; then
  check "fail2ban jail.local uses the systemd backend" grep -qE '^backend *= *systemd' /etc/fail2ban/jail.local
  if has_systemd; then
    check "fail2ban is enabled at boot" systemctl is-enabled --quiet fail2ban
    check "fail2ban sshd jail is running" fail2ban-client status sshd
  else
    skip "systemd is not running, fail2ban service checks skipped"
  fi
else
  flunk "fail2ban is installed"
fi

check "persistent journal directory exists" test -d /var/log/journal
check "journald size limit is configured" grep -q '^SystemMaxUse=' /etc/systemd/journald.conf.d/00-limit.conf
if has_systemd; then
  boots="$(journalctl --list-boots --no-pager 2>/dev/null | grep -c . || true)"
  if [[ $boots -gt 1 ]]; then
    pass "journal keeps history across reboots ($boots boots)"
  else
    advise "journal lists only one boot. Reboot once to prove persistence."
  fi
fi

check "unattended-upgrades is installed" is_installed unattended-upgrades
check "package lists refresh daily" grep -qx 'APT::Periodic::Update-Package-Lists "1";' /etc/apt/apt.conf.d/20auto-upgrades
check "security upgrades run daily" grep -qx 'APT::Periodic::Unattended-Upgrade "1";' /etc/apt/apt.conf.d/20auto-upgrades
check "automatic reboot is disabled" grep -qx 'Unattended-Upgrade::Automatic-Reboot "false";' /etc/apt/apt.conf.d/99local-upgrades

if in_container; then
  skip "running inside a container, swap and swappiness checks skipped"
else
  check "swap is active" bash -c "swapon --show --noheadings | grep -q ."
  if [[ -f /swapfile ]]; then
    check "/swapfile is 600 and owned by root" test "$(stat -c '%a %U' /swapfile)" == "600 root"
    check "/swapfile is in /etc/fstab" grep -qE '^/swapfile[[:space:]]' /etc/fstab
  fi
  check "/etc/fstab has no errors" bash -c "findmnt --verify 2>&1 | tail -1 | grep -qE '(^| )0 parse errors, 0 errors|no errors'"
  check "vm.swappiness is $swappiness" test "$(cat /proc/sys/vm/swappiness)" == "$swappiness"
fi

if has_systemd; then
  check "timezone is $timezone" same_timezone "$(timedatectl show --property=Timezone --value)" "$timezone"
  if in_container; then
    skip "running inside a container, NTP checks skipped"
  else
    check "NTP synchronization is enabled" test "$(timedatectl show --property=NTP --value)" == yes
    if [[ $(timedatectl show --property=NTPSynchronized --value) == yes ]]; then
      pass "clock is synchronized"
    else
      advise "clock is not synchronized yet. Wait a minute and run the checks again."
    fi
  fi
else
  skip "systemd is not running, time checks skipped"
fi

if [[ -n ${NEW_HOSTNAME:-} ]]; then
  check "hostname is $NEW_HOSTNAME" test "$(hostname)" == "$NEW_HOSTNAME"
  check "/etc/hosts maps 127.0.1.1 to $NEW_HOSTNAME" grep -qE "^127\.0\.1\.1[[:space:]]+$NEW_HOSTNAME([[:space:]]|$)" /etc/hosts
fi
if [[ -f /etc/cloud/cloud.cfg ]]; then
  check "cloud-init preserves the hostname" grep -qE '^preserve_hostname:[[:space:]]*true' /etc/cloud/cloud.cfg
fi

if [[ -f /var/run/reboot-required ]]; then
  advise "a reboot is pending (/var/run/reboot-required)"
fi

printf '\nResult: %d passed, %d failed, %d warnings, %d skipped\n' "$PASSED" "$FAILED" "$WARNED" "$SKIPPED"
[[ $FAILED -eq 0 ]]
