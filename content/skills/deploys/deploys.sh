#!/usr/bin/env bash
# deploys.sh — the ship log. Every deploy and release, what it was, where
# it went, and whether it worked.
#
# A deploy that left no record is a deploy you cannot answer questions
# about. Before v0.45.0 this Element had two half-ledgers that could not
# be joined: `build/deploy` appended a row to build/deploy-log.md but
# never tagged, and `/release` tagged but ran its own discovered deploy
# command and wrote nothing. So "what went to staging on the 14th, and
# who sent it" had no answer.
#
# SHAPE — records are the truth, the index is a derived view.
#
#   deploys/records/<id>.md     one file per execution, YAML frontmatter
#
# Ids are <KIND>-<timestamp>-<env>: DEP- for a deploy or release,
# ENV- for a config transfer written by env-sync.sh. One ledger, one
# reader — "what went out and where" is one question, not two.
#   deploys/DEPLOYS.md          regenerated from records; never hand-edited
#
# One file per execution means two concurrent branches touch different
# files. A single append-only markdown table conflicts on every PR the
# moment there is a second long-lived branch, and a ledger that conflicts
# on every PR gets deleted.
#
# IDs are timestamp-based (DEP-YYYYMMDD-HHMMSS-<env>) with a collision
# suffix, not a counter. A counter races: two worktrees both read "12",
# both write TASK-012-<different-slug>.md, and both succeed because the
# slugs differ. A timestamp plus suffix cannot collide that way.
#
# SECRETS NEVER ENTER A RECORD. Not values, not env-file contents, not
# command output that might contain either. A record holds WHAT shipped,
# WHERE, WHEN, and BY WHOM. Nothing that reads a secret writes here.
#
# Usage:
#   deploys.sh open <env> <class> <intent> <tag> [approval]  -> prints id
#   deploys.sh close <id> <status> <duration_s> [error_stage]
#   deploys.sh index                      regenerate DEPLOYS.md
#   deploys.sh list [--env E] [--limit N]
#   deploys.sh show <id>
#   deploys.sh check                      exit 3 if the index is stale
#
# Exit: 0 ok · 1 error · 2 usage · 3 drift
#
# Portability: bash 3.2 (stock macOS). No python3 required — the record
# format is line-oriented so grep/awk parse it.

set -euo pipefail

