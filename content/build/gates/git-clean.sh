#!/usr/bin/env bash
# gates/git-clean.sh — refuse if the working tree is dirty
#
# Exits 0 if clean, 1 if dirty (with a list of dirty files).
#
# BOOKKEEPING IS NOT DIRTINESS (non-prod only)
#
# The toolkit writes records as you work and does not stage them:
#
#   tasks/            task enforcement files stubs and ledger rows
#   deploys/          the ship log writes a record per execution
#   build/deploy-log  the legacy one-line append
#
# The last two are written BY THIS PIPELINE. Without the exclusion the
# first staging deploy succeeds, writes its own record, and the SECOND
# one fails this gate on the evidence of the first — a deploy pipeline
# deadlocked by its own audit trail. (Found by running it twice; it
# reads fine.)
#
# The same applies to task churn: counting it makes the inner loop
# "edit → deploy to staging → look" demand a commit on every iteration.
# The second time that bites, someone aliases FORCE_DIRTY=1 — and
# FORCE_DIRTY is blanket, so the PRODUCTION clean-tree check goes with it.
#
# So for non-production classes those paths are excluded. For
# ENV_CLASS=prod the check is unfiltered: nothing is waved through on the
# way to production, and a release should be coming off a clean tree
# anyway. Set BOOKKEEPING_STRICT=1 to get the unfiltered check everywhere.
#
# The audit system must never be the reason a deploy gate fires.
# Operators disable the gate that costs them, not the one that protects
# them.
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

ENV_CLASS="${ENV_CLASS:-unclassified}"
STRICT="${BOOKKEEPING_STRICT:-${TASK_CHURN_STRICT:-0}}"

DIRTY=""
EXCLUDED=""
if [[ "$ENV_CLASS" == "prod" || "$STRICT" == "1" ]]; then
  DIRTY="$(git status --porcelain)"
else
  # `:(exclude)` is a pathspec magic word, supported by git 1.9+.
  DIRTY="$(git status --porcelain -- . \
            ':(exclude)tasks/' ':(exclude)deploys/' ':(exclude)build/deploy-log.md')"
  EXCLUDED="$(git status --porcelain -- 'tasks/' 'deploys/' 'build/deploy-log.md')"
fi

if [[ -n "$DIRTY" ]]; then
  echo "✗ Working tree is dirty:"
  git status --short
  echo ""
  echo "Commit, stash, or set FORCE_DIRTY=1 (not recommended for prod)."
  exit 1
fi

if [[ -n "$EXCLUDED" ]]; then
  n="$(printf '%s\n' "$EXCLUDED" | grep -c . || true)"
  echo "  (${n:-0} uncommitted bookkeeping file(s) ignored — tasks/, deploys/,"
  echo "   build/deploy-log.md. ENV_CLASS=prod or BOOKKEEPING_STRICT=1 counts them.)"
fi

echo "✓ Working tree clean"
