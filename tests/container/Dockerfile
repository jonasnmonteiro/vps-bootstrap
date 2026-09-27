ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ENV container=docker

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus sudo iproute2 openssh-server openssh-client cloud-init ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && touch /etc/cloud/cloud-init.disabled

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
