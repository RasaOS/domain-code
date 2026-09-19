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

VALID_STATUS="success failed in-flight"
VALID_INTENT="deploy release"

# ---------------------------------------------------------------- paths
project_root() {
  local d
  if d="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$d"
    return 0
  fi
  echo "error: not inside a git repo" >&2
  return 1
}

ROOT="$(project_root)" || exit 1
LEDGER_DIR="$ROOT/deploys"
RECORDS_DIR="$LEDGER_DIR/records"
INDEX="$LEDGER_DIR/DEPLOYS.md"

ensure_dirs() { mkdir -p "$RECORDS_DIR"; }

# Read one frontmatter field from a record. Line-oriented on purpose.
field() {
  local file="$1" key="$2"
  awk -v k="$key" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"   { exit }
    infm {
      i = index($0, ":")
      if (i > 0 && substr($0, 1, i-1) == k) {
        v = substr($0, i+1)
        sub(/^[ \t]+/, "", v)
        print v
        exit
      }
    }
  ' "$file"
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
  ensure_dirs

  local stamp base id n
  stamp="$(date -u '+%Y%m%d-%H%M%S')"
  base="DEP-${stamp}-${env_name}"
  id="$base"
  n=1
  # Reserve the ID itself with noclobber, not a slug-bearing filename:
  # two callers in the same second must not both succeed.
  while ! ( set -C; : > "$RECORDS_DIR/.$id.lock" ) 2>/dev/null; do
    n=$(( n + 1 ))
    id="${base}-${n}"
    [ "$n" -lt 100 ] || { echo "error: cannot allocate a deploy id" >&2; return 1; }
  done

  local sha branch
  sha="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"

  {
    echo "---"
    echo "id: $id"
    echo "kind: $intent"
    echo "environment: $env_name"
    echo "class: $klass"
    echo "tag: $tag"
    echo "sha: $sha"
    echo "branch: $branch"
    echo "user: $(whoami)"
    echo "host: $(hostname -s 2>/dev/null || echo unknown)"
    echo "started: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "finished: "
    echo "status: in-flight"
    echo "duration_s: "
    echo "error_stage: "
    echo "approval: ${approval:-none}"
    echo "task_refs: "
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
  local f="$RECORDS_DIR/$id.md"
  [ -f "$f" ] || { echo "error: no such deploy record: $id" >&2; return 1; }

  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/deploys.XXXXXX")"
  awk -v st="$status" -v dur="$duration" -v es="$error_stage" \
      -v fin="$(date -u '+%Y-%m-%d %H:%M:%S UTC')" '
    NR==1 && $0=="---" { infm=1; print; next }
    infm && $0=="---"  { infm=0; print; next }
    infm {
      if ($0 ~ /^status:/)      { print "status: " st;      next }
      if ($0 ~ /^duration_s:/)  { print "duration_s: " dur; next }
      if ($0 ~ /^error_stage:/) { print "error_stage: " es; next }
      if ($0 ~ /^finished:/)    { print "finished: " fin;   next }
    }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"

  rm -f "$RECORDS_DIR/.$id.lock"
  cmd_index >/dev/null
  printf '%s\n' "$id"
}

# --------------------------------------------------------------- index
cmd_index() {
  ensure_dirs
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/deploys.XXXXXX")"
  {
    echo "# Deploys"
    echo ""
    echo "<!-- GENERATED by .claude/skills/deploys/deploys.sh index — DO NOT HAND-EDIT."
    echo "     The files under deploys/records/ are the truth; this is a view. -->"
    echo ""
    echo "| When (UTC) | Kind | Environment | Class | Tag | Who | Status | Took | ID |"
    echo "|---|---|---|---|---|---|---|---|---|"
    local f
    for f in $(ls -1 "$RECORDS_DIR"/DEP-*.md 2>/dev/null | sort -r || true); do
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
    done
    echo ""
    echo "_Regenerate with \`.claude/skills/deploys/deploys.sh index\`._"
  } > "$tmp" && mv "$tmp" "$INDEX"
  echo "wrote $INDEX"
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
  for f in $(ls -1 "$RECORDS_DIR"/DEP-*.md 2>/dev/null | sort -r || true); do
    [ -f "$f" ] || continue
    local e; e="$(field "$f" environment)"
    [ -z "$filter_env" ] || [ "$e" = "$filter_env" ] || continue
    n=$(( n + 1 ))
    [ "$n" -le "$limit" ] || break
    printf '%-21s %-8s %-14s %-8s %s\n' \
      "$(field "$f" started)" "$(field "$f" kind)" "$e" \
      "$(field "$f" status)" "$(field "$f" tag)"
  done
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
  recorded="$(ls -1 "$RECORDS_DIR"/DEP-*.md 2>/dev/null | wc -l | tr -d ' ' || true)"
  recorded="${recorded:-0}"
  if [ ! -f "$INDEX" ]; then
    [ "$recorded" -eq 0 ] && { echo "no deploys yet"; return 0; }
    echo "✗ $recorded record(s) but no DEPLOYS.md — run: deploys.sh index" >&2
    return 3
  fi
  indexed="$(grep -c '^| .* | `DEP-' "$INDEX" 2>/dev/null | tr -d ' ' || true)"
  indexed="${indexed:-0}"
  if [ "$recorded" -ne "$indexed" ]; then
    echo "✗ ledger drift: $recorded record(s), $indexed row(s) in DEPLOYS.md" >&2
    echo "  run: .claude/skills/deploys/deploys.sh index" >&2
    return 3
  fi
  local stuck
  stuck="$(grep -l '^status: in-flight' "$RECORDS_DIR"/DEP-*.md 2>/dev/null | wc -l | tr -d ' ' || true)"
  if [ "${stuck:-0}" -gt 0 ]; then
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
