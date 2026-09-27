#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Create the admin user, add it to sudo and install its SSH keys"

user="${ADMIN_USER:-}"

if [[ -z $user ]]; then
  refuse "ADMIN_USER is not set."
  exit 0
fi
[[ $user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "ADMIN_USER '$user' is not a valid user name."
[[ $user != root ]] || die "ADMIN_USER must be a regular user, not root."

exists=1
if id "$user" >/dev/null 2>&1; then
  ok "User '$user' exists."
else
  exists=0
  run useradd --create-home --shell /bin/bash --user-group "$user"
  changed "created user $user"
fi

if [[ $exists == 1 ]] && id -nG "$user" | tr ' ' '\n' | grep -qx sudo; then
  ok "User '$user' is in the sudo group."
else
  run usermod -aG sudo "$user"
  changed "added $user to the sudo group"
fi

home="$(getent passwd "$user" | cut -d: -f6 || true)"
home="${home:-/home/$user}"
ssh_dir="$home/.ssh"
keys="$ssh_dir/authorized_keys"

if [[ -s $keys ]]; then
  ok "SSH keys already present in $keys."
elif [[ -s /root/.ssh/authorized_keys ]]; then
  run install -d -m 700 -o "$user" -g "$user" "$ssh_dir"
  run install -m 600 -o "$user" -g "$user" /root/.ssh/authorized_keys "$keys"
  changed "copied /root/.ssh/authorized_keys to $keys"
else
  refuse "No keys in $keys and none in /root/.ssh/authorized_keys to copy."
fi

fix_mode() {
  local path=$1 want_mode=$2 current
  [[ -e $path ]] || return 0
  current="$(stat -c '%a %U' "$path")"
  if [[ $current != "$want_mode $user" ]]; then
    run chown "$user:$user" "$path"
    run chmod "$want_mode" "$path"
    changed "fixed owner and mode of $path (was $current)"
  fi
}

if [[ $exists == 1 ]]; then
  fix_mode "$ssh_dir" 700
  fix_mode "$keys" 600
  if [[ -d $home && $(( 8#$(stat -c '%a' "$home") & 8#022 )) -ne 0 ]]; then
    run chmod go-w "$home"
    changed "removed group and other write permission from $home"
  fi
fi

if [[ $exists == 0 && $DRY_RUN == 1 ]]; then
  exit 0
fi

if [[ $(passwd -S "$user" | awk '{print $2}') == P ]]; then
  ok "User '$user' has a password for sudo."
elif sudo -l -U "$user" 2>/dev/null | grep -q 'NOPASSWD: ALL'; then
  ok "User '$user' has passwordless sudo, no password needed."
elif [[ $ASSUME_YES == 1 || ! -t 0 ]]; then
  warn "User '$user' has no password, so sudo will not work for it yet. Set one with: sudo passwd $user"
else
  log "Choose the sudo password for '$user' (store it in your password manager)."
  run passwd "$user"
  changed "set the password of $user"
fi
