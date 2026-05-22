#!/usr/bin/env bash
# auto-save.sh — toggle and execute auto-save behavior.
#
# auto-save is a session-lifecycle pattern built on top of /save:
#   - SessionStart hook injects context so the AI knows to perform
#     periodic in-session merges via /save --mode replace.
#   - PreCompact hook archives the current SAVED.md before context
#     compaction (otherwise the AI loses the thread and a merge
#     can't be done).
#   - SessionEnd hook archives the current SAVED.md when the session
#     terminates (the standard archive-style save we'd do manually).
#
# This script handles:
#   - on/off: installing/removing the three hooks via install-hook.sh
#   - status: reporting whether the hooks are installed
#   - archive: what the PreCompact and SessionEnd hooks call
#   - context: what the SessionStart hook calls (emits JSON to
#     stdout that Claude Code passes as additionalContext to the AI)

set -euo pipefail

# Hooks the on/off toggle installs.
# Format: "<Event>|<command>"
declare -a AUTO_SAVE_HOOKS=(
  "SessionStart|bash .claude/skills/auto-save/auto-save.sh context"
  "PreCompact|bash .claude/skills/auto-save/auto-save.sh archive"
  "SessionEnd|bash .claude/skills/auto-save/auto-save.sh archive"
)

# Default cadence guidance for the in-session merge. The AI uses
# judgment; this is the suggested rhythm baked into the SessionStart
# context. Change here to evolve the policy as we learn.
AUTO_SAVE_CADENCE_GUIDANCE="every 5–8 user prompts, OR at any clear thread shift (whichever comes first)"

# Default target for hook installation — per-user (gitignored).
AUTO_SAVE_TARGET=".claude/settings.local.json"

usage() {
  cat <<'EOF'
auto-save.sh — toggle and execute the auto-save pattern.

USAGE:
  auto-save.sh on
      Install SessionStart + PreCompact + SessionEnd hooks into
      .claude/settings.local.json. After installation, the next
      session will see auto-save active.

  auto-save.sh off
      Remove the three hooks.

  auto-save.sh status
      Report whether the hooks are installed.

  auto-save.sh archive
      Archive the current SAVED.md (delegates to save.sh archive).
      Called automatically by the PreCompact and SessionEnd hooks.
      No-op if SAVED.md is empty.

  auto-save.sh context
      Emit JSON to stdout for the SessionStart hook — injects
      "auto-save is active" instruction into the AI's context.
      Called automatically.

EXIT CODES:
  0  success
  1  operational error
  2  usage error
EOF
}

# Resolve worktree root.
project_root() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "error: not inside a git repo" >&2
    return 1
  }
  ( cd -P "$top" 2>/dev/null && pwd -P )
}

# Resolve the install-hook.sh path within the same skills tree.
install_hook_script() {
  local root
  root="$(project_root)" || return 1
  # In a synced project: .claude/skills/install-hook/install-hook.sh
  # In the kit repo: kit/skills/install-hook/install-hook.sh
  if [ -f "$root/.claude/skills/install-hook/install-hook.sh" ]; then
    echo "$root/.claude/skills/install-hook/install-hook.sh"
  elif [ -f "$root/kit/skills/install-hook/install-hook.sh" ]; then
    echo "$root/kit/skills/install-hook/install-hook.sh"
  else
    echo "error: install-hook.sh not found in expected locations" >&2
    return 1
  fi
}

# Resolve the save.sh path within the same skills tree.
save_script() {
  local root
  root="$(project_root)" || return 1
  if [ -f "$root/.claude/skills/save/save.sh" ]; then
    echo "$root/.claude/skills/save/save.sh"
  elif [ -f "$root/kit/skills/save/save.sh" ]; then
    echo "$root/kit/skills/save/save.sh"
  else
    echo "error: save.sh not found in expected locations" >&2
    return 1
  fi
}

cmd_on() {
  local install_hook
  install_hook="$(install_hook_script)" || return 1

  local entry event command
  for entry in "${AUTO_SAVE_HOOKS[@]}"; do
    event="${entry%%|*}"
    command="${entry#*|}"
    bash "$install_hook" add "$event" "$command" --target "$AUTO_SAVE_TARGET"
  done

  echo ""
  echo "auto-save: ON"
  echo "  - SessionStart  → injects auto-save context for the AI"
  echo "  - PreCompact    → archives SAVED.md before context compaction"
  echo "  - SessionEnd    → archives SAVED.md at session termination"
  echo ""
  echo "Hooks live in $AUTO_SAVE_TARGET (per-user, gitignored)."
  echo "Toggle off with: bash <skill-dir>/auto-save.sh off"
}

