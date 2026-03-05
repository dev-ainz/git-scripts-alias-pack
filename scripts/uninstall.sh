#!/usr/bin/env sh
set -eu

print_usage() {
  cat <<'EOF'
Usage: bash scripts/uninstall.sh [--all]

Options:
  --all       Remove aliases even if they do not point to this repository
  -h, --help  Show this help
EOF
}

quote_for_sh() {
  escaped_path="$(printf '%s' "$1" | sed "s/'/'\"'\"'/g")"
  printf "'%s'" "$escaped_path"
}

remove_all_values=0
for option in "$@"; do
  case "$option" in
  --all)
    remove_all_values=1
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

remove_alias_if_needed() {
  alias_name="$1"
  script_path="$2"
  alias_key="alias.$alias_name"
  current_value="$(git config --global --get "$alias_key" || true)"

  if [ -z "$current_value" ]; then
    echo "alias.$alias_name was not configured."
    return
  fi

  if [ "$remove_all_values" -eq 1 ]; then
    git config --global --unset-all "$alias_key"
    echo "Removed alias.$alias_name"
    return
  fi

  expected_value="!$(quote_for_sh "$script_path")"
  if [ "$current_value" = "$expected_value" ]; then
    git config --global --unset-all "$alias_key"
    echo "Removed alias.$alias_name"
    return
  fi

  echo "Skipped alias.$alias_name because it points to another command. Use --all to remove it."
}

remove_alias_if_needed "pn" "$repository_root/aliases/pn.sh"
remove_alias_if_needed "rb" "$repository_root/aliases/rb.sh"
remove_alias_if_needed "bpd" "$repository_root/aliases/bpd.sh"

echo "Uninstall completed."
