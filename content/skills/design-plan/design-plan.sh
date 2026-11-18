#!/usr/bin/env bash
# design-plan.sh — deterministic half of /design-plan: scaffold a design plan
# (per screen, per size class) and validate it.
#
# The UI block of a request plan is plan/ui-section.md, one fragment shared
# with /plan and /develop; this script never carries a copy of it.

set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_rfm="$(cd "$_here/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
[ -f "$_rfm" ] || { echo "error: $(basename "$0"): .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; exit 70; }
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
rfm_require 1 || exit 70

UI_SECTION="$_here/../plan/ui-section.md"
AUDIT_SH="$_here/../audit/audit.sh"
DESIGN_AUDIT_SH="$_here/../design-audit/design-audit.sh"

# Sections of a design plan (`**Kind.** design`), in render order. "Screens"
# holds one "### Screen: <name>" block per screen.
declare -a DESIGN_PLAN_SECTIONS=(
  "Goal"
  "Screens"
  "Tokens and components"
  "Data"
  "Checks that prove it"
)

declare -a SIZE_CLASSES=(compact medium expanded)

usage() {
  cat <<'EOF'
design-plan.sh — scaffolding for the /design-plan skill.

USAGE:
  design-plan.sh scaffold <slug> --audit <path>
      Emit a design plan (Kind design) to stdout. <path> is a design audit
      (or a request audit) that validates. Copy the Screen block once per
      screen.

  design-plan.sh scaffold --in <request-plan>
      Emit only the UI/UX block (plan/ui-section.md), for a request plan's
      "## UI/UX and screens" section.

  design-plan.sh validate <file>
      Kind design: the audit validates, sections present, no <to-fill>, and
      every Screen block has a Back target and all three size classes.
      Kind request: that plan's UI/UX section has no <to-fill>.
      Exit 0 if compliant, 3 if not.

EXIT CODES:
  0 success   1 operational error   2 usage error   3 validation failed
EOF
}

audit_path() {
  local p="$1" root
  [ -f "$p" ] && { echo "$p"; return 0; }
  root="$(rasa_root)" || return 1
  [ -f "$root/$p" ] && { echo "$root/$p"; return 0; }
  return 1
}

# The audit must exist and validate: design-audit.sh for a design audit,
# audit.sh otherwise.
check_audit() {
  local p="$1" resolved sh
  resolved="$(audit_path "$p")" || { echo "audit not found: $p" >&2; return 1; }
  sh="$AUDIT_SH"
  grep -qx '\*\*Kind\.\*\* design' "$resolved" && sh="$DESIGN_AUDIT_SH"
  bash "$sh" validate "$resolved" >/dev/null 2>&1 \
    || { echo "audit does not validate: $p (bash $sh validate)" >&2; return 1; }
}

# Same awk as design-audit.sh's section_text: that script runs main on load,
# so it cannot be sourced.
section_text() {
  awk -v h="## $2" '$0==h{on=1;next} /^## /{on=0} on' "$1"
}

cmd_scaffold() {
  if [ "${1:-}" = "--in" ]; then
    [ -n "${2:-}" ] || { echo "error: scaffold --in needs <request-plan>" >&2; return 2; }
    [ -f "$2" ] || { echo "error: not found: $2" >&2; return 1; }
    cat "$UI_SECTION"
    return 0
  fi
  local slug="${1:-}" audit="" sc
  [ -n "$slug" ] || { echo "error: scaffold needs <slug> --audit <path>, or --in <file>" >&2; return 2; }
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --audit) audit="${2:-}"; shift 2 ;;
      --audit=*) audit="${1#--audit=}"; shift ;;
      *) echo "error: unknown flag: $1" >&2; return 2 ;;
    esac
  done
  [ -n "$audit" ] || { echo "error: scaffold needs --audit <path>" >&2; return 2; }
  check_audit "$audit" || return 3
  cat <<EOF
# Design plan — ${slug}

**Kind.** design
**Audit.** ${audit}

## Goal

<to-fill — the person's words, and what the screens must do>

## Screens