cmd_off() {
  local install_hook
  install_hook="$(install_hook_script)" || return 1

  local entry event command
  for entry in "${AUTO_SAVE_HOOKS[@]}"; do
    event="${entry%%|*}"
    command="${entry#*|}"
    bash "$install_hook" remove "$event" "$command" --target "$AUTO_SAVE_TARGET"
  done

  echo ""
  echo "auto-save: OFF"
}

cmd_status() {
  local install_hook root target
  install_hook="$(install_hook_script)" || return 1
  root="$(project_root)" || return 1
  target="$root/$AUTO_SAVE_TARGET"

  if [ ! -f "$target" ]; then
    echo "auto-save: OFF (no $AUTO_SAVE_TARGET)"
    return 0
  fi

  # Count how many of our hooks are present.
  local count=0 expected=${#AUTO_SAVE_HOOKS[@]} entry event command
  for entry in "${AUTO_SAVE_HOOKS[@]}"; do
    event="${entry%%|*}"
    command="${entry#*|}"
    if grep -F -q "$command" "$target" 2>/dev/null; then
      count=$(( count + 1 ))
    fi
  done

  if [ "$count" -eq "$expected" ]; then
    echo "auto-save: ON ($count/$expected hooks installed)"
  elif [ "$count" -eq 0 ]; then
    echo "auto-save: OFF (0/$expected hooks installed)"
  else
    echo "auto-save: PARTIAL ($count/$expected hooks installed) — run 'auto-save on' to fully install"
    return 0
  fi
}

cmd_archive() {
  # Called by PreCompact and SessionEnd hooks. Delegates to save.sh.
  # Silent by design — PreCompact/SessionEnd fire regardless of save
  # state, and "refused: nothing to archive" is the expected no-op
  # when SAVED.md is empty/missing. Stderr is discarded so the hook
  # doesn't pollute the user's terminal / harness log with noise.
  # If save.sh has a real failure, the user notices at next /save
  # rather than here — acceptable tradeoff for hook quietude.
  local save
  save="$(save_script)" || return 0
  bash "$save" archive >/dev/null 2>&1 || true
}

cmd_context() {
  # Called by SessionStart hook. Emits JSON with additionalContext
  # that gets injected into the AI's session-start context. The AI
  # reads this and knows to perform periodic in-session merges.
  #
  # Schema based on Claude Code's documented hook output format.
  # If the schema differs, this is the single place to fix.
  python3 - <<PY
import json
cadence = """${AUTO_SAVE_CADENCE_GUIDANCE}"""
context = (
    "📌 **Auto-save mode is ACTIVE for this session.**\n\n"
    "## Your auto-save responsibilities\n\n"
    "1. **Periodic in-session merges.** ${AUTO_SAVE_CADENCE_GUIDANCE}, "
    "invoke /save with --mode replace. The content should be a "
    "merged update of the current SAVED.md plus this session's "
    "activity (NOT a fresh-write).\n\n"
    "2. **Merge rules per section:**\n"
    "   - \`✅ What we did\` — accumulate (keep existing bullets, add new)\n"
    "   - \`🧠 What we worked out\` — accumulate\n"
    "   - \`🚧 What's open\` — replace with current state (closed items drop off)\n"
    "   - \`🧪 Threads not yet pulled\` — accumulate\n"
    "   - \`📎 References\` — accumulate, dedupe\n"
    "   - \`> **When.**\` — update to current time\n"
    "   - \`> **Branch.**\` — auto-injected by save.sh\n\n"
    "3. **Tell the user.** When you auto-save mid-response, include a "
    "terse single-line note at the bottom of your reply: "
    "*— auto-saved at <HH:MM> —*. Silent saves feel magical in a bad way.\n\n"
    "4. **PreCompact and SessionEnd are handled by hooks** — you don't "
    "need to worry about archiving on those events. The hooks call "
    "save.sh archive automatically. Your job is the in-session merges.\n\n"
    "5. **Turn auto-save off** with: bash .claude/skills/auto-save/auto-save.sh off\n"
)
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context}}))
PY
}

main() {
  local action="${1:-}"
  shift || true

  case "$action" in
    -h|--help|help|"") usage; return 0 ;;
    on)      cmd_on ;;
    off)     cmd_off ;;
    status)  cmd_status ;;
    archive) cmd_archive ;;
    context) cmd_context ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
