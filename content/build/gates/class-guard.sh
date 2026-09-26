#!/usr/bin/env bash
# gates/class-guard.sh — enforce DIRECTION: deploy goes down, release goes up.
#
# THE RULE
#
#   /deploy  targets dev or staging. It can NEVER reach production.
#   /release targets production, and always tags.
#
# Same pipeline underneath; the direction is what differs. So "deploy to
# prod" is not a thing you can typo your way into — it is refused here,
# structurally, before any stage runs.
#
# WHY A CLASS AND NOT A NAME
#
# The old gate was `case "$ENV" in prod|production)` in 10-preflight.sh.
# Exact match, no default arm. `production-us`, `prod-eu`, `live`, `PROD`
# all sailed past with no gate at all. Direction is a property of the
# ENVIRONMENT, declared once in .claude/environments.json, not a property
# of how someone spelled it on the command line.
#
# Classification (see environment.sh `class`):
#   declared `class` wins — EXCEPT that a prod-looking name overrides a
#   non-prod declaration, because guessing wrong in that direction puts a
#   deploy into production;
#   no class + prod-looking name  -> prod   (escalate, never de-escalate);
#   no class + ordinary name      -> unclassified.
#
# unclassified is deliberately not fatal for a deploy: every project that
# upgrades into this version starts with an unclassified registry, and
# failing every deploy closed on upgrade would get this gate deleted. It
# IS fatal for a release. Run `environment.sh classes` and declare them.
#
# NO BYPASS. git-clean.sh has FORCE_DIRTY and approval.sh has
# FORCE_APPROVAL; this gate has nothing. An escape hatch on the one thing
# a gate exists to prevent is decoration. The sanctioned route to
# production is /release, and it already exists.
#
# Usage:
#   gates/class-guard.sh <env> <intent>       intent = deploy | release
#
# Exit: 0 allowed · 1 refused · 2 usage error
#
# Portability: bash 3.2 (stock macOS).

set -euo pipefail

ENV_NAME="${1:-}"
INTENT="${2:-}"

# An environment name is a plain name. `./prod` resolved to environments/prod/
# while the registry lookup and the name heuristic both missed it — every gate
# fell to "unclassified" and an untested change reached production.
case "$ENV_NAME" in
  [A-Za-z0-9]*) ;;
  *) echo "✗ class-guard: bad environment name '$ENV_NAME' — letters, digits, . _ - only, starting with a letter or digit." >&2; exit 2 ;;
esac
case "$ENV_NAME" in
  *[!A-Za-z0-9._-]*) echo "✗ class-guard: bad environment name '$ENV_NAME' — letters, digits, . _ - only." >&2; exit 2 ;;
esac

if [ -z "$ENV_NAME" ] || [ -z "$INTENT" ]; then
  echo "usage: class-guard.sh <env> <intent>   # intent = deploy | release" >&2
  exit 2
fi

case "$INTENT" in
  deploy|release) ;;
  *)
    echo "✗ class-guard: intent must be 'deploy' or 'release' (got '$INTENT')." >&2
    exit 2
    ;;
esac

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_SH="$PROJECT_DIR/.claude/skills/environment/environment.sh"

CLASS=""
SOURCE=""

if [ -f "$ENV_SH" ]; then
  # `class` exits 1 when the registry cannot be read, 2 for an environment
  # it does not list, 3 for one it lists without a class. The first two used
  # to fall to the name heuristic — so one trailing comma in the registry, or
  # a name the registry has never heard of, disarmed every gate. Both now
  # refuse. Only 3 (listed, unclassified) takes the heuristic below.
  set +e
  CLASS="$(bash "$ENV_SH" class "$ENV_NAME" 2>/dev/null)"; CRC=$?
  set -e
  case "$CRC" in
    0|3) ;;
    2) echo "✗ class-guard: '$ENV_NAME' is not in the environment registry (.claude/environments.json) — declare it with its class first." >&2; exit 1 ;;
    *) echo "✗ class-guard: the environment registry (.claude/environments.json) cannot be read — fix it; refusing to guess the class." >&2
       bash "$ENV_SH" class "$ENV_NAME" 2>&1 >/dev/null | sed 's/^/    /' >&2 || true
       exit 1 ;;
  esac
  SOURCE="registry"
fi

case "$CLASS" in
  dev|staging|prod) ;;
  *)
    # No registry, or the registry could not classify it. Apply the same
    # escalate-only name heuristic so a prod-looking environment is still
    # caught in a project that never set up the environment skill.
    # Token test, matching environment.sh. A substring test escalated
    # preprod / non-prod / reproduction-test / alive-service to production.
    lower="$(printf '%s' "$ENV_NAME" | tr '[:upper:]' '[:lower:]')"
    CLASS="unclassified"; SOURCE="${SOURCE:-no registry}"
    case "$lower" in
      *preprod*|*pre-prod*|*pre_prod*|*nonprod*|*non-prod*|*non_prod*|*notprod*|*not-prod*|*not_prod*)
        ;;
      *)
        for _tok in $(printf '%s' "$lower" | tr '\-_.' '   '); do
          case "$_tok" in
            prod*|live*) CLASS="prod"; SOURCE="name heuristic" ;;
          esac
        done
        ;;
    esac
    ;;
esac

refuse() {
  echo "" >&2
  echo "✗ class-guard: REFUSED — $1" >&2
  echo "" >&2
  echo "  environment : $ENV_NAME" >&2
  echo "  class       : $CLASS ($SOURCE)" >&2
  echo "  intent      : $INTENT" >&2
  echo "" >&2
  shift
  while [ $# -gt 0 ]; do echo "  $1" >&2; shift; done
  echo "" >&2
  exit 1
}

if [ "$INTENT" = "deploy" ]; then
  case "$CLASS" in
    prod)
      refuse "deploy cannot target a production environment." \
        "This is the whole point of the deploy/release split:" \
        "  deploy  -> dev, staging      (lower environments)" \
        "  release -> prod              (tagged, official)" \
        "" \
        "If you meant to ship to production, use /release." \
        "If '$ENV_NAME' is NOT production, declare its class in" \
        ".claude/environments.json — but note that a name containing" \
        "'prod' or 'live' is treated as production regardless, so rename" \
        "it if that is wrong."
      ;;
    unclassified)
      echo "⚠ class-guard: '$ENV_NAME' has no declared class ($SOURCE)." >&2
      echo "  Allowing the deploy — it does not look like production — but" >&2
      echo "  this environment is unguarded until you declare it. Run:" >&2
      echo "      .claude/skills/environment/environment.sh classes" >&2
      echo "  and add \"class\": \"dev\"|\"staging\"|\"prod\" in .claude/environments.json." >&2
      ;;
  esac
  echo "✓ class-guard: deploy → $ENV_NAME (class: $CLASS)"
  exit 0
fi

# intent = release
if [ "$CLASS" != "prod" ]; then
  refuse "release targets production, and '$ENV_NAME' is not production." \
    "release means: tag this version and ship it to prod." \
    "To ship to a lower environment, use /deploy." \
    "" \
    "If '$ENV_NAME' really is production, declare it:" \
    "  \"$ENV_NAME\": { \"class\": \"prod\", ... }  in .claude/environments.json"
fi

echo "✓ class-guard: release → $ENV_NAME (class: $CLASS)"
exit 0
