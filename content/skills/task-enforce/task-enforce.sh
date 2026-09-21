#!/usr/bin/env bash
# task-enforce.sh — no code change without a task. Enforced at CHANGE
# time, not commit time.
#
# WHY THIS AND NOT /task-guard
#
# /task-guard is a git pre-commit hook. It fires after N edits have
# already landed, and its own SKILL.md sells "never blocks a commit".
# That is a reconciler, not a gate. This is the gate: a PreToolUse hook
# on Edit|Write|MultiEdit|NotebookEdit that DENIES the tool call when the
# change is not linked to a task, mints the task, and lets the retry
# through.
#
# One deny per task, not per edit. The deny sets the current-task
# pointer, so the immediate retry succeeds and everything after it is
# linked. The cost of the audit trail is one interrupted tool call.
#
# CLASSIFICATION — three ways, not two
#
#   meta   .claude/**, tasks/**        recorded, mints no task
#   docs   docs/**, *.md, LICENSE, …   recorded, mints no task
#   code   everything else             mints a task
#
# `audit_anyway` overrides the exemptions and SHIPS NON-EMPTY. The
# exemption exists so touching a README is not a task; it does not exist
# so that .claude/environments.json — the file that decides what counts
# as production — can be edited untracked. An agent flipping
# "class": "prod" to "staging" there would let the next /deploy reach
# production through a gate working exactly as designed.
#
# Verbs:
#   task-enforce.sh on | off | status
#   task-enforce.sh guard                 (hook entry point; reads stdin)
#   task-enforce.sh current               print the linked task
#   task-enforce.sh set <TASK-NNN>        link work to an existing task
#   task-enforce.sh clear                 unlink (next code edit re-gates)
#   task-enforce.sh new "<title>"         mint a stub and link it
#   task-enforce.sh classify <path>       show how a path classifies
#
# Exit: 0 ok · 1 error · 2 usage · 3 refused
#
# Portability: bash 3.2 (stock macOS). python3 for JSON only.

set -euo pipefail

CONFIG_REL=".claude/task-enforcement.json"
CC_TARGET=".claude/settings.json"
CC_EVENT="PreToolUse"
CC_MATCHER="Edit|Write|MultiEdit|NotebookEdit"
CC_COMMAND="bash .claude/skills/task-enforce/task-enforce.sh guard"

repo_root() {
  local d
  if d="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$d"; return 0
  fi
  return 1
}

# Machine-local, keyed on the WORKTREE (not the common git dir): two
# worktrees are two pieces of work and must not share a task pointer.
# environment.sh deliberately does the opposite for the current env.
pointer_path() {
  local root="$1" key
  key="$(printf '%s' "$root" | shasum -a 256 2>/dev/null | cut -c1-12)"
  [ -n "$key" ] || key="default"
  printf '%s\n' "$HOME/.claude/projects/task-enforce-$key/current-task"
}

cfg_get() {
  # cfg_get <root> <dotted.key> [default]
  local root="$1" key="$2" dflt="${3:-}"
  local f="$root/$CONFIG_REL"
  [ -f "$f" ] || { printf '%s\n' "$dflt"; return 0; }
  python3 - "$f" "$key" "$dflt" <<'PY' 2>/dev/null || printf '%s\n' "$dflt"
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print(sys.argv[3]); raise SystemExit(0)
cur = d
for part in sys.argv[2].split('.'):
    if not isinstance(cur, dict) or part not in cur:
        print(sys.argv[3]); raise SystemExit(0)
    cur = cur[part]
if isinstance(cur, bool):
    print("true" if cur else "false")
elif isinstance(cur, list):
    print("\n".join(str(x) for x in cur))
else:
    print(cur)
PY
}

is_enabled() { [ "$(cfg_get "$1" enabled false)" = "true" ]; }

