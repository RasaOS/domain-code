#!/usr/bin/env bash
# design-build.sh — deterministic half of /design-build: check that every
# planned screen has evidence per size class, and take best-effort screenshots.
#
# shoot is never fatal: no browser means "skipped", exit 0. It refuses
# production, and refuses to write anywhere git does not ignore.

set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_rfm="$(cd "$_here/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
[ -f "$_rfm" ] || { echo "error: $(basename "$0"): .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; exit 70; }
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
rfm_require 1 || exit 70

ENV_SH="$_here/../environment/environment.sh"

# Reference viewport per size class, "<class>|<width>|<height>". The web
# conventions file (web-conventions.md, Screen sizes) is the source of the
# widths; a project that sets others edits this list.
declare -a SIZES=(
  "compact|375|812"
  "medium|768|1024"
  "expanded|1280|800"
)

SHOT_TIMEOUT=30          # seconds per screenshot
SHOT_MAX_BYTES=307200    # 300 KB: larger is reported, never fatal

usage() {
  cat <<'EOF'
design-build.sh — checks and screenshots for the /design-build skill.

USAGE:
  design-build.sh check <plan> [--slug <slug>]
      For every "### Screen:" block of the plan and every size class:
      evidence exists, either .claude/scratch/design/<slug>/<screen>-<class>.png
      or a non-empty described layout line "- **<class>:**" in the plan.
      Also: the plan's tokens and components slot is filled. Exit 3 lists gaps.
      <slug> defaults to the plan's file name without date and extension.

  design-build.sh shoot <url-or-file> --screen <name> [--slug <slug>] [--env <env>]
      Screenshot the three size classes to
      .claude/scratch/design/<slug>/<screen>-<class>.png. Accepts file://, an
      existing file, localhost, 127.0.0.1 and [::1]. Any other host needs
      --env <env>, and that environment must not be production.
      Seed or fixture data only. No browser: prints "screenshots: skipped
      (no browser)" and exits 0.

EXIT CODES:
  0 success (or skipped)   1 operational error   2 usage error   3 refused / gaps found
EOF
}

scratch_dir() { echo "$(rasa_root)/.claude/scratch/design/$1"; }

plan_slug() {
  local b
  b="$(basename "$1" .md)"
  printf '%s' "$b" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//'
}

safe_name() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//'; }

cmd_check() {
  local plan="${1:-}" slug="" line name="" gaps=0 dir c have
  [ -n "$plan" ] || { echo "error: check needs <plan>" >&2; return 2; }
  [ -f "$plan" ] || { echo "error: plan not found: $plan" >&2; return 1; }
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --slug) slug="${2:-}"; shift 2 ;;
      *) echo "error: unknown flag: $1" >&2; return 2 ;;
    esac
  done
  [ -n "$slug" ] || slug="$(plan_slug "$plan")"
  dir="$(scratch_dir "$slug")"

  # Per screen: collect the described layout line of each class.
  local n=0 spec cls
  local d_compact="" d_medium="" d_expanded="" tokens=""
  finish() {
    [ -n "$name" ] || return 0
    n=$((n + 1))
    local sn
    sn="$(safe_name "$name")"
    for spec in "${SIZES[@]}"; do
      cls="${spec%%|*}"
      eval "have=\$d_$cls"
      if [ -f "$dir/${sn}-${cls}.png" ]; then continue; fi
      case "$have" in
        ""|*"<to-fill"*) echo "no evidence: screen '$name' at $cls (no ${sn}-${cls}.png, no described layout)" >&2; gaps=$((gaps + 1)) ;;
      esac
    done
    case "$tokens" in
      ""|*"<to-fill"*) echo "screen '$name': Tokens and components reused is not filled" >&2; gaps=$((gaps + 1)) ;;
    esac
  }
  while IFS= read -r line; do
    case "$line" in
      "### Screen:"*)
        finish
        name="${line#\#\#\# Screen:}"; name="${name# }"
        d_compact=""; d_medium=""; d_expanded=""; tokens="" ;;
      "## "*) finish; name="" ;;
      "- **compact:**"*) d_compact="${line#*:\*\*}" ;;
      "- **medium:**"*) d_medium="${line#*:\*\*}" ;;
      "- **expanded:**"*) d_expanded="${line#*:\*\*}" ;;
      "- **Tokens and components reused:**"*) tokens="${line#*:\*\*}" ;;
    esac
  done < "$plan"
  finish
  if [ "$n" -eq 0 ]; then
    echo "no '### Screen:' block in $plan" >&2
    gaps=$((gaps + 1))
  fi
  [ "$gaps" -eq 0 ] || { echo "$gaps gap(s)" >&2; return 3; }
  echo "ok"
}

