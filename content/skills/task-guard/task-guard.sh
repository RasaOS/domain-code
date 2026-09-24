#!/usr/bin/env bash
# task-guard.sh — enforce the change-audit rule: every code or
# configuration change is linked to a task.
#
# Owns the deterministic mechanics: installing/removing a git
# pre-commit hook, classifying staged files as auditable (code /
# runtime config) or not, auto-creating a stub task when an
# auditable change has no active task, and appending to the change
# ledger. SKILL.md routes the on/off/status choice; the rest runs
# unattended from the hook.
#
# The model is auto-create, never block: a commit is never
# rejected. When an auditable change has no task, the hook files one
# with .claude/bin/task (rasa.module.tasks v1.0.0) into tasks/triage/
# and rides it — plus its tasks/history.tsv line and the ledger row —
# into the same commit, so the audit trail is never broken.
#
# "Has a task" means, in order: the current-task pointer /task-enforce
# keeps; else a task in active/ or review/ (in flight — review/ is an
# open PR, and a fix-up commit on it belongs to it). A filed stub becomes
# the current task, so the next unlinked commit links to it instead of
# filing another.

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

# Git hook the on/off toggle installs.
GIT_HOOK="pre-commit"
HOOK_SUB="guard-commit"

usage() {
  cat <<'EOF'
task-guard.sh — enforce: every code/config change is task-linked.

USAGE:
  task-guard.sh on | off | status

  on        Install the pre-commit hook; start the change ledger
            (tasks/CHANGES.md). Idempotent.
  off       Remove the pre-commit hook. Leaves tasks/ + the ledger.
  status    Report ON / OFF and the ledger entry count.

HOOK HANDLER (called by the hook — not for direct use):
  guard-commit   pre-commit: ensure staged code/config changes are
                 task-linked; file a task (tasks/triage/) through
                 .claude/bin/task if not; append to the change ledger.
                 Always exits 0 — never blocks.

EXIT CODES:
  0  success
  1  operational error
  2  usage error
EOF
}

# ── helpers ──────────────────────────────────────────────────────
# The project this install serves — its ledgers and .claude/ live here.
# rasa_root (the shared library) walks up to the install's lockfile and
# never past the repository top; see its comment for the order.
repo_root() { rasa_root; }

git_common_dir() {
  local d
  d="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  ( cd -P "$d" 2>/dev/null && pwd -P )
}

# Same resolution order as rasa_actor() elsewhere in the Element — RASA_ACTOR
# first, so an agent harness can identify itself instead of inheriting whatever
# git identity the clone happens to carry. See stamps.md, "Stamp: run".
actor() {
  local a="${RASA_ACTOR:-}"
  [ -n "$a" ] || a="$(git config user.name 2>/dev/null || true)"
  [ -n "$a" ] || a="$(whoami 2>/dev/null || true)"
  [ -n "$a" ] || a="${USER:-unknown}"
  printf '%s' "$a"
}

now_stamp() { date '+%Y-%m-%d %H:%M'; }

self_path() {
  local root; root="$(repo_root)" || return 1
  if   [ -f "$root/.claude/skills/task-guard/task-guard.sh" ]; then
    echo "$root/.claude/skills/task-guard/task-guard.sh"
  elif [ -f "$root/kit/skills/task-guard/task-guard.sh" ]; then
    echo "$root/kit/skills/task-guard/task-guard.sh"
  else
    echo "error: task-guard.sh not found in expected locations" >&2
    return 1
  fi
}

ledger_path() { echo "$(repo_root)/tasks/CHANGES.md"; }