# The shared record library — rasa_root, the frontmatter reader and writer,
# rasa_actor. Found relative to this script (content/lib/domain-code/ in the
# Element, .claude/lib/domain-code/ in an install), never through the project
# root it exists to resolve.
_rfm="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
[ -f "$_rfm" ] || { echo "error: $(basename "$0"): .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; exit 70; }
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
rfm_require 1 || exit 70
rfm_trap_cleanup   # an interrupted write leaves no temp file beside a record

VALID_STATUS="success failed in-flight"
VALID_INTENT="deploy release"

# ---------------------------------------------------------------- paths
# The actor is the library's rasa_actor — the ONE resolution order across the
# Element (RASA_ACTOR, then git user.name, then the OS user; stamps.md,
# "Stamp: run"). It refuses an identity that carries a control character:
# before 0.54.0, RASA_ACTOR=$'bot\nstatus: success' made an in-flight deploy
# read as a success.

# The project this install serves — its ledgers and .claude/ live here.
# rasa_root (the shared library) walks up to the install's lockfile and
# never past the repository top; see its comment for the order.
project_root() { rasa_root; }

ROOT="$(project_root)" || exit 1
LEDGER_DIR="$ROOT/deploys"
RECORDS_DIR="$LEDGER_DIR/records"
INDEX="$LEDGER_DIR/DEPLOYS.md"

ensure_dirs() { mkdir -p "$RECORDS_DIR"; }

# Read one frontmatter field from a record; empty when absent or unreadable.
# The library's reader: a BOM, CRLF or a trailing space on a fence no longer
# hides a record's fields (before 0.54.0 such a record indexed as a blank row).
field() { rfm_get "$1" "$2" 2>/dev/null || true; }

# A record id names a file in records/, so it may not be a path.
valid_id() {
  case "$1" in
    ''|*/*|.*) echo "error: bad deploy id '$1'" >&2; return 2 ;;
  esac
}

usage() {
  sed -n '3,42p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------- open
# Calls cmd_index, defined below — bash resolves functions at call time.
cmd_open() {
  local env_name="$1" klass="$2" intent="$3" tag="$4" approval="${5:-}"
  case " $VALID_INTENT " in
    *" $intent "*) ;;
    *) echo "error: intent must be one of: $VALID_INTENT" >&2; return 2 ;;
  esac
  # Every value is checked, and the actor resolved, BEFORE the id is reserved.
  # The reservation is the record file itself and is never removed, so a
  # refusal after it would leave an empty record behind for good. The
  # environment is part of the id, and so of a file name.
  case "$env_name" in
    ''|*/*|.*) echo "error: bad environment name '$env_name'" >&2; return 2 ;;
  esac
  approval="${approval:-none}"
  rfm_check environment "$env_name" || return 2
  rfm_check class "$klass"          || return 2
  rfm_check tag "$tag"              || return 2
  rfm_check approval "$approval"    || return 2
  local who host
  who="$(rasa_actor)" || return 2
  host="$(hostname -s 2>/dev/null || true)"; [ -n "$host" ] || host=unknown
  rfm_check host "$host" || return 2

  # `rev-parse` prints to stdout AND exits non-zero in a commit-less repo, so
  # `$(cmd || echo unknown)` appends a second line and corrupts the record.
  # `--verify --quiet` prints nothing and exits 1 cleanly — same idiom bin/init
  # uses for ELEMENT_SHA (773d89b), kept identical on purpose so there is one
  # lesson here and not two.
  local sha branch
  sha="$(git -C "$ROOT" rev-parse --verify --quiet --short HEAD 2>/dev/null || true)"
  branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ -n "$sha" ] || sha="unknown"
  { [ -n "$branch" ] && [ "$branch" != "HEAD" ]; } || branch="unknown"
  rfm_check sha "$sha"       || return 2
  rfm_check branch "$branch" || return 2
  ensure_dirs

  local stamp base id n
  stamp="$(date -u '+%Y%m%d-%H%M%S')"
  base="DEP-${stamp}-${env_name}"
  id="$base"
  n=1
  # The RECORD FILE ITSELF is the reservation, claimed with noclobber.
  #
  # This used to reserve a separate `.$id.lock`, which `close` then
  # deleted — so a second open in the same second found no lock, reused
  # the id, and OVERWROTE the completed record. Measured: 8 back-to-back
  # deploys left 2 record files, and `check` still reported "consistent".
  # An audit trail that silently discards entries while claiming health is
  # worse than no audit trail.
  #
  # Reserving the .md means the name can never be reused, because the file
  # is never removed.
  while ! ( set -C; : > "$RECORDS_DIR/$id.md" ) 2>/dev/null; do
    n=$(( n + 1 ))
    id="${base}-${n}"
    [ "$n" -lt 1000 ] || { echo "error: cannot allocate a deploy id" >&2; return 1; }
  done

  # Same keys, same order, same bytes as before 0.54.0 — every value was
  # checked above, so no line below can be refused.
  {
    echo "---"
    rfm_line id "$id"
    rfm_line kind "$intent"
    rfm_line environment "$env_name"
    rfm_line class "$klass"
    rfm_line tag "$tag"
    rfm_line sha "$sha"
    rfm_line branch "$branch"
    rfm_line user "$who"
    rfm_line host "$host"
    rfm_line started "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    rfm_line finished ""
    rfm_line status in-flight
    rfm_line duration_s ""
    rfm_line error_stage ""
    rfm_line approval "$approval"
    rfm_line task_refs ""
    echo "---"
    echo ""
    echo "# $id"
    echo ""
    echo "\`$intent\` → **$env_name** (class: $klass) at tag \`$tag\`."
    echo ""
    echo "## Notes"
    echo ""
    echo "_(none)_"
  } > "$RECORDS_DIR/$id.md"

  # Index on open, not only on close: an in-flight deploy belongs in the
  # view (as `…`), and without this `check` reports false drift for the
  # entire duration of every run.
  cmd_index >/dev/null

  printf '%s\n' "$id"
}

