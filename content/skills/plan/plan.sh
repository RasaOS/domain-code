#!/usr/bin/env bash
# plan.sh — deterministic scaffolding, validation and persistence for the
# request plan of the /plan skill (SKILL.md "Pattern F").
#
# The judgment is the conversation; this script handles what is mechanical:
# the fixed section skeleton (plan-template.md), the checks that a plan is
# finished, and where it is saved (docs/plans/).

set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_rfm="$(cd "$_here/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
[ -f "$_rfm" ] || { echo "error: $(basename "$0"): .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; exit 70; }
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
rfm_require 1 || exit 70

TEMPLATE="$_here/plan-template.md"  # with data-section.md and ui-section.md
AUDIT_SH="$_here/../audit/audit.sh"

# Sections of a request plan, in order. Keep in step with plan-template.md.
declare -a PLAN_SECTIONS=(
  "Goal"
  "Carried from the audit"
  "Approach"
  "Data"
  "UI/UX and screens"
  "Sources of truth read"
  "Tasks to file"
  "Checks that prove it"
  "Risks"
)

usage() {
  cat <<'USAGE'
plan.sh — request plan scaffolding for /plan

  plan.sh scaffold <slug> --audit <path>
      Print the plan skeleton. <path> is the request audit it answers; it
      must exist and validate (audit.sh validate). Every blank is <to-fill>.
  plan.sh validate <file>
      Exit 0 when the plan is finished, 3 when not: a missing section, a
      remaining <to-fill, an Audit path that is missing or does not validate,
      a Carried-from-the-audit bullet without a disposition (or none at
      all), or a Tasks-to-file bullet without x-ui: true|false.
  plan.sh save <slug> <file>
      Validate, then write docs/plans/<date>-<slug>.md; print its path.
USAGE
}

slug_of() {
  echo "$1" | tr '/' '-' | tr -cd 'a-zA-Z0-9-' | tr 'A-Z' 'a-z' \
    | sed -E 's/^-+|-+$//g; s/-+/-/g' | cut -c1-80
}

# Resolve an audit path from the project root (or as given).
audit_path() {
  local p="$1" root
  [ -f "$p" ] && { echo "$p"; return 0; }
  root="$(rasa_root)" || return 1
  [ -f "$root/$p" ] && { echo "$root/$p"; return 0; }
  return 1
}

check_audit() {
  local p="$1" resolved
  resolved="$(audit_path "$p")" || { echo "audit not found: $p" >&2; return 1; }
  bash "$AUDIT_SH" validate "$resolved" >/dev/null 2>&1 \
    || { echo "audit does not validate: $p (bash $AUDIT_SH validate)" >&2; return 1; }
}

# Body of one section: lines after "## <title>" up to the next "## ".
section_body() {
  awk -v t="## $2" '
    $0 == t { on = 1; next }
    /^## / { on = 0 }
    on { print }
  ' "$1"
}

cmd_scaffold() {
  local slug="" audit="" s
  [ $# -ge 1 ] || { echo "error: scaffold needs <slug> --audit <path>" >&2; return 2; }
  slug="$(slug_of "$1")"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --audit) audit="${2:-}"; shift 2 || true ;;
      *) echo "error: unknown option: $1" >&2; return 2 ;;
    esac
  done
  [ -n "$slug" ] || { echo "error: empty slug" >&2; return 2; }
  [ -n "$audit" ] || { echo "error: scaffold needs --audit <path>" >&2; return 2; }
  check_audit "$audit" || return 3
  [ -f "$TEMPLATE" ] || { echo "error: plan-template.md is missing" >&2; return 70; }
  # Line by line: a path may hold characters sed or ${//} would read. The Data
  # and UI sections are shared fragments (develop pastes the same files into a
  # task body), so they have one source.
  local line
  while IFS= read -r line; do
    case "$line" in
      "{{DATA_SECTION}}") cat "$_here/data-section.md" ;;
      "{{UI_SECTION}}") cat "$_here/ui-section.md" ;;
      *)
        line="${line//\{\{SLUG\}\}/$slug}"
        printf '%s\n' "${line//\{\{AUDIT\}\}/$audit}" ;;
    esac
  done < "$TEMPLATE"
}

