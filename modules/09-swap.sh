#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

describe "Create a swap file and set a conservative swappiness"

size="${SWAP_SIZE:-2G}"
swappiness="${SWAPPINESS:-10}"
swapfile=/swapfile
fstab_line="$swapfile none swap sw 0 0"

[[ $size =~ ^[1-9][0-9]*[MG]$ ]] || die "SWAP_SIZE must look like 512M or 2G, got '$size'."
if [[ ! $swappiness =~ ^[0-9]+$ ]] || (( swappiness < 1 || swappiness > 100 )); then
  die "SWAPPINESS must be between 1 and 100, got '$swappiness'. Zero triggers the OOM killer earlier."
fi

if in_container; then
  warn "Running inside a container: swap and vm.swappiness belong to the host. Skipping."
  exit 0
fi

if swapon --show --noheadings | grep -q .; then
  ok "Swap is already active: $(swapon --show --noheadings | awk '{print $1, $3}' | paste -sd ',' -)"
else
  if [[ ! -f $swapfile ]]; then
    avail_kb="$(df --output=avail -k / | tail -1)"
    unit_kb=1024
    [[ $size == *G ]] && unit_kb=1048576
    need_kb=$(( ${size%?} * unit_kb ))
    (( avail_kb > need_kb * 2 )) || die "Not enough free space on / for a $size swap file."
    run fallocate -l "$size" "$swapfile"
    run chmod 600 "$swapfile"
    run mkswap "$swapfile"
    changed "created $swapfile ($size)"
  fi
  run swapon "$swapfile"
  changed "activated $swapfile"
fi

if [[ -f $swapfile ]]; then
  mode="$(stat -c '%a %U' "$swapfile")"
  if [[ $mode != "600 root" ]]; then
    run chown root:root "$swapfile"
    run chmod 600 "$swapfile"
    changed "fixed mode of $swapfile (was $mode)"
  fi
fi

if [[ -f $swapfile || $CHANGED == 1 ]]; then
  if grep -qE "^${swapfile}[[:space:]]" /etc/fstab; then
    ok "$swapfile is in /etc/fstab."
  else
    append_line /etc/fstab "$fstab_line"
    changed "added $swapfile to /etc/fstab"
    if [[ $DRY_RUN == 0 ]]; then
      summary="$(findmnt --verify 2>&1 | tail -1)"
      grep -qE '(^| )0 parse errors, 0 errors' <<<"$summary" || grep -q 'no errors' <<<"$summary" \
        || die "findmnt --verify reports problems in /etc/fstab: $summary. Fix it before any reboot."
    fi
  fi
fi

sync_content /etc/sysctl.d/99-swappiness.conf 644 < <(render "$CONFIG_DIR/sysctl/99-swappiness.conf" SWAPPINESS="$swappiness")
if [[ $(cat /proc/sys/vm/swappiness) != "$swappiness" ]]; then
  run sysctl -q --load=/etc/sysctl.d/99-swappiness.conf
  changed "applied vm.swappiness=$swappiness"
fi
