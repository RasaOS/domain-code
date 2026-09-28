#!/usr/bin/env bash
# land.sh — get a skill's outputs onto the trunk the way their class allows,
# always from the latest trunk. The program is land.py beside this file; this
# wrapper resolves the install, keeps the hook paths fast, and owns the
# argument contract.
#
# Two classes, decided by land.py and nowhere else:
#   docs  dated doc outputs (docs/audits/, docs/decisions/, … ) and the task
#         ledger (tasks/**/*.md, tasks/history.tsv). They land by themselves:
#         a land/ branch cut from the freshly fetched trunk, a PR, CI, a merge
#         pinned to the verified head, then the checkout is brought up to date.
#   code  everything else — including CLAUDE.md, anything it imports, .claude/
#         and .github/. It lands only through a PR the skill never merges.
#
# Usage:
#   land.sh classify <path>...          docs | code per path; exit 3 if any code
#   land.sh docs --skill S --title T [--summary X] [--tasks "IDS"] [--wait SECS] -- <path>...
#                                       land doc outputs by themselves
#   land.sh pr   --skill S --title T [--summary X] [--tasks "IDS"] [--draft]
#                [--verified X] [--risk X] [--branch B] [--message M] [--switch] -- <path>...
#                                       open (or update) a PR, synced with the
#                                       trunk. Never merges. On a branch: commits
#                                       there. On the trunk: builds the branch
#                                       aside, checkout untouched (--switch moves
#                                       the checkout onto it instead)
#   land.sh auto --skill S --title T [...] -- <path>...
#                                       split by class: docs land, code → pr
#   land.sh merge  --pr N --sha SHA [--pr-json FILE] [--checks-json FILE]... [--wait SECS]
#                                       finish a docs landing (verify, checks,
#                                       merge pinned to SHA, settle)
#   land.sh verify --pr N --sha SHA     the pushed-artifact gate, by git alone
#   land.sh settle --pr N | --branch B  after a merge made with other tooling
#   land.sh sync [--fetch-only] [--push]
#                                       bring the latest trunk into this checkout
#                                       (fast-forward on the trunk, merge on a
#                                       branch; never a rebase, never a force)
#   land.sh fresh --sha SHA [--pr N]    exit 0 if SHA contains the latest trunk
#   land.sh sync-pr --branch B          merge the trunk into a PR's branch, push
#   land.sh status                      guards, landings in flight, trunk rules
#   land.sh hooks                       install the guards (idempotent)
#   land.sh session | guard-bash | guard-edit | guard-mcp | guard-push
#                                       hook entry points (stdin: hook payload)
#
# Exit: 0 ok · 1 error · 2 usage · 3 refused (class, precondition, credential)
#       · 4 finish with the session's GitHub tooling (no gh; follow `next=`)
#       · 5 conflict with the trunk (nothing pushed, files untouched)
#       · 6 checks failing/pending or merge refused (the PR stays open)
#       · 7 the remote or environment refused the push
#
# Portability: bash 3.2 (stock macOS). python3 3.6+, git 2.20+; gh optional.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LAND_PY="$here/land.py"

usage() { sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'; }

deny_json() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$1"
}

verb="${1:-}"
case "$verb" in
  -h|--help|help|"") usage; exit 0 ;;

  guard-bash)
    # Every Bash call passes here: most leave before python starts. Quotes
    # and backslashes are dropped first, so g\it or gi''t cannot slip past.
    payload="$(cat)"
    norm="$(printf '%s' "$payload" | tr -d "\\\\\"'")"
    case "$norm" in
      *git*|*gh*|*GIT_GUARD*|*hooks*|*CLAUDECODE*|*GIT_CONFIG*|*pre-push*|*.git/*) ;;
      *) exit 0 ;;
    esac
    if ! command -v python3 >/dev/null 2>&1; then
      case "$norm" in
        *push*|*send-pack*) deny_json "python3 is missing, so this git push cannot be checked against the trunk guard. Refused." ;;
      esac
      exit 0
    fi
    printf '%s' "$payload" | python3 "$LAND_PY" guard-bash
    exit 0 ;;

  guard-edit)
    payload="$(cat)"
    case "$payload" in *.git*) ;; *) exit 0 ;; esac
    command -v python3 >/dev/null 2>&1 || { deny_json "python3 is missing, so a write under .git/ cannot be checked. Refused."; exit 0; }
    printf '%s' "$payload" | python3 "$LAND_PY" guard-edit
    exit 0 ;;

  guard-mcp)
    payload="$(cat)"
    command -v python3 >/dev/null 2>&1 || { deny_json "python3 is missing, so this GitHub write cannot be checked. Refused."; exit 0; }
    printf '%s' "$payload" | python3 "$LAND_PY" guard-mcp
    exit 0 ;;

  guard-push)
    shift
    if ! command -v python3 >/dev/null 2>&1; then
      [ "${CLAUDECODE:-}" = "1" ] || exit 0
      echo "land: python3 is missing, so this push cannot be checked against the trunk guard; refused" >&2
      exit 1
    fi
    exec python3 "$LAND_PY" guard-push "$@" ;;
esac

command -v python3 >/dev/null 2>&1 || { echo "land: python3 is required" >&2; exit 1; }

case "$verb" in
  classify)
    # Pure: it works outside an install too (no CLAUDE.md imports then).
    shift
    _rfm="$here/../../lib/domain-code/frontmatter.sh"
    root=""
    if [ -f "$_rfm" ]; then
      # shellcheck source=../../lib/domain-code/frontmatter.sh
      . "$_rfm"
      root="$(rasa_root 2>/dev/null || true)"
    fi
    LAND_ROOT="${root:-$PWD}" exec python3 "$LAND_PY" classify "$@" ;;
  docs|pr|auto|merge|verify|settle|sync|fresh|sync-pr|status|hooks|session) ;;
  *) echo "error: unknown verb: $verb" >&2; usage >&2; exit 2 ;;
esac

# The shared record library: rasa_root, to work from the install's root
# wherever this was called from.
_rfm="$(cd "$here/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
if [ ! -f "$_rfm" ]; then
  [ "$verb" = "session" ] && exit 0
  echo "error: land.sh: .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2
  exit 70
fi
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
if ! root="$(rasa_root 2>/dev/null)"; then
  [ "$verb" = "session" ] && exit 0
  echo "error: land.sh: not inside an installed project (set RASA_ROOT)" >&2
  exit 3
fi

if [ "$verb" = "session" ]; then
  # A session hook never fails the session.
  LAND_ROOT="$root" python3 "$LAND_PY" "$@" 2>&1 || true
  exit 0
fi
LAND_ROOT="$root" exec python3 "$LAND_PY" "$@"
