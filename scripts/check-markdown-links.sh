#!/usr/bin/env bash
# Validate that every local Markdown link resolves to an existing path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

failed=0
while IFS= read -r -d '' markdown; do
  while IFS= read -r target; do
    target="${target%%#*}"
    [ -n "$target" ] || continue
    case "$target" in
      http://*|https://*|mailto:*|//*)
        continue
        ;;
    esac

    target="${target//%20/ }"
    if [ ! -e "$(dirname "$markdown")/$target" ]; then
      printf '%s: missing %s\n' "$markdown" "$target" >&2
      failed=1
    fi
  done < <(
    grep -oE '!?\[[^]]*\]\([^)]+\)' "$markdown" |
      sed -E 's/.*\(([^ )]+).*/\1/' || true
  )
done < <(find . -type f -name '*.md' -not -path './.git/*' -print0)

[ "$failed" -eq 0 ] || exit 1
echo "Markdown links: OK"
