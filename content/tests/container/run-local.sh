#!/usr/bin/env bash
# tests/container/run-local.sh — boot the container locally and smoke-test it.
#
# Runs the image, waits for it to become ready, hits a health endpoint,
# then tears down. Exit 0 if the container booted and responded.
#
# Required env vars:
#   IMAGE_NAME    — image to test
# Optional:
#   DEPLOY_TAG    — tag (default: local)
#   PORT          — port to map and hit (default: 8080)
#   HEALTH_PATH   — health endpoint path (default: /health)
#   READY_TIMEOUT — seconds to wait for ready (default: 30)

set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:?IMAGE_NAME required}"
TAG="${DEPLOY_TAG:-local}"
PORT="${PORT:-8080}"
HEALTH_PATH="${HEALTH_PATH:-/health}"
READY_TIMEOUT="${READY_TIMEOUT:-30}"

CONTAINER_ID=""
cleanup() {
  if [[ -n "$CONTAINER_ID" ]]; then
    echo "  → cleanup: docker rm -f $CONTAINER_ID >/dev/null"
    docker rm -f "$CONTAINER_ID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ─── Boot ──────────────────────────────────────────────────────────────────
echo "  → docker run -d -p $PORT:$PORT $IMAGE_NAME:$TAG"
CONTAINER_ID=$(docker run -d -p "$PORT:$PORT" "$IMAGE_NAME:$TAG")
echo "    container_id=$CONTAINER_ID"

# Stash container ID for check-logs.sh
echo "$CONTAINER_ID" > /tmp/greenlight-container-id

# ─── Wait for ready ────────────────────────────────────────────────────────
echo "  → waiting up to ${READY_TIMEOUT}s for http://localhost:$PORT$HEALTH_PATH"
ELAPSED=0
while [[ "$ELAPSED" -lt "$READY_TIMEOUT" ]]; do
  if curl -sf "http://localhost:$PORT$HEALTH_PATH" >/dev/null 2>&1; then
    echo "  ✓ ready after ${ELAPSED}s"
    break
  fi
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

if [[ "$ELAPSED" -ge "$READY_TIMEOUT" ]]; then
  echo "  ✗ container did not become ready within ${READY_TIMEOUT}s"
  echo "  --- container logs ---"
  docker logs "$CONTAINER_ID" | tail -50
  exit 1
fi

# ─── Smoke: health endpoint returns 2xx ────────────────────────────────────
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT$HEALTH_PATH" || echo "000")
if [[ ! "$HTTP_CODE" =~ ^2[0-9][0-9]$ ]]; then
  echo "  ✗ health endpoint returned $HTTP_CODE (expected 2xx)"
  exit 1
fi

echo "  ✓ health endpoint OK ($HTTP_CODE)"
echo "  ✓ Local run passed."
