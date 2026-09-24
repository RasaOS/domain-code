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
#   task-enforce.sh new "<title>"         file a task (triage/) and link it
#   task-enforce.sh stamp <id> <key> <v>  set an x- key (code-task-rules.md §7)
#   task-enforce.sh who                   the actor handle for bin/task --by
#   task-enforce.sh classify <path>       show how a path classifies
#
# Tasks are filed through .claude/bin/task (rasa.module.tasks v1.0.0), never
# written by hand: it allocates the id, writes tasks/history.tsv and records
# the task's digest in one act.
#
# Exit: 0 ok · 1 error · 2 usage · 3 refused
#
# Portability: bash 3.2 (stock macOS). python3 for JSON only.

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
rfm_trap_cleanup   # an interrupted write leaves no temp file beside a task

CONFIG_REL=".claude/task-enforcement.json"
CC_TARGET=".claude/settings.json"
CC_EVENT="PreToolUse"
CC_MATCHER="Edit|Write|MultiEdit|NotebookEdit"
CC_COMMAND="bash .claude/skills/task-enforce/task-enforce.sh guard"

# The project this install serves — its ledgers and .claude/ live here.
# rasa_root (the shared library) walks up to the install's lockfile and
# never past the repository top; see its comment for the order.
repo_root() { rasa_root; }

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
# Filing goes through .claude/bin/task. It allocates the id under an atomic
# lock AND creates the file inside that lock, so two sessions can never be
# handed one number — the window the mkdir-then-write allocator that used to
# live here left open, and the duplicate ids real ledgers carry came through.
# It also writes the tasks/history.tsv line and records the digest.

task_driver() { printf '%s\n' "$1/.claude/bin/task"; }

# actor_handle — RASA_ACTOR (stamps.md "Stamp: run"), else the git identity,
# folded into the handle grammar bin/task enforces ([a-z0-9][a-z0-9._-]*,
# at most 32). Empty when neither is set: bin/task then resolves it itself.
actor_handle() {
  local a="${RASA_ACTOR:-}"
  [ -n "$a" ] || a="$(git config user.name 2>/dev/null || true)"
  printf '%s' "$a" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9._-]\{1,\}/-/g; s/^[^a-z0-9]\{1,\}//' | cut -c1-32
}

# task_annotate <root> <file> <key> <value> [<note>]
# Upsert one frontmatter key and set `updated` to today — one rename, through
# the library — optionally put a note under the task's `# ` heading, then
# re-record the task's digest row: what a bin/task verb does after it writes.
# Without the re-digest, the validator would read this write as an unrecorded
# same-day edit (I-34) on its next run.
#
# Before 0.54.0 this was a Python rewrite that matched the fences exactly: a
# task with a BOM was refused as having no frontmatter, a CRLF task was
# rewritten with LF line endings throughout, a trailing space on the closing
# fence made it rewrite a BODY line, a key that appeared twice was rewritten
# at its first copy only, and the file was rewritten in place.
task_annotate() {
  local root="$1" file="$2" key="$3" value="$4" note="${5:-}" today tid
  today="$(date '+%Y-%m-%d')"
  if [ -n "$note" ]; then
    rfm_value_ok "$note" || [ $? -eq 3 ] || {
      echo "error: refusing a task note with a newline or control character" >&2
      return 2; }
  fi
  rfm_set "$file" "$key" "$value" updated "$today" || return $?
  if [ -n "$note" ]; then task_note "$file" "$note" || return 1; fi
  tid="$(rfm_get "$file" id 2>/dev/null || true)"
  case "$tid" in
    TASK-*) case "$tid" in *[!A-Za-z0-9.-]*) return 0 ;; esac ;;
    *) return 0 ;;
  esac
  task_digest "$root" "$file" "$tid" "$today"
}

