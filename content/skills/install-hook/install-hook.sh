#!/usr/bin/env bash
# install-hook.sh — install / remove / list Claude Code hooks in a
# settings.json file. Reusable foundation for any skill that needs
# to configure hooks (auto-save being the first user).
#
# Language note: this script uses python3 for JSON manipulation per
# script-craft.md's policy — JSON-by-bash is genuinely clumsy and
# error-prone. python3 is universally available on macOS + Linux.

set -euo pipefail

usage() {
  cat <<'EOF'
install-hook.sh — add / remove / list Claude Code hooks.

USAGE:
  install-hook.sh add <Event> <command> [--target <file>] [--matcher <pattern>]
      Add a hook entry. If the target file or hooks structure doesn't
      exist, the script creates them. Idempotent — adding the same
      Event+command twice is a no-op.

  install-hook.sh remove <Event> <command> [--target <file>]
      Remove a hook entry matching Event+command. No-op if not present.

  install-hook.sh list [--target <file>]
      Print the hooks block from the target file.

  install-hook.sh help

TARGETS:
  Default: .claude/settings.local.json (per-user, gitignored)
  Other useful values:
    .claude/settings.json           project-shared, committed
    ~/.claude/settings.json         user-global, all projects

EVENTS (Claude Code hook event names):
  PreToolUse, PostToolUse, UserPromptSubmit,
  SessionStart, SessionEnd, Stop, PreCompact, Notification

HOOK ENTRY SCHEMA (what gets written):
  {
    "hooks": {
      "<Event>": [
        { "matcher": "<pattern>",
          "hooks": [{"type": "command", "command": "<cmd>"}] }
      ]
    }
  }

  Matcher is "" by default (matches everything — appropriate for
  session-lifecycle events like SessionStart). For PreToolUse /
  PostToolUse hooks, set a pattern via --matcher.

EXIT CODES:
  0  success
  1  operational error (no python3, not in a git repo, bad target path)
  2  usage error
EOF
}

# Resolve worktree root (where .claude/ lives for default targets).
project_root() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "error: not inside a git repo" >&2
    return 1
  }
  ( cd -P "$top" 2>/dev/null && pwd -P )
}