cmd_validate() {
  local f="$1" bad=0 sec body line ap n unfilled
  [ -f "$f" ] || { echo "error: validate target not found: $f" >&2; return 1; }

  grep -qx '\*\*Kind\.\*\* request' "$f" || { echo "missing header: **Kind.** request" >&2; bad=$((bad + 1)); }

  ap="$(sed -n 's/^\*\*Audit\.\*\* *//p' "$f" | head -1)"
  case "$ap" in
    ""|*"<to-fill"*|*"{{"*) echo "missing header: **Audit.** <path>" >&2; bad=$((bad + 1)) ;;
    *) check_audit "$ap" || bad=$((bad + 1)) ;;
  esac

  for sec in "${PLAN_SECTIONS[@]}"; do
    grep -qxF "## ${sec}" "$f" || { echo "missing section: ${sec}" >&2; bad=$((bad + 1)); }
  done

  unfilled="$(grep -c '<to-fill' "$f" 2>/dev/null)" || unfilled=0
  case "$unfilled" in ''|*[!0-9]*) unfilled=0 ;; esac
  if [ "$unfilled" -gt 0 ]; then
    echo "${unfilled} <to-fill> placeholder(s) remaining" >&2
    bad=$((bad + 1))
  fi

  body="$(section_body "$f" "Carried from the audit")"
  n=0
  while IFS= read -r line; do
    case "$line" in
      "- "*)
        n=$((n + 1))
        case "$line" in
          *"done here"*|*"dropped because"*|*"later as"*) ;;
          *) echo "carried item without a disposition (done here / dropped because / later as): $line" >&2; bad=$((bad + 1)) ;;
        esac ;;
    esac
  done <<EOT
$body
EOT
  if [ "$n" -eq 0 ]; then
    echo "Carried from the audit is empty: every audit item needs a bullet and a disposition" >&2
    bad=$((bad + 1))
  fi

  body="$(section_body "$f" "Tasks to file")"
  n=0
  while IFS= read -r line; do
    case "$line" in
      "- "*)
        n=$((n + 1))
        case "$line" in
          *"x-ui: true"*|*"x-ui: false"*) ;;
          *) echo "task without x-ui: true|false: $line" >&2; bad=$((bad + 1)) ;;
        esac ;;
    esac
  done <<EOT
$body
EOT
  if [ "$n" -eq 0 ] && ! printf '%s\n' "$body" | grep -q '^Not touched:'; then
    echo "Tasks to file is empty: list the tasks, or one line: Not touched: <why>" >&2
    bad=$((bad + 1))
  fi

  [ "$bad" -eq 0 ] || return 3
  echo "ok"
}

cmd_save() {
  local slug f root dest n=2
  [ $# -ge 2 ] || { echo "error: save needs <slug> <file>" >&2; return 2; }
  slug="$(slug_of "$1")"; f="$2"
  [ -n "$slug" ] || { echo "error: empty slug" >&2; return 2; }
  cmd_validate "$f" >/dev/null || { cmd_validate "$f" >&2 || true; return 3; }
  root="$(rasa_root)" || return 1
  mkdir -p "$root/docs/plans"
  dest="$root/docs/plans/$(date '+%Y-%m-%d')-${slug}.md"
  while [ -e "$dest" ]; do
    dest="$root/docs/plans/$(date '+%Y-%m-%d')-${slug}-${n}.md"
    n=$((n + 1))
  done
  cp "$f" "$dest"
  echo "${dest#"$root"/}"
}

main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    -h|--help|help|"") usage ;;
    scaffold) cmd_scaffold "$@" ;;
    validate)
      [ $# -ge 1 ] || { echo "error: validate needs <file>" >&2; return 2; }
      cmd_validate "$1" ;;
    save) cmd_save "$@" ;;
    *) echo "error: unknown action: $action" >&2; usage >&2; return 2 ;;
  esac
}

main "$@"
