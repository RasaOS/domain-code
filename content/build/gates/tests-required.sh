#!/usr/bin/env bash
# tests-required.sh — refuse a production deploy whose test gate would run nothing.
#
# $1 = environment name (for messaging only; the decision keys on ENV_CLASS)
#
# THERE IS DELIBERATELY NO BYPASS ENVIRONMENT VARIABLE. Same precedent as
# class-guard.sh. FORCE_DIRTY is the in-repo proof that a comment saying "don't
# use this for prod" is not a gate — git-clean.sh returns on it before its own
# class logic ever runs. The escape hatch here is "write one test".
#
# Reads only ENV_CLASS and the filesystem, so it cannot be disarmed by an
# unreadable environment registry the way class-guard's registry path can.
#
# Calibration, copied from class-guard: hard-fail at prod class, warn-and-pass
# everywhere else, permanently. Dev and staging workflows are untouched.

set -euo pipefail
ENV_NAME="${1:-unknown}"
ENV_CLASS="${ENV_CLASS:-unclassified}"

GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$GATES_DIR/../.." && pwd)"
SUITES_DIR="$PROJECT_DIR/tests/suites"
STAMPS_DIR="$PROJECT_DIR/tests/stamps"

# shellcheck source=/dev/null
. "$GATES_DIR/suite-lib.sh"

AT_PROD=false
[ "$ENV_CLASS" = "prod" ] && AT_PROD=true

# verdict <reason> — refuse at prod, warn below it.
verdict() {
  if [ "$AT_PROD" = true ]; then
    {
      echo "✗ tests-required: REFUSED — $1"
      echo ""
      echo "  Environment '$ENV_NAME' is class prod. A gate suite that runs no"
      echo "  tests is not a gate, so this deploy is refused."
      echo ""
      echo "  Suite file: ${SUITE_FILE:-$SUITES_DIR/pre-deploy.md}"
      echo ""
      echo "  Fix: add at least one active test stamp's name to the suite's"
      echo "  'tests:' list. Both YAML forms work:"
      echo ""
      echo "      tests:"
      echo "        - my-stamp-name"
      echo ""
      unwired_stamps
      echo "  No tests at all yet? Write one bash script covering the riskiest"
      echo "  path, put it in tests/scripts/, stamp it under tests/stamps/, and"
      echo "  list the stamp here. test-rules.md sanctions exactly this."
      echo ""
      echo "  There is no flag or environment variable that skips this gate."
    } >&2
    exit 1
  fi
  echo "⚠ tests-required: $1 (class '$ENV_CLASS' — warning only; this would"
  echo "  REFUSE the deploy at prod class)"
  exit 0
}

# List stamps that exist but are wired into no suite — the most useful thing we
# can tell someone who just got blocked.
unwired_stamps() {
  [ -d "$STAMPS_DIR" ] || return 0
  _listed=""
  if [ -n "${SUITE_FILE:-}" ] && [ -f "${SUITE_FILE:-}" ]; then
    _listed="$(suite_tests "$SUITE_FILE" 2>/dev/null || true)"
  fi
  _found=""
  for _f in "$STAMPS_DIR"/*.md; do
    [ -f "$_f" ] || continue
    _nm="$(stamp_field "$_f" name)"; [ -n "$_nm" ] || continue
    [ "$(stamp_field "$_f" status)" = "active" ] || continue
    printf '%s\n' "$_listed" | grep -qx "$_nm" && continue
    _found="$_found    - $_nm
"
  done
  if [ -n "$_found" ]; then
    echo "  These active stamps already exist and are wired into no suite:"
    printf '%s' "$_found"
    echo ""
  fi
}

# ── Decide ────────────────────────────────────────────────────────────────────

command -v python3 >/dev/null 2>&1 || \
  verdict "python3 is required to read the suite and is not available"

SUITE_FILE=""
if ! SUITE_FILE="$(suite_file_for_class "$SUITES_DIR" "$ENV_CLASS")"; then
  SUITE_FILE=""
  verdict "no test suite exists at $SUITES_DIR"
fi

set +e
TESTS="$(suite_tests "$SUITE_FILE")"; PARSE_RC=$?
set -e
[ "$PARSE_RC" -eq 3 ] && \
  verdict "the 'tests:' key in $(basename "$SUITE_FILE") is not in a form this gate can read"
[ "$PARSE_RC" -ne 0 ] && \
  verdict "could not read $(basename "$SUITE_FILE") (rc=$PARSE_RC)"

[ -z "$TESTS" ] && verdict "suite '$(basename "$SUITE_FILE" .md)' lists no tests"

# Would anything ACTUALLY run? Quarantined members are skipped by 30-test.sh, so
# an all-quarantined suite is an empty suite by another route. A member with no
# stamp, or an ambiguous one, cannot run either.
RUNNABLE=0
while IFS= read -r t; do
  [ -n "$t" ] || continue
  set +e
  SF="$(stamp_for "$STAMPS_DIR" "$t")"; SRC=$?
  set -e
  [ "$SRC" -ne 0 ] && continue                       # missing or ambiguous
  SF="$(printf '%s' "$SF" | head -1)"
  ST="$(stamp_field "$SF" status)"
  [ "$ST" = "quarantined" ] && continue
  RUNNABLE=$((RUNNABLE + 1))
done <<EOF
$TESTS
EOF

[ "$RUNNABLE" -eq 0 ] && \
  verdict "every member of '$(basename "$SUITE_FILE" .md)' is quarantined, missing a stamp, or ambiguous — nothing would run"

echo "✓ tests-required: $(basename "$SUITE_FILE" .md) has $RUNNABLE runnable test(s) (class: $ENV_CLASS)"
exit 0