# task_note <file> <text> — put <text> under the task's `# ` heading after a
# blank line, in the file's own line ending. A body edit, so it is not
# rfm_set's; it uses the library's awk preamble (the same fences rfm_set
# finds), a temp file beside the task that starts as a copy of it (the mode
# is kept), and one rename. awk stops at the heading and tail copies the rest
# byte for byte, as the library's writer does. No heading: nothing is written.
task_note() {
  local file="$1" dir tmp nrf k ro="" rc=0
  dir="$(dirname "$file")"
  tmp="$(mktemp "$dir/.rfm.XXXXXX")" || return 1
  RFM_TMP="$tmp"; nrf="$tmp.nr"
  [ "$(ls -ld "$file" | cut -c3)" = "-" ] && ro=1
  cp -p "$file" "$tmp" 2>/dev/null || true
  chmod u+w "$tmp" 2>/dev/null || true
  TE_NOTE="$2" TE_NRF="$nrf" LC_ALL=C awk "$RFM_AWK"'
    NR == 1 { fm = is_fence(line); print raw; next }
    fm && is_fence(line) { fm = 0; print raw; next }
    !fm && line ~ /^# / {
      print raw; printf "%s\n%s%s\n", cr, ENVIRON["TE_NOTE"], cr
      f = ENVIRON["TE_NRF"]; print NR > f; exit
    }
    { print raw }
  ' "$file" > "$tmp" || rc=$?
  k="$(cat "$nrf" 2>/dev/null || true)"
  rm -f "$nrf"
  case "$rc:$k" in
    0:) rm -f "$tmp"; RFM_TMP=""; return 0 ;;           # no heading
    0:*[!0-9]*) rc=1 ;;
    0:*) tail -n +"$((k + 1))" "$file" >> "$tmp" || rc=1 ;;
  esac
  if [ "$rc" -eq 0 ]; then
    [ -z "$ro" ] || chmod u-w "$tmp" 2>/dev/null || true
    if mv -f "$tmp" "$file"; then RFM_TMP=""; return 0; fi
  fi
  rm -f "$tmp"; RFM_TMP=""
  echo "error: could not add the note to $file — the note is not there" >&2
  return 1
}

# task_digest <root> <file> <id> <updated> — re-record the task's row in
# tasks/.state/digests.tsv, as bin/task's record_digest does. An unparseable
# ledger is left alone: check-tasks re-seeds it, and says so.
task_digest() {
  python3 - "$@" <<'PY'
import hashlib, os, sys
root, path, tid, updated = sys.argv[1:5]
digests = os.path.join(root, "tasks", ".state", "digests.tsv")
if not os.path.isfile(digests):
    sys.exit(0)
rows = {}
with open(digests, encoding="utf-8") as fh:
    for ln in fh.read().split("\n"):
        if not ln:
            continue
        f = ln.split("\t")
        if len(f) != 4:
            sys.exit(0)  # unparseable: check-tasks re-seeds it, and says so
        rows[f[0]] = f
with open(path, "rb") as fh:
    sha = hashlib.sha256(fh.read()).hexdigest()
rows[tid] = [tid, sha, updated, os.path.basename(os.path.dirname(path))]
tmp = digests + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    fh.write("".join("\t".join(r) + "\n" for _, r in sorted(rows.items())))
os.replace(tmp, digests)
PY
}

mint_stub() {
  # mint_stub <root> <title> <origin> [trigger-path]  → prints the new id
  local root="$1" title="$2" origin="$3" trigger="${4:-}"
  local drv by note out id file body="" shown=""
  drv="$(task_driver "$root")"
  [ -f "$drv" ] || return 1
  by="$(actor_handle)"
  # The trigger is a file path: one line before it goes into the history note
  # or the task body.
  [ -z "$trigger" ] || shown="$(rfm_clean "$trigger")"
  note="$origin"; [ -n "$shown" ] && note="$origin: $shown"
  if [ -n "$by" ]; then
    out="$(python3 "$drv" new --root "$root" --quiet --type change \
      --by "$by" --note "$note" "$title" </dev/null 2>/dev/null)" || return 1
  else
    out="$(python3 "$drv" new --root "$root" --quiet --type change \
      --note "$note" "$title" </dev/null 2>/dev/null)" || return 1
  fi
  id="$(printf '%s\n' "$out" | awk 'NR==1 { print $1 }')"
  file="$(printf '%s\n' "$out" | awk 'NR==2 { sub(/^[[:space:]]+/, ""); print }')"
  case "$id" in TASK-*) ;; *) return 1 ;; esac
  [ -f "$file" ] || return 1
  if [ "$origin" = "auto-fallback" ]; then
    body="> **Filed automatically** because a code change${shown:+ to \`$shown\`} was attempted with no task linked. The title came from the file being edited, not from anyone's intent — rewrite it to say what this work IS, then graduate it into a phase or close it."
  fi
  task_annotate "$root" "$file" x-origin "$origin" "$body" || return 1
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
  # The task names a file here, so it must be a plain id; and the path is
  # made one line — a newline in it used to append forged rows.
  case "$task" in ''|.*|*[!A-Za-z0-9._-]*) task="" ;; esac
  rel="$(rfm_clean "$rel")"
  day="$(date -u '+%Y-%m-%d')"
  dir="$root/tasks/changes"; mkdir -p "$dir"
  f="$dir/$day-${task:-unlinked}.md"
  if [ ! -f "$f" ]; then
    { echo "# $day · ${task:-unlinked}"; echo ""
      echo "| Time (UTC) | Class | Path |"; echo "|---|---|---|"; } > "$f"
  fi
  printf '| %s | %s | `%s` |\n' "$(date -u '+%H:%M:%S')" "$klass" "$rel" >> "$f"
}