# ---------------------------------------------------------- classify
# Returns: code | docs | meta. Globs are matched with bash `case`, so a
# pattern like `build/environments/*/env.sh` works without extglob.
matches_any() {
  local path="$1"; shift
  local pat
  for pat in "$@"; do
    [ -n "$pat" ] || continue
    # shellcheck disable=SC2254
    case "$path" in $pat) return 0 ;; esac
    case "$pat" in
      */'**') case "$path" in "${pat%/**}"/*) return 0 ;; esac ;;
    esac
  done
  return 1
}

classify_path() {
  local root="$1" rel="$2"
  local anyway docs meta result="code"

  # `set -f` is load-bearing. The pattern lists are expanded unquoted so
  # the shell word-splits them, and WITHOUT noglob it also PATHNAME-expands
  # them against the cwd first: `*.md` becomes whatever .md files happen to
  # be sitting there, and `tasks/**` becomes the real subdirectories. Then
  # README.md classifies as `code` and every doc edit files a task. Found
  # by testing, not by reading.
  set -f
  anyway="$(cfg_get "$root" classify.audit_anyway '')"
  meta="$(cfg_get "$root" classify.exempt_meta '')"
  docs="$(cfg_get "$root" classify.exempt_docs '')"

  # audit_anyway wins over every exemption.
  # shellcheck disable=SC2086
  if [ -n "$anyway" ] && matches_any "$rel" $anyway; then
    result="code"
  # shellcheck disable=SC2086
  elif [ -n "$meta" ] && matches_any "$rel" $meta; then
    result="meta"
  # shellcheck disable=SC2086
  elif [ -n "$docs" ] && matches_any "$rel" $docs; then
    result="docs"
  fi
  set +f
  printf '%s\n' "$result"
}

# ------------------------------------------------------------ task id
# Reserve the ID with a real mutex. `set -C` on a filename does NOT work
# here: two sessions both compute TASK-012, write
# TASK-012-<different-slug>.md, and BOTH succeed because the paths
# differ. mkdir is atomic everywhere.
next_task_id() {
  local root="$1" lockdir="$root/tasks/.id.lock" n=0 id
  mkdir -p "$root/tasks" 2>/dev/null || true
  while ! mkdir "$lockdir" 2>/dev/null; do
    n=$(( n + 1 ))
    if [ "$n" -gt 50 ]; then
      # Stale lock from a killed process — 50 tries is ~5s.
      rm -rf "$lockdir" 2>/dev/null || true
    fi
    [ "$n" -lt 100 ] || return 1
    sleep 0.1 2>/dev/null || sleep 1
  done
  local max=0 f base num
  for f in $(find "$root/tasks" -name 'TASK-*.md' 2>/dev/null || true); do
    base="$(basename "$f")"
    num="$(printf '%s' "$base" | sed -n 's/^TASK-\([0-9][0-9]*\).*/\1/p')"
    [ -n "$num" ] || continue
    num="$(printf '%s' "$num" | sed 's/^0*//')"; [ -n "$num" ] || num=0
    [ "$num" -gt "$max" ] && max="$num"
  done
  id="$(printf 'TASK-%03d' "$(( max + 1 ))")"
  printf '%s\n' "$id"
  rmdir "$lockdir" 2>/dev/null || true
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//' | cut -c1-48
}

mint_stub() {
  # mint_stub <root> <title> <origin> [trigger-path]
  local root="$1" title="$2" origin="$3" trigger="${4:-}"
  local id slug dir file
  id="$(next_task_id "$root")" || return 1
  slug="$(slugify "$title")"; [ -n "$slug" ] || slug="untitled"
  dir="$root/tasks/backlog"
  mkdir -p "$dir"
  file="$dir/$id-$slug.md"
  {
    echo "---"
    echo "id: $id"
    echo "category: stub"
    echo "phase: null"
    echo "status: backlog"
    echo "owner: unassigned"
    echo "blocked_by:"
    echo "outcome: unrecorded"
    # One timestamp grammar across the Element: the hotfix template's
    # `YYYY-MM-DD HH:MM UTC` is canonical. This used to emit seconds too.
    echo "filed: $(date -u '+%Y-%m-%d %H:%M UTC')"
    echo "origin: $origin"
    echo "---"
    echo ""
    echo "# $id: $title"
    echo ""
    echo "> STATUS: STUB — light tracking only. No full spec is expected."
    if [ "$origin" = "auto-fallback" ]; then
      echo ">"
      echo "> **Filed automatically** because a code change was attempted with"
      echo "> no task linked. The title came from the file being edited, not"
      echo "> from anyone's intent — rewrite it to say what this work IS."
    fi
    echo ""
    echo "## What this is"
    echo ""
    if [ -n "$trigger" ]; then
      echo "Work touching \`$trigger\`."
    else
      echo "_(describe in one or two sentences)_"
    fi
    echo ""
    echo "## Files expected to change"
    echo ""
    [ -n "$trigger" ] && echo "- \`$trigger\`" || echo "- _(unknown)_"
    echo ""
    echo "## References"
    echo ""
    echo "_(deploy records, evidence, related tasks)_"
    echo ""
    echo "## Notes"
    echo ""
    echo "-"
  } > "$file"
  printf '%s\n' "$id"
}

