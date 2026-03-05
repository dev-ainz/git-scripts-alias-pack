#!/usr/bin/env sh
set -eu

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This command must run inside a Git repository." >&2
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "Remote 'origin' was not found. Configure it before running git pn." >&2
  exit 1
fi

has_upstream=1
if ! git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
  has_upstream=0
fi

if [ "$has_upstream" -eq 1 ]; then
  commit_lines="$(git log --reverse --format='* **%s**' '@{u}..HEAD')"
else
  commit_lines="$(git log --reverse --format='* **%s**' HEAD --not --remotes=origin)"
fi

if [ -z "$commit_lines" ]; then
  echo "No new commits to push."
  exit 0
fi

echo "Pushing these commits:"
echo "$commit_lines"

if [ "$has_upstream" -eq 1 ]; then
  git push
else
  git push -u origin HEAD
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI was not found. The PR comment step was skipped."
  exit 0
fi

if gh pr view >/dev/null 2>&1; then
  gh pr comment --body "$commit_lines"
  exit 0
fi

echo "No pull request found for this branch, so no comment was added."
