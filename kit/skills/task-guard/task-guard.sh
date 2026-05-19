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
# rejected. When an auditable change has no task, the hook creates
# a minimal stub and rides it (plus the ledger row) into the same
# commit, so the audit trail is never broken.

set -euo pipefail

# Git hook the on/off toggle installs.
GIT_HOOK="pre-commit"
HOOK_SUB="guard-commit"

usage() {
  cat <<'EOF'
task-guard.sh — enforce: every code/config change is task-linked.

USAGE:
  task-guard.sh on | off | status

  on        Install the pre-commit hook; scaffold tasks/ + the
            change ledger (tasks/CHANGES.md). Idempotent.
  off       Remove the pre-commit hook. Leaves tasks/ + the ledger.
  status    Report ON / OFF and the ledger entry count.

HOOK HANDLER (called by the hook — not for direct use):
  guard-commit   pre-commit: ensure staged code/config changes are
                 task-linked; auto-create a stub if not; append to
                 the change ledger. Always exits 0 — never blocks.

EXIT CODES:
  0  success
  1  operational error
  2  usage error
EOF
}

# ── helpers ──────────────────────────────────────────────────────
repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    echo "error: not inside a git repo" >&2
    return 1
  }
}

git_common_dir() {
  local d
  d="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  ( cd -P "$d" 2>/dev/null && pwd -P )
}

actor() {
  local a
  a="$(git config user.name 2>/dev/null || true)"
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

# ── next task id ─────────────────────────────────────────────────
# Highest TASK-NNN across tasks/, plus one, zero-padded to 3.
next_task_id() {
  local root max=0 n f
  root="$(repo_root)" || return 1
  while IFS= read -r f; do
    n="$(basename "$f")"
    n="${n#TASK-}"
    n="${n%%-*}"
    n="${n%.md}"
    case "$n" in ''|*[!0-9]*) continue ;; esac
    n=$((10#$n))
    [ "$n" -gt "$max" ] && max="$n"
  done < <(find "$root/tasks" -name 'TASK-*.md' 2>/dev/null)
  printf 'TASK-%03d' $((max + 1))
}

# slugify <string> — lowercase kebab-case, alnum only.
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' '-' \
    | sed 's/-\{2,\}/-/g; s/^-//; s/-$//'
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
# create_stub <task-id> <slug> <file>... — writes the stub, echoes
# its path.
create_stub() {
  local id="$1" slug="$2"; shift 2
  local root file path
  root="$(repo_root)"
  mkdir -p "$root/tasks/active"
  path="$root/tasks/active/${id}-auto-${slug}.md"
  {
    printf '# %s — auto-created: %s\n\n' "$id" "$slug"
    printf '> ⚠️ Auto-created by /task-guard at commit time. A code or\n'
    printf '> configuration change was committed with no active task.\n'
    printf '> This stub exists so the change keeps an audit trail.\n\n'
    printf '**Status.** STUB — not spec'"'"'d.\n\n'
    printf '**Why not spec'"'"'d.** The change was made directly — a quick\n'
    printf 'fix or hotfix — without filing a task first. /task-guard\n'
    printf 'created this retroactively so the change ledger stays\n'
    printf 'complete.\n\n'
    printf '**Created.** %s\n\n' "$(now_stamp)"
    printf '**Author.** %s\n\n' "$(actor)"
    printf '**Files touched in the triggering commit.**\n'
    for file in "$@"; do printf -- '- `%s`\n' "$file"; done
    printf '\n## Next step\n\n'
    printf 'Spec this retroactively with `/task` (Operation 3), or — if\n'
    printf 'the change genuinely needs no spec — close it with a one-line\n'
    printf 'note and move it to `tasks/done/`.\n'
  } > "$path"
  echo "$path"
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
  mkdir -p "$root/tasks/active"
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

  # Active tasks present?
  local active=() a
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    active+=("$(basename "$a" .md)")
  done < <(ls "$root"/tasks/active/*.md 2>/dev/null || true)

  local task_ref auto=0 note="—"
  if [ "${#active[@]}" -eq 0 ]; then
    # No active task — auto-create a stub and ride it in this commit.
    local id slug stub
    id="$(next_task_id)"
    slug="$(slugify "$(basename "${auditable[0]%.*}")")"
    [ -n "$slug" ] || slug="change"
    stub="$(create_stub "$id" "$slug" "${auditable[@]}")"
    git add -- "$stub" 2>/dev/null || true
    task_ref="$id"
    auto=1
    note="Stub — spec retroactively or close with a note."
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
