#!/usr/bin/env bash
# save.sh — deterministic state-save mechanics for the /save skill.
#
# The AI synthesizes content into a temp file; this script handles all
# file plumbing: archive policy, timestamps, TIMELINE.md upkeep,
# filename collisions. Run via `.claude/skills/save/save.sh <action>`
# from anywhere inside a git repo.

set -euo pipefail

usage() {
  cat <<'EOF'
save.sh — state-save and archive mechanics for the /save skill.

USAGE:
  save.sh status
      Report whether SAVED.md exists, when last written, archive count.

  save.sh write <content-file> [--mode auto|archive|replace]
      Write <content-file> into SAVED.md (path below).
      --mode auto     (default) archive existing SAVED.md if non-empty, then write
      --mode archive  force archive of existing SAVED.md before writing
                      (errors if SAVED.md is empty/missing)
      --mode replace  overwrite SAVED.md without archiving

  save.sh archive
      Archive current SAVED.md to <saves-dir>/<YYYY-MM-DD-HHMM>.md,
      prepend an entry to TIMELINE.md. No new content written.

  save.sh current-branch
      Echo the current git branch (or "None" for detached HEAD).
      Used by save.sh internally and exposed for /load.

LAYOUT:
  Saves live in user-global space (not in the project repo):

  ~/.claude/projects/<mangled-repo-key>/saves/
    SAVED.md                Current snapshot.
    TIMELINE.md             Newest-first index of archived snapshots.
    <YYYY-MM-DD-HHMM>.md    Archived snapshots, sorted by timestamp.

  The <mangled-repo-key> is the absolute path of the *main* repo
  root with "/" replaced by "-" (e.g. -Users-chazzromeo-claude-kit).
  All worktrees of the same project share one save state.

TIMELINE entry format:
  - **<YYYY-MM-DD HH:MM>** — [<title>](<filename>)
  <title> is the first H1 ("# ...") in the archived file, or
  "saved snapshot" if no H1 is present.

EXIT CODES:
  0  success
  1  operational error (missing file, write failure, not in a git repo)
  2  usage error (bad flags)
  3  refused (e.g. --mode archive when SAVED.md is empty)
EOF
}

# Resolve the *main* repo's working tree root, even when called from a
# linked worktree. Uses --git-common-dir so all worktrees of one project
# share a single save state under ~/.claude/projects/<key>/saves/.
#
# `cd -P` and `pwd -P` resolve symlinks physically, which is critical on
# macOS where /tmp is a symlink to /private/tmp. Without this, the main
# worktree and linked worktrees produce different project keys.
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

# Path-mangle the project root into a key for ~/.claude/projects/<key>/.
# Matches the convention used by Claude Code's memory directory:
# leading slashes become a leading hyphen.
project_key() {
  local root
  root="$(project_root)" || return 1
  echo "${root//\//-}"
}

# 0 iff file exists AND has at least one non-whitespace character.
has_content() {
  local f="$1"
  [ -f "$f" ] && grep -q '[^[:space:]]' "$f" 2>/dev/null
}

# Echo first H1 from a file (stripped of "# " and length-capped),
# or "saved snapshot" if no H1.
extract_title() {
  local f="$1" title
  title="$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# *//' | tr -d '\r' | cut -c1-200)"
  if [ -z "$title" ]; then
    echo "saved snapshot"
  else
    echo "$title"
  fi
}

# Echo current branch name, or "None" if detached HEAD / no commits.
current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo "None"
}

# If <file> doesn't already have `> **Branch.** ...`, inject one based on
# the current branch. Inserts after the last `> **...**` header line, or
# appends to the end if no header block exists.
inject_branch_if_missing() {
  local f="$1"
  if grep -q '^> \*\*Branch\.\*\*' "$f" 2>/dev/null; then
    return 0
  fi

  local branch
  branch="$(current_branch)"

  if grep -q '^> \*\*' "$f" 2>/dev/null; then
    awk -v branch="$branch" '
      BEGIN { last_meta = 0 }
      /^> \*\*/ { last_meta = NR }
      { lines[NR] = $0 }
      END {
        for (i = 1; i <= NR; i++) {
          print lines[i]
          if (i == last_meta) {
            print "> **Branch.** " branch
          }
        }
      }
    ' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  else
    printf '\n> **Branch.** %s\n' "$branch" >> "$f"
  fi
}

# Portable mtime (BSD/macOS + GNU/Linux).
file_mtime_human() {
  local f="$1"
  date -r "$f" '+%Y-%m-%d %H:%M' 2>/dev/null \
    || stat -c '%y' "$f" 2>/dev/null | cut -c1-16 \
    || echo "unknown"
}

