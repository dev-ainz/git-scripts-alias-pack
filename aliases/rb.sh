#!/usr/bin/env sh
set -eu

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This command must run inside a Git repository." >&2
  exit 1
fi

max_results="${1:-30}"
case "$max_results" in
  "" | *[!0-9]*)
    max_results=30
    ;;
esac

if [ "$max_results" -eq 0 ]; then
  max_results=30
fi

git reflog show --all --date=iso \
  | grep -E 'checkout: moving from|switch: moving from' \
  | sed -E 's/.*moving from .* to ([^[:space:]]+).*/\1/' \
  | awk '!seen[$0]++' \
  | head -n "$max_results"
