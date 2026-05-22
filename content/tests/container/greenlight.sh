#!/usr/bin/env bash
# tests/container/greenlight.sh — pre-deploy image validation
#
# Composes validate-image → run-local → check-logs. Exit 0 only if all
# three pass — that's the "green light" for deploy.
#
# Wired into the pre-deploy suite via a test stamp named "container-greenlight".
#
# Required env vars (set by build/deploy via env.sh):
#   IMAGE_NAME    — name of the image being deployed (no tag)
#   DEPLOY_TAG    — tag to test (defaults to "local" if running standalone)

set -euo pipefail

CONTAINER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="${IMAGE_NAME:?IMAGE_NAME required}"
TAG="${DEPLOY_TAG:-local}"

echo "═══════════════════════════════════════════════════════════"
echo "  Container greenlight: $IMAGE_NAME:$TAG"
echo "═══════════════════════════════════════════════════════════"

# ─── Stage 1: static validation ────────────────────────────────────────────
echo ""
echo "▶ Static validation (validate-image.sh)"
if ! "$CONTAINER_DIR/validate-image.sh"; then
  echo "✗ Static validation failed."
  exit 1
fi

# ─── Stage 2: run locally + smoke ──────────────────────────────────────────
echo ""
echo "▶ Local run + smoke (run-local.sh)"
if ! "$CONTAINER_DIR/run-local.sh"; then
  echo "✗ Local run failed."
  exit 1
fi

# ─── Stage 3: log check ────────────────────────────────────────────────────
echo ""
echo "▶ Log check (check-logs.sh)"
if ! "$CONTAINER_DIR/check-logs.sh"; then
  echo "✗ Log check failed."
  exit 1
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  ✓ Green light: $IMAGE_NAME:$TAG cleared for deploy"
echo "═══════════════════════════════════════════════════════════"
