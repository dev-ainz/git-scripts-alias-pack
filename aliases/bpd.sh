#!/usr/bin/env sh
set -eu

print_usage() {
  cat <<'EOF'
Usage: git bpd [MAIN_REF] [BASE_BRANCH] [LIMIT] [--missing|-m]

Examples:
  git bpd
  git bpd origin/main staging
  git bpd origin/main staging 1000
  git bpd -m
EOF
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This command must run inside a Git repository." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI was not found. Install and authenticate gh before running git bpd." >&2
  exit 127
fi

show_missing=0
main_reference=""
base_reference_argument=""
result_limit=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -m | --missing)
      show_missing=1
      shift
      continue
      ;;
    -h | --help)
      print_usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
  esac

  if [ -z "$main_reference" ]; then
    main_reference="$1"
    shift
    continue
  fi

  if [ -z "$base_reference_argument" ]; then
    base_reference_argument="$1"
    shift
    continue
  fi

  if [ -z "$result_limit" ]; then
    result_limit="$1"
    shift
    continue
  fi

  echo "Ignoring extra argument: $1" >&2
  shift
done

main_reference="${main_reference:-origin/main}"
base_reference_argument="${base_reference_argument:-staging}"
result_limit="${result_limit:-500}"

case "$result_limit" in
  "" | *[!0-9]*)
    result_limit=500
    ;;
esac

if [ "$result_limit" -eq 0 ]; then
  result_limit=500
fi

git fetch origin --prune >/dev/null 2>&1 || true

remote_name="${base_reference_argument%%/*}"
branch_name_from_argument="${base_reference_argument#*/}"

if [ "$remote_name" != "$base_reference_argument" ] && git remote | grep -qx "$remote_name"; then
  base_reference="$base_reference_argument"
  base_branch_name="$branch_name_from_argument"
else
  base_branch_name="$base_reference_argument"
  base_reference="origin/$base_reference_argument"
fi

tab_char="$(printf '\t')"

pr_rows="$(
  gh pr list \
    --state merged \
    --base "$base_branch_name" \
    --limit "$result_limit" \
    --json number,title,mergedAt,mergeCommit \
    --jq '.[] | [.number, .title, .mergedAt, (.mergeCommit.oid // "")] | @tsv' \
    2>&1
)" || {
  gh_exit_code="$?"
  echo "gh pr list failed with exit code $gh_exit_code." >&2
  echo "$pr_rows" >&2
  exit "$gh_exit_code"
}

printf '%s\n' "$pr_rows" \
  | while IFS="$tab_char" read -r pr_number pr_title pr_merged_at merge_commit_sha; do
    merge_commit_sha="${merge_commit_sha:-}"

    if [ -z "$pr_number$pr_title$pr_merged_at$merge_commit_sha" ]; then
      continue
    fi

    if [ -n "$merge_commit_sha" ] && git merge-base --is-ancestor "$merge_commit_sha" "$main_reference" 2>/dev/null; then
      continue
    fi

    if [ -n "$merge_commit_sha" ] && ! git merge-base --is-ancestor "$merge_commit_sha" "$base_reference" 2>/dev/null; then
      if [ "$show_missing" -eq 1 ]; then
        printf 'MISSING_IN_BASE\t#%s\t%s\t%s\t%s\n' "$pr_number" "$pr_title" "$pr_merged_at" "$merge_commit_sha"
      fi
      continue
    fi

    revert_commit_sha=""
    if [ -n "$merge_commit_sha" ]; then
      revert_commit_sha="$(
        git log "$base_reference" \
          --since="$pr_merged_at" \
          --grep="This reverts commit $merge_commit_sha" \
          -n 1 \
          --format='%H' \
          2>/dev/null || true
      )"
    fi

    if [ -n "$merge_commit_sha" ] && [ -n "$revert_commit_sha" ]; then
      printf 'REVERTED\t#%s\t%s\t%s\t%s\trevert=%s\n' "$pr_number" "$pr_title" "$pr_merged_at" "$merge_commit_sha" "$revert_commit_sha"
      continue
    fi

    printf 'PENDING\t#%s\t%s\t%s\t%s\n' "$pr_number" "$pr_title" "$pr_merged_at" "$merge_commit_sha"
  done
