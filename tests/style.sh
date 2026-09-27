#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

status=0

list_code_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files --cached --others --exclude-standard -- '*.sh' 'configs/*' 'Makefile' 'tests/container/Dockerfile' '.github/workflows/*.yml' '.env.example'
  else
    find . -type f \( -name '*.sh' -o -path './configs/*' -o -name 'Makefile' -o -path './tests/container/Dockerfile' -o -path './.github/workflows/*.yml' -o -name '.env.example' \) | sed 's|^\./||'
  fi
}

list_all_files() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files --cached --others --exclude-standard
  else
    find . -type f ! -path './.git/*' | sed 's|^\./||'
  fi
}

while IFS= read -r file; do
  [[ -n $file && -f $file ]] || continue
  perl -ne 'if ($. > 1 && /^\s*#/) { print "$ARGV:$.: $_"; $found = 1 } END { exit($found ? 1 : 0) }' "$file" || status=1
done < <(list_code_files)

while IFS= read -r file; do
  [[ -n $file && -f $file ]] || continue
  perl -CSD -ne 'if (/[\x{2013}\x{2014}\x{2600}-\x{27BF}\x{1F300}-\x{1FAFF}]/) { print "$ARGV:$.: $_"; $found = 1 } END { exit($found ? 1 : 0) }' "$file" || status=1
done < <(list_all_files)

if [[ $status -eq 0 ]]; then
  echo "Style check passed: no comments, dashes or emojis."
else
  echo "Style check failed: remove the lines listed above." >&2
fi
exit "$status"