# --------------------------------------------------------------- close
cmd_close() {
  local id="$1" status="$2" duration="${3:-}" error_stage="${4:-}"
  case " $VALID_STATUS " in
    *" $status "*) ;;
    *) echo "error: status must be one of: $VALID_STATUS" >&2; return 2 ;;
  esac
  valid_id "$id" || return 2
  case "$duration" in
    *[!0-9]*) echo "error: duration must be whole seconds, got '$duration'" >&2; return 2 ;;
  esac
  local f="$RECORDS_DIR/$id.md"
  [ -f "$f" ] || { echo "error: no such deploy record: $id" >&2; return 1; }

  # All four keys in one rename, through the library. Before 0.54.0 this was
  # an exact-fence awk: a record with a BOM or CRLF was never closed (it stayed
  # in-flight, rc 0), a trailing space on the fence rewrote body lines, and the
  # temp file in $TMPDIR left the record mode 0600. A refusal (no readable
  # frontmatter, a key that appears twice) now leaves the record byte-identical
  # and the library says why. error_stage is free text from a pipeline: it is
  # made one line, not refused.
  rfm_set "$f" status "$status" duration_s "$duration" \
    error_stage "$(rfm_clean "$error_stage")" \
    finished "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" || return 1

  cmd_index >/dev/null
  printf '%s\n' "$id"
}

# --------------------------------------------------------------- index
# The view is built in memory, then published with one same-directory rename
# that keeps the file's mode (it used to be a temp in $TMPDIR, moved across
# devices, which left DEPLOYS.md 0600).
cmd_index() {
  ensure_dirs
  local body
  body="$(index_body)" || return 1
  printf '%s\n' "$body" | rfm_write_atomic "$INDEX" || return 1
  echo "wrote $INDEX"
}

index_body() {
  {
    echo "# Deploys"
    echo ""
    echo "<!-- GENERATED by .claude/skills/deploys/deploys.sh index — DO NOT HAND-EDIT."
    echo "     The files under deploys/records/ are the truth; this is a view. -->"
    echo ""
    echo "| When (UTC) | Kind | Environment | Class | Tag | Who | Status | Took | ID |"
    echo "|---|---|---|---|---|---|---|---|---|"
    local f
    # `for f in $(ls …)` word-splits, so every ledger view was EMPTY in a
    # repo whose path contains a space — and `check` then reported drift it
    # could not fix. Process substitution (not a pipe) keeps the loop in
    # this shell so counters survive.
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      local mark dur
      case "$(field "$f" status)" in
        success)   mark="✓" ;;
        failed)    mark="✗" ;;
        in-flight) mark="…" ;;
        *)         mark="?" ;;
      esac
      dur="$(field "$f" duration_s)"
      [ -n "$dur" ] && dur="${dur}s"
      printf '| %s | %s | %s | %s | `%s` | %s | %s | %s | `%s` |\n' \
        "$(field "$f" started)" "$(field "$f" kind)" "$(field "$f" environment)" \
        "$(field "$f" class)" "$(field "$f" tag)" "$(field "$f" user)" \
        "$mark" "$dur" "$(field "$f" id)"
    done < <(ls -1 "$RECORDS_DIR"/???-*.md 2>/dev/null | sort -r || true)
    echo ""
    echo "_Regenerate with \`.claude/skills/deploys/deploys.sh index\`._"
  }
}

