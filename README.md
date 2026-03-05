# Git Scripts Alias Pack

Small, focused Git aliases to speed up common day-to-day workflows:

- `pn`: push current branch and comment the branch PR with the new commit titles.
- `rb`: list recently visited branches from reflog history.
- `bpd`: list merged PRs in a base branch that are still not in main.

## Prerequisites

- Git
- POSIX shell (`sh`, available in Git Bash/WSL/macOS/Linux)
- GitHub CLI (`gh`) for `pn` PR comments and `bpd`

## Quick Install

```bash
git clone https://github.com/dev-ainz/git-scripts-alias-pack.git git-scripts
cd git-scripts
bash scripts/install.sh
```

If one or more aliases already exist and you want to replace them:

```bash
bash scripts/install.sh --force
```

## Aliases

### `git pn`

Pushes local commits and, when a PR exists, posts those commit titles as a PR comment.

```bash
git pn
```

Notes:

- Uses the upstream range when the branch already tracks a remote branch.
- Uses commits not present on `origin/*` when the branch has no upstream.
- Skips PR comment step when `gh` is missing or no PR exists.

### `git rb [N]`

Lists recently visited branches (checkout/switch events), unique and ordered by recency.

```bash
git rb
git rb 50
```

Defaults:

- `N=30`

### `git bpd [MAIN_REF] [BASE_BRANCH] [LIMIT] [--missing|-m]`

Shows merged PRs in `BASE_BRANCH` that are not yet in `MAIN_REF`.

```bash
git bpd
git bpd origin/main staging
git bpd origin/main staging 1000
git bpd -m
```

Defaults:

- `MAIN_REF=origin/main`
- `BASE_BRANCH=staging`
- `LIMIT=500`

Output status values:

- `PENDING`: PR merge commit not in main and still in base branch history
- `REVERTED`: PR merge commit appears reverted in base branch history
- `MISSING_IN_BASE`: merge commit not found in base branch history (`--missing` only)

## Update

Pull the latest changes and run install again:

```bash
git pull
bash scripts/install.sh --force
```

## Uninstall

Removes aliases only when they still point to this repository:

```bash
bash scripts/uninstall.sh
```

Remove aliases even if they point elsewhere:

```bash
bash scripts/uninstall.sh --all
```

## Verify Setup

```bash
git config --global --get-regexp '^alias\.(pn|rb|bpd)$'
```

## Repository Layout

```text
aliases/
  pn.sh
  rb.sh
  bpd.sh
scripts/
  install.sh
  uninstall.sh
```

## Troubleshooting

- `gh` auth issues:
  - run `gh auth status`
  - run `gh auth login` if needed
- command not found:
  - run aliases from a shell where Git and `gh` are in `PATH`
- alias not updated:
  - run `bash scripts/install.sh --force`
