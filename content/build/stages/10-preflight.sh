#!/usr/bin/env bash
# 10-preflight.sh — checks before doing anything
#
# Invoke gates here. Default behavior: require a clean working tree.
# Customize per project: tag-matches, secrets-present, branch-name, etc.
#
# $1 = environment name (dev / staging / prod / ...)

set -euo pipefail
ENV="${1:?missing environment}"

GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../gates" && pwd)"

# ─── Always: working tree must be clean ────────────────────────────────────
"$GATES_DIR/git-clean.sh"

# ─── Tag-matches gate (uncomment if your project releases by tag) ──────────
# "$GATES_DIR/tag-matches.sh"

# ─── Production gates ──────────────────────────────────────────────────────
case "$ENV" in
  prod|production)
    # Approval prompt before prod
    "$GATES_DIR/approval.sh" "Deploy $DEPLOY_TAG to production?"
    ;;
esac

echo "Preflight OK for env: $ENV"
