#!/usr/bin/env bash
# 60-verify.sh — after the deploy lands, prove the environment works.
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
# A failure here fails the deploy and the ship log records `failed at
# 60-verify` — but the new build IS running in the environment. Roll it back.
#
# $1 = environment name

set -euo pipefail
ENV="${1:?missing environment}"
ENV_CLASS="${ENV_CLASS:-unclassified}"
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$STAGE_DIR/../.."

if [ ! -f tests/suites/smoke.md ]; then
  if [ "$ENV_CLASS" = "prod" ]; then
    echo "✗ No tests/suites/smoke.md — '$ENV' is class prod and must be verified after deploy." >&2
    exit 1
  fi
  echo "⚠ No tests/suites/smoke.md — '$ENV' was not verified after deploy (class '$ENV_CLASS': warning only)."
  exit 0
fi

echo "Verifying the deployed environment '$ENV' with suite: smoke"
if TEST_SUITE=smoke bash "$STAGE_DIR/30-test.sh" "$ENV"; then
  echo "✓ '$ENV' verified after deploy."
  exit 0
fi
{
  echo ""
  echo "✗ '$ENV' FAILED verification after deploy."
  echo "  The new build is running there now. Roll it back (the Rollback row of"
  echo "  the environment's cloud stamp), then find out why smoke failed."
} >&2
exit 1
