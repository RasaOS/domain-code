#!/usr/bin/env bash
# deploy-check.sh — "deploys never go backwards", for a deploy that does NOT
# go through ./build/deploy (a raw `firebase deploy`, a project's own
# deploy script, a console upload). Same two checks as the pipeline's gates,
# same code (build/gates/deploy-sync-lib.sh):
#
#   1. trunk-sync      fetch the trunk; prod must be exactly its tip, a lower
#                      environment must contain it.
#   2. live-contained  the commit live in the environment now must be an
#                      ancestor of HEAD — a deploy replaces the whole target.
#
# Run it immediately before the deploy command, from the checkout you are
# about to deploy, and do not deploy unless it prints PASS.
#
# Usage:
#   deploy-check.sh --env <name> [--prod] [--trunk origin/main]
#                   [--live-sha <sha|none> | --live-cmd "<cmd>"]
#                   [--trunk-only | --live-only]
#
#   --env        the environment name (as in build/environments/<name>/ or
#                .claude/environments.json; any plain name otherwise)
#   --prod       treat it as production (else: ENV_CLASS, the registry, the
#                name heuristic — `prod*`/`live*` tokens are prod)
#   --trunk      the trunk to sync with (default: DEPLOY_TRUNK, else
#                [git] trunk in build/pipeline-config.toml, else the remote's
#                HEAD, else origin/main)
#   --live-sha   the commit live in the environment now, or `none`
#   --live-cmd   a command that prints it (e.g. curl a version file)
#                With neither: the env.sh live_sha hook / LIVE_SHA_CMD, then
#                the newest successful ship-log record.
#
# Overrides (loud): ALLOW_BEHIND_TRUNK=1, ALLOW_DROP_LIVE=1,
# LIVE_SHA_UNKNOWN_OK=1. Rule text: .claude/pipeline-rules.md.
#
# Works from any directory: the project is found from this script's own
# location (.claude/skills/deploy/ → the install root, which may be a
# sub-directory of a monorepo), never from the cwd.
#
# Exit: 0 PASS · 1 REFUSED · 2 usage
#
# Portability: bash 3.2 (stock macOS).

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LIB=""
ROOT=""
# An install: .claude/skills/deploy/ → build/gates/ beside .claude/.
# The Element's own tree: content/skills/deploy/ → content/build/gates/.
for cand in "$here/../../..:build/gates" "$here/../..:build/gates"; do
  r="${cand%%:*}"; g="${cand#*:}"
  if [ -f "$r/$g/deploy-sync-lib.sh" ]; then LIB="$r/$g/deploy-sync-lib.sh"; ROOT="$r"; break; fi
done
[ -n "$LIB" ] || { echo "error: build/gates/deploy-sync-lib.sh is missing — re-run the Element's bin/init" >&2; exit 2; }

usage() { sed -n '15,33p' "$0" | sed 's/^# \{0,1\}//'; }

ENV_NAME="" PROD=0 DO_TRUNK=1 DO_LIVE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --env)        ENV_NAME="${2:-}"; shift ;;
    --env=*)      ENV_NAME="${1#*=}" ;;
    --prod)       PROD=1 ;;
    --trunk)      export DEPLOY_TRUNK="${2:-}"; shift ;;
    --trunk=*)    export DEPLOY_TRUNK="${1#*=}" ;;
    --live-sha)   export LIVE_SHA="${2:-}"; shift ;;
    --live-sha=*) export LIVE_SHA="${1#*=}" ;;
    --live-cmd)   export LIVE_SHA_CMD="${2:-}"; shift ;;
    --live-cmd=*) export LIVE_SHA_CMD="${1#*=}" ;;
    --trunk-only) DO_LIVE=0 ;;
    --live-only)  DO_TRUNK=0 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "error: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
case "$ENV_NAME" in
  ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) echo "error: --env <name> is required (letters, digits, . _ -)" >&2; exit 2 ;;
esac
if [ -n "${LIVE_SHA:-}" ] && [ -n "${LIVE_SHA_CMD:-}" ]; then
  echo "error: give --live-sha or --live-cmd, not both" >&2; exit 2
fi

# shellcheck source=/dev/null
. "$LIB"
ds_init "$ROOT" || exit 2
if [ "$PROD" = 1 ]; then CLASS=prod; else CLASS="$(ds_env_class "$ENV_NAME")"; fi
echo "deploy-check: $ENV_NAME (class: $CLASS) at $(git -C "$DS_PROJECT" rev-parse --short HEAD 2>/dev/null || echo '?')" >&2

rc=0
OUT=""
if [ "$DO_TRUNK" = 1 ]; then
  o="$(ds_trunk_check "$ENV_NAME" "$CLASS")" || rc=1
  OUT="$OUT$o
"
fi
if [ "$DO_LIVE" = 1 ] && [ "$rc" = 0 ]; then
  o="$(ds_live_check "$ENV_NAME" "$CLASS")" || rc=1
  OUT="$OUT$o
"
fi

# The machine lines, for a caller that records them.
printf '%s' "$OUT" | sed '/^$/d'
if [ "$rc" = 0 ]; then
  ov="$(printf '%s' "$OUT" | sed -n 's/^override=//p' | tr '\n' ',' | sed 's/,$//')"
  if [ -n "$ov" ]; then echo "PASS (with overrides: $ov) — deploy $ENV_NAME now, then confirm it is live"
  else echo "PASS — deploy $ENV_NAME now, then confirm the live commit is $(git -C "$DS_PROJECT" rev-parse --short HEAD)"; fi
  exit 0
fi
echo "REFUSED — do not deploy $ENV_NAME from this checkout (reason above)"
exit 1
