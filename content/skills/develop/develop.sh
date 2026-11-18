#!/usr/bin/env bash
# develop.sh — the mechanical half of /develop: read the sources of truth,
# gate a task, start it. The judgment (building to the plan) is the agent's.
#
#   develop.sh sources                 tenant + repo sources of truth
#   develop.sh check-unfilled <file>   unfilled <...> placeholders in a task
#   develop.sh gate <id>               may this task be started?
#   develop.sh start <id>              gate, then bin/task start
#
# Exit: 0 ok, 1 task not found or bad input, 3 refused (reasons on stderr).

set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_rfm="$(cd "$_here/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
[ -f "$_rfm" ] || { echo "error: $(basename "$0"): .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; exit 70; }
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
rfm_require 1 || exit 70

AUDIT_SH="$_here/../audit/audit.sh"
PLAN_SH="$_here/../plan/plan.sh"
CONTRACT_SH="$_here/../contract/contract.sh"
ENFORCE_SH="$_here/../task-enforce/task-enforce.sh"

# Labels a filled UI block carries (or one `Not touched:` line instead).
declare -a UI_LABELS=(
  "Size classes" "States" "Back stack" "Accessibility"
  "Interaction feedback" "Visuals" "Design source"
)

usage() {
  cat <<'USAGE'
develop.sh — /develop's mechanical steps

  develop.sh sources
      First line "tenant: none" or "tenant: <abs path>", then one line per
      existing source: the tenant's contracts/ conventions/ decisions/
      design/ CLAUDE.md, then the repo's CLAUDE.md and contracts/. Exit 0.
  develop.sh check-unfilled <file>
      Exit 3 and list file:line of every <...> placeholder outside code
      fences, inline code and the Blocker / Notes sections.
  develop.sh gate <id>
      Exit 0 when the task may start; 3 with every reason when not.
  develop.sh start <id>
      gate, then `bin/task start <id> --by <actor>`.
USAGE
}

fm() { rfm_get "$1" "$2" 2>/dev/null || true; }

# Body of one "## <title>" section.
section_body() {
  awk -v t="## $2" '
    $0 == t { on = 1; next }
    /^## / { on = 0 }
    on { print }
  ' "$1"
}

# --- sources ----------------------------------------------------------------

tenant_path() {
  local root="$1" p=""
  if [ -n "${RASA_TENANT:-}" ]; then
    p="$RASA_TENANT"
  elif [ -f "$root/.claude/rasa-deployment.md" ]; then
    p="$(sed -n 's/^tenant:[[:space:]]*//p' "$root/.claude/rasa-deployment.md" | head -1)"
  fi
  case "$p" in "~"|"~/"*) p="$HOME${p#"~"}" ;; esac
  case "$p" in ""|"<"*) return 1 ;; esac
  [ -d "$p" ] || return 1
  (cd "$p" && pwd)
}

cmd_sources() {
  local root t d
  root="$(rasa_root)" || return 1
  if t="$(tenant_path "$root")"; then
    echo "tenant: $t"
    for d in contracts conventions decisions design; do
      [ -d "$t/$d" ] && echo "$t/$d/"
    done
    [ -f "$t/CLAUDE.md" ] && echo "$t/CLAUDE.md"
  else
    echo "tenant: none"
  fi
  [ -f "$root/CLAUDE.md" ] && echo "$root/CLAUDE.md"
  [ -d "$root/contracts" ] && echo "$root/contracts/"
  return 0
}

# --- check-unfilled ---------------------------------------------------------

# "line N: text" for each placeholder, N counted in the whole file. The
# frontmatter is the library's to read (rfm_body); fences, ## Blocker and
# ## Notes are skipped, and inline code is stripped first so a task can quote
# a path or a type.
unfilled_lines() {
  local total body_lines
  total="$(awk 'END { print NR }' "$1")"
  body_lines="$(rfm_body "$1" | awk 'END { print NR }')"
  rfm_body "$1" | OFF="$((total - body_lines))" awk '
    /^```/ || /^~~~/ { fence = !fence; next }
    fence { next }
    /^## / { skip = ($0 == "## Blocker" || $0 == "## Notes"); next }
    skip { next }
    {
      l = $0
      gsub(/`[^`]*`/, "", l)
      if (l ~ /<[^<>[:space:]][^<>]*>/) print "line " (NR + ENVIRON["OFF"]) ": " $0
    }
  '
}

cmd_check_unfilled() {
  local f="${1:-}" out
  [ -f "$f" ] || { echo "error: check-unfilled needs an existing <file>" >&2; return 1; }
  out="$(unfilled_lines "$f")"
  if [ -n "$out" ]; then
    printf '%s\n' "$out" >&2
    echo "unfilled placeholder(s) above — fill or delete each" >&2
    return 3
  fi
  echo "ok"
}

