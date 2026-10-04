#!/usr/bin/env bash
# gates/trunk-sync.sh — rule 1 of "deploys never go backwards": sync with
# the trunk first.
#
#   prod class     HEAD must BE the freshly fetched trunk tip (or, for
#                  /release's own release PR, RELEASE_PR=<n>: contain it).
#   lower classes  the trunk tip must be an ancestor of HEAD — a feature
#                  branch synced with the trunk may go to dev or staging.
#
# The trunk: DEPLOY_TRUNK (`origin/main` or `main`), else build/
# pipeline-config.toml `[git] trunk`, else the remote's HEAD, else `main`.
# It is fetched right here, right before the deploy. A failed fetch refuses
# at prod and warns below it (comparing with the last fetched trunk). With no
# remote at all, the local trunk branch is the trunk.
#
# On refusal it names the missing trunk commits and the fix. Override:
# ALLOW_BEHIND_TRUNK=1 (loud; build/deploy records it in the ship log).
#
# Stdout carries only machine lines (`trunk_sha=…`, `override=…`); everything
# for a person goes to stderr. See deploy-sync-lib.sh and pipeline-rules.md.
#
# Usage: gates/trunk-sync.sh <env>        (class from ENV_CLASS, else resolved)
# Exit:  0 pass · 1 refused · 2 usage
#
# Portability: bash 3.2 (stock macOS).

set -euo pipefail
ENV_NAME="${1:-}"
case "$ENV_NAME" in
  ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) echo "usage: trunk-sync.sh <env>" >&2; exit 2 ;;
esac
GATES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=deploy-sync-lib.sh
. "$GATES_DIR/deploy-sync-lib.sh"
ds_init "$GATES_DIR/../.." || exit 2
ds_trunk_check "$ENV_NAME" "$(ds_env_class "$ENV_NAME")"