# CHANGES.md is built in memory and published with one same-directory rename
# that keeps its mode (it used to be a temp in $TMPDIR, which left it 0600).
ledger_index() {
  local root="$1" out="$root/tasks/CHANGES.md" dir="$root/tasks/changes" body
  [ -d "$dir" ] || return 0
  body="$(ledger_index_body "$dir")" || return 1
  printf '%s\n' "$body" | rfm_write_atomic "$out"
}

ledger_index_body() {
  local dir="$1"
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
  }
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
  title="work on $(rfm_clean "$(basename "$rel")")"
  if id="$(mint_stub "$root" "$title" auto-fallback "$rel")"; then
    set_current "$root" "$id"
    ledger_row "$root" "$id" "$rel" code; ledger_index "$root"
    emit_deny "No task was linked to this change, so one was filed: ${id} (tasks/triage/). It is now the current task — RETRY THIS EDIT and it will proceed, along with everything after it.

The title was derived from the filename, not from intent. Before continuing, open ${id} and write what this work actually is, plus the files you expect to change.

If this belongs to an existing task instead: bash .claude/skills/task-enforce/task-enforce.sh set TASK-NNN"
  else
    emit_deny "Task enforcement is on and a task could not be filed: .claude/bin/task is missing or refused. Run .claude/bin/check-tasks to see why, re-run the Element's bin/init, or run: bash .claude/skills/task-enforce/task-enforce.sh off"
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
  # An auto-filed task still in triage/ is one nobody has looked at yet; an
  # outcome is only meaningful once a task has reached completed/.
  local n_auto=0 n_unrec=0 f
  for f in "$root"/tasks/triage/TASK-*.md; do
    [ -f "$f" ] || continue
    [ "$(fm_field "$f" x-origin)" = "auto-fallback" ] && n_auto=$((n_auto + 1))
  done
  for f in "$root"/tasks/completed/TASK-*.md; do
    [ -f "$f" ] || continue
    [ -n "$(fm_field "$f" x-outcome)" ] || n_unrec=$((n_unrec + 1))
  done
  [ "$n_auto" -gt 0 ] && echo "  auto-filed tasks in triage needing a real title: ${n_auto}"
  [ "$n_unrec" -gt 0 ] && echo "  completed tasks with no recorded outcome: ${n_unrec}"
  echo ""
}

# ---------- frontmatter read/write ----------
# Read one key from a file's frontmatter. Empty if absent or if the file has
# no readable block. Never reads the body. The library's scalar reader: it
# keeps this reader's convention (a trailing ` # comment` is dropped), finds
# the fences through a BOM, CRLF or a trailing blank, and — the one change —
# unquotes a quoted value as YAML does, where 0.53.1 kept the quotes.
fm_field() { rfm_get_scalar "$1" "$2" 2>/dev/null || true; }