# Prepend an entry below TIMELINE.md's header. Create timeline if absent.
# Strategy: insert above the first existing "- " bullet so manual header
# prose is preserved. If no bullets exist yet, append at end.
prepend_timeline() {
  local timeline_md="$1" entry="$2"

  if [ ! -f "$timeline_md" ]; then
    cat >"$timeline_md" <<EOF
# Timeline — saved snapshots

> Newest-first index. Each entry points to its archived snapshot file.
> Maintained by \`save.sh\`. Manual header prose above the list is preserved.

${entry}
EOF
    return 0
  fi

  if grep -q '^- ' "$timeline_md"; then
    awk -v entry="$entry" '
      BEGIN { inserted = 0 }
      /^- / && !inserted { print entry; inserted = 1 }
      { print }
    ' "$timeline_md" >"${timeline_md}.tmp"
    mv "${timeline_md}.tmp" "$timeline_md"
  else
    printf '\n%s\n' "$entry" >>"$timeline_md"
  fi
}

# Archive SAVED.md → <saves-dir>/<stamp>.md, prepend TIMELINE entry.
# Caller MUST verify SAVED.md is non-empty first.
# Echoes the archive path on success.
do_archive() {
  local saved_md="$1" timeline_md="$2" saved_dir="$3"

  local stamp human title archive_name archive_path n
  stamp="$(date '+%Y-%m-%d-%H%M')"
  human="$(date '+%Y-%m-%d %H:%M')"
  title="$(extract_title "$saved_md")"

  archive_name="${stamp}.md"
  archive_path="$saved_dir/$archive_name"
  n=2
  while [ -e "$archive_path" ]; do
    archive_name="${stamp}-${n}.md"
    archive_path="$saved_dir/$archive_name"
    n=$((n + 1))
  done

  mv "$saved_md" "$archive_path"

  local entry="- **${human}** — [${title}](${archive_name})"
  prepend_timeline "$timeline_md" "$entry"

  echo "$archive_path"
}

cmd_status() {
  local saved_dir="$1" saved_md="$2"
  local archive_count=0

  if [ -d "$saved_dir" ]; then
    # Count archived files (stamped 20YY-...), excluding SAVED.md and TIMELINE.md.
    archive_count="$(find "$saved_dir" -maxdepth 1 -type f -name '20*.md' 2>/dev/null | wc -l | tr -d ' ')"
  fi

  if has_content "$saved_md"; then
    local mtime
    mtime="$(file_mtime_human "$saved_md")"
    echo "SAVED.md present, last written ${mtime} (${archive_count} archived)"
  else
    echo "SAVED.md empty or missing (${archive_count} archived)"
  fi
}

cmd_archive() {
  local saved_dir="$1" saved_md="$2" timeline_md="$3"
  if ! has_content "$saved_md"; then
    echo "refused: SAVED.md is empty or missing; nothing to archive" >&2
    return 3
  fi
  local archived
  archived="$(do_archive "$saved_md" "$timeline_md" "$saved_dir")"
  echo "archived → ${archived}"
}

cmd_write() {
  local saved_dir="$1" saved_md="$2" timeline_md="$3"
  shift 3

  local content_file="" mode="auto"
  while [ $# -gt 0 ]; do
    case "$1" in
      --mode)
        if [ $# -lt 2 ]; then
          echo "error: --mode requires a value" >&2
          return 2
        fi
        mode="$2"
        shift 2
        ;;
      --mode=*)
        mode="${1#--mode=}"
        shift
        ;;
      --) shift; break ;;
      -*)
        echo "error: unknown flag: $1" >&2
        return 2
        ;;
      *)
        if [ -z "$content_file" ]; then
          content_file="$1"
        else
          echo "error: unexpected argument: $1" >&2
          return 2
        fi
        shift
        ;;
    esac
  done

  if [ -z "$content_file" ]; then
    echo "error: write requires a content file" >&2
    return 2
  fi
  if [ ! -f "$content_file" ]; then
    echo "error: content file not found: $content_file" >&2
    return 1
  fi
  if ! has_content "$content_file"; then
    echo "error: content file is empty" >&2
    return 1
  fi

  case "$mode" in
    auto|archive|replace) ;;
    *)
      echo "error: --mode must be one of: auto, archive, replace (got: $mode)" >&2
      return 2
      ;;
  esac

  local archived=""
  if has_content "$saved_md"; then
    case "$mode" in
      auto|archive)
        archived="$(do_archive "$saved_md" "$timeline_md" "$saved_dir")"
        ;;
      replace)
        : # no archive, overwrite below
        ;;
    esac
  else
    if [ "$mode" = "archive" ]; then
      echo "refused: SAVED.md is empty; --mode archive requires existing content" >&2
      return 3
    fi
  fi

  cp "$content_file" "$saved_md"
  inject_branch_if_missing "$saved_md"

  if [ -n "$archived" ]; then
    echo "wrote SAVED.md (archived previous → $(basename "$archived"))"
  else
    echo "wrote SAVED.md"
  fi
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

  mkdir -p "$saved_dir"

  case "$action" in
    status)         cmd_status        "$saved_dir" "$saved_md" ;;
    write)          cmd_write         "$saved_dir" "$saved_md" "$timeline_md" "$@" ;;
    archive)        cmd_archive       "$saved_dir" "$saved_md" "$timeline_md" ;;
    current-branch) current_branch ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
