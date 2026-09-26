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

# verdict <reason> [<fix>] — refuse at staging/prod (warn below), naming the
# fix. The default fix is to build and test; a refusal whose cause is
# something else says what that is.
verdict() {
  if enforced; then
    {
      echo "✗ verified-build: REFUSED — $1"
      echo ""
      echo "  '$ENV' is class $ENV_CLASS: only a build that passed ./build/test ships here."
      echo "  Fix:  ${2:-./build/build  &&  ./build/test}"
    } >&2
    exit 1
  fi
  echo "⚠ verified-build: $1 (class '$ENV_CLASS' — warning only; refused at staging and prod)" >&2
  exit 0
}

SHA="$(vl_head)" || verdict "this repository has no commits."
SRC="$(vl_source)" || verdict "cannot fingerprint HEAD's source."

# The NEWEST test run of HEAD decides — not the newest passing one. A pass
# followed by a failure of the same commit is a failing commit (or a flaky
# test), and either way it is not verified.
TREC="$(vl_newest "$VL_RUNS_DIR" TST "$SRC")" \
  || verdict "no passing test run for HEAD (${SHA:0:12})."
TID="$(basename "$TREC" .md)"
case "$(vl_field "$TREC" status)" in
  passed) ;;
  *) verdict "the most recent test run of HEAD, $TID, did not pass ($(vl_field "$TREC" status): $(vl_field "$TREC" reason))." ;;
esac
BID="$(vl_field "$TREC" build)"
BREC="$VL_BUILDS_DIR/$BID.md"
[ -f "$BREC" ] || verdict "$TID names build $BID, and there is no such record."
[ "$(vl_field "$BREC" status)" = "success" ] || verdict "$BID did not succeed."
[ "$(vl_field "$BREC" source)" = "$SRC" ] || verdict "$BID built different source than HEAD."
[ "$(vl_field "$BREC" artifacts_digest)" = "$(vl_field "$TREC" artifacts_digest)" ] \
  || verdict "$TID tested a different fingerprint than $BID recorded."
FOR="$(vl_field "$BREC" built_for)"
if [ -n "$FOR" ] && [ "$FOR" != "any" ] && [ "$FOR" != "$ENV" ]; then
  verdict "$BID was built for '$FOR', not '$ENV'." "./build/build --env=$ENV  &&  ./build/test"
fi
vl_build_still_matches "$BREC" || verdict "$BID's artifacts changed after it was tested."

# A build that declared nothing is bound to its source only: whatever sits on
# disk at deploy time is what ships, and nothing can tell. Refused at prod
# unless the build said so on purpose (`source=commit` in $BUILD_ARTIFACTS —
# for a deploy that builds from source itself); a warning at staging.
if [ "$(vl_field "$BREC" artifacts_digest)" = "none" ]; then
  if enforced; then
    verdict "$BID declared no artifacts, so nothing proves what ships is what was tested." \
      "in build/stages/20-build.sh, echo each output into \$BUILD_ARTIFACTS (echo dist >> \"\$BUILD_ARTIFACTS\"), or echo source=commit if your deploy builds from source — then ./build/build && ./build/test"
  fi
  echo "⚠ verified-build: $BID declared no artifacts — bound to its source only; staging and prod refuse it." >&2
fi

if [ "$ENV_CLASS" = "prod" ]; then
  [ -f tests/suites/smoke.md ] \
    || verdict "no tests/suites/smoke.md — a production deploy must be verified after it lands (stages/60-verify.sh)." \
         "write tests/suites/smoke.md listing at least one smoke test (template: .claude/tests/_template-smoke.md; shape: test-rules.md)"
  SMOKE="$(suite_tests tests/suites/smoke.md)"; SRC=$?
  [ "$SRC" -eq 0 ] && [ -n "$SMOKE" ] \
    || verdict "tests/suites/smoke.md lists no tests it can read — production would be verified by nothing." \
         "add at least one smoke test's name to the tests: list in tests/suites/smoke.md"
fi

echo "✓ verified-build: $BID tested by $TID ($(vl_field "$TREC" gate) gate, e2e $(vl_field "$TREC" e2e))" >&2
echo "verified_build=$BID"
echo "verified_test=$TID"
echo "build_artifacts=${BREC%.md}.artifacts"
echo "artifacts_digest=$(vl_field "$BREC" artifacts_digest)"
echo "build_tag=$(vl_field "$BREC" build_tag)"