# stamp <TASK-NNN> <key> <value> — set one of this domain's own keys.
#
# rasa.module.tasks v1.0.0 owns every bare frontmatter key and rejects any it
# does not know (I-11); the `x-` prefix is the one extension seam. So stamp
# writes only x- keys (code-task-rules.md §7) plus `priority`, checks each
# value, and refuses the keys the lifecycle owns with the command to use
# instead. The old names — origin, owner, outcome, severity — are accepted
# and written as their x- form, so a caller from before 0.53 still lands.
cmd_stamp() {
  local id="$1" key="$2" val="$3" root file allowed=""
  root="$(repo_root)" || return 1
  # The id becomes a find -name pattern: `*` used to stamp whichever task
  # file find listed first.
  case "$id" in
    TASK-*) case "$id" in *[!A-Za-z0-9.-]*) id="" ;; esac ;;
    *) id="" ;;
  esac
  [ -n "$id" ] || { echo "error: '$1' is not a task id (TASK-NNN)" >&2; return 2; }

  case "$key" in
    origin|owner|outcome|severity) key="x-$key" ;;
  esac
  case "$key" in
    x-origin)   allowed="manual auto-fallback auto-guard" ;;
    x-outcome)  allowed="shipped reverted" ;;
    x-severity) allowed="critical high medium low" ;;
    priority)   allowed="now high normal low" ;;
    x-owner)
      case "$val" in
        ''|*[!a-z0-9._-]*) echo "error: x-owner must be a handle ([a-z0-9._-])" >&2; return 2 ;;
      esac ;;
    status)
      echo "error: there is no status field — the directory is the state." >&2
      echo "  move it with .claude/bin/task (start, submit, pass, block, close, …)" >&2
      return 2 ;;
    phase)
      echo "error: phase is set by: .claude/bin/task graduate $id --phase <P>" >&2
      return 2 ;;
    id|type|created|created_by|updated|completed_by|resolution|resolution_ref|needs|target)
      echo "error: '$key' belongs to the task lifecycle — see .claude/task-rules.md §3" >&2
      return 2 ;;
    *)
      echo "error: '$key' is not a stampable field" >&2
      echo "  allowed: x-origin x-owner x-outcome x-severity priority" >&2
      return 2 ;;
  esac
  if [ -n "$allowed" ]; then
    case " $allowed " in
      *" $val "*) ;;
      *) echo "error: $key must be one of: $allowed" >&2; return 2 ;;
    esac
  fi

  file="$(find "$root/tasks" -path "$root/tasks/.state" -prune -o -name "$id-*.md" -print 2>/dev/null | head -1)"
  [ -n "$file" ] || { echo "error: no task file for $id under tasks/" >&2; return 1; }

  if [ "$key" = "priority" ] && [ "$val" = "now" ]; then
    case "$file" in
      */tasks/triage/*|*/tasks/backlog/*)
        echo "error: priority now is a route, not a label — a now task is being worked." >&2
        echo "  start it first: .claude/bin/task start $id  (task-rules.md §7, I-14)" >&2
        return 2 ;;
    esac
  fi

  task_annotate "$root" "$file" "$key" "$val" || return 1
  echo "$id: $key = $val"
}

# ---------- the spec-only fast-path gate ----------
#
# autonomy-rules.md Exception 2 lets /auto-task and /auto-phase merge spec-only
# PRs to main unattended, and rests its whole safety argument on one sentence:
# "The moment any non-allowlist file is in the change set, the fast-path is off
# — no exceptions."
#
# Nothing checked that. There was no script behind either skill, and no
# `git diff --name-only` anywhere near them, so the allowlist was prose applied
# by the same model that authored the change, moments before it merged to main.
# Every other gate in this Element is a program: class-guard.sh,
# tests-required.sh, approval.sh, git-clean.sh, and the PreToolUse deny above.
#
# Corroboration that prose is not enough: the allowlist itself was silently
# corrupted from v0.48.0 until v0.49.0 — a duplicated line that left it not
# parsing as a list — and nothing caught it, because nothing read it.
#
# NO BYPASS VARIABLE, by the class-guard precedent.

# The allowlist, defined ONCE. Prose cites this; this is what runs.
SPEC_ALLOW_GLOBS="tasks/*.md tasks/**/*.md tasks/history.tsv"

