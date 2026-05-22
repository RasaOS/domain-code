#!/usr/bin/env bash
# tests/container/check-logs.sh — parse container logs for expected startup
# patterns and the absence of forbidden patterns (errors, panics, etc.).
#
# Reads from the container started by run-local.sh (container ID stashed
# in /tmp/greenlight-container-id), or from a docker logs invocation.
#
# Customize EXPECTED_PATTERNS and FORBIDDEN_PATTERNS for the project.

set -euo pipefail

# Container ID from run-local.sh
if [[ ! -f /tmp/greenlight-container-id ]]; then
  echo "  ✗ no container ID stashed — did run-local.sh run first?"
  exit 1
fi
CONTAINER_ID=$(cat /tmp/greenlight-container-id)

# ─── Patterns ──────────────────────────────────────────────────────────────
# Project-specific. Edit per service.
EXPECTED_PATTERNS=(
  # "Server listening on"
  # "Database connected"
)

FORBIDDEN_PATTERNS=(
  "panic"
  "FATAL"
  "stack trace"
  "uncaught exception"
)

# ─── Read logs ─────────────────────────────────────────────────────────────
LOGS=$(docker logs "$CONTAINER_ID" 2>&1)

# ─── Required patterns must be present ─────────────────────────────────────
for pattern in "${EXPECTED_PATTERNS[@]}"; do
  if ! grep -qE "$pattern" <<< "$LOGS"; then
    echo "  ✗ expected log pattern not found: $pattern"
    echo "  --- last 30 log lines ---"
    tail -30 <<< "$LOGS"
    exit 1
  fi
  echo "  ✓ found: $pattern"
done

# ─── Forbidden patterns must be absent ─────────────────────────────────────
for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
  if grep -qE -i "$pattern" <<< "$LOGS"; then
    echo "  ✗ forbidden log pattern found: $pattern"
    echo "  --- matching lines ---"
    grep -E -i "$pattern" <<< "$LOGS" | head -10
    exit 1
  fi
done

echo "  ✓ Log check passed."
