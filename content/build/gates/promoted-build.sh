#!/usr/bin/env bash
# promoted-build.sh — production gets only a build staging already ran.
#
# $1 = environment name. Reads ENV_CLASS and VERIFIED_BUILD (exported by
# build/deploy after gates/verified-build.sh passed). Runs at prod class only.
#
# Passes when deploys/records/ holds a SUCCESSFUL deploy of the same build
# (BLD id) to an environment of class staging. A successful deploy record
# means every stage passed — 60-verify's smoke check included — so "staged"
# means "ran in staging and was verified there", not "was sent there".
#
# Matched on the build record, not the commit: two builds of one commit are
# two different artifacts, and production gets the one staging ran.
#
# No staging environment declared (the registry lists no class-staging
# environment, or there is no registry): warns loudly and passes — production
# is then the first place this build runs, and the warning says so. Declare a
# staging environment to make this gate bind.
#
# THERE IS DELIBERATELY NO BYPASS VARIABLE. A hotfix goes through staging too:
# ./build/build, ./build/test, deploy to staging, then release.
#
# Exit: 0 pass · 1 refused

set -uo pipefail
ENV="${1:?missing environment}"
ENV_CLASS="${ENV_CLASS:-unclassified}"
[ "$ENV_CLASS" = "prod" ] || exit 0

GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$GATES_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1
# shellcheck source=/dev/null
. "$GATES_DIR/verify-lib.sh" || exit 1

BID="${VERIFIED_BUILD:-}"
if [ -z "$BID" ]; then
  echo "✗ promoted-build: REFUSED — no verified build to promote (verified-build did not pass)." >&2
  exit 1
fi

# Which environments are staging? The registry decides; no registry, no
# staging declared.
ENV_SH="$PROJECT_DIR/.claude/skills/environment/environment.sh"
STAGING=""
if [ -f "$ENV_SH" ]; then
  # An unreadable registry is refused, not read as "no staging declared" —
  # that would wave every prod release through with a warning.
  REG="$PROJECT_DIR/.claude/environments.json"
  if [ -f "$REG" ] && ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$REG" 2>/dev/null; then
    echo "✗ promoted-build: REFUSED — the environment registry ($REG) cannot be read." >&2
    exit 1
  fi
  CLASSES="$(bash "$ENV_SH" classes 2>/dev/null || true)"
  STAGING="$(printf '%s\n' "${CLASSES:-}" | awk '$2 == "staging" { print $1 }')"
fi
if [ -z "$STAGING" ]; then
  {
    echo "⚠ promoted-build: no staging environment is declared — production is the"
    echo "  first place $BID runs. Declare one (environment.sh) to make this gate bind."
  } >&2
  exit 0
fi

hit=""
for f in deploys/records/DEP-*.md; do
  [ -f "$f" ] || continue
  [ "$(vl_field "$f" build)" = "$BID" ] || continue
  [ "$(vl_field "$f" status)" = "success" ] || continue
  [ "$(vl_field "$f" class)" = "staging" ] || continue
  # A --dry-run closes `success` with error_stage `dry-run`: it ran no stage,
  # so it is not "ran in staging". Only a real, clean deploy counts.
  [ -z "$(vl_field "$f" error_stage)" ] || continue
  hit="$(basename "$f" .md) → $(vl_field "$f" environment)"
done

if [ -z "$hit" ]; then
  {
    echo "✗ promoted-build: REFUSED — $BID has not been deployed to staging successfully."
    echo ""
    echo "  Production gets only a build that ran — and passed its smoke check — in"
    echo "  staging ($(echo $STAGING | tr ' ' ',')). Ship it there first:"
    echo "    ./build/deploy --env=$(echo $STAGING | awk '{print $1}') --intent=deploy"
  } >&2
  exit 1
fi
echo "✓ promoted-build: $BID was verified in staging ($hit)" >&2
exit 0
