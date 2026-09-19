#!/usr/bin/env bash
# gates/approval.sh — prompt for explicit "yes" before continuing
#
# Used for production deploys and other irreversible actions. Exits 0 only on
# exact "yes" (case-insensitive).
#
# The gate prompts on the CONTROLLING TERMINAL (/dev/tty), not on stdin.
# That distinction is the whole point: a pipeline stage runs with stdin
# redirected while a human is still sitting at the terminal. Testing `-t 0`
# confuses "stdin is a pipe" with "nobody is there" and fails closed on the
# exact caller this gate exists to stop — see CHANGELOG 0.43.1.
#
# No controlling terminal at all (CI, a detached runner, a tool-driven shell)
# genuinely means no human can approve, so the gate fails closed unless
# FORCE_APPROVAL=1.
#
# Bypass with FORCE_APPROVAL=1 — only use in trusted automation (CI runner
# with its own approval step), never for interactive prod from a laptop.
#
# APPROVAL_TIMEOUT (seconds, default 120, integer) bounds the wait. A
# detached process can inherit a terminal nobody is watching; without a
# timeout that hangs a deploy indefinitely. Timing out ABORTS — the gate
# never approves by default. Set 0 to wait forever.
#
# Usage:
#   gates/approval.sh "Deploy v1.2.3 to production?"
#
# Portability: bash 3.2 (stock macOS). No ${var,,}, no mapfile, no readarray.
# `read -t` takes integer seconds only on 3.2 — do not pass a fraction.

set -euo pipefail

PROMPT="${1:-Proceed?}"

if [ "${FORCE_APPROVAL:-0}" = "1" ]; then
  echo "⚠️  FORCE_APPROVAL=1 — auto-approving: $PROMPT"
  exit 0
fi

# Validate before probing the terminal, so a bad value reports itself rather
# than hiding behind "no controlling terminal".
APPROVAL_TIMEOUT="${APPROVAL_TIMEOUT:-120}"
case "$APPROVAL_TIMEOUT" in
  ''|*[!0-9]*)
    echo "✗ Approval gate: APPROVAL_TIMEOUT must be a whole number of seconds." >&2
    exit 1
    ;;
esac

# Probe the controlling terminal in a way that cannot kill the script: a
# redirection failure on `:` fails that command only, unlike a failure on
# `exec`, which exits a non-interactive shell outright.
if ! { : < /dev/tty; } 2>/dev/null; then
  echo "✗ Approval gate: no controlling terminal and FORCE_APPROVAL is not set." >&2
  echo "  Approval cannot be obtained automatically. Aborting." >&2
  exit 1
fi

# Prompt on the terminal too — stdout may be captured by the caller.
{
  printf '\n'
  printf '─────────────────────────────────────────────────────────\n'
  printf ' %s\n' "$PROMPT"
  printf '─────────────────────────────────────────────────────────\n'
  printf " Type 'yes' to confirm, anything else to abort: "
} > /dev/tty

# A closed terminal or an expired timeout must abort, not approve — so a
# failed read leaves REPLY empty, which falls through to the deny arm.
REPLY=""
if [ "$APPROVAL_TIMEOUT" -eq 0 ]; then
  IFS= read -r REPLY < /dev/tty || REPLY=""
else
  IFS= read -r -t "$APPROVAL_TIMEOUT" REPLY < /dev/tty || REPLY=""
fi

# bash 3.2 has no ${REPLY,,}. Strip whitespace as well as lowercasing: some
# terminals deliver a trailing \r, and `IFS= read` (used so the value is not
# word-split) preserves the leading space of a fat-fingered " yes".
reply_lc=$(printf '%s' "$REPLY" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

case "$reply_lc" in
  yes)
    printf ' ✓ Approved by %s at %s\n' "$(whoami)" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    exit 0
    ;;
  *)
    printf ' ✗ Not approved. Aborting.\n'
    exit 1
    ;;
esac
