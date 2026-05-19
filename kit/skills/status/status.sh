#!/usr/bin/env bash
# status.sh — deterministic project status snapshot.
#
# Renders the kit-canonical /status output every invocation. AI's job
# is to call this script and surface stdout verbatim — no synthesis,
# no rewording, no rendering judgments.
#
# Catalogue: §2 Live status dashboard + markdown tables for tabular
# data (commits, PRs). §23 Activity timeline and §25 Alert variants
# may be added in a later version; this v1 covers the core sections.

set -euo pipefail

# Box-drawing width budget. Total visible width of every horizontal line
# is TOTAL_WIDTH. INNER_WIDTH = the space between the two `│` borders.
TOTAL_WIDTH=62
INNER_WIDTH=60
LABEL_WIDTH=12
# VALUE_WIDTH derived so that "│  G L<L>  V<V>  │" fits exactly INNER_WIDTH
# where G is a 1-column glyph: 2 + 1 + 1 + LABEL_WIDTH + 2 + VALUE_WIDTH + 2 = INNER_WIDTH
# → VALUE_WIDTH = 60 - 20 = 40
VALUE_WIDTH=40

usage() {
  cat <<'EOF'
status.sh — deterministic project status snapshot.

USAGE:
  status.sh dashboard     (default) Emit the full status report to stdout.
  status.sh data          Emit raw key=value data for composition / debug.

EXIT CODES:
  0  success
  1  operational error (not in a git repo)
  2  usage error
EOF
}

# Resolve the *main* repo root, even from a linked worktree. Mirrors
# save.sh's project_root for cross-script consistency.
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

# Repeat a character N times. Uses a loop instead of `tr` because `tr`
# operates on bytes, not codepoints — multi-byte chars like ─ (U+2500)
# can't be substituted correctly through `tr`.
repeat_char() {
  local c="$1" n="$2" i
  for (( i = 0; i < n; i++ )); do
    printf '%s' "$c"
  done
}

# ===== Data gather =====

repo_name() {
  basename "$(project_root)"
}

# Echo the project's current goal (one line) from the Goal section of
# CLAUDE.md. Empty if there's no CLAUDE.md or no goal; a hint string if
# the goal is still an unfilled {{placeholder}}.
current_goal() {
  local root cm line
  root="$(project_root)" || return 0
  cm="$root/CLAUDE.md"
  [ -f "$cm" ] || return 0
  line="$(grep -m1 '^\*\*Current goal\.\*\*' "$cm" 2>/dev/null \
    | sed 's/^\*\*Current goal\.\*\*[[:space:]]*//')"
  [ -n "$line" ] || return 0
  case "$line" in
    *'{{'*) echo "(not set — fill the Goal section in CLAUDE.md)" ;;
    *)      echo "$line" ;;
  esac
}

current_branch() {
  git symbolic-ref --short HEAD 2>/dev/null || echo "(detached)"
}

production_tag() {
  git tag --list 'v*' --sort=-v:refname 2>/dev/null | head -1
}

# Echo "<tag> (<sha> / <date>)" for the production tag, or "- (no tags)".
# ASCII-only on purpose — bash ${#var} is locale-dependent (bytes vs chars),
# so dashboard padding math only stays correct if values are single-byte.
# Box-drawing in borders is fine because those chars aren't padded.
production_info() {
  local tag
  tag="$(production_tag)"
  if [ -z "$tag" ]; then
    echo "- (no tags)"
    return
  fi
  local sha date
  sha="$(git rev-list -n 1 --abbrev-commit "$tag" 2>/dev/null || echo "?")"
  date="$(git log -1 --format='%cs' "$tag" 2>/dev/null || echo "?")"
  echo "$tag ($sha / $date)"
}