# Production refusal. file:// and loopback are allowed; anything else needs
# --env <env> naming a registered environment that is not production.
refuse_production() {
  local target="$1" envname="$2" host
  case "$target" in
    file://*) return 0 ;;
    http://*|https://*)
      host="${target#*://}"; host="${host%%/*}"; host="${host%%:*}"
      case "$host" in
        localhost|127.0.0.1|"[::1]") return 0 ;;
      esac ;;
    *) [ -f "$target" ] && return 0 ;;
  esac
  if [ -z "$envname" ]; then
    echo "refused: $target is not local. Pass --env <env> naming a non-production environment of this project (environment.sh list), or shoot a local copy." >&2
    return 3
  fi
  if [ ! -f "$ENV_SH" ]; then
    echo "refused: environment.sh is missing, cannot tell whether $envname is production" >&2
    return 3
  fi
  # prod-env lists the production environments (exit 3 when there are none).
  if bash "$ENV_SH" prod-env 2>/dev/null | grep -qxF "$envname"; then
    echo "refused: $envname is a production environment" >&2
    return 3
  fi
  bash "$ENV_SH" show "$envname" >/dev/null 2>&1 \
    || { echo "refused: $envname is not a registered environment" >&2; return 3; }
  return 0
}

# Print the browser command's name or path, or nothing.
find_browser() {
  local c
  # DESIGN_BROWSER overrides the search: a command to use, or "none".
  if [ -n "${DESIGN_BROWSER:-}" ]; then
    [ "$DESIGN_BROWSER" = "none" ] || printf '%s\n' "$DESIGN_BROWSER"
    return 0
  fi
  for c in google-chrome chromium chromium-browser chrome; do
    command -v "$c" 2>/dev/null && return 0
  done
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
           "/Applications/Chromium.app/Contents/MacOS/Chromium"; do
    [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  return 0
}

# Run a command with a wall-clock limit; macOS has no timeout(1).
with_timeout() {
  local secs="$1"; shift
  perl -e 'alarm shift; exec @ARGV or exit 127' "$secs" "$@"
}

cmd_shoot() {
  local target="${1:-}" screen="" slug="" envname="" dir out browser spec cls w h url sn size
  [ -n "$target" ] || { echo "error: shoot needs <url-or-file>" >&2; return 2; }
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --screen) screen="${2:-}"; shift 2 ;;
      --slug) slug="${2:-}"; shift 2 ;;
      --env) envname="${2:-}"; shift 2 ;;
      *) echo "error: unknown flag: $1" >&2; return 2 ;;
    esac
  done
  [ -n "$screen" ] || { echo "error: shoot needs --screen <name>" >&2; return 2; }
  [ -n "$slug" ] || slug="design"
  sn="$(safe_name "$screen")"
  refuse_production "$target" "$envname" || return 3

  dir="$(scratch_dir "$slug")"
  # Never write into a tracked path: the folder must be git-ignored.
  if ! git -C "$(rasa_root)" check-ignore -q "${dir#$(rasa_root)/}/x.png" 2>/dev/null; then
    echo "refused: ${dir#$(rasa_root)/}/ is not git-ignored. Add this line to .gitignore, then run again:" >&2
    echo ".claude/scratch/" >&2
    return 3
  fi

  browser="$(find_browser)"
  if [ -z "$browser" ]; then
    echo "screenshots: skipped (no browser). Describe the layout per size class in the plan instead."
    return 0
  fi
  case "$target" in
    http://*|https://*|file://*) url="$target" ;;
    *) url="file://$(cd "$(dirname "$target")" && pwd)/$(basename "$target")" ;;
  esac
  mkdir -p "$dir"
  for spec in "${SIZES[@]}"; do
    IFS='|' read -r cls w h <<EOT
$spec
EOT
    out="$dir/${sn}-${cls}.png"
    if with_timeout "$SHOT_TIMEOUT" "$browser" --headless --disable-gpu --hide-scrollbars \
         --window-size="${w},${h}" --screenshot="$out" "$url" >/dev/null 2>&1 && [ -s "$out" ]; then
      size="$(wc -c < "$out" | tr -d ' ')"
      echo "shot: ${out#$(rasa_root)/} (${size} bytes)"
      [ "$size" -le "$SHOT_MAX_BYTES" ] || echo "note: ${cls} PNG is over 300 KB; attach a smaller capture"
    else
      rm -f "$out"
      echo "screenshots: ${cls} failed or timed out; describe that layout in the plan"
    fi
  done
  return 0
}

main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    -h|--help|help|"") usage ;;
    check) cmd_check "$@" ;;
    shoot) cmd_shoot "$@" ;;
    *) echo "error: unknown action: $action" >&2; usage >&2; return 2 ;;
  esac
}

main "$@"
