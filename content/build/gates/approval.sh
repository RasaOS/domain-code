#!/usr/bin/env bash
# gates/approval.sh — prompt for explicit "yes" before continuing
#
# Used for production deploys and other irreversible actions. Reads from
# stdin; exits 0 only on exact "yes" (case-insensitive).
#
# Bypass with FORCE_APPROVAL=1 — only use in trusted automation (CI runner
# with its own approval step), never for interactive prod from a laptop.
#
# Usage:
#   gates/approval.sh "Deploy v1.2.3 to production?"

set -euo pipefail

PROMPT="${1:-Proceed?}"

if [[ "${FORCE_APPROVAL:-0}" == "1" ]]; then
  echo "⚠️  FORCE_APPROVAL=1 — auto-approving: $PROMPT"
  exit 0
fi

# Non-interactive contexts (CI without TTY) must set FORCE_APPROVAL=1 or fail
if [[ ! -t 0 ]]; then
  echo "✗ Approval gate: non-interactive stdin and FORCE_APPROVAL is not set."
  echo "  Approval cannot be obtained automatically. Aborting."
  exit 1
fi

echo ""
echo "─────────────────────────────────────────────────────────"
echo " $PROMPT"
echo "─────────────────────────────────────────────────────────"
echo -n " Type 'yes' to confirm, anything else to abort: "
read -r REPLY

case "${REPLY,,}" in
  yes)
    echo " ✓ Approved by $(whoami) at $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    exit 0
    ;;
  *)
    echo " ✗ Not approved. Aborting."
    exit 1
    ;;
esac