# Resolve --target to an absolute path. Handles tilde expansion and
# project-relative shortcuts.
resolve_target() {
  local target="$1"
  case "$target" in
    /*)
      echo "$target"
      ;;
    \~/*)
      echo "$HOME/${target#\~/}"
      ;;
    *)
      # Relative — resolve from worktree root.
      local root
      root="$(project_root)" || return 1
      echo "$root/$target"
      ;;
  esac
}

# Ensure python3 is available; fail clearly if not.
require_python3() {
  command -v python3 >/dev/null 2>&1 || {
    echo "error: install-hook.sh requires python3 (for JSON manipulation)" >&2
    return 1
  }
}

# Ensure target file exists with at least { } — create if missing.
ensure_target_exists() {
  local target="$1"
  if [ -f "$target" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  echo '{}' > "$target"
}

cmd_add() {
  local event="$1" command="$2"
  local target="${3:-.claude/settings.local.json}"
  local matcher="${4:-}"

  local target_abs
  target_abs="$(resolve_target "$target")" || return 1
  ensure_target_exists "$target_abs"

  python3 - "$target_abs" "$event" "$command" "$matcher" <<'PY'
import json, sys
target, event, command, matcher = sys.argv[1:5]

with open(target) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        print(f"error: target file is not valid JSON: {target}", file=sys.stderr)
        sys.exit(1)

hooks = data.setdefault("hooks", {})
event_list = hooks.setdefault(event, [])

# Idempotency: check whether a matcher-group with this command already exists.
for group in event_list:
    if group.get("matcher", "") != matcher:
        continue
    inner = group.setdefault("hooks", [])
    if any(h.get("type") == "command" and h.get("command") == command for h in inner):
        print(f"already installed: {event} -> {command}")
        sys.exit(0)
    # Same matcher, new command — append to inner list.
    inner.append({"type": "command", "command": command})
    break
else:
    # No matching group — create a new one.
    event_list.append({
        "matcher": matcher,
        "hooks": [{"type": "command", "command": command}],
    })

with open(target, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"installed: {event} -> {command}")
PY
}

cmd_remove() {
  local event="$1" command="$2"
  local target="${3:-.claude/settings.local.json}"

  local target_abs
  target_abs="$(resolve_target "$target")" || return 1
  if [ ! -f "$target_abs" ]; then
    echo "target file doesn't exist: $target_abs" >&2
    return 0
  fi

  python3 - "$target_abs" "$event" "$command" <<'PY'
import json, sys
target, event, command = sys.argv[1:4]

with open(target) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        print(f"error: target file is not valid JSON: {target}", file=sys.stderr)
        sys.exit(1)

hooks = data.get("hooks", {})
event_list = hooks.get(event, [])

removed_count = 0
new_event_list = []
for group in event_list:
    inner = group.get("hooks", [])
    new_inner = [h for h in inner if not (h.get("type") == "command" and h.get("command") == command)]
    removed_count += len(inner) - len(new_inner)
    if new_inner:
        # Keep the group with its remaining hooks.
        new_group = dict(group)
        new_group["hooks"] = new_inner
        new_event_list.append(new_group)
    # else: group becomes empty -> drop it entirely

if new_event_list:
    hooks[event] = new_event_list
elif event in hooks:
    del hooks[event]

if not hooks and "hooks" in data:
    del data["hooks"]

with open(target, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

if removed_count:
    print(f"removed: {event} -> {command} ({removed_count} entr{'ies' if removed_count != 1 else 'y'})")
else:
    print(f"not present: {event} -> {command}")
PY
}

cmd_list() {
  local target="${1:-.claude/settings.local.json}"
  local target_abs
  target_abs="$(resolve_target "$target")" || return 1

  if [ ! -f "$target_abs" ]; then
    echo "target file doesn't exist: $target_abs"
    echo "no hooks installed."
    return 0
  fi

  python3 - "$target_abs" <<'PY'
import json, sys
target = sys.argv[1]
with open(target) as f:
    try:
        data = json.load(f)
    except json.JSONDecodeError:
        print(f"error: target file is not valid JSON: {target}", file=sys.stderr)
        sys.exit(1)

hooks = data.get("hooks", {})
if not hooks:
    print("no hooks installed.")
    sys.exit(0)

for event, groups in hooks.items():
    print(f"{event}:")
    for group in groups:
        matcher = group.get("matcher", "")
        for h in group.get("hooks", []):
            tag = f" [matcher={matcher!r}]" if matcher else ""
            print(f"  - {h.get('type', '?')}: {h.get('command', '?')}{tag}")
PY
}

# ===== argument parser =====
# Supports:
#   add <Event> <command> [--target <file>] [--matcher <pattern>]
#   remove <Event> <command> [--target <file>]
#   list [--target <file>]
parse_flags() {
  # Sets _POS_ARGS, _TARGET, _MATCHER from arg array.
  _POS_ARGS=()
  _TARGET=""
  _MATCHER=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --target)
        _TARGET="${2:-}"
        shift 2 || { echo "error: --target needs a value" >&2; return 2; }
        ;;
      --target=*)
        _TARGET="${1#--target=}"
        shift
        ;;
      --matcher)
        _MATCHER="${2:-}"
        shift 2 || { echo "error: --matcher needs a value" >&2; return 2; }
        ;;
      --matcher=*)
        _MATCHER="${1#--matcher=}"
        shift
        ;;
      *)
        _POS_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

main() {
  local action="${1:-}"
  shift || true

  case "$action" in
    -h|--help|help|"") usage; return 0 ;;
  esac

  require_python3 || return 1

  case "$action" in
    add)
      parse_flags "$@"
      [ "${#_POS_ARGS[@]}" -ge 2 ] || {
        echo "error: add needs <Event> <command>" >&2
        return 2
      }
      cmd_add "${_POS_ARGS[0]}" "${_POS_ARGS[1]}" "${_TARGET:-.claude/settings.local.json}" "${_MATCHER}"
      ;;
    remove)
      parse_flags "$@"
      [ "${#_POS_ARGS[@]}" -ge 2 ] || {
        echo "error: remove needs <Event> <command>" >&2
        return 2
      }
      cmd_remove "${_POS_ARGS[0]}" "${_POS_ARGS[1]}" "${_TARGET:-.claude/settings.local.json}"
      ;;
    list)
      parse_flags "$@"
      cmd_list "${_TARGET:-.claude/settings.local.json}"
      ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
