#!/usr/bin/env bash
# runs.sh — the run ledger. One record per episode of agent or human work.
#
# An autonomous run used to leave nothing behind. The autonomy report was
# RENDERED in chat and never written, so a run that died mid-way left no
# trace at all — and silently-dead runs are exactly the escape rate you need
# in order to ever loosen a gate. This is the durable half of that report.
#
# SHAPE — records are the truth (see stamps.md, "Stamp: run").
#
#   tasks/runs/<RUN-id>.md    one file per run, YAML frontmatter
#
# Ids are RUN-YYYYMMDD-HHMMSS, with a numeric suffix on collision. Timestamps
# rather than a counter: a counter races — two worktrees both read "12", both
# write a differently-slugged file, and both succeed.
#
# One file per run, not one append-only log: a single log conflicts on every
# PR the moment two long-lived branches exist, and a ledger that conflicts on
# every PR gets deleted. Same reasoning as deploys/records/ and
# tasks/changes/.
#
# OPENED BEFORE THE WORK, sealed after. A record written only at the end
# cannot represent a run that died, which is the one outcome most worth
# knowing about.
#
# Why tasks/runs/ and not a top-level runs/: task-enforcement exempts
# `tasks/**` while classify_path defaults to `code`, so a top-level runs/
# would have every write here DENIED in every consumer — and that config is
# skip-if-exists, so the fix would never reach an existing install. git-clean
# likewise excludes only deploys/, build/deploy-log.md and tasks/.
#
# Usage:
#   runs.sh open <kind> [task_refs]     -> prints the run id
#   runs.sh close <id> <outcome> [gate]
#   runs.sh list [--limit N] [--open]
#   runs.sh show <id>
#   runs.sh attempts <TASK-NNN>         -> count of runs touching that task
#
# Exit: 0 ok · 1 error · 2 usage
#
# Portability: bash 3.2 (stock macOS). No python3 required.

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

VALID_KIND="mission auto-task auto-develop auto-test auto-phase auto-bug auto-hotfix manual"
VALID_OUTCOME="completed stopped-at-gate failed abandoned"

# The project this install serves — its ledgers and .claude/ live here.
# rasa_root (the shared library) walks up to the install's lockfile and
# never past the repository top; see its comment for the order.
repo_root() { rasa_root; }

# The actor is the library's: rasa_actor, the ONE resolution order across the
# Element (env-rules.md "RASA_ACTOR", stamps.md "Stamp: run" -> actor), which
# refuses an identity carrying a control character; and rasa_actor_kind — an
# agent identifies itself by setting RASA_ACTOR, and absent that a run is
# attributed to the human whose identity the clone carries.

ROOT="$(repo_root)" || exit 1
RUNS_DIR="$ROOT/tasks/runs"

ensure_dirs() { mkdir -p "$RUNS_DIR"; }

# Read one frontmatter key. Never reads the body. Empty when absent. The
# library's reader: before 0.54.0 a CRLF record read as having no status, so
# `close` refused it as "already ''" and the run stayed in-flight for good.
field() { rfm_get "$1" "$2" 2>/dev/null || true; }

record_path() { printf '%s/%s.md' "$RUNS_DIR" "$1"; }