Copy the block once per screen. Names of tokens and components come from \`design-audit.sh discover\` only.

### Screen: <to-fill — name>

- **Address:** <to-fill — URL or typed path value>
- **Back target:** <to-fill — the screen back returns to, and the state it keeps>
- **Navigation in/out:** <to-fill — how the person arrives and leaves>
EOF
  for sc in "${SIZE_CLASSES[@]}"; do
    echo "- **${sc}:** <to-fill — layout: regions, order, what collapses or stacks>"
  done
  cat <<EOF
- **States:** <to-fill — loading, empty, error, populated, no permission>
- **Feedback per action:** <to-fill — pending, success, failure; destructive confirms>
- **Accessibility:** <to-fill — focus order, labels, contrast>
- **Visuals:** <to-fill — each data block: chart, colour code, tile or table, and why; palette from the Design source; legend>
- **Tokens and components reused:** <to-fill — names from discover; a new one needs a reason>
- **Data fields:** <to-fill — fields, contract stamp; a locked contract stops the work>

## Tokens and components

<to-fill — what is reused across screens; each new token or component with its reason>

## Data

<to-fill — entities and fields, schema owner, contract stamp and whether locked, migration file; or \`Not touched: <why>\`>

## Checks that prove it

<to-fill — evidence per screen and size class (a screenshot or a described layout); the states described>
EOF
}

# Check every "### Screen:" block: a Back target and all three size classes.
# Prints one line per problem; the count is the return value.
check_screens() {
  local f="$1" line name="" bad=0 n=0
  local seen_back=0 seen_compact=0 seen_medium=0 seen_expanded=0
  flush() {
    [ -n "$name" ] || return 0
    n=$((n + 1))
    [ "$seen_back" -eq 1 ] || { echo "screen '$name' has no Back target" >&2; bad=$((bad + 1)); }
    [ "$seen_compact" -eq 1 ] || { echo "screen '$name' is missing size class compact" >&2; bad=$((bad + 1)); }
    [ "$seen_medium" -eq 1 ] || { echo "screen '$name' is missing size class medium" >&2; bad=$((bad + 1)); }
    [ "$seen_expanded" -eq 1 ] || { echo "screen '$name' is missing size class expanded" >&2; bad=$((bad + 1)); }
  }
  while IFS= read -r line; do
    case "$line" in
      "### Screen:"*)
        flush
        name="${line#\#\#\# Screen:}"
        seen_back=0; seen_compact=0; seen_medium=0; seen_expanded=0 ;;
      "## "*) flush; name="" ;;
      "- **Back target:**"*) seen_back=1 ;;
      "- **compact:**"*) seen_compact=1 ;;
      "- **medium:**"*) seen_medium=1 ;;
      "- **expanded:**"*) seen_expanded=1 ;;
    esac
  done < "$f"
  flush
  if [ "$n" -eq 0 ]; then
    echo "no '### Screen:' block: a design plan covers at least one screen" >&2
    bad=$((bad + 1))
  fi
  [ "$bad" -gt 0 ] && return 1
  return 0
}

cmd_validate() {
  local f="${1:-}" bad=0 sec ap unfilled
  [ -n "$f" ] || { echo "error: validate needs <file>" >&2; return 2; }
  [ -f "$f" ] || { echo "error: validate target not found: $f" >&2; return 1; }
  if grep -qx '\*\*Kind\.\*\* design' "$f"; then
    ap="$(sed -n 's/^\*\*Audit\.\*\* *//p' "$f" | head -1)"
    case "$ap" in
      ""|*"<to-fill"*) echo "missing header: **Audit.** <path>" >&2; bad=$((bad + 1)) ;;
      *) check_audit "$ap" || bad=$((bad + 1)) ;;
    esac
    for sec in "${DESIGN_PLAN_SECTIONS[@]}"; do
      grep -qxF "## ${sec}" "$f" || { echo "missing section: ${sec}" >&2; bad=$((bad + 1)); }
    done
    check_screens "$f" || bad=$((bad + 1))
    unfilled="$(grep -c '<to-fill' "$f")" || unfilled=0
  elif grep -qx '\*\*Kind\.\*\* request' "$f"; then
    grep -qxF "## UI/UX and screens" "$f" || { echo "missing section: UI/UX and screens" >&2; bad=$((bad + 1)); }
    unfilled="$(section_text "$f" "UI/UX and screens" | grep -c '<to-fill')" || unfilled=0
  else
    echo "error: no '**Kind.** design' or '**Kind.** request' line in $f" >&2
    return 3
  fi
  if [ "${unfilled:-0}" -gt 0 ]; then
    echo "${unfilled} <to-fill> placeholder(s) remaining" >&2
    bad=$((bad + 1))
  fi
  [ "$bad" -eq 0 ] || return 3
  echo "ok"
}

main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    -h|--help|help|"") usage ;;
    scaffold) cmd_scaffold "$@" ;;
    validate) cmd_validate "$@" ;;
    *) echo "error: unknown action: $action" >&2; usage >&2; return 2 ;;
  esac
}

main "$@"