# Echo "<branch> · clean|dirty · N ahead/behind origin" or just the cleaner form.
branch_state() {
  local branch
  branch="$(current_branch)"

  local dirty_state
  if git diff --quiet HEAD -- 2>/dev/null \
      && git diff --cached --quiet 2>/dev/null \
      && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
    dirty_state="clean"
  else
    dirty_state="dirty"
  fi

  local upstream
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"

  local ahead_behind=""
  if [ -n "$upstream" ]; then
    local counts behind ahead
    counts="$(git rev-list --left-right --count "${upstream}...HEAD" 2>/dev/null || echo "0 0")"
    behind="$(echo "$counts" | awk '{print $1}')"
    ahead="$(echo "$counts" | awk '{print $2}')"
    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
      ahead_behind=" | ${ahead} ahead, ${behind} behind"
    elif [ "$ahead" -gt 0 ]; then
      ahead_behind=" | ${ahead} ahead"
    elif [ "$behind" -gt 0 ]; then
      ahead_behind=" | ${behind} behind"
    fi
  fi

  echo "${branch} | ${dirty_state}${ahead_behind}"
}

worktree_count() {
  git worktree list 2>/dev/null | wc -l | tr -d ' '
}

active_task_count() {
  local root tasks_dir
  root="$(project_root)" || return 1
  tasks_dir="$root/tasks/active"
  if [ ! -d "$tasks_dir" ]; then
    echo "0"
    return
  fi
  find "$tasks_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' '
}

has_pending_release() {
  # Heuristic: if main has commits past the latest tag, there's pending work.
  local tag
  tag="$(production_tag)"
  if [ -z "$tag" ]; then
    return 1
  fi
  local count
  count="$(git rev-list --count "${tag}..HEAD" 2>/dev/null || echo "0")"
  if [ "$count" -gt 0 ]; then
    local noun="commits"
    [ "$count" -eq 1 ] && noun="commit"
    echo "$count $noun past $tag, untagged"
    return 0
  fi
  return 1
}

# ===== Box rendering =====

