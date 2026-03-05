#!/usr/bin/env sh
set -eu

print_usage() {
  cat <<'EOF'
Usage: bash scripts/install.sh [--force]

Options:
  --force   Replace existing alias values
  -h, --help  Show this help
EOF
}

quote_for_sh() {
  escaped_path="$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")"
  printf "'%s'" "$escaped_path"
}

force_overwrite=0
for option in "$@"; do
  case "$option" in
  --force)
    force_overwrite=1
    ;;
  -h | --help)
    print_usage
    exit 0
    ;;
  *)
    echo "Unknown option: $option" >&2
    print_usage >&2
    exit 1
    ;;
  esac
done

script_directory="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
repository_root="$(CDPATH= cd -- "$script_directory/.." && pwd -P)"

pn_script_path="$repository_root/aliases/pn.sh"
rb_script_path="$repository_root/aliases/rb.sh"
bpd_script_path="$repository_root/aliases/bpd.sh"

if [ ! -f "$pn_script_path" ] || [ ! -f "$rb_script_path" ] || [ ! -f "$bpd_script_path" ]; then
  echo "Alias scripts were not found. Run this script from the repository checkout." >&2
  exit 1
fi

chmod +x "$pn_script_path" "$rb_script_path" "$bpd_script_path" >/dev/null 2>&1 || true

skipped_alias_count=0

install_alias() {
  alias_name="$1"
  script_path="$2"
  alias_key="alias.$alias_name"
  desired_value="!$(quote_for_sh "$script_path")"
  current_value="$(git config --global --get "$alias_key" || true)"

  if [ -n "$current_value" ] && [ "$current_value" != "$desired_value" ] && [ "$force_overwrite" -ne 1 ]; then
    echo "Skipped $alias_name because alias.$alias_name already exists. Use --force to replace it."
    skipped_alias_count=$((skipped_alias_count + 1))
    return
  fi

  git config --global "$alias_key" "$desired_value"
  echo "Configured git $alias_name"
}

install_alias "pn" "$pn_script_path"
install_alias "rb" "$rb_script_path"
install_alias "bpd" "$bpd_script_path"

if [ "$skipped_alias_count" -gt 0 ]; then
  echo "Installation completed with $skipped_alias_count skipped alias(es)."
  exit 2
fi

echo "Installation completed."
