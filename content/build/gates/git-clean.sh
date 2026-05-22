#!/usr/bin/env bash
# gates/git-clean.sh — refuse if working tree is dirty
#
# Exits 0 if clean, 1 if dirty (with a list of dirty files).
#
# Override with FORCE_DIRTY=1 (don't do this for prod deploys).

set -euo pipefail

if [[ "${FORCE_DIRTY:-0}" == "1" ]]; then
  echo "⚠️  FORCE_DIRTY=1 — skipping clean-tree check"
  exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "git-clean gate: not inside a git repo; skipping."
  exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "✗ Working tree is dirty:"
  git status --short
  echo ""
  echo "Commit, stash, or set FORCE_DIRTY=1 (not recommended for prod)."
  exit 1
fi
