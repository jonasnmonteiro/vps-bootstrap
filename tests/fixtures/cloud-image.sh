#!/usr/bin/env bash
set -euo pipefail

id ubuntu >/dev/null 2>&1 || useradd --create-home --shell /bin/bash ubuntu
echo 'ubuntu:insecure-default' | chpasswd
echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/90-cloud-init-users
chmod 440 /etc/sudoers.d/90-cloud-init-users

install -d -m 755 /etc/ssh/sshd_config.d
printf 'PasswordAuthentication yes\n' >/etc/ssh/sshd_config.d/50-cloud-init.conf

grep -q '^preserve_hostname:' /etc/cloud/cloud.cfg \
  && sed -i 's/^preserve_hostname:.*/preserve_hostname: false/' /etc/cloud/cloud.cfg \
  || echo 'preserve_hostname: false' >>/etc/cloud/cloud.cfg

install -d -m 700 /root/.ssh
rm -f /root/test_key /root/test_key.pub
ssh-keygen -q -t ed25519 -N '' -C test-key -f /root/test_key
cat /root/test_key.pub >/root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

install -d -m 755 /run/sshd
systemctl restart ssh
