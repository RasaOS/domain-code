#!/usr/bin/env bash
# 10-preflight.sh — checks before doing anything
#
# Invoke gates here. Default behavior: require a clean working tree.
# Customize per project: tag-matches, secrets-present, branch-name, etc.
#
# $1 = environment name (dev / staging / prod / ...)
#
# Reads from the environment (exported by build/deploy):
#   ENV_CLASS   dev | staging | prod | unclassified — DIRECTION, not name
#   INTENT      deploy | release
#   SKIP_GATES  true | false — skips the OPTIONAL gates only
#
# Before v0.44.0 this stage decided production by `case "$ENV" in
# prod|production)` with no default arm, so `production-us`, `prod-eu`,
# `live` and `PROD` all took NO gate. Class is resolved once in
# build/deploy and passed down; never re-match the name here.

set -euo pipefail
ENV="${1:?missing environment}"

GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../gates" && pwd)"

ENV_CLASS="${ENV_CLASS:-unclassified}"
INTENT="${INTENT:-deploy}"
SKIP_GATES="${SKIP_GATES:-false}"

# ─── Optional gates ────────────────────────────────────────────────────────
# These are the ones --skip-gates is allowed to skip. A production deploy
# never skips them, whatever was passed: "the tree was dirty" is not a
# thing you get to wave through on the way to prod.
if [ "$SKIP_GATES" = "true" ] && [ "$ENV_CLASS" != "prod" ]; then
  echo "  (optional gates skipped: --skip-gates)"
else
  # Working tree must be clean
  "$GATES_DIR/git-clean.sh"

  # Tag-matches gate (uncomment if your project releases by tag)
  # "$GATES_DIR/tag-matches.sh"
fi

# ─── Production gates ──────────────────────────────────────────────────────
# Keyed on CLASS, not on how the environment was spelled. Not skippable.
if [ "$ENV_CLASS" = "prod" ]; then
  "$GATES_DIR/approval.sh" "$INTENT $DEPLOY_TAG to production ($ENV)?"
fi

echo "Preflight OK for env: $ENV (class: $ENV_CLASS, intent: $INTENT)"
