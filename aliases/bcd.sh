#!/usr/bin/env sh
set -eu

print_usage() {
  cat <<'USAGE'
Usage: git bcd [MAIN_REF] [BASE_BRANCH] [LIMIT] [--missing|-m]

Examples:
  git bcd
  git bcd origin/main staging
  git bcd origin/main staging 1000
  git bcd -m
USAGE
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This command must run inside a Git repository." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI was not found. Install and authenticate gh before running git bcd." >&2
  exit 127
fi

show_missing=0
main_reference=""
base_reference_argument=""
result_limit=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -m|--missing)
      show_missing=1
      shift
      continue
      ;;
    -h|--help)
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
  ""|*[!0-9]*)
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

print_commit_lines() {
  pr_number="$1"
  pr_title="$2"
  status_label="$3"
  extra_field="$4"

  commit_rows="$(
    gh pr view "$pr_number" \
      --json commits \
      --jq '.commits[] | [(.messageHeadline // ""), (.oid // "")] | @tsv' \
      2>/dev/null || true
  )"

  if [ -z "$commit_rows" ]; then
    if [ -n "$extra_field" ]; then
      printf '%s\t#%s\tPR: %s\tCOMMIT: <unknown>\t<unknown>\t%s\n' "$status_label" "$pr_number" "$pr_title" "$extra_field"
    else
      printf '%s\t#%s\tPR: %s\tCOMMIT: <unknown>\t<unknown>\n' "$status_label" "$pr_number" "$pr_title"
    fi
    return
  fi

  printf '%s\n' "$commit_rows" |
    while IFS="$tab_char" read -r commit_name commit_id; do
      commit_name="${commit_name:-<unknown>}"
      commit_id="${commit_id:-<unknown>}"

      if [ -n "$extra_field" ]; then
        printf '%s\t#%s\tPR: %s\tCOMMIT: %s\t%s\t%s\n' "$status_label" "$pr_number" "$pr_title" "$commit_name" "$commit_id" "$extra_field"
      else
        printf '%s\t#%s\tPR: %s\tCOMMIT: %s\t%s\n' "$status_label" "$pr_number" "$pr_title" "$commit_name" "$commit_id"
      fi
    done
}

printf '%s\n' "$pr_rows" |
  while IFS="$tab_char" read -r pr_number pr_title pr_merged_at merge_commit_sha; do
    merge_commit_sha="${merge_commit_sha:-}"

    if [ -z "$pr_number$pr_title$pr_merged_at$merge_commit_sha" ]; then
      continue
    fi

    if [ -n "$merge_commit_sha" ] && git merge-base --is-ancestor "$merge_commit_sha" "$main_reference" 2>/dev/null; then
      continue
    fi

    if [ -n "$merge_commit_sha" ] && ! git merge-base --is-ancestor "$merge_commit_sha" "$base_reference" 2>/dev/null; then
      if [ "$show_missing" -eq 1 ]; then
        print_commit_lines "$pr_number" "$pr_title" "MISSING_IN_BASE" ""
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
      print_commit_lines "$pr_number" "$pr_title" "REVERTED" "revert=$revert_commit_sha"
      continue
    fi

    print_commit_lines "$pr_number" "$pr_title" "PENDING" ""
  done
