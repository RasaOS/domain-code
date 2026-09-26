#!/usr/bin/env bash
# 30-test.sh — run the test suite for this environment
#
# Reads tests/suites/<suite>.md and runs each member test. Suite chosen by
# CLASS (not by environment NAME — the old `case "$ENV" in prod|production)`
# gave `production-us` the ordinary pre-deploy suite instead of the gate).
#
# Test stamps live in tests/stamps/<dated_name>.md with frontmatter declaring
# how to run each test. See test-rules.md.
#
# Parsing is delegated to gates/suite-lib.sh, which the tests-required gate
# also uses, so the stage and the gate can never disagree about what "empty"
# means. This stage previously carried its own awk parser that understood only
# block-sequence YAML: `tests: [auth, api-health]` parsed as ZERO tests and the
# suite exited 0.
#
# THE EXIT RULE, one condition rather than four:
#   FAILED > 0                     -> exit 1, at every class
#   RAN == 0 and class is prod     -> exit 1
#   otherwise                      -> exit 0
# The second clause closes empty-list, all-quarantined, unparseable-list and
# unresolved-stamp together. build/deploy runs gates/tests-required.sh for the
# same reason, but that gate does not cover DIRECT invocation of this stage —
# which the shipped suite body tells operators to do.
#
# TWO INPUTS from the phase scripts (build/test, 60-verify.sh). Both can
# only narrow or tighten the stage, never loosen it:
#   TEST_SUITE=<name>  run tests/suites/<name>.md instead of choosing by
#                      class. A named suite that does not exist is an error
#                      at every class — never a fall-back to another suite.
#   TEST_STRICT=1      apply the prod rule (a suite that runs nothing fails)
#                      whatever the class. build/test always sets it.
#
# $1 = environment name

set -euo pipefail
ENV="${1:?missing environment}"
ENV_CLASS="${ENV_CLASS:-unclassified}"

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$STAGE_DIR/../.." && pwd)"
SUITES_DIR="$PROJECT_DIR/tests/suites"
STAMPS_DIR="$PROJECT_DIR/tests/stamps"

# Relative run_commands must resolve against the project, not the caller's cwd.
cd "$PROJECT_DIR"

# shellcheck source=/dev/null
. "$PROJECT_DIR/build/gates/suite-lib.sh"

at_prod() { [ "$ENV_CLASS" = "prod" ] || [ "${TEST_STRICT:-0}" = "1" ]; }

# fail_or_warn <message> — exit 1 at prod class, warn and exit 0 below it.
fail_or_warn() {
  if at_prod; then
    echo "✗ $1" >&2
    if [ "$ENV_CLASS" = "prod" ]; then
      echo "  Environment '$ENV' is class prod: a suite that runs no tests fails." >&2
    else
      echo "  TEST_STRICT=1: a suite that runs no tests fails." >&2
    fi
    exit 1
  fi
  echo "⚠ $1 (class '$ENV_CLASS' — warning only; this fails at prod class)"
  exit 0
}

