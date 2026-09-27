#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
source lib/common.sh

BOOTSTRAP_VERSION="1.0.0"
LOG_FILE="${LOG_FILE:-/var/log/vps-bootstrap.log}"

usage() {
  cat <<EOF
vps-bootstrap $BOOTSTRAP_VERSION

Usage: sudo ./bootstrap.sh [options]

Options:
  --auto          Select every module and skip all questions.
  --dry-run       Show what would change without changing anything.
  --only LIST     Run only these modules, comma separated (for example: ssh,firewall).
  --list          List the modules in execution order and exit.
  --version       Print the version and exit.
  -h, --help      Show this help and exit.

Settings are read from the environment first, then from .env (see .env.example).
EOF
}

module_name() { basename "$1" .sh | cut -d- -f2-; }
module_description() { sed -n 's/^describe "\(.*\)"$/\1/p' "$1"; }

list_modules() {
  local m
  for m in modules/*.sh; do
    printf '  %-24s %s\n' "$(basename "$m" .sh)" "$(module_description "$m")"
  done
}

AUTO=0
ONLY=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --auto) AUTO=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --only)
      [[ $# -ge 2 ]] || die "--only needs a comma separated list of modules."
      ONLY=$2
      shift
      ;;
    --only=*) ONLY=${1#*=} ;;
    --list) list_modules; exit 0 ;;
    --version) echo "$BOOTSTRAP_VERSION"; exit 0 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
  shift
done

[[ $EUID -eq 0 ]] || die "Run with sudo. Even --dry-run needs root to read the current state."

if [[ $(. /etc/os-release 2>/dev/null && echo "${ID:-}-${VERSION_ID:-}") != ubuntu-24.04 ]]; then
  if [[ $DRY_RUN == 1 ]]; then
    warn "Built and tested for Ubuntu 24.04 LTS only."
  else
    die "Built and tested for Ubuntu 24.04 LTS only."
  fi
fi

if [[ $AUTO == 1 ]]; then
  ASSUME_YES=1
elif [[ ! -t 0 ]]; then
  die "No terminal to ask questions on. Use --auto to run unattended."
fi
export DRY_RUN ASSUME_YES

if [[ $DRY_RUN == 0 ]]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
  log "vps-bootstrap $BOOTSTRAP_VERSION started $(date -u '+%Y-%m-%dT%H:%M:%SZ'), logging to $LOG_FILE"
fi

if [[ -z ${ADMIN_USER:-} && -n ${SUDO_USER:-} && ${SUDO_USER:-} != root ]]; then
  ADMIN_USER=$SUDO_USER
fi
if [[ -z ${ADMIN_USER:-} && $ASSUME_YES == 0 ]]; then
  read -rp "Name of the admin user to create or use (empty to skip): " ADMIN_USER
fi
export ADMIN_USER="${ADMIN_USER:-}"

ALL=(modules/*.sh)
SELECTED=()

if [[ -n $ONLY ]]; then
  IFS=',' read -ra wanted <<<"$ONLY"
  for w in "${wanted[@]}"; do
    match=""
    for m in "${ALL[@]}"; do
      [[ $(module_name "$m") == "$w" || $(basename "$m" .sh) == "$w" ]] && match=$m
    done
    [[ -n $match ]] || die "Unknown module '$w'. Use --list to see the names."
  done
  for m in "${ALL[@]}"; do
    for w in "${wanted[@]}"; do
      if [[ $(module_name "$m") == "$w" || $(basename "$m" .sh) == "$w" ]]; then
        SELECTED+=("$m")
        break
      fi
    done
  done
elif [[ $ASSUME_YES == 1 ]] || ask "Apply ALL modules?"; then
  SELECTED=("${ALL[@]}")
else
  for m in "${ALL[@]}"; do
    if ask "  $(module_name "$m"): $(module_description "$m")?"; then
      SELECTED+=("$m")
    fi
  done
fi

if [[ ${#SELECTED[@]} -eq 0 ]]; then
  log "Nothing selected. Exiting without changes."
  exit 0
fi

echo
log "Plan (runs in this order, whatever order you answered in):"
for m in "${SELECTED[@]}"; do
  printf '   %-24s %s\n' "$(basename "$m" .sh)" "$(module_description "$m")"
done
printf '   admin user: %s\n' "${ADMIN_USER:-<not set>}"
if [[ $DRY_RUN == 1 ]]; then
  log "Dry run: nothing will be changed."
fi
echo

if [[ $ASSUME_YES == 0 && $DRY_RUN == 0 ]]; then
  ask "Run the plan above?" || { log "Cancelled. Nothing was changed."; exit 0; }
fi

CHANGES_FILE="$(mktemp)"
export CHANGES_FILE
trap 'rm -f "$CHANGES_FILE"' EXIT

for m in "${SELECTED[@]}"; do
  echo
  if ! bash "$m"; then
    fail "$(basename "$m" .sh) failed. The modules after it were NOT run."
    exit 1
  fi
done

echo
count="$(wc -l <"$CHANGES_FILE")"
if [[ $count -eq 0 ]]; then
  log "No changes needed. The system already matches the desired state."
elif [[ $DRY_RUN == 1 ]]; then
  log "Dry run finished: $count change(s) would be made."
else
  log "$count change(s) applied:"
  sed 's/^/   /' "$CHANGES_FILE"
fi

if [[ $DRY_RUN == 0 ]]; then
  echo
  status=0
  bash checks/verify.sh || status=$?
  if [[ -f /var/run/reboot-required ]]; then
    warn "Reboot required. Reboot, then run: sudo ./checks/verify.sh"
  fi
  exit "$status"
fi
