#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Disable SSH password login through a drop-in that wins over cloud-init"

user="${ADMIN_USER:-}"
permit_root="${SSH_PERMIT_ROOT_LOGIN:-prohibit-password}"
dest=/etc/ssh/sshd_config.d/00-hardening.conf

case $permit_root in
  prohibit-password | no) ;;
  *) die "SSH_PERMIT_ROOT_LOGIN must be 'prohibit-password' or 'no', got '$permit_root'." ;;
esac

key_file=""
if [[ -n $user ]] && id "$user" >/dev/null 2>&1; then
  key_file="$(getent passwd "$user" | cut -d: -f6)/.ssh/authorized_keys"
elif [[ -n $user && $DRY_RUN == 1 ]]; then
  log "User '$user' does not exist yet. 03-admin-user would copy the keys of root."
  key_file=/root/.ssh/authorized_keys
fi
if [[ -z $key_file ]] || ! ssh-keygen -lf "$key_file" >/dev/null 2>&1; then
  refuse "Admin user '${user:-unset}' has no valid SSH key. Disabling passwords now would lock you out."
fi
if [[ $permit_root == prohibit-password && ! -s /root/.ssh/authorized_keys ]]; then
  warn "root has no SSH key, so root login will be impossible. Recovery goes through the provider console."
fi

backup=""
if [[ -f $dest ]]; then
  backup="$(mktemp)"
  cp -p "$dest" "$backup"
fi

sync_content "$dest" 644 < <(render "$CONFIG_DIR/ssh/00-hardening.conf" PERMIT_ROOT_LOGIN="$permit_root")

if [[ $DRY_RUN == 1 ]]; then
  if [[ $FILE_CHANGED == 1 ]]; then
    run sshd -t
    run systemctl restart ssh
  fi
  exit 0
fi

rollback() {
  if [[ -n $backup ]]; then
    install -m 644 "$backup" "$dest"
  else
    rm -f "$dest"
  fi
  die "$1 The previous SSH configuration was restored and sshd was not restarted."
}

[[ -d /run/sshd ]] || install -d -m 755 /run/sshd
sshd -t || rollback "sshd -t rejected the configuration."

effective="$(sshd -T 2>/dev/null)"
for expected in "passwordauthentication no" "kbdinteractiveauthentication no" "pubkeyauthentication yes"; do
  grep -qx "$expected" <<<"$effective" || rollback "Effective setting is not '$expected'. Another file in /etc/ssh/sshd_config.d wins."
done
if [[ $permit_root == no ]]; then
  grep -qx "permitrootlogin no" <<<"$effective" || rollback "Effective PermitRootLogin is not 'no'."
else
  grep -qxE "permitrootlogin (prohibit-password|without-password)" <<<"$effective" || rollback "Effective PermitRootLogin is not 'prohibit-password'."
fi
ok "Effective sshd settings match the hardening policy."

if [[ $FILE_CHANGED == 1 ]]; then
  restart_service ssh
  warn "Open a NEW terminal and confirm you can still log in before closing this one."
fi
rm -f "$backup"