# A run id names a file in tasks/runs/, so it may not be a path.
valid_id() {
  case "$1" in
    ''|*/*|.*) echo "error: bad run id '$1'" >&2; return 2 ;;
  esac
}

cmd_open() {
  local kind="$1" refs="${2:-}"
  case " $VALID_KIND " in
    *" $kind "*) ;;
    *) echo "error: kind must be one of: $VALID_KIND" >&2; return 2 ;;
  esac
  # Every value is checked, and the actor resolved, BEFORE the id is reserved.
  # The reservation is the record file itself and is never removed, so a
  # refusal after it would leave an empty record behind for good. (Before
  # 0.54.0, RASA_ACTOR=$'bot\nstatus: completed' forged a sealed run.)
  local who wkind
  who="$(rasa_actor)" || return 2
  wkind="$(rasa_actor_kind)"
  rfm_check task_refs "$refs" || return 2

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
  base="RUN-${stamp}"
  id="$base"
  n=1
  # The RECORD FILE ITSELF is the reservation, claimed with noclobber. Same
  # lesson deploys.sh records: a separate lockfile that `close` deletes lets a
  # second open in the same second reuse the id and OVERWRITE a finished
  # record. Reserving the .md means the name can never be reused.
  while ! ( set -C; : > "$(record_path "$id")" ) 2>/dev/null; do
    n=$(( n + 1 ))
    id="${base}-${n}"
    [ "$n" -lt 1000 ] || { echo "error: cannot allocate a run id" >&2; return 1; }
  done

  # Same keys, same order, same bytes as before 0.54.0 — every value was
  # checked above, so no line below can be refused.
  {
    echo "---"
    rfm_line run_id "$id"
    rfm_line kind "$kind"
    rfm_line actor "$who"
    rfm_line actor_kind "$wkind"
    rfm_line status in-flight
    rfm_line outcome ""
    rfm_line gate ""
    rfm_line task_refs "$refs"
    rfm_line started "$(date -u '+%Y-%m-%d %H:%M UTC')"
    rfm_line started_epoch "$(date -u '+%s')"
    rfm_line finished ""
    rfm_line duration_s ""
    rfm_line sha "$sha"
    rfm_line branch "$branch"
    echo "---"
    echo ""
    echo "# $id"
    echo ""
    echo "\`$kind\` run, opened by $who."
    echo ""
    echo "## Autonomy report"
    echo ""
    echo "<!-- The rendered report goes here when the run closes. Decisions"
    echo "     made, hard gates hit, what's next. -->"
  } > "$(record_path "$id")"

  printf '%s\n' "$id"
}

cmd_close() {
  local id="$1" outcome="$2" gate="${3:-}"
  case " $VALID_OUTCOME " in
    *" $outcome "*) ;;
    *) echo "error: outcome must be one of: $VALID_OUTCOME" >&2; return 2 ;;
  esac
  valid_id "$id" || return 2
  local f; f="$(record_path "$id")"
  [ -f "$f" ] || { echo "error: no run record $id" >&2; return 1; }

  local cur; cur="$(field "$f" status)"
  [ "$cur" = "in-flight" ] || {
    echo "error: $id is already '$cur' — a sealed record is not rewritten" >&2
    return 1
  }

  # started_epoch is read from the file and must be digits before it meets
  # shell arithmetic, where a value like `a[$(cmd)]` would run the command.
  local started_epoch now dur status
  started_epoch="$(field "$f" started_epoch)"
  now="$(date -u '+%s')"
  case "$started_epoch" in
    ''|*[!0-9]*) dur="" ;;
    *)           dur=$(( now - started_epoch )) ;;
  esac
  case "$outcome" in
    completed) status="completed" ;;
    failed)    status="failed" ;;
    *)         status="stopped" ;;
  esac

  # All five keys in one rename, through the library: the record keeps its
  # mode, BOM and line endings (the old awk wrote a temp in $TMPDIR, which left
  # the record 0600), and a refusal leaves it byte-identical. The gate is free
  # text written by a person or an agent: made one line, never refused.
  rfm_set "$f" status "$status" outcome "$outcome" gate "$(rfm_clean "$gate")" \
    finished "$(date -u '+%Y-%m-%d %H:%M UTC')" duration_s "$dur" || return 1

  echo "$id: $outcome${dur:+ (${dur}s)}"
}

cmd_list() {
  local limit=20 only_open=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) limit="${2:-20}"; shift 2 ;;
      --open)  only_open=true; shift ;;
      *) shift ;;
    esac
  done
  [ -d "$RUNS_DIR" ] || { echo "(no runs yet)"; return 0; }
  local f n=0
  printf '%-26s %-12s %-16s %-14s %s\n' "RUN" "KIND" "ACTOR" "STATUS" "OUTCOME"
  for f in $(ls -r "$RUNS_DIR"/RUN-*.md 2>/dev/null); do
    [ -f "$f" ] || continue
    local st; st="$(field "$f" status)"
    if [ "$only_open" = true ] && [ "$st" != "in-flight" ]; then continue; fi
    printf '%-26s %-12s %-16s %-14s %s\n' \
      "$(field "$f" run_id)" "$(field "$f" kind)" "$(field "$f" actor)" \
      "$st" "$(field "$f" outcome)"
    n=$(( n + 1 ))
    [ "$n" -lt "$limit" ] || break
  done
  [ "$n" -gt 0 ] || echo "(none)"
}

cmd_show() {
  local f; f="$(record_path "$1")"
  [ -f "$f" ] || { echo "error: no run record $1" >&2; return 1; }
  cat "$f"
}

# attempts <TASK-NNN> — how many runs touched this task.
# Derived, never stored: a counter on the task would need a read-modify-write
# per run, and would be wrong for runs that never closed.
cmd_attempts() {
  local task="$1" f n=0
  [ -d "$RUNS_DIR" ] || { echo 0; return 0; }
  for f in "$RUNS_DIR"/RUN-*.md; do
    [ -f "$f" ] || continue
    case ",$(field "$f" task_refs | tr -d ' ')," in
      *",$task,"*) n=$(( n + 1 )) ;;
    esac
  done
  echo "$n"
}

main() {
  local action="${1:-}"; [ $# -gt 0 ] && shift
  case "$action" in
    open)
      [ $# -ge 1 ] || { echo "error: open needs <kind>" >&2; return 2; }
      cmd_open "$1" "${2:-}" ;;
    close)
      [ $# -ge 2 ] || { echo "error: close needs <id> <outcome>" >&2; return 2; }
      cmd_close "$1" "$2" "${3:-}" ;;
    list)     cmd_list "$@" ;;
    show)
      [ $# -ge 1 ] || { echo "error: show needs <id>" >&2; return 2; }
      cmd_show "$1" ;;
    attempts)
      [ $# -ge 1 ] || { echo "error: attempts needs <TASK-NNN>" >&2; return 2; }
      cmd_attempts "$1" ;;
    -h|--help|help|"") sed -n '3,42p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "error: unknown action: $action" >&2; return 2 ;;
  esac
}

main "$@"
