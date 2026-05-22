#!/usr/bin/env bash
# load.sh — read-side data gather for the /load skill.
#
# Reads SAVED.md, scans recent TIMELINE entries, and emits git log
# since the save was written. The AI synthesizes from this output;
# the script just does the deterministic data collection.

set -euo pipefail

usage() {
  cat <<'EOF'
load.sh — rehydrate-from-save data gather for the /load skill.

USAGE:
  load.sh status
      Report whether SAVED.md exists and when it was last written.

  load.sh orient
      Emit the full orient data:
        - SAVED.md content
        - Last 5 TIMELINE.md entries
        - Git log since SAVED.md was written
        - Branch comparison (saved vs. current)

  load.sh branch
      Echo the branch recorded in SAVED.md (or "None").

  load.sh checkout
      Check out the branch recorded in SAVED.md.
      Refuses (exit 3) if: working tree is dirty, branch is "None",
      or branch doesn't exist locally. Already-on-branch is a no-op.

EXIT CODES:
  0  success
  1  no SAVED.md (nothing to load)
  2  usage error
  3  refused (dirty tree, branch missing, branch is "None", etc.)
EOF
}

# Resolve the *main* repo's working tree root (worktree-safe via
# --git-common-dir). Must match save.sh's project_root exactly so
# /save and /load read/write the same location.
#
# `cd -P` / `pwd -P` follow symlinks physically — critical on macOS
# where /tmp -> /private/tmp would otherwise produce different keys
# between the main worktree and linked worktrees.
project_root() {
  local common_dir
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || {
    echo "error: not inside a git repo" >&2
    return 1
  }
  local abs_common
  abs_common="$(cd -P "$common_dir" 2>/dev/null && pwd -P)" || return 1
  dirname "$abs_common"
}

# Path-mangle to match save.sh + Claude Code's memory directory convention.
project_key() {
  local root
  root="$(project_root)" || return 1
  echo "${root//\//-}"
}

has_content() {
  local f="$1"
  [ -f "$f" ] && grep -q '[^[:space:]]' "$f" 2>/dev/null
}

file_mtime_human() {
  local f="$1"
  date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null \
    || stat -c '%y' "$f" 2>/dev/null | cut -c1-16 \
    || echo "unknown"
}

# Echo the file's mtime in a form `git log --since=` accepts.
file_mtime_iso() {
  local f="$1"
  date -r "$f" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
    || stat -c '%y' "$f" 2>/dev/null | cut -c1-19 \
    || echo ""
}

# Echo the branch recorded in SAVED.md (from `> **Branch.** ...` line).
# Empty if no Branch line present.
extract_saved_branch() {
  local f="$1"
  grep -m1 '^> \*\*Branch\.\*\*' "$f" 2>/dev/null \
    | sed 's/^> \*\*Branch\.\*\*[[:space:]]*//' \
    | tr -d '\r' \
    | sed 's/[[:space:]]*$//'
}

# Echo the current branch (or "None" for detached HEAD / no commits).
current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo "None"
}

# 0 if the working tree is clean — no staged changes, no unstaged
# changes, no untracked files (honoring .gitignore). Strict by design:
# the AI/user should commit or stash anything before branch-switching.
working_tree_clean() {
  git diff --quiet HEAD -- 2>/dev/null \
    && git diff --cached --quiet 2>/dev/null \
    && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]
}

# 0 if the given branch exists locally.
branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

# Echo the path of any *other* worktree that has this branch checked out,
# or empty if no other worktree owns it. Git refuses to check out a
# branch that's already checked out in another worktree, so we surface
# this as a refusal-3 instead of letting git error out.
branch_in_use_elsewhere() {
  local branch="$1"
  local self
  self="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  git worktree list --porcelain 2>/dev/null \
    | awk -v branch="refs/heads/$branch" -v self="$self" '
        /^worktree / { wt = substr($0, 10); next }
        /^branch / {
          if ($2 == branch && wt != self) {
            print wt
            exit
          }
        }
      '
}

cmd_status() {
  local saved_md="$1"
  if has_content "$saved_md"; then
    echo "SAVED.md present, last written $(file_mtime_human "$saved_md")"
    return 0
  else
    echo "no SAVED.md (or empty)"
    return 1
  fi
}

