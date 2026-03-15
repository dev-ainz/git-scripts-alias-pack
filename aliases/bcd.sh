#!/usr/bin/env sh
set -eu

print_usage() {
  cat <<'USAGE'
Usage: git bcd [-l LIMIT] [--hash] [-s] [-t] [-b BASE] [-h HEAD] [--help]

Examples:
  git bcd
  git bcd -b release -h main
  git bcd --status --time --hash
  git bcd -l 100
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

show_hash=0
show_status=0
show_time=0
head_reference_argument="main"
base_reference_argument="staging"
result_limit="50"
positional_argument_index=0

resolve_branch_reference() {
  requested_reference="$1"
  resolved_branch_name="$requested_reference"
  resolved_reference="$requested_reference"
  remote_name="${requested_reference%%/*}"

  if [ "$remote_name" != "$requested_reference" ] && git remote | grep -qx "$remote_name"; then
    resolved_branch_name="${requested_reference#*/}"
    resolved_reference="$requested_reference"
    return
  fi

  if git show-ref --verify --quiet "refs/remotes/origin/$requested_reference"; then
    resolved_reference="origin/$requested_reference"
    return
  fi

  if git show-ref --verify --quiet "refs/heads/$requested_reference"; then
    resolved_reference="$requested_reference"
  fi
}

print_commit_line() {
  status_label="$1"
  pr_number="$2"
  pr_title="$3"
  commit_name="$4"
  commit_id="$5"
  pr_merged_at="$6"
  revert_commit_sha="$7"

  if [ "$show_status" -eq 1 ]; then
    printf '%s\t' "$status_label"
  fi

  printf '#%s\tPR: %s\tCOMMIT: %s' "$pr_number" "$pr_title" "$commit_name"

  if [ "$show_time" -eq 1 ]; then
    printf '\t%s' "$pr_merged_at"
  fi

  if [ "$show_hash" -eq 1 ]; then
    printf '\t%s' "$commit_id"

    if [ -n "$revert_commit_sha" ]; then
      printf '\trevert=%s' "$revert_commit_sha"
    fi
  fi

  printf '\n'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -l|--limit)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for $1." >&2
        exit 1
      fi
      result_limit="$2"
      shift 2
      continue
      ;;
    --hash)
      show_hash=1
      shift
      continue
      ;;
    -s|--status)
      show_status=1
      shift
      continue
      ;;
    -t|--time)
      show_time=1
      shift
      continue
      ;;
    -b|--base)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for $1." >&2
        exit 1
      fi
      base_reference_argument="$2"
      shift 2
      continue
      ;;
    -h|--head)
      if [ "$#" -lt 2 ]; then
        echo "Missing value for $1." >&2
        exit 1
      fi
      head_reference_argument="$2"
      shift 2
      continue
      ;;
    --help)
      print_usage
      exit 0
      ;;
    -*)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac

  positional_argument_index=$((positional_argument_index + 1))

  case "$positional_argument_index" in
    1)
      head_reference_argument="$1"
      ;;
    2)
      base_reference_argument="$1"
      ;;
    3)
      result_limit="$1"
      ;;
    *)
      echo "Ignoring extra argument: $1" >&2
      ;;
  esac

  shift
done

case "$result_limit" in
  ""|*[!0-9]*)
    result_limit=50
    ;;
esac

if [ "$result_limit" -eq 0 ]; then
  result_limit=50
fi

git fetch origin --prune >/dev/null 2>&1 || true

resolve_branch_reference "$head_reference_argument"
head_reference="$resolved_reference"

resolve_branch_reference "$base_reference_argument"
base_reference="$resolved_reference"
base_branch_name="$resolved_branch_name"

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
  pr_merged_at="$4"
  revert_commit_sha="$5"

  commit_rows="$(
    gh pr view "$pr_number" \
      --json commits \
      --jq '.commits[] | [(.messageHeadline // ""), (.oid // "")] | @tsv' \
      2>/dev/null || true
  )"

  if [ -z "$commit_rows" ]; then
    print_commit_line "$status_label" "$pr_number" "$pr_title" "<unknown>" "<unknown>" "$pr_merged_at" "$revert_commit_sha"
    return
  fi

  printf '%s\n' "$commit_rows" |
    while IFS="$tab_char" read -r commit_name commit_id; do
      commit_name="${commit_name:-<unknown>}"
      commit_id="${commit_id:-<unknown>}"
      print_commit_line "$status_label" "$pr_number" "$pr_title" "$commit_name" "$commit_id" "$pr_merged_at" "$revert_commit_sha"
    done
}

printf '%s\n' "$pr_rows" |
  while IFS="$tab_char" read -r pr_number pr_title pr_merged_at merge_commit_sha; do
    merge_commit_sha="${merge_commit_sha:-}"

    if [ -z "$pr_number$pr_title$pr_merged_at$merge_commit_sha" ]; then
      continue
    fi

    if [ -n "$merge_commit_sha" ] && git merge-base --is-ancestor "$merge_commit_sha" "$head_reference" 2>/dev/null; then
      continue
    fi

    if [ -n "$merge_commit_sha" ] && ! git merge-base --is-ancestor "$merge_commit_sha" "$base_reference" 2>/dev/null; then
      print_commit_lines "$pr_number" "$pr_title" "MISSING_IN_BASE" "$pr_merged_at" ""
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
      print_commit_lines "$pr_number" "$pr_title" "REVERTED" "$pr_merged_at" "$revert_commit_sha"
      continue
    fi

    print_commit_lines "$pr_number" "$pr_title" "PENDING" "$pr_merged_at" ""
  done
