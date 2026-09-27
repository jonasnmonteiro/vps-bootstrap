#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Install official Docker CE, Compose plugin and configure hardened daemon limits"

user="${ADMIN_USER:-}"

if is_installed docker-ce && [[ -f /etc/docker/daemon.json ]]; then
  ok "Docker CE is installed."
else
  run install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    run curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    run chmod a+r /etc/apt/keyrings/docker.asc
  fi
  arch="$(dpkg --print-architecture)"
  codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable" > /tmp/docker.list
  sync_file /tmp/docker.list /etc/apt/sources.list.d/docker.list 644
  rm -f /tmp/docker.list
  run apt_get update -qq
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

run install -d -m 755 /etc/docker
sync_file "$CONFIG_DIR/docker/daemon.json" /etc/docker/daemon.json 644

if [[ -n $user ]] && id "$user" >/dev/null 2>&1; then
  if id -nG "$user" | tr ' ' '\n' | grep -qx docker; then
    ok "User '$user' is in the docker group."
  else
    run usermod -aG docker "$user"
    changed "added user $user to docker group"
  fi
fi

if has_systemd; then
  if systemctl is-enabled --quiet docker 2>/dev/null; then
    ok "Docker service is enabled."
  else
    run systemctl enable docker
    changed "enabled docker service"
  fi
  if [[ $FILE_CHANGED == 1 ]]; then
    restart_service docker
  fi
fi