cmd_orient() {
  local saved_dir="$1" saved_md="$2" timeline_md="$3"

  if ! has_content "$saved_md"; then
    echo "no SAVED.md to load from $saved_md" >&2
    return 1
  fi

  echo "===== SAVED.md (written $(file_mtime_human "$saved_md")) ====="
  cat "$saved_md"
  echo ""

  if [ -f "$timeline_md" ]; then
    echo "===== TIMELINE.md (last 5 entries) ====="
    local entries
    entries="$(grep '^- \*\*' "$timeline_md" 2>/dev/null | head -5 || true)"
    if [ -n "$entries" ]; then
      echo "$entries"
    else
      echo "(no entries)"
    fi
    echo ""
  else
    echo "===== TIMELINE.md ====="
    echo "(not present — no archive history yet)"
    echo ""
  fi

  echo "===== Branch comparison ====="
  local saved_br current_br
  saved_br="$(extract_saved_branch "$saved_md")"
  current_br="$(current_branch)"
  if [ -z "$saved_br" ]; then
    echo "saved branch: (not recorded — pre-branch-tracking save)"
  else
    echo "saved branch:   $saved_br"
  fi
  echo "current branch: $current_br"
  if [ -n "$saved_br" ] && [ "$saved_br" != "$current_br" ] && [ "$saved_br" != "None" ]; then
    echo "MISMATCH — run 'load.sh checkout' to switch to $saved_br"
  fi
  echo ""

  echo "===== Git activity since SAVED.md was written ====="
  local saved_ts
  saved_ts="$(file_mtime_iso "$saved_md")"
  if [ -z "$saved_ts" ]; then
    echo "(couldn't determine save timestamp)"
    return 0
  fi

  # Saves live in user-global space (~/.claude/projects/<key>/saves/),
  # not under the project tree, so plain git log captures only real
  # project activity — no save-snapshot noise to filter out.
  local log
  log="$(git log --since="$saved_ts" --oneline 2>/dev/null || true)"
  if [ -z "$log" ]; then
    echo "(no commits since save)"
    return 0
  fi

  local total
  total="$(echo "$log" | wc -l | tr -d ' ')"
  echo "$log" | head -20
  if [ "$total" -gt 20 ]; then
    echo "... and $((total - 20)) more"
  fi
}

cmd_branch() {
  local saved_md="$1"
  if ! has_content "$saved_md"; then
    echo "no SAVED.md" >&2
    return 1
  fi
  local saved_br
  saved_br="$(extract_saved_branch "$saved_md")"
  if [ -z "$saved_br" ]; then
    echo "(not recorded)"
  else
    echo "$saved_br"
  fi
}

cmd_checkout() {
  local saved_md="$1"
  if ! has_content "$saved_md"; then
    echo "refused: no SAVED.md" >&2
    return 1
  fi

  local saved_br current_br
  saved_br="$(extract_saved_branch "$saved_md")"
  current_br="$(current_branch)"

  if [ -z "$saved_br" ]; then
    echo "refused: SAVED.md has no Branch line (pre-branch-tracking save)" >&2
    return 3
  fi

  if [ "$saved_br" = "None" ]; then
    echo "refused: saved branch is 'None' (no checkout action defined)" >&2
    return 3
  fi

  if [ "$saved_br" = "$current_br" ]; then
    echo "already on $current_br"
    return 0
  fi

  if ! working_tree_clean; then
    echo "refused: working tree has uncommitted changes; commit or stash first" >&2
    return 3
  fi

  if ! branch_exists "$saved_br"; then
    echo "refused: branch '$saved_br' does not exist locally" >&2
    return 3
  fi

  local elsewhere
  elsewhere="$(branch_in_use_elsewhere "$saved_br")"
  if [ -n "$elsewhere" ]; then
    echo "refused: branch '$saved_br' is checked out in worktree at $elsewhere" >&2
    return 3
  fi

  git checkout "$saved_br"
}

main() {
  local action="${1:-}"
  shift || true

  case "$action" in
    -h|--help|help|"")
      usage
      return 0
      ;;
  esac

  local key
  key="$(project_key)" || return 1
  local saved_dir="$HOME/.claude/projects/$key/saves"
  local saved_md="$saved_dir/SAVED.md"
  local timeline_md="$saved_dir/TIMELINE.md"

  case "$action" in
    status)   cmd_status   "$saved_md" ;;
    orient)   cmd_orient   "$saved_dir" "$saved_md" "$timeline_md" ;;
    branch)   cmd_branch   "$saved_md" ;;
    checkout) cmd_checkout "$saved_md" ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
