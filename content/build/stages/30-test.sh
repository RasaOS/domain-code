#!/usr/bin/env bash
# 30-test.sh — run the test suite for this environment
#
# Reads tests/suites/<suite>.md and runs each member test. Suite chosen
# by env (default: pre-deploy; prod uses prod-gate if present).
#
# Test stamps live in tests/stamps/<dated_name>.md with frontmatter
# declaring how to run each test. See test-rules.md.
#
# $1 = environment name

set -euo pipefail
ENV="${1:?missing environment}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITES_DIR="$PROJECT_DIR/tests/suites"

# ─── Pick the suite for this env ───────────────────────────────────────────
SUITE=""
case "$ENV" in
  prod|production)
    if   [[ -f "$SUITES_DIR/prod-gate.md"  ]]; then SUITE="prod-gate"
    elif [[ -f "$SUITES_DIR/pre-deploy.md" ]]; then SUITE="pre-deploy"
    fi
    ;;
  *)
    if [[ -f "$SUITES_DIR/pre-deploy.md" ]]; then SUITE="pre-deploy"; fi
    ;;
esac

if [[ -z "$SUITE" ]]; then
  echo "No test suite for env=$ENV. Skipping."
  exit 0
fi

SUITE_FILE="$SUITES_DIR/$SUITE.md"
echo "Running test suite: $SUITE ($SUITE_FILE)"

# ─── Parse member tests from suite frontmatter ─────────────────────────────
# Suite file format (see test-rules.md):
#   ---
#   tests:
#     - user-auth-flow
#     - api-health-check
#   ---
#
# Extract names between `tests:` and the next non-indented key (or end of frontmatter).
TESTS=$(
  awk '
    /^---$/ { fence++; next }
    fence == 1 && /^tests:/ { in_tests = 1; next }
    fence == 1 && in_tests && /^  *- / { sub(/^  *- */, ""); print; next }
    fence == 1 && in_tests && /^[a-zA-Z]/ { in_tests = 0 }
    fence == 2 { exit }
  ' "$SUITE_FILE"
)

if [[ -z "$TESTS" ]]; then
  echo "Suite '$SUITE' has no tests listed. Skipping."
  exit 0
fi

# ─── For each member test: find its stamp, run its run_command ─────────────
STAMPS_DIR="$PROJECT_DIR/tests/stamps"
FAIL=0

while IFS= read -r TEST_NAME; do
  [[ -z "$TEST_NAME" ]] && continue

  # Find the stamp file by name field (dated filenames vary)
  STAMP_FILE=$(grep -lE "^name:[[:space:]]*${TEST_NAME}\b" "$STAMPS_DIR"/*.md 2>/dev/null | head -1)
  if [[ -z "$STAMP_FILE" ]]; then
    echo "  ✗ $TEST_NAME — stamp not found in tests/stamps/"
    FAIL=1
    continue
  fi

  # Extract run_command from the stamp's frontmatter
  RUN_CMD=$(awk '/^---$/{f++; next} f==1 && /^run_command:/ {sub(/^run_command:[[:space:]]*/, ""); print; exit}' "$STAMP_FILE")
  if [[ -z "$RUN_CMD" ]]; then
    echo "  ✗ $TEST_NAME — stamp has no run_command"
    FAIL=1
    continue
  fi

  echo "  ▷ $TEST_NAME"
  if bash -c "$RUN_CMD" >/dev/null 2>&1; then
    echo "    ✓ pass"
  else
    echo "    ✗ fail"
    FAIL=1
  fi
done <<< "$TESTS"

if [[ "$FAIL" -ne 0 ]]; then
  echo ""
  echo "Test suite '$SUITE' failed."
  exit 1
fi

echo "Test suite '$SUITE' passed."
