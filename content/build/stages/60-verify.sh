#!/usr/bin/env bash
# 60-verify.sh — after the deploy lands, prove the environment works; if it
# does not, put the last verified build back.
#
# Runs tests/suites/smoke.md through stages/30-test.sh against the environment
# just deployed. ENVIRONMENT, DEPLOY_TO, DEPLOY_TAG and ENV_CLASS are exported
# by build/deploy; smoke tests read them to find their target.
#
# Before this stage, "deploy succeeded" meant a shell process exited 0. A
# release that shipped and then took the environment down was recorded as a
# success, forever.
#
#   prod class      smoke.md required (gates/verified-build.sh refuses the
#                   deploy up front if it is missing); a smoke suite that runs
#                   nothing FAILS.
#   below prod      runs smoke.md if present; without one, warns and passes.
#
# WARM-UP. A service that was deployed a second ago is often still starting.
# Smoke is tried up to VERIFY_ATTEMPTS times (default 3), VERIFY_DELAY seconds
# apart (default 10). Only the last attempt's failure counts.
#
# ROLLBACK. If every attempt fails and build/environments/<env>/rollback.sh
# exists and is executable, it is run with:
#   ROLLBACK_TO_TAG, ROLLBACK_TO_BUILD, ROLLBACK_TO_DEPLOY
# naming the most recent SUCCESSFUL deploy of this environment (a deploy that
# passed this very stage). Smoke then runs once more against the result. The
# deploy is still recorded as failed at 60-verify either way — the output says
# whether the environment is back on a verified build or still on the bad one.
#
# $1 = environment name

set -euo pipefail
ENV="${1:?missing environment}"
ENV_CLASS="${ENV_CLASS:-unclassified}"
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$STAGE_DIR/../.."
# shellcheck source=/dev/null
. "$STAGE_DIR/../gates/verify-lib.sh"

ATTEMPTS="${VERIFY_ATTEMPTS:-3}"; case "$ATTEMPTS" in ''|*[!0-9]*|0) ATTEMPTS=3 ;; esac
DELAY="${VERIFY_DELAY:-10}";      case "$DELAY" in ''|*[!0-9]*) DELAY=10 ;; esac

if [ ! -f tests/suites/smoke.md ]; then
  if [ "$ENV_CLASS" = "prod" ]; then
    echo "✗ No tests/suites/smoke.md — '$ENV' is class prod and must be verified after deploy." >&2
    exit 1
  fi
  echo "⚠ No tests/suites/smoke.md — '$ENV' was not verified after deploy (class '$ENV_CLASS': warning only)."
  exit 0
fi

smoke() { TEST_SUITE=smoke bash "$STAGE_DIR/30-test.sh" "$ENV"; }

n=1
while :; do
  echo "Verifying the deployed environment '$ENV' with suite: smoke (attempt $n/$ATTEMPTS)"
  if smoke; then
    echo "✓ '$ENV' verified after deploy."
    exit 0
  fi
  [ "$n" -lt "$ATTEMPTS" ] || break
  echo "  … not yet healthy — retrying in ${DELAY}s"
  sleep "$DELAY"
  n=$((n + 1))
done

echo "" >&2
echo "✗ '$ENV' FAILED verification after deploy ($ATTEMPTS attempt(s))." >&2

ROLLBACK="build/environments/$ENV/rollback.sh"
if [ ! -x "$ROLLBACK" ]; then
  {
    echo "  The new build is running there NOW, and $ROLLBACK does not exist."
    echo "  Roll it back by hand (the Rollback row of the environment's cloud stamp),"
    echo "  then add $ROLLBACK so the next failed verification undoes itself."
  } >&2
  exit 1
fi

# The last deploy of this environment that passed this stage. This run's own
# record is still in-flight, so it can never be the answer.
LAST=""
for f in deploys/records/DEP-*.md; do
  [ -f "$f" ] || continue
  [ "$(vl_field "$f" environment)" = "$ENV" ] || continue
  [ "$(vl_field "$f" status)" = "success" ] || continue
  # Not a dry-run (it deployed nothing), and never the build that just failed.
  [ -z "$(vl_field "$f" error_stage)" ] || continue
  [ -z "${BUILD_ID:-}" ] || [ "$(vl_field "$f" build)" != "$BUILD_ID" ] || continue
  LAST="$f"
done
if [ -z "$LAST" ]; then
  echo "  No earlier verified deploy of '$ENV' to roll back to — the new build is running there NOW." >&2
  exit 1
fi
ROLLBACK_TO_DEPLOY="$(basename "$LAST" .md)"
ROLLBACK_TO_TAG="$(vl_field "$LAST" tag)"
ROLLBACK_TO_BUILD="$(vl_field "$LAST" build)"
export ROLLBACK_TO_DEPLOY ROLLBACK_TO_TAG ROLLBACK_TO_BUILD

echo "↺ Rolling '$ENV' back to $ROLLBACK_TO_DEPLOY (tag ${ROLLBACK_TO_TAG:-?}, build ${ROLLBACK_TO_BUILD:-unrecorded})" >&2
if ! "$ROLLBACK"; then
  echo "✗ $ROLLBACK FAILED — '$ENV' is in an unknown state. Act now." >&2
  exit 1
fi
if smoke; then
  echo "↺ '$ENV' is back on $ROLLBACK_TO_DEPLOY and verified. This deploy is still recorded as failed." >&2
else
  echo "✗ '$ENV' failed verification after the rollback too — act now." >&2
fi
exit 1
