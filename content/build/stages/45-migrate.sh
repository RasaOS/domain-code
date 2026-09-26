#!/usr/bin/env bash
# 45-migrate.sh — apply database migrations BEFORE the new code deploys.
#
# Opt-in, per environment: runs build/environments/<env>/migrate.sh when it
# exists and is executable; otherwise a no-op. Ordered after 40-publish and
# before 50-deploy, so new code never meets an old schema.
#
# The contract the project's migrate.sh keeps (migration-rules.md):
#   - EXPAND / CONTRACT. A migration applied here runs while the PREVIOUS
#     code is still serving: it must be backward-compatible with it. Drop a
#     column in a later release, after no deployed code reads it.
#   - Idempotent. A re-run applies nothing twice.
#   - Logged. Append the run to MIGRATIONS.md (what, when, who, environment,
#     result).
#   - Non-zero on failure. The deploy stops here and the new code never
#     ships; the ship log records `failed at 45-migrate`.
#
# At prod class this runs after 10-preflight's approval gate — the pipeline is
# the "explicit job with review gates" migration-rules.md requires. A
# migration marked irreversible still needs its own backup step inside
# migrate.sh; the pipeline cannot know it is needed.
#
# $1 = environment name

set -euo pipefail
ENV="${1:?missing environment}"
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIGRATE="$STAGE_DIR/../environments/$ENV/migrate.sh"

if [ ! -e "$MIGRATE" ]; then
  echo "No migrations for '$ENV' (no environments/$ENV/migrate.sh)."
  exit 0
fi
if [ ! -x "$MIGRATE" ]; then
  echo "✗ $MIGRATE exists but is not executable — refusing to skip migrations silently." >&2
  echo "  chmod +x $MIGRATE" >&2
  exit 1
fi

echo "Applying migrations for '$ENV' before the code deploys"
"$MIGRATE"
echo "✓ migrations applied for '$ENV'"
