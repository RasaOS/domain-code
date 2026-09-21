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

VALID_KIND="mission auto-task auto-develop auto-test auto-phase auto-bug auto-hotfix manual"
VALID_OUTCOME="completed stopped-at-gate failed abandoned"

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    echo "error: not inside a git repo" >&2
    return 1
  }
}

# rasa_actor — the ONE actor-resolution order across the Element.
# See env-rules.md "RASA_ACTOR" and stamps.md "Stamp: run" -> actor.
rasa_actor() {
  local a="${RASA_ACTOR:-}"
  [ -n "$a" ] || a="$(git config user.name 2>/dev/null || true)"
  [ -n "$a" ] || a="$(whoami 2>/dev/null || true)"
  [ -n "$a" ] || a="${USER:-unknown}"
  printf '%s' "$a"
}

# An agent identifies itself by setting RASA_ACTOR. Absent that, a run is
# attributed to the human whose identity the clone carries.
actor_kind() {
  if [ -n "${RASA_ACTOR:-}" ]; then printf 'agent'; else printf 'human'; fi
}

ROOT="$(repo_root)" || exit 1
RUNS_DIR="$ROOT/tasks/runs"

ensure_dirs() { mkdir -p "$RUNS_DIR"; }

# Read one frontmatter key. Never reads the body.
field() {
  awk -v k="$2" '
    NR==1 && $0=="---" { fm=1; next }
    fm && $0=="---"    { exit }
    fm {
      if ($0 ~ "^"k"[[:space:]]*:") {
        sub("^"k"[[:space:]]*:[[:space:]]*", "")
        sub(/[[:space:]]+$/, "")
        print; exit
      }
    }
  ' "$1" 2>/dev/null
}

record_path() { printf '%s/%s.md' "$RUNS_DIR" "$1"; }

cmd_open() {
  local kind="$1" refs="${2:-}"
  case " $VALID_KIND " in
    *" $kind "*) ;;
    *) echo "error: kind must be one of: $VALID_KIND" >&2; return 2 ;;
  esac
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

  # NOTE: `$(cmd || echo unknown)` is wrong here and corrupts the record.
  # On a repo with no commits, `git rev-parse --abbrev-ref HEAD` PRINTS "HEAD"
  # and THEN exits non-zero, so the fallback appends rather than replaces and
  # the frontmatter gets a stray bare `unknown` line after `branch:`. Assign
  # first, then test the status.
  local sha branch
  if ! sha="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null)"; then sha="unknown"; fi
  if ! branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"; then branch="unknown"; fi
  [ -n "$sha" ] || sha="unknown"
  [ -n "$branch" ] || branch="unknown"

  {
    echo "---"
    echo "run_id: $id"
    echo "kind: $kind"
    echo "actor: $(rasa_actor)"
    echo "actor_kind: $(actor_kind)"
    echo "status: in-flight"
    echo "outcome: "
    echo "gate: "
    echo "task_refs: $refs"
    echo "started: $(date -u '+%Y-%m-%d %H:%M UTC')"
    echo "started_epoch: $(date -u '+%s')"
    echo "finished: "
    echo "duration_s: "
    echo "sha: $sha"
    echo "branch: $branch"
    echo "---"
    echo ""
    echo "# $id"
    echo ""
    echo "\`$kind\` run, opened by $(rasa_actor)."
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
  local f; f="$(record_path "$id")"
  [ -f "$f" ] || { echo "error: no run record $id" >&2; return 1; }

  local cur; cur="$(field "$f" status)"
  [ "$cur" = "in-flight" ] || {
    echo "error: $id is already '$cur' — a sealed record is not rewritten" >&2
    return 1
  }

  local started_epoch now dur status
  started_epoch="$(field "$f" started_epoch)"
  now="$(date -u '+%s')"
  if [ -n "$started_epoch" ]; then dur=$(( now - started_epoch )); else dur=""; fi
  case "$outcome" in
    completed) status="completed" ;;
    failed)    status="failed" ;;
    *)         status="stopped" ;;
  esac

  local tmp; tmp="$(mktemp)"
  awk -v st="$status" -v oc="$outcome" -v gt="$gate" \
      -v fin="$(date -u '+%Y-%m-%d %H:%M UTC')" -v dur="$dur" '
    NR==1 && $0=="---" { fm=1; print; next }
    fm && $0=="---"    { fm=0; print; next }
    fm && /^status:/     { print "status: " st; next }
    fm && /^outcome:/    { print "outcome: " oc; next }
    fm && /^gate:/       { print "gate: " gt; next }
    fm && /^finished:/   { print "finished: " fin; next }
    fm && /^duration_s:/ { print "duration_s: " dur; next }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"

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