# Top border with a left-justified title: "┌─ <title> ──...──┐"
# Layout: "┌" (1) + "─" (1) + " " (1) + title (T) + " " (1) + dashes (N) + "┐" (1) = TOTAL_WIDTH
# → N = TOTAL_WIDTH - T - 5
box_top() {
  local title="$1"
  local title_len=${#title}
  local dashes=$(( TOTAL_WIDTH - title_len - 5 ))
  if [ "$dashes" -lt 2 ]; then
    # Title too long — truncate so dashes >= 2
    local max_title=$(( TOTAL_WIDTH - 7 ))
    title="${title:0:$max_title}"
    dashes=2
  fi
  printf '┌─ %s ' "$title"
  repeat_char '─' "$dashes"
  printf '┐\n'
}

# Blank row: "│" + INNER_WIDTH spaces + "│"
box_blank() {
  printf '│'
  repeat_char ' ' "$INNER_WIDTH"
  printf '│\n'
}

# Single dashboard row.
# Layout (visible cols): "│" + "  " + glyph(1) + " " + label(LABEL_WIDTH) + "  " + value(VALUE_WIDTH) + "  " + "│"
# Total inner = 2 + 1 + 1 + LABEL_WIDTH + 2 + VALUE_WIDTH + 2 = INNER_WIDTH (60)
box_row() {
  local glyph="$1" label="$2" value="$3"
  local pad=$(( VALUE_WIDTH - ${#value} ))
  if [ "$pad" -lt 0 ]; then
    value="${value:0:$((VALUE_WIDTH - 1))}…"
    pad=0
  fi
  printf '│  %s %-*s  %s' "$glyph" "$LABEL_WIDTH" "$label" "$value"
  repeat_char ' ' "$pad"
  printf '  │\n'
}

# Bottom border: "└" + (TOTAL_WIDTH - 2) dashes + "┘"
box_bottom() {
  printf '└'
  repeat_char '─' "$INNER_WIDTH"
  printf '┘\n'
}

# ===== Sections =====

render_dashboard() {
  local repo now
  repo="$(repo_name)"
  now="$(date '+%Y-%m-%d %H:%M %Z')"

  box_top "${repo} · ${now}"
  box_blank

  # Production
  local prod_tag
  prod_tag="$(production_tag)"
  if [ -n "$prod_tag" ]; then
    box_row '●' 'Production' "$(production_info)"
  else
    box_row '○' 'Production' '- (no tags yet)'
  fi

  # Branch
  box_row '●' 'Branch' "$(branch_state)"

  # Worktrees (only show if more than 1)
  local wt
  wt="$(worktree_count)"
  if [ "$wt" -gt 1 ]; then
    local noun="worktrees"
    [ "$wt" -eq 1 ] && noun="worktree"
    box_row '●' 'Worktrees' "$wt $noun active"
  fi

  # In flight tasks
  local active
  active="$(active_task_count)"
  if [ "$active" -gt 0 ]; then
    local noun="tasks"
    [ "$active" -eq 1 ] && noun="task"
    box_row '◐' 'In flight' "$active $noun active"
  else
    box_row '○' 'In flight' '- (no active tasks)'
  fi

  # Pending release (only if there's untagged work past the latest tag)
  local pending
  if pending="$(has_pending_release)"; then
    box_row '◐' 'Pending' "$pending"
  fi

  box_blank
  box_bottom
}

render_commits() {
  echo ""
  echo "## Recent commits"
  echo ""
  if ! git rev-parse HEAD >/dev/null 2>&1; then
    echo "_No commits yet._"
    return
  fi
  echo "| SHA | Author | When | Subject |"
  echo "|---|---|---|---|"
  # Truncate subject to ~60 chars; replace pipe chars to keep table clean.
  git log -10 --pretty=format:'%h%x1F%an%x1F%ar%x1F%s' 2>/dev/null \
    | awk -F$'\x1F' '{
        subj = $4
        gsub(/\|/, "/", subj)
        if (length(subj) > 60) { subj = substr(subj, 1, 59) "…" }
        printf "| `%s` | %s | %s | %s |\n", $1, $2, $3, subj
      }'
}

render_prs() {
  echo ""
  echo "## Open pull requests"
  echo ""
  if ! command -v gh >/dev/null 2>&1; then
    echo "_\`gh\` not installed — PR list skipped._"
    return
  fi
  local prs
  prs="$(gh pr list --json number,title,author,headRefName,createdAt --limit 20 2>/dev/null)" || {
    echo "_\`gh pr list\` failed — auth lapsed, no network, or repo not linked._"
    return
  }
  if [ -z "$prs" ] || [ "$prs" = "[]" ]; then
    echo "_No open PRs._"
    return
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "_\`jq\` not installed — raw \`gh\` JSON skipped._"
    return
  fi
  echo "| # | Title | Author | Branch | Age |"
  echo "|---|---|---|---|---|"
  echo "$prs" | jq -r '
    .[]
    | "| #\(.number) | \(.title[0:60]) | \(.author.login) | \(.headRefName) | \(.createdAt[0:10]) |"
  '
}

render_active_tasks() {
  echo ""
  echo "## In flight"
  echo ""
  local root tasks_dir
  root="$(project_root)" || return 1
  tasks_dir="$root/tasks/active"
  if [ ! -d "$tasks_dir" ]; then
    echo "_No \`tasks/active/\` directory in this project._"
    return
  fi
  local found=0
  for f in "$tasks_dir"/*.md; do
    [ -e "$f" ] || continue
    found=1
    local title
    title="$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# *//' | tr -d '\r' | cut -c1-80)"
    [ -z "$title" ] && title="$(basename "$f" .md)"
    echo "- **${title}** — \`tasks/active/$(basename "$f")\`"
  done
  if [ "$found" -eq 0 ]; then
    echo "_No active tasks._"
  fi
}

render_inbox() {
  local root inbox
  root="$(project_root)" || return 1
  inbox="$root/.claude/inbox"

  # No inbox dir = project doesn't use /inbox. Render nothing.
  [ -d "$inbox" ] || return 0

  # Identity: lowercased first word of git config user.name.
  # Fall back to .claude/inbox/_me.md if cached.
  local handle
  handle="$(git config user.name 2>/dev/null | awk '{print tolower($1)}')"
  if [ -z "$handle" ] && [ -f "$inbox/_me.md" ]; then
    handle="$(head -1 "$inbox/_me.md" 2>/dev/null | tr -d '[:space:]')"
  fi
  [ -n "$handle" ] || return 0

  echo ""
  echo "## 📬 Inbox"
  echo ""

  local my_inbox="$inbox/$handle.md"
  if [ ! -f "$my_inbox" ]; then
    echo "_No inbox file for \`@${handle}\` yet._"
    return 0
  fi

  # Inbox message header format (per /inbox SKILL.md):
  #   ### `#0001` `[unread]` from `@sender` · 2026-05-10 23:00
  # We count and list lines matching the unread variant.
  local unread_count
  unread_count="$(grep -c '^### `#[0-9]\{1,5\}` `\[unread\]`' "$my_inbox" 2>/dev/null || echo 0)"
  unread_count="${unread_count//$'\n'/}"

  if [ "${unread_count:-0}" -eq 0 ]; then
    echo "_No unread for \`@${handle}\`._"
    return 0
  fi

  local plural="messages"
  [ "$unread_count" -eq 1 ] && plural="message"
  echo "**${unread_count} unread ${plural}** for \`@${handle}\`:"
  echo ""

  # List up to 5 unread headers, stripped of the leading `### `.
  grep '^### `#[0-9]' "$my_inbox" 2>/dev/null \
    | grep '`\[unread\]`' \
    | head -5 \
    | sed 's/^### /- /'

  if [ "$unread_count" -gt 5 ]; then
    echo ""
    echo "_…and $((unread_count - 5)) more. Run \`/inbox\` for full read view._"
  fi
}

render_roadmap() {
  echo ""
  echo "## Top of roadmap"
  echo ""
  local root roadmap
  root="$(project_root)" || return 1
  roadmap="$root/tasks/ROADMAP.md"
  if [ ! -f "$roadmap" ]; then
    echo "_No \`tasks/ROADMAP.md\` in this project._"
    return
  fi
  # First 5 lines of roadmap that look like list items (start with - or *)
  local lines
  lines="$(grep -m5 -E '^[[:space:]]*[-*]' "$roadmap" 2>/dev/null || true)"
  if [ -z "$lines" ]; then
    echo "_ROADMAP.md present but no list items found in the first scan._"
    return
  fi
  echo "$lines"
}

# ===== Subcommands =====

cmd_dashboard() {
  local repo
  repo="$(repo_name)" || return 1

  echo "# Project status · ${repo} · $(date '+%Y-%m-%d')"
  echo ""
  local goal
  goal="$(current_goal)"
  if [ -n "$goal" ]; then
    echo "🎯 **Goal** — ${goal}"
    echo ""
  fi
  echo '```'
  render_dashboard
  echo '```'

  render_commits
  render_prs
  render_active_tasks
  render_roadmap
  render_inbox
}

cmd_data() {
  local repo
  repo="$(repo_name)" || return 1

  echo "repo=${repo}"
  echo "now=$(date '+%Y-%m-%d %H:%M %Z')"
  echo "current_goal=$(current_goal)"
  echo "branch=$(current_branch)"
  echo "branch_state=$(branch_state)"
  echo "production_tag=$(production_tag)"
  echo "production_info=$(production_info)"
  echo "worktree_count=$(worktree_count)"
  echo "active_task_count=$(active_task_count)"
  local pending=""
  pending="$(has_pending_release 2>/dev/null || true)"
  echo "pending_release=${pending}"

  # Inbox: handle + unread count (silently empty if no inbox dir or no handle).
  local root inbox handle
  root="$(project_root)" || return 1
  inbox="$root/.claude/inbox"
  handle="$(git config user.name 2>/dev/null | awk '{print tolower($1)}')"
  if [ -z "$handle" ] && [ -f "$inbox/_me.md" ]; then
    handle="$(head -1 "$inbox/_me.md" 2>/dev/null | tr -d '[:space:]')"
  fi
  echo "inbox_handle=${handle}"
  if [ -d "$inbox" ] && [ -n "$handle" ] && [ -f "$inbox/$handle.md" ]; then
    local n
    n="$(grep -c '^### `#[0-9]\{1,5\}` `\[unread\]`' "$inbox/$handle.md" 2>/dev/null || echo 0)"
    echo "inbox_unread=${n//$'\n'/}"
  else
    echo "inbox_unread=0"
  fi
}

main() {
  local action="${1:-dashboard}"
  shift || true

  case "$action" in
    -h|--help|help) usage; return 0 ;;
    dashboard)      cmd_dashboard ;;
    data)           cmd_data ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