# spec_path_ok <path> — bash 3.2, no extglob, no globstar.
# Allowed: anything under tasks/ ending .md, at any depth — tasks/PHASES.md,
# tasks/ROADMAP.md, tasks/RELEASES.md and tasks/**/*.md — plus
# tasks/history.tsv, the transition log .claude/bin/task appends to on every
# filing and move. It is data, not code: without it, no spec-only change set
# that files or moves a task could ever pass. tasks/tasks.config.yml is NOT
# allowed — it declares the ledger's actors and targets, and a change to it
# is a decision, not a spec.
spec_path_ok() {
  case "$1" in
    tasks/history.tsv) return 0 ;;
    tasks/*.md) return 0 ;;
    tasks/*/*.md|tasks/*/*/*.md|tasks/*/*/*/*.md) return 0 ;;
    *) return 1 ;;
  esac
}

# cmd_spec_gate [--pr <N>]
#   no args  -> check the dirty working tree (pre-push)
#   --pr <N> -> check the PUSHED artifact via gh (pre-merge). This is the
#               load-bearing mode: local state at check time is not necessarily
#               what got pushed, and the merge acts on the PR, not the tree.
cmd_spec_gate() {
  local root paths="" mode="tree" pr=""
  root="$(repo_root)" || return 1

  if [ "${1:-}" = "--pr" ]; then
    mode="pr"; pr="${2:-}"
    [ -n "$pr" ] || { echo "error: --pr needs a number" >&2; return 2; }
    command -v gh >/dev/null 2>&1 || {
      echo "✗ spec-gate: gh is required to read PR $pr and is not available" >&2
      echo "  Refusing. 'cannot check' is not 'nothing to find'." >&2
      return 1
    }
    paths="$(gh pr view "${pr#\#}" --json files --jq '.files[].path' 2>/dev/null)" || {
      echo "✗ spec-gate: could not read the file list for PR $pr" >&2
      echo "  Refusing. An unreadable PR is never a pass." >&2
      return 1
    }
  else
    # -uall is load-bearing: plain --porcelain COLLAPSES an untracked
    # directory to "tasks/" instead of listing the files inside it, so a
    # genuinely spec-only change set in a fresh repo would be refused for
    # containing a path that is not *.md. Fails closed either way, but a gate
    # that cries wolf on correct input is the gate that gets removed.
    paths="$(git -C "$root" status --porcelain -uall | awk '{ $1=""; sub(/^ +/,""); print }')"
  fi

  if [ -z "$paths" ]; then
    echo "✗ spec-gate: empty change set — nothing to merge"
    return 1
  fi

  local bad="" n=0 p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$(( n + 1 ))
    spec_path_ok "$p" || bad="$bad  $p
"
  done <<EOF
$paths
EOF

  if [ -n "$bad" ]; then
    {
      echo "✗ spec-gate: REFUSED — the change set is not spec-only."
      echo ""
      echo "  These paths are outside the allowlist ($SPEC_ALLOW_GLOBS):"
      printf '%s' "$bad"
      echo "  The spec-file fast-path exists BECAUSE spec files do not execute."
      echo "  With any other file present the carve-out does not apply: leave the"
      echo "  work uncommitted and say in the autonomy report that the fast-path"
      echo "  was skipped, per autonomy-rules.md Exception 2."
      echo ""
      echo "  There is no flag or environment variable that skips this gate."
    } >&2
    return 1
  fi

  echo "✓ spec-gate: $n path(s), all spec-only (${mode}${pr:+ #$pr})"
  return 0
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
    spec-gate)
      cmd_spec_gate "$@" ;;
    stamp)
      [ $# -ge 3 ] || { echo "error: stamp needs TASK-NNN <key> <value>" >&2; return 2; }
      cmd_stamp "$1" "$2" "$3" ;;
    who)
      # For `.claude/bin/task <verb> --by "$(… who)"`: RASA_ACTOR folded into
      # the handle grammar bin/task enforces, so an agent:runner style value
      # does not fail its check. Prints `unknown` when nothing identifies
      # the actor — bin/task's own word for an unrecorded one.
      local h; h="$(actor_handle)"; printf '%s\n' "${h:-unknown}" ;;
    classify)
      [ $# -ge 1 ] || { echo "error: classify needs a path" >&2; return 2; }
      local r; r="$(repo_root)" || return 1
      printf '%s\t%s\n' "$1" "$(classify_path "$r" "$1")" ;;
    -h|--help|help|"") sed -n '3,46p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "error: unknown action: $action" >&2; return 2 ;;
  esac
}

main "$@"
