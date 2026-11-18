#!/usr/bin/env bash
# design-audit.sh — deterministic half of /design-audit: find the project's
# style sources, scaffold a design audit, validate one.
#
# Names and paths only. discover never reads a colour, spacing or type value
# and never invents a token: what it prints is what exists on disk.

set -euo pipefail

_rfm="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
[ -f "$_rfm" ] || { echo "error: $(basename "$0"): .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; exit 70; }
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
rfm_require 1 || exit 70

# Sections of a standalone design audit (`**Kind.** design`), in render order.
declare -a DESIGN_SECTIONS=(
  "Screens in scope"
  "Design source found"
  "Per size class"
  "States"
  "Interaction feedback"
  "Accessibility"
  "Data shown"
  "Visuals"
  "Uniformity"
  "Findings ranked"
  "Open questions"
)

# Chart libraries recognised in a dependency manifest. Names live here and
# nowhere in the shipped rules. Format: "<manifest>|<regex of library names>".
declare -a CHART_LIBS=(
  "package.json|\"(chart\\.js|recharts|d3|victory|echarts|apexcharts|highcharts|@nivo/[a-z]+|plotly\\.js)\""
  "requirements.txt|^(matplotlib|plotly|bokeh|altair)"
  "Package.swift|SwiftCharts|DGCharts|Charts"
)

# Directories the scan never enters.
PRUNE='-name node_modules -o -name .git -o -name vendor -o -name dist -o -name build -o -name target -o -name .venv -o -name Pods -o -name DerivedData'

usage() {
  cat <<'EOF'
design-audit.sh — scaffolding for the /design-audit skill.

USAGE:
  design-audit.sh discover
      List the project's style sources and chart libraries, one per line:
        source | path | kind | confidence
      Names and paths only. Prints "none found" and exits 0 when there are
      none. The tenant comes from develop.sh sources (its first line,
      "tenant: none" or "tenant: <path>").

  design-audit.sh scaffold <slug>
      Emit a standalone design audit (Kind design) to stdout.

  design-audit.sh scaffold --in <request-audit>
      Emit only the UI/UX block, to paste under "## UI/UX and screens" of a
      request audit. There is one block for both: audit/ui-audit-section.md.

  design-audit.sh validate <file>
      Kind design: every section present, no <to-fill> left.
      Kind request: the "UI/UX and screens" section has no <to-fill> left.
      Exit 0 if compliant, 3 if not.

EXIT CODES:
  0 success   1 operational error   2 usage error   3 validation failed
EOF
}

# One row per style source. $1=source $2=path $3=kind $4=confidence
row() { printf '%s | %s | %s | %s\n' "$1" "$2" "$3" "$4"; }

# The tenant path, from the /develop skill's sources verb. No lookup of its own.
tenant_path() {
  local dev out
  dev="$(dirname "${BASH_SOURCE[0]}")/../develop/develop.sh"
  [ -f "$dev" ] || return 0
  out="$(bash "$dev" sources 2>/dev/null | head -1)" || return 0
  case "$out" in
    "tenant: none"|"") ;;
    "tenant: "*) echo "${out#tenant: }" ;;
  esac
}

cmd_discover() {
  local root tenant found
  root="$(rasa_root)" || return 1
  found="$(
    tenant="$(tenant_path)"
    if [ -n "$tenant" ] && [ -d "$tenant/design" ]; then
      row tenant "$tenant/design/" design-dir high
    fi
    cd "$root"
    local d f
    for d in design docs/design; do
      [ -d "$d" ] && row repo "$d/" design-dir high
    done
    for f in DESIGN.md STYLEGUIDE.md; do
      [ -f "$f" ] && row repo "$f" style-doc high
    done
    # shellcheck disable=SC2086
    find . -maxdepth 5 \( $PRUNE \) -prune -o -type f \
      \( -iname 'tokens.*' -o -iname '*.tokens.json' -o -iname 'design-tokens.*' \
         -o -iname 'theme.*' -o -iname 'tailwind.config.*' -o -iname 'colors.xml' \) -print 2>/dev/null \
      | sed 's|^\./||' | sort | head -20 | while read -r f; do row repo "$f" token-file high; done
    # shellcheck disable=SC2086
    find . -maxdepth 5 \( $PRUNE \) -prune -o -type d \
      \( -name '*.xcassets' \) -print 2>/dev/null \
      | sed 's|^\./||' | sort | head -10 | while read -r f; do row repo "$f/" asset-catalog high; done
    # CSS custom properties: names the file declares, never their values.
    # shellcheck disable=SC2086
    find . -maxdepth 5 \( $PRUNE \) -prune -o -type f \( -name '*.css' -o -name '*.scss' \) -print 2>/dev/null \
      | sed 's|^\./||' | sort | head -200 | while read -r f; do
          grep -qE '(^|[{;[:space:]])--[a-zA-Z][a-zA-Z0-9-]*[[:space:]]*:' "$f" 2>/dev/null \
            && row repo "$f" css-variables medium
        done | head -10
    local spec manifest rx
    for spec in "${CHART_LIBS[@]}"; do
      manifest="${spec%%|*}"; rx="${spec#*|}"
      [ -f "$manifest" ] && grep -qE "$rx" "$manifest" 2>/dev/null && row chart-lib "$manifest" chart-library medium
    done
    true
  )"
  if [ -z "$found" ]; then
    echo "none found"
  else
    echo "$found"
  fi
}