# --- gate -------------------------------------------------------------------

find_task() {
  local root="$1" id="$2" f
  for f in "$root"/tasks/backlog/"$id"-*.md "$root"/tasks/active/"$id"-*.md; do
    [ -f "$f" ] && { echo "$f"; return 0; }
  done
  return 1
}

# Gate reasons, one per line on stdout; empty when the task passes.
gate_reasons() {
  local root="$1" f="$2" prio plan audit ui body stamp name line lab p

  if rfm_body "$f" | grep -q 'STATUS: STUB'; then
    echo "stub depth: expand it first (expanding-a-task.md)"
  fi

  unfilled_lines "$f" | while IFS= read -r line; do
    echo "unfilled: $line"
  done

  prio="$(fm "$f" priority)"; plan="$(fm "$f" x-plan)"
  audit="$(fm "$f" x-audit)"; ui="$(fm "$f" x-ui)"

  # The audit/plan link applies to a task carrying x-plan; priority: now is exempt.
  if [ -n "$plan" ] && [ "$prio" != "now" ]; then
    if [ -z "$audit" ]; then
      echo "x-plan without x-audit"
    elif [ ! -f "$root/$audit" ] || ! bash "$AUDIT_SH" validate "$root/$audit" >/dev/null 2>&1; then
      echo "x-audit does not exist or does not validate: $audit"
    fi
    if [ ! -f "$root/$plan" ] || ! bash "$PLAN_SH" validate "$root/$plan" >/dev/null 2>&1; then
      echo "x-plan does not exist or does not validate: $plan"
    fi
    if ! grep -qx '## Data' "$f"; then
      echo "no '## Data' section (paste plan/data-section.md, fill it or one 'Not touched:' line)"
    fi
  fi

  if [ "$ui" = "true" ]; then
    body="$(section_body "$f" "UI/UX and screens")"
    if ! grep -qx '## UI/UX and screens' "$f"; then
      echo "x-ui: true but no '## UI/UX and screens' section (paste plan/ui-section.md)"
    elif ! printf '%s\n' "$body" | grep -q '^Not touched:'; then
      for lab in "${UI_LABELS[@]}"; do
        printf '%s\n' "$body" | grep -qF "**${lab}:**" || echo "UI block lacks: ${lab}"
      done
    fi
  fi

  # A locked contract named on the Data block's Contract stamp line stops the task.
  line="$(section_body "$f" "Data" | grep -F '**Contract stamp:**' | head -1 || true)"
  if [ -n "$line" ] && [ -d "$root/contracts/stamps" ]; then
    for p in "$root"/contracts/stamps/*.md; do
      [ -f "$p" ] || continue
      name="$(basename "$p" .md)"
      case "$line" in
        *"$name"*)
          (cd "$root" && bash "$CONTRACT_SH" check "contracts/stamps/$name.md" >/dev/null 2>&1) \
            || echo "locked contract: $name (unlock it deliberately with /contract, or change the plan)" ;;
      esac
    done
  fi
  return 0
}

cmd_gate() {
  local id="${1:-}" root f reasons
  [ -n "$id" ] || { echo "error: gate needs <id>" >&2; return 1; }
  root="$(rasa_root)" || return 1
  f="$(find_task "$root" "$id")" || { echo "error: no $id in tasks/backlog or tasks/active" >&2; return 1; }
  reasons="$(gate_reasons "$root" "$f")"
  if [ -n "$reasons" ]; then
    echo "gate: $id refused" >&2
    printf '%s\n' "$reasons" | sed 's/^/  - /' >&2
    return 3
  fi
  echo "ok"
}

cmd_start() {
  local id="${1:-}" root task_bin
  cmd_gate "$id" || return $?
  root="$(rasa_root)"
  task_bin="$root/.claude/bin/task"
  [ -x "$task_bin" ] || task_bin="$_here/../../bin/task"
  [ -f "$task_bin" ] || { echo "error: bin/task not found" >&2; return 1; }
  RASA_ROOT="$root" "$task_bin" start "$id" --by "$(bash "$ENFORCE_SH" who)"
}

main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    -h|--help|help|"") usage ;;
    sources) cmd_sources ;;
    check-unfilled) cmd_check_unfilled "$@" ;;
    gate) cmd_gate "$@" ;;
    start) cmd_start "$@" ;;
    *) echo "error: unknown action: $action" >&2; usage >&2; return 2 ;;
  esac
}

main "$@"
