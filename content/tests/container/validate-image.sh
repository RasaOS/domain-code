#!/usr/bin/env bash
# tests/container/validate-image.sh — static checks against the Dockerfile
# and (optionally) the built image. No container is run here.
#
# Default: hadolint on the Dockerfile. Uncomment trivy/dive/snyk as
# needed for your project's security and size budgets.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOCKERFILE="${DOCKERFILE:-$PROJECT_DIR/Dockerfile}"
IMAGE_NAME="${IMAGE_NAME:-}"
TAG="${DEPLOY_TAG:-local}"

if [[ ! -f "$DOCKERFILE" ]]; then
  echo "✗ Dockerfile not found at $DOCKERFILE"
  exit 1
fi

# ─── Lint Dockerfile (hadolint) ────────────────────────────────────────────
if command -v hadolint >/dev/null 2>&1; then
  echo "  → hadolint $DOCKERFILE"
  hadolint "$DOCKERFILE" || {
    echo "✗ hadolint reported issues."
    exit 1
  }
else
  echo "  ⚠ hadolint not installed; skipping Dockerfile lint."
  echo "    brew install hadolint   # or see https://github.com/hadolint/hadolint"
fi

# ─── Vulnerability scan (trivy) — uncomment if you have it installed ───────
# if [[ -n "$IMAGE_NAME" ]] && command -v trivy >/dev/null 2>&1; then
#   echo "  → trivy image $IMAGE_NAME:$TAG"
#   trivy image --severity HIGH,CRITICAL --exit-code 1 "$IMAGE_NAME:$TAG" || {
#     echo "✗ trivy found HIGH/CRITICAL vulnerabilities."
#     exit 1
#   }
# fi

# ─── Image size budget — uncomment with your size limit ────────────────────
# if [[ -n "$IMAGE_NAME" ]]; then
#   SIZE_BYTES=$(docker image inspect "$IMAGE_NAME:$TAG" --format='{{.Size}}' 2>/dev/null || echo 0)
#   MAX_BYTES=$((500 * 1024 * 1024))   # 500 MB
#   if [[ "$SIZE_BYTES" -gt "$MAX_BYTES" ]]; then
#     echo "✗ Image size $SIZE_BYTES exceeds budget $MAX_BYTES bytes."
#     exit 1
#   fi
# fi

echo "  ✓ Static validation passed."
