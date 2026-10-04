#!/usr/bin/env bash
# gates/live-contained.sh — rule 2 of "deploys never go backwards": never
# drop what another session shipped.
#
# A deploy replaces the whole target. So the commit live in <env> right now
# must be an ancestor of HEAD, or this deploy removes whatever that commit
# added. The live commit, first found wins:
#
#   1. LIVE_SHA=<sha|none> in the environment (the checker's --live-sha);
#   2. the environment's hook — a `live_sha` function, else LIVE_SHA_CMD, in
#      build/environments/<env>/env.sh: e.g. curl a version file the deploy
#      writes, or read the sha a service reports. It prints the commit, or
#      `none` for an environment that was never deployed;
#   3. with no hook: the newest successful (not dry-run) ship-log record for
#      <env> — deploys/records/ in this checkout, and those committed on the
#      trunk. Weaker: another checkout's deploy is only here if it committed
#      its record. A hook is what makes this gate complete.
#
# Refuses: a live commit HEAD does not contain (listing the live commits it
# would drop), a live commit git does not know even after fetching, and — at
# prod class — a live commit nobody can name (no hook, no record) unless
# LIVE_SHA_UNKNOWN_OK=1. Below prod an unknown live commit warns.
# Override: ALLOW_DROP_LIVE=1 (loud; recorded in the ship log).
#
# Stdout carries only machine lines (`live_sha=…`, `override=…`).
#
# Usage: gates/live-contained.sh <env>
# Exit:  0 pass · 1 refused · 2 usage
#
# Portability: bash 3.2 (stock macOS).

set -euo pipefail
ENV_NAME="${1:-}"
case "$ENV_NAME" in
  ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) echo "usage: live-contained.sh <env>" >&2; exit 2 ;;
esac
GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=deploy-sync-lib.sh
. "$GATES_DIR/deploy-sync-lib.sh"
ds_init "$GATES_DIR/../.." || exit 2
ds_live_check "$ENV_NAME" "$(ds_env_class "$ENV_NAME")"