# ------------------------------------------------------------- ledger
# Per-day-per-task files, regenerated into tasks/CHANGES.md. A single
# append-only file conflicts on every PR the moment there are two
# long-lived branches, and a ledger that conflicts on every PR gets
# deleted. Same discipline as deploys/.
ledger_row() {
  local root="$1" task="$2" rel="$3" klass="$4"
  local day dir f
  day="$(date -u '+%Y-%m-%d')"
  dir="$root/tasks/changes"; mkdir -p "$dir"
  f="$dir/$day-${task:-unlinked}.md"
  if [ ! -f "$f" ]; then
    { echo "# $day · ${task:-unlinked}"; echo ""
      echo "| Time (UTC) | Class | Path |"; echo "|---|---|---|"; } > "$f"
  fi
  printf '| %s | %s | `%s` |\n' "$(date -u '+%H:%M:%S')" "$klass" "$rel" >> "$f"
}

ledger_index() {
  local root="$1" out="$root/tasks/CHANGES.md" dir="$root/tasks/changes"
  [ -d "$dir" ] || return 0
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/changes.XXXXXX")"
  { echo "# Changes"; echo ""
    echo "<!-- GENERATED from tasks/changes/ — DO NOT HAND-EDIT. -->"; echo ""
    local f
    # `for f in $(ls …)` word-splits — empty index under any path with a
    # space. Process substitution, not a pipe, so this stays in-shell.
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      echo "## $(basename "$f" .md)"; echo ""
      sed -n '3,$p' "$f"; echo ""
    done < <(ls -1 "$dir"/*.md 2>/dev/null | sort -r || true)
  } > "$tmp" && mv "$tmp" "$out"
}

# ------------------------------------------------------------- pointer
get_current() {
  local p; p="$(pointer_path "$1")"
  [ -f "$p" ] || return 1
  local v; v="$(tr -d '[:space:]' < "$p")"
  [ -n "$v" ] || return 1
  printf '%s\n' "$v"
}

task_exists() {
  find "$1/tasks" -name "$2-*.md" 2>/dev/null | grep -q .
}

set_current() {
  local p; p="$(pointer_path "$1")"
  mkdir -p "$(dirname "$p")"
  printf '%s\n' "$2" > "$p"
}

# --------------------------------------------------------------- deny
emit_deny() {
  python3 - "$1" <<'PY'
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": sys.argv[1],
}}))
PY
}

# -------------------------------------------------------------- guard
cmd_guard() {
  local root; root="$(repo_root 2>/dev/null)" || exit 0
  is_enabled "$root" || exit 0

  local payload; payload="$(cat)"

  if ! command -v python3 >/dev/null 2>&1; then
    # Fail CLOSED. The contract is "no code change without an audit
    # trail"; allowing on a broken interpreter would quietly void it.
    emit_deny "Task enforcement is on but python3 is unavailable, so the guard cannot classify this change. Enforcement fails closed by design. Install python3, or run: bash .claude/skills/task-enforce/task-enforce.sh off"
    exit 0
  fi

  local rel; rel="$(python3 - "$root" "$payload" <<'PY' 2>/dev/null || true
import json, os, sys
root = os.path.realpath(sys.argv[1])
try:
    data = json.loads(sys.argv[2])
except Exception:
    raise SystemExit(0)
fp = (data.get("tool_input") or {}).get("file_path") or ""
if not fp:
    raise SystemExit(0)
ap = os.path.realpath(fp if os.path.isabs(fp) else os.path.join(root, fp))
if not ap.startswith(root + os.sep):
    raise SystemExit(0)          # outside the repo — not ours to police
print(os.path.relpath(ap, root))
PY
)"
  [ -n "$rel" ] || exit 0

  local klass; klass="$(classify_path "$root" "$rel")"

  local task=""
  task="$(get_current "$root" 2>/dev/null || true)"
  if [ -n "$task" ] && ! task_exists "$root" "$task"; then
    task=""      # pointer outlived its task file
  fi

  if [ "$klass" != "code" ]; then
    # Recorded, never gated. The trail stays complete without the
    # backlog filling up with README touches.
    ledger_row "$root" "$task" "$rel" "$klass"; ledger_index "$root"
    exit 0
  fi

  if [ -n "$task" ]; then
    ledger_row "$root" "$task" "$rel" code; ledger_index "$root"
    exit 0
  fi

  # Code change, nothing linked. Mint, link, deny once.
  local title id
  title="work on $(basename "$rel")"
  if id="$(mint_stub "$root" "$title" auto-fallback "$rel")"; then
    set_current "$root" "$id"
    ledger_row "$root" "$id" "$rel" code; ledger_index "$root"
    emit_deny "No task was linked to this change, so one was filed: ${id} (tasks/backlog/). It is now the current task — RETRY THIS EDIT and it will proceed, along with everything after it.

The title was derived from the filename, not from intent. Before continuing, open ${id} and write what this work actually is, plus the files you expect to change.

If this belongs to an existing task instead: bash .claude/skills/task-enforce/task-enforce.sh set TASK-NNN"
  else
    emit_deny "Task enforcement is on and a task could not be filed (could not allocate an id under tasks/). Fix the tasks/ directory or run: bash .claude/skills/task-enforce/task-enforce.sh off"
  fi
  exit 0
}

# -------------------------------------------------------------- verbs
cmd_on() {
  local root; root="$(repo_root)" || { echo "error: not in a git repo" >&2; return 1; }
  local cfg="$root/$CONFIG_REL"
  [ -f "$cfg" ] || { echo "error: $CONFIG_REL is missing — reinstall the Element or copy the seed template." >&2; return 1; }
  python3 - "$cfg" true <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["enabled"] = (sys.argv[2] == "true")
json.dump(d, open(sys.argv[1], "w"), indent=2); open(sys.argv[1], "a").write("\n")
PY
  local ih="$root/.claude/skills/install-hook/install-hook.sh"
  if [ -f "$ih" ]; then
    bash "$ih" add "$CC_EVENT" "$CC_MATCHER" "$CC_COMMAND" --target "$CC_TARGET" >/dev/null 2>&1 \
      || bash "$ih" add "$CC_EVENT" "$CC_MATCHER" "$CC_COMMAND" >/dev/null 2>&1 || true
  fi
  echo "✓ task enforcement ON"
  echo "  A code change with no linked task is denied once, a stub is filed,"
  echo "  and the retry proceeds. Docs and .claude/** are recorded, not gated"
  echo "  — except the paths in classify.audit_anyway."
  cmd_status
}

cmd_off() {
  local root; root="$(repo_root)" || return 1
  local cfg="$root/$CONFIG_REL"
  [ -f "$cfg" ] && python3 - "$cfg" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["enabled"] = False
json.dump(d, open(sys.argv[1], "w"), indent=2); open(sys.argv[1], "a").write("\n")
PY
  echo "✓ task enforcement OFF (the hook stays installed but allows everything)"
}

cmd_status() {
  local root; root="$(repo_root)" || return 1
  local state="off"; is_enabled "$root" && state="on"
  echo ""
  echo "  enforcement : $state"
  echo "  current task: $(get_current "$root" 2>/dev/null || echo '(none — next code edit files one)')"
  echo "  config      : $CONFIG_REL"
  local anyway; anyway="$(cfg_get "$root" classify.audit_anyway '')"
  if [ -n "$anyway" ]; then
    echo "  always audited (overrides exemptions):"
    printf '%s\n' "$anyway" | sed 's/^/    · /'
  fi
  # Both counters read FRONTMATTER, not the whole file. The old unanchored
  # `grep -l '^origin: auto-fallback'` also matched any task whose BODY quoted
  # that line at column 0 — which every task spec documenting this field does.
  local n_auto=0 n_unrec=0 f
  for f in $(find "$root/tasks" -name 'TASK-*.md' 2>/dev/null); do
    [ -f "$f" ] || continue
    [ "$(fm_field "$f" origin)" = "auto-fallback" ] && n_auto=$((n_auto + 1))
    case "$(fm_field "$f" outcome)" in
      ''|unrecorded) n_unrec=$((n_unrec + 1)) ;;
    esac
  done
  [ "$n_auto" -gt 0 ] && echo "  auto-filed stubs needing a real title: ${n_auto}"
  [ "$n_unrec" -gt 0 ] && echo "  tasks with no recorded outcome: ${n_unrec}"
  echo ""
}

# ---------- frontmatter read/write ----------
# Read one key from a file's FIRST frontmatter block. Empty if absent or if
# the file has no block. Never reads the body.
fm_field() {
  awk -v k="$2" '
    NR==1 && $0=="---" { fm=1; next }
    fm && $0=="---"    { exit }
    fm {
      if ($0 ~ "^"k"[[:space:]]*:") {
        sub("^"k"[[:space:]]*:[[:space:]]*", "")
        sub(/[[:space:]]+#.*$/, "")
        sub(/[[:space:]]+$/, "")
        print; exit
      }
    }
  ' "$1" 2>/dev/null
}

# The keys `stamp` may write. Restricted on purpose: nothing else validates
# task frontmatter, so a typo'd key would otherwise be written silently and
# read back as absent forever.
STAMPABLE="id category status phase owner blocked_by outcome filed origin severity"

# stamp <TASK-NNN> <key> <value> — a real UPSERT over a task's frontmatter.
#
# Rewrites the key if present, INSERTS it before the closing `---` if absent,
# and fails loudly when the file has no frontmatter block at all. That last
# case matters: contract.sh's fm_set — the Element's only other frontmatter
# writer — has no insert branch, so setting a missing key returns exit 0 with
# the file byte-identical. A field nothing can write does not exist.
cmd_stamp() {
  local id="$1" key="$2" val="$3" root file tmp
  root="$(repo_root)" || return 1

  case " $STAMPABLE " in
    *" $key "*) ;;
    *) echo "error: '$key' is not a stampable field" >&2
       echo "  allowed: $STAMPABLE" >&2
       return 2 ;;
  esac

  file="$(find "$root/tasks" -name "$id-*.md" 2>/dev/null | head -1)"
  [ -n "$file" ] || { echo "error: no task file for $id under tasks/" >&2; return 1; }

  head -1 "$file" | grep -q '^---$' || {
    echo "error: $file has no frontmatter block — refusing to stamp" >&2
    echo "  add a '---' block first; see stamps.md 'Stamp: task'" >&2
    return 1
  }

  tmp="$(mktemp)"
  awk -v k="$key" -v v="$val" '
    NR==1 && $0=="---" { fm=1; print; next }
    fm && $0=="---" {
      if (!seen) print k": "v          # insert before the closing fence
      fm=0; print; next
    }
    fm && $0 ~ "^"k"[[:space:]]*:" { print k": "v; seen=1; next }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"

  echo "$id: $key = $val"
}

main() {
  local action="${1:-}"; [ $# -gt 0 ] && shift
  case "$action" in
    guard)  cmd_guard ;;
    on)     cmd_on ;;
    off)    cmd_off ;;
    status) cmd_status ;;
    current) local r; r="$(repo_root)" || return 1; get_current "$r" || { echo "(none)"; return 0; } ;;
    set)
      [ $# -ge 1 ] || { echo "error: set needs TASK-NNN" >&2; return 2; }
      local r; r="$(repo_root)" || return 1
      task_exists "$r" "$1" || { echo "error: no task file for $1 under tasks/" >&2; return 1; }
      set_current "$r" "$1"; echo "current task → $1" ;;
    clear)
      local r; r="$(repo_root)" || return 1
      rm -f "$(pointer_path "$r")"; echo "current task cleared" ;;
    new)
      [ $# -ge 1 ] || { echo "error: new needs a title" >&2; return 2; }
      local r; r="$(repo_root)" || return 1
      local id; id="$(mint_stub "$r" "$1" manual)" || return 1
      set_current "$r" "$id"; echo "filed + linked: $id" ;;
    stamp)
      [ $# -ge 3 ] || { echo "error: stamp needs TASK-NNN <key> <value>" >&2; return 2; }
      cmd_stamp "$1" "$2" "$3" ;;
    classify)
      [ $# -ge 1 ] || { echo "error: classify needs a path" >&2; return 2; }
      local r; r="$(repo_root)" || return 1
      printf '%s\t%s\n' "$1" "$(classify_path "$r" "$1")" ;;
    -h|--help|help|"") sed -n '3,46p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "error: unknown action: $action" >&2; return 2 ;;
  esac
}

main "$@"
