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
#   builds/, tests/runs/  build/build and build/test write the build and
#                     test records the verified-build gate reads
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
# TWO TIERS, because two different systems write here.
#
#   ALWAYS excluded: deploys/ and build/deploy-log.md. These are written
#   BY THIS PIPELINE, during the very run being gated — build/deploy opens
#   a ship-log record before stage 10 executes. Counting them is
#   self-referential: a release off a PERFECTLY CLEAN tree failed its own
#   preflight on the record it had just written, so 100% of pipeline
#   releases failed. Excluding them for non-prod only (the first attempt
#   at this fix) left production broken, which is the half that matters.
#
#   Excluded for NON-PROD only: tasks/. That is task enforcement's
#   bookkeeping — a different system, representing work in progress, and
#   a production release legitimately should not be carrying uncommitted
#   task churn.
#
# BOOKKEEPING_STRICT=1 excludes nothing, anywhere.
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

# Anchor at the repo root. `git status` is cwd-scoped, so a gate invoked
# from a subdirectory would report a clean tree while the rest of the repo
# was dirty. (`:/` as a pathspec base does NOT combine with :(exclude) —
# verified; cd is what actually works.)
cd "$(git rev-parse --show-toplevel)" || exit 1

ENV_CLASS="${ENV_CLASS:-unclassified}"
STRICT="${BOOKKEEPING_STRICT:-${TASK_CHURN_STRICT:-0}}"

# `:(exclude)` is a pathspec magic word, supported by git 1.9+.
# `:/` anchors to the repo root so the result does not depend on the cwd
# the caller happened to be in.
PIPELINE_OWN=(':(exclude)deploys/' ':(exclude)build/deploy-log.md' ':(exclude)builds/' ':(exclude)tests/runs/')
TASK_CHURN=(':(exclude)tasks/')

DIRTY=""
EXCLUDED=""
if [[ "$STRICT" == "1" ]]; then
  DIRTY="$(git status --porcelain)"
elif [[ "$ENV_CLASS" == "prod" ]]; then
  DIRTY="$(git status --porcelain -- . "${PIPELINE_OWN[@]}")"
  EXCLUDED="$(git status --porcelain -- 'deploys/' 'build/deploy-log.md' 'builds/' 'tests/runs/')"
else
  DIRTY="$(git status --porcelain -- . "${PIPELINE_OWN[@]}" "${TASK_CHURN[@]}")"
  EXCLUDED="$(git status --porcelain -- 'tasks/' 'deploys/' 'build/deploy-log.md' 'builds/' 'tests/runs/')"
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
  if [[ "$ENV_CLASS" == "prod" ]]; then
    echo "  (${n:-0} pipeline-owned bookkeeping file(s) ignored — deploys/, builds/,"
    echo "   tests/runs/, build/deploy-log.md. tasks/ IS counted for prod.)"
  else
    echo "  (${n:-0} bookkeeping file(s) ignored — tasks/, deploys/, builds/,"
    echo "   tests/runs/, build/deploy-log.md. BOOKKEEPING_STRICT=1 counts them.)"
  fi
fi

echo "✓ Working tree clean"