# ── auditable classification ─────────────────────────────────────
# is_auditable <repo-relative-path> — 0 if the path is a code or
# runtime-config change the change-audit rule applies to. Docs, the
# task system itself, and .claude/ meta are NOT auditable.
is_auditable() {
  local p="$1"
  case "$p" in
    tasks/*|docs/*|.claude/*) return 1 ;;
  esac
  case "$(basename "$p")" in
    *.md|LICENSE|.gitignore|.gitattributes|.editorconfig) return 1 ;;
  esac
  return 0
}

# ── change ledger ────────────────────────────────────────────────
ensure_ledger() {
  local ledger; ledger="$(ledger_path)"
  [ -f "$ledger" ] && return 0
  mkdir -p "$(dirname "$ledger")"
  cat > "$ledger" <<'EOF'
# Change ledger

Append-only audit of every code / configuration change and the
task it is linked to. Written by `/task-guard` at commit time —
do not hand-edit.

Each row rides in the same commit as the change it records, so the
exact commit is recoverable with `git blame`/`git log` on this
file. Newest entries at the bottom.
EOF
}

# ledger_append <task-ref> <auto:0|1> <note> <file>...
ledger_append() {
  local task_ref="$1" auto="$2" note="$3"; shift 3
  local ledger; ledger="$(ledger_path)"
  {
    printf '\n## %s — %s\n' "$(now_stamp)" "$task_ref"
    printf -- '- **Author.** %s\n' "$(actor)"
    if [ "$auto" = "1" ]; then
      printf -- '- **Task.** %s — auto-created (no active task at commit time)\n' "$task_ref"
    else
      printf -- '- **Task.** %s — linked to active work\n' "$task_ref"
    fi
    printf -- '- **Files.** %s\n' "$(printf '%s, ' "$@" | sed 's/, $//')"
    printf -- '- **Note.** %s\n' "$note"
  } >> "$ledger"
}

# ── stub task creation ───────────────────────────────────────────
ENFORCE_SH=".claude/skills/task-enforce/task-enforce.sh"

# actor_handle — actor() folded into the handle grammar bin/task accepts
# ([a-z0-9][a-z0-9._-]*, at most 32 characters).
actor_handle() {
  actor | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9._-]\{1,\}/-/g; s/^[^a-z0-9]\{1,\}//' | cut -c1-32
}

# create_stub <file>... — files a task for these paths through
# .claude/bin/task, marks it x-origin: auto-guard, and echoes
# "<id> <path>". Returns non-zero if the task driver is missing or refuses.
create_stub() {
  local root drv by out id path title note
  root="$(repo_root)" || return 1
  drv="$root/.claude/bin/task"
  [ -f "$drv" ] || return 1
  title="change to $(basename "$1")"
  note="auto-guard: $(printf '%s ' "$@" | cut -c1-160)"
  by="$(actor_handle)"
  if [ -n "$by" ]; then
    out="$(python3 "$drv" new --root "$root" --quiet --type change \
      --by "$by" --note "$note" "$title" </dev/null 2>/dev/null)" || return 1
  else
    out="$(python3 "$drv" new --root "$root" --quiet --type change \
      --note "$note" "$title" </dev/null 2>/dev/null)" || return 1
  fi
  id="$(printf '%s\n' "$out" | awk 'NR==1 { print $1 }')"
  path="$(printf '%s\n' "$out" | awk 'NR==2 { sub(/^[[:space:]]+/, ""); print }')"
  case "$id" in TASK-*) ;; *) return 1 ;; esac
  # x-origin + a re-recorded digest, through the one writer that does both.
  [ -f "$root/$ENFORCE_SH" ] \
    && bash "$root/$ENFORCE_SH" stamp "$id" x-origin auto-guard >/dev/null 2>&1 || true
  printf '%s %s\n' "$id" "$path"
}

# current_task — the /task-enforce pointer, if it names a task on disk.
current_task() {
  local root t
  root="$(repo_root)" || return 1
  [ -f "$root/$ENFORCE_SH" ] || return 1
  t="$(bash "$root/$ENFORCE_SH" current 2>/dev/null | tr -d '[:space:]')"
  case "$t" in TASK-*) printf '%s\n' "$t" ;; *) return 1 ;; esac
}

# ── git-hook shim install / remove (sentinel block) ──────────────
TG_OPEN="# >>> task-guard >>>"
TG_CLOSE="# <<< task-guard <<<"

_strip_block() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk -v o="$TG_OPEN" -v c="$TG_CLOSE" '
    index($0,o){skip=1}
    !skip{print}
    index($0,c){skip=0}
  ' "$file" > "$file.tg.tmp" && mv "$file.tg.tmp" "$file"
}

install_git_hook() {
  local hooks_dir file self block
  hooks_dir="$(git_common_dir)/hooks"
  mkdir -p "$hooks_dir"
  file="$hooks_dir/$GIT_HOOK"
  self="$(self_path)" || return 1
  block="$(printf '%s\n%s\n%s' \
    "$TG_OPEN" \
    "bash \"$self\" $HOOK_SUB || true" \
    "$TG_CLOSE")"

  if [ ! -f "$file" ]; then
    printf '#!/usr/bin/env bash\n%s\n' "$block" > "$file"
  elif grep -qF "$TG_OPEN" "$file"; then
    _strip_block "$file"
    printf '%s\n' "$block" >> "$file"
  else
    { head -n1 "$file"; printf '%s\n' "$block"; tail -n +2 "$file"; } \
      > "$file.tg.tmp" && mv "$file.tg.tmp" "$file"
  fi
  chmod +x "$file"
}

remove_git_hook() {
  local file; file="$(git_common_dir)/hooks/$GIT_HOOK"
  [ -f "$file" ] || return 0
  _strip_block "$file"
  # If only a shebang + blank lines remain, we created it — drop it.
  if ! grep -qvE '^[[:space:]]*(#!.*)?[[:space:]]*$' "$file"; then
    rm -f "$file"
  fi
}

git_hook_installed() {
  local file; file="$(git_common_dir)/hooks/$GIT_HOOK"
  [ -f "$file" ] && grep -qF "$TG_OPEN" "$file"
}

# ── on / off / status ────────────────────────────────────────────
cmd_on() {
  local root; root="$(repo_root)" || return 1
  install_git_hook || return 1
  ensure_ledger
  cat <<EOF

task-guard: ON
  Hook       $(git_common_dir)/hooks/$GIT_HOOK  →  $HOOK_SUB
  Rule       every staged code/config change must be task-linked;
             a stub is auto-created when there's no active task.
  Ledger     tasks/CHANGES.md  (append-only, rides in each commit)

Per-machine — run 'task-guard on' once per machine, per project.
Takes effect on the next commit.
EOF
}

cmd_off() {
  remove_git_hook
  echo ""
  echo "task-guard: OFF — pre-commit hook removed. tasks/ and the ledger left intact."
}

cmd_status() {
  local root ledger count="0"
  root="$(repo_root)" || return 1
  ledger="$(ledger_path)"
  [ -f "$ledger" ] && count="$(grep -c '^## ' "$ledger" 2>/dev/null || echo 0)"

  if git_hook_installed; then
    echo "task-guard: ON — pre-commit hook installed."
  else
    echo "task-guard: OFF — run 'task-guard on' to enforce the change-audit rule."
  fi
  echo "  ledger: tasks/CHANGES.md — ${count} change(s) recorded"
}

# ── guard-commit (pre-commit hook handler) ───────────────────────
cmd_guard_commit() {
  # Never break a commit. Any failure → exit 0.
  repo_root >/dev/null 2>&1 || exit 0
  local root; root="$(repo_root)"

  # Staged added/copied/modified files that are auditable.
  local auditable=() f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_auditable "$f" && auditable+=("$f")
  done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null || true)

  [ "${#auditable[@]}" -gt 0 ] || exit 0   # no code/config change

  # In-flight tasks present? active/ is being worked; review/ is an open
  # PR, and a fix-up commit on it belongs to it.
  local active=() a
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    active+=("$(basename "$a" .md)")
  done < <(ls "$root"/tasks/active/*.md "$root"/tasks/review/*.md 2>/dev/null || true)

  local task_ref auto=0 note="—" cur=""
  cur="$(current_task 2>/dev/null || true)"
  if [ -n "$cur" ]; then
    task_ref="$cur"
  elif [ "${#active[@]}" -eq 0 ]; then
    # No task in flight — file one and ride it in this commit.
    local made id stub
    if made="$(create_stub "${auditable[@]}")"; then
      id="${made%% *}"; stub="${made#* }"
      git add -- "$stub" "$root/tasks/history.tsv" 2>/dev/null || true
      [ -f "$root/$ENFORCE_SH" ] && bash "$root/$ENFORCE_SH" set "$id" >/dev/null 2>&1 || true
      task_ref="$id"
      auto=1
      note="Filed to tasks/triage/ — retitle it, then graduate or close it."
    else
      task_ref="unlinked"
      note="No task could be filed (.claude/bin/task missing or refused) — run .claude/bin/check-tasks."
    fi
  elif [ "${#active[@]}" -eq 1 ]; then
    task_ref="$(printf '%s' "${active[0]}" | cut -d- -f1,2)"
  else
    local refs="" t
    for t in "${active[@]}"; do
      refs="$refs$(printf '%s' "$t" | cut -d- -f1,2), "
    done
    task_ref="multiple active (${refs%, })"
  fi

  ensure_ledger
  ledger_append "$task_ref" "$auto" "$note" "${auditable[@]}"
  git add -- "$(ledger_path)" 2>/dev/null || true
  exit 0
}

# ── dispatch ─────────────────────────────────────────────────────
main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    -h|--help|help|"") usage; return 0 ;;
    on)            cmd_on ;;
    off)           cmd_off ;;
    status)        cmd_status ;;
    guard-commit)  cmd_guard_commit ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