# ---------------------------------------------------------------- list
cmd_list() {
  local filter_env="" limit=20
  while [ $# -gt 0 ]; do
    case "$1" in
      --env)   filter_env="${2:-}"; shift 2 ;;
      --env=*) filter_env="${1#*=}"; shift ;;
      --limit) limit="${2:-20}"; shift 2 ;;
      --limit=*) limit="${1#*=}"; shift ;;
      *) echo "error: unknown list arg: $1" >&2; return 2 ;;
    esac
  done
  [ -d "$RECORDS_DIR" ] || { echo "(no deploys recorded yet)"; return 0; }

  local n=0 f
  printf '%-21s %-8s %-14s %-8s %s\n' "WHEN (UTC)" "KIND" "ENV" "STATUS" "TAG"
  # See the note in cmd_index: word-splitting broke this under any path
  # containing a space.
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    local e; e="$(field "$f" environment)"
    [ -z "$filter_env" ] || [ "$e" = "$filter_env" ] || continue
    n=$(( n + 1 ))
    [ "$n" -le "$limit" ] || break
    printf '%-21s %-8s %-14s %-8s %s\n' \
      "$(field "$f" started)" "$(field "$f" kind)" "$e" \
      "$(field "$f" status)" "$(field "$f" tag)"
  done < <(ls -1 "$RECORDS_DIR"/???-*.md 2>/dev/null | sort -r || true)
  [ "$n" -gt 0 ] || echo "(no matching deploys)"
}

# ---------------------------------------------------------------- show
cmd_show() {
  local f="$RECORDS_DIR/$1.md"
  [ -f "$f" ] || { echo "error: no such deploy record: $1" >&2; return 1; }
  cat "$f"
}

# --------------------------------------------------------------- check
# The index is derived, so it can go stale — someone hand-edits it, or a
# record lands from a merge without a regeneration. Exit 3 on drift so a
# pipeline or a pre-release check can catch it.
cmd_check() {
  [ -d "$RECORDS_DIR" ] || { echo "no ledger yet — nothing to check"; return 0; }
  local recorded indexed
  # `|| true` is load-bearing: with `set -o pipefail`, a grep/ls that
  # correctly finds nothing exits 1 and takes the whole script with it.
  recorded="$(ls -1 "$RECORDS_DIR"/???-*.md 2>/dev/null | wc -l | tr -d ' ' || true)"
  recorded="${recorded:-0}"
  if [ ! -f "$INDEX" ]; then
    [ "$recorded" -eq 0 ] && { echo "no deploys yet"; return 0; }
    echo "✗ $recorded record(s) but no DEPLOYS.md — run: deploys.sh index" >&2
    return 3
  fi
  indexed="$(grep -cE '^\| .* \| `[A-Z]{3}-' "$INDEX" 2>/dev/null | tr -d ' ' || true)"
  indexed="${indexed:-0}"
  if [ "$recorded" -ne "$indexed" ]; then
    echo "✗ ledger drift: $recorded record(s), $indexed row(s) in DEPLOYS.md" >&2
    echo "  run: .claude/skills/deploys/deploys.sh index" >&2
    return 3
  fi
  # Each record's own status field — a `grep '^status:'` over the files also
  # counted a matching line in a record's notes, and missed a CRLF record.
  local stuck=0 f
  while IFS= read -r f; do
    if [ "$(field "$f" status)" = in-flight ]; then stuck=$(( stuck + 1 )); fi
  done < <(ls -1 "$RECORDS_DIR"/???-*.md 2>/dev/null || true)
  if [ "$stuck" -gt 0 ]; then
    echo "⚠ $stuck deploy(s) still marked in-flight — a run died without closing." >&2
  fi
  echo "✓ ledger consistent: $recorded record(s)"
}

# ------------------------------------------------------------- dispatch
main() {
  local action="${1:-}"
  [ $# -gt 0 ] && shift
  case "$action" in
    open)
      [ $# -ge 4 ] || { echo "error: open needs <env> <class> <intent> <tag>" >&2; return 2; }
      cmd_open "$@" ;;
    close)
      [ $# -ge 2 ] || { echo "error: close needs <id> <status>" >&2; return 2; }
      cmd_close "$@" ;;
    index) cmd_index ;;
    list)  cmd_list "$@" ;;
    show)
      [ $# -ge 1 ] || { echo "error: show needs <id>" >&2; return 2; }
      cmd_show "$1" ;;
    check) cmd_check ;;
    -h|--help|help|"") usage ;;
    *) echo "error: unknown action: $action" >&2; usage >&2; return 2 ;;
  esac
}

main "$@"
