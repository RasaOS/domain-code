#!/usr/bin/env bash
# verified-build.sh — refuse to deploy a build nobody tested.
#
# $1 = environment name. Reads ENV_CLASS (exported by build/deploy).
#
# Passes when tests/runs/ holds a PASSED test record for HEAD whose build
# record (builds/records/) succeeded, built HEAD, was built for this
# environment or for any, and whose artifacts are still on disk with the
# fingerprint the build recorded. On a pass it prints, on stdout:
#   verified_build=<BLD-id>
#   verified_test=<TST-id>
#   build_artifacts=<manifest path>
# and build/deploy ships that build instead of rebuilding it. Everything else
# goes to stderr.
#
# At prod class it also requires tests/suites/smoke.md with at least one test:
# stages/60-verify.sh runs it against the deployed environment, and finding it
# missing AFTER the deploy would be too late to refuse.
#
# Calibration: hard-fail at staging and prod; warn-and-pass at dev and for an
# unclassified environment, so the inner "edit → deploy to dev → look" loop is
# untouched. THERE IS DELIBERATELY NO BYPASS VARIABLE — same precedent as
# class-guard.sh and tests-required.sh. The way through is ./build/build then
# ./build/test.
#
# Exit: 0 pass (or warn below staging) · 1 refused

set -uo pipefail
ENV="${1:?missing environment}"
ENV_CLASS="${ENV_CLASS:-unclassified}"

GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$GATES_DIR/../.." || exit 1
# shellcheck source=/dev/null
. "$GATES_DIR/verify-lib.sh" || exit 1
# shellcheck source=/dev/null
. "$GATES_DIR/suite-lib.sh" || exit 1

enforced() { [ "$ENV_CLASS" = "prod" ] || [ "$ENV_CLASS" = "staging" ]; }

verdict() {
  if enforced; then
    {
      echo "✗ verified-build: REFUSED — $1"
      echo ""
      echo "  '$ENV' is class $ENV_CLASS: only a build that passed ./build/test ships here."
      echo "  Run:  ./build/build${2:+ --env=$ENV}  &&  ./build/test"
    } >&2
    exit 1
  fi
  echo "⚠ verified-build: $1 (class '$ENV_CLASS' — warning only; refused at staging and prod)" >&2
  exit 0
}

SHA="$(vl_head)" || verdict "this repository has no commits."

TREC="$(vl_latest "$VL_RUNS_DIR" TST "$SHA" passed)" \
  || verdict "no passing test run for HEAD (${SHA:0:12})."
TID="$(basename "$TREC" .md)"
BID="$(vl_field "$TREC" build)"
BREC="$VL_BUILDS_DIR/$BID.md"
[ -f "$BREC" ] || verdict "$TID names build $BID, and there is no such record."
[ "$(vl_field "$BREC" status)" = "success" ] || verdict "$BID did not succeed."
[ "$(vl_field "$BREC" sha)" = "$SHA" ] || verdict "$BID built a different commit than HEAD."
[ "$(vl_field "$BREC" artifacts_digest)" = "$(vl_field "$TREC" artifacts_digest)" ] \
  || verdict "$TID tested a different fingerprint than $BID recorded."
FOR="$(vl_field "$BREC" built_for)"
if [ -n "$FOR" ] && [ "$FOR" != "any" ] && [ "$FOR" != "$ENV" ]; then
  verdict "$BID was built for '$FOR', not '$ENV'." env
fi
vl_build_still_matches "$BREC" || verdict "$BID's artifacts changed after it was tested."

if [ "$ENV_CLASS" = "prod" ]; then
  [ -f tests/suites/smoke.md ] \
    || verdict "no tests/suites/smoke.md — a production deploy must be verified after it lands (stages/60-verify.sh)."
  SMOKE="$(suite_tests tests/suites/smoke.md)"; SRC=$?
  [ "$SRC" -eq 0 ] && [ -n "$SMOKE" ] \
    || verdict "tests/suites/smoke.md lists no tests it can read — production would be verified by nothing."
fi

echo "✓ verified-build: $BID tested by $TID ($(vl_field "$TREC" gate) gate, e2e $(vl_field "$TREC" e2e))" >&2
echo "verified_build=$BID"
echo "verified_test=$TID"
echo "build_artifacts=${BREC%.md}.artifacts"