# ─── Pick the suite ────────────────────────────────────────────────────────
if [ -n "${TEST_SUITE:-}" ]; then
  case "$TEST_SUITE" in
    */*|.*|"") echo "✗ TEST_SUITE must be a suite name, got '$TEST_SUITE'" >&2; exit 1 ;;
  esac
  SUITE_FILE="$SUITES_DIR/$TEST_SUITE.md"
  if [ ! -f "$SUITE_FILE" ]; then
    echo "✗ Suite '$TEST_SUITE' was asked for by name and does not exist ($SUITE_FILE)." >&2
    exit 1
  fi
elif ! SUITE_FILE="$(suite_file_for_class "$SUITES_DIR" "$ENV_CLASS")"; then
  fail_or_warn "No test suite found in $SUITES_DIR"
fi
SUITE="$(basename "$SUITE_FILE" .md)"
echo "Running test suite: $SUITE ($SUITE_FILE)"

set +e
TESTS="$(suite_tests "$SUITE_FILE")"; PARSE_RC=$?
set -e
case "$PARSE_RC" in
  0) ;;
  3) fail_or_warn "Suite '$SUITE' has a 'tests:' key this parser cannot read." ;;
  4) fail_or_warn "python3 is required to read the suite and is not available." ;;
  *) fail_or_warn "Could not read suite '$SUITE' (rc=$PARSE_RC)." ;;
esac

[ -z "$TESTS" ] && fail_or_warn "Suite '$SUITE' lists no tests."

# ─── Run members ───────────────────────────────────────────────────────────
RAN=0; SKIPPED=0; FAILED=0

while IFS= read -r TEST_NAME; do
  [ -n "$TEST_NAME" ] || continue

  set +e
  STAMP_FILE="$(stamp_for "$STAMPS_DIR" "$TEST_NAME")"; LOOKUP_RC=$?
  set -e

  # These branches were unreachable before: under `set -euo pipefail` the old
  # `grep ... | head -1` assignment killed the stage outright, so a missing
  # stamp exited with NO diagnostic at all.
  if [ "$LOOKUP_RC" -eq 1 ]; then
    echo "  ✗ $TEST_NAME — no stamp with this exact name in tests/stamps/"
    FAILED=$((FAILED + 1)); continue
  fi
  if [ "$LOOKUP_RC" -eq 2 ]; then
    echo "  ✗ $TEST_NAME — ambiguous: more than one stamp declares this name"
    printf '%s' "$STAMP_FILE" | sed 's/^/      /'
    FAILED=$((FAILED + 1)); continue
  fi
  STAMP_FILE="$(printf '%s' "$STAMP_FILE" | head -1)"

  STATUS="$(stamp_field "$STAMP_FILE" status)"
  case "$STATUS" in
    quarantined)
      # Documented in test-rules.md: skip-and-warn rather than fail. Does NOT
      # count as having run, so an all-quarantined suite is an empty suite.
      echo "  ⚠ $TEST_NAME — quarantined, skipped"
      SKIPPED=$((SKIPPED + 1)); continue
      ;;
    retired)
      # A retired test still listed in a selected gate suite is a broken suite.
      # Treating it like quarantined would make `status: retired` a permanent
      # silent bypass.
      echo "  ✗ $TEST_NAME — retired but still listed in suite '$SUITE'"
      FAILED=$((FAILED + 1)); continue
      ;;
    active) ;;
    *)
      # Unknown or absent: RUN it and warn. Skipping on an unrecognized value
      # would let a typo in `status:` disarm the gate.
      echo "  ⚠ $TEST_NAME — unrecognized status '${STATUS:-<none>}', running anyway"
      ;;
  esac

  RUN_CMD="$(stamp_field "$STAMP_FILE" run_command)"
  if [ -z "$RUN_CMD" ]; then
    echo "  ✗ $TEST_NAME — stamp has no run_command ($STAMP_FILE)"
    FAILED=$((FAILED + 1)); continue
  fi

  echo "  ▷ $TEST_NAME"
  set +e
  OUTPUT="$(bash -c "$RUN_CMD" 2>&1)"; TEST_RC=$?
  set -e
  RAN=$((RAN + 1))
  if [ "$TEST_RC" -eq 0 ]; then
    echo "    ✓ pass"
  else
    # Print the output. Hiding it behind >/dev/null is how a blocked consumer
    # ends up reaching for --skip-tests instead of reading the failure.
    echo "    ✗ fail (exit $TEST_RC)"
    printf '%s\n' "$OUTPUT" | sed 's/^/      /'
    FAILED=$((FAILED + 1))
  fi
done <<EOF
$TESTS
EOF

# ─── Verdict ───────────────────────────────────────────────────────────────
echo ""
echo "Suite '$SUITE': ran $RAN, skipped $SKIPPED, failed $FAILED"

if [ "$FAILED" -gt 0 ]; then
  echo "Test suite '$SUITE' failed." >&2
  exit 1
fi

if [ "$RAN" -eq 0 ]; then
  fail_or_warn "Suite '$SUITE' ran no tests (every member quarantined or unresolvable)."
fi

echo "Test suite '$SUITE' passed."