cmd_scaffold() {
  if [ "${1:-}" = "--in" ]; then
    [ -n "${2:-}" ] || { echo "error: scaffold --in needs <request-audit>" >&2; return 2; }
    [ -f "$2" ] || { echo "error: not found: $2" >&2; return 1; }
    cat "$(dirname "${BASH_SOURCE[0]}")/../audit/ui-audit-section.md"
    return 0
  fi
  local slug="${1:-}" section
  [ -n "$slug" ] || { echo "error: scaffold needs <slug> or --in <file>" >&2; return 2; }
  cat <<EOF
# Design audit — ${slug}

**Kind.** design
**Confidence.** <to-fill — high / mixed / low + one-line why>

---

EOF
  for section in "${DESIGN_SECTIONS[@]}"; do
    echo "## ${section}"
    echo ""
    case "$section" in
      "Screens in scope")
        echo "<to-fill — one line per screen: its address and its back target>" ;;
      "Design source found")
        echo "<to-fill — paste or summarise \`design-audit.sh discover\`; \`none declared\` is an open question>" ;;
      "Per size class")
        echo "- **compact:** <to-fill — what breaks, what is cut off, what reflows>"
        echo "- **medium:** <to-fill — what breaks, what is cut off, what reflows>"
        echo "- **expanded:** <to-fill — what breaks, what is cut off, what reflows>" ;;
      "Data shown")
        echo "<to-fill — fields shown, contract stamp, locked or not; or \`Not touched: <why>\`>" ;;
      "Visuals")
        echo "<to-fill — data shown as text that reads better as a chart, colour code or tile; charts that mislead or rely on colour alone>" ;;
      "Uniformity")
        echo "<to-fill — one-off colour, spacing or type values where a token exists>" ;;
      "Findings ranked")
        echo "<to-fill — ranked, most severe first: <path:line> — what is wrong — what to do>" ;;
      *)
        echo "<to-fill>" ;;
    esac
    echo ""
  done
}

# The text of one "## " section: from its heading to the next heading.
section_text() {
  awk -v h="## $2" '$0==h{on=1;next} /^## /{on=0} on' "$1"
}

cmd_validate() {
  local f="${1:-}" missing=0 section unfilled
  [ -n "$f" ] || { echo "error: validate needs <file>" >&2; return 2; }
  [ -f "$f" ] || { echo "error: validate target not found: $f" >&2; return 1; }
  if grep -qx '\*\*Kind\.\*\* design' "$f"; then
    for section in "${DESIGN_SECTIONS[@]}"; do
      if ! grep -qxF "## ${section}" "$f"; then
        echo "missing section: ${section}" >&2
        missing=$(( missing + 1 ))
      fi
    done
    unfilled="$(grep -c '<to-fill' "$f")" || unfilled=0
  elif grep -qx '\*\*Kind\.\*\* request' "$f"; then
    if ! grep -qxF "## UI/UX and screens" "$f"; then
      echo "missing section: UI/UX and screens" >&2
      missing=$(( missing + 1 ))
    fi
    unfilled="$(section_text "$f" "UI/UX and screens" | grep -c '<to-fill')" || unfilled=0
  else
    echo "error: no '**Kind.** design' or '**Kind.** request' line in $f" >&2
    return 3
  fi
  if [ "${unfilled:-0}" -gt 0 ]; then
    echo "${unfilled} <to-fill> placeholder(s) remaining" >&2
    missing=$(( missing + 1 ))
  fi
  [ "$missing" -eq 0 ] || return 3
  echo "ok"
}

main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    -h|--help|help|"") usage ;;
    discover) cmd_discover ;;
    scaffold) cmd_scaffold "$@" ;;
    validate) cmd_validate "$@" ;;
    *) echo "error: unknown action: $action" >&2; usage >&2; return 2 ;;
  esac
}

main "$@"
