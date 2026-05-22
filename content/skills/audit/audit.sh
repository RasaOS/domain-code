#!/usr/bin/env bash
# audit.sh — deterministic scaffolding + persistence for the /audit skill.
#
# The auditor agent (kit/agents/auditor.md) produces the judgment;
# this script handles everything mechanical: target resolution,
# library detection, scaffold rendering, validation, and persistence.
#
# Design rule: anything that might change as we learn lives in one
# of the declarative arrays at the top of this file. Add a section,
# severity tier, lens, or manifest parser by appending to its array —
# no code rewrites needed.

set -euo pipefail

# ============================================================
# CONFIG — extend these to evolve the audit shape over time.
# ============================================================

# Audit body sections in render order. Format: "<glyph> <title>".
# Add or reorder by editing this list. The auditor agent's system
# prompt should be updated to match if you add a section.
declare -a AUDIT_SECTIONS=(
  "🏗 Breakdown"
  "✅ What's working"
  "🔍 Findings"
  "⚖️ Tradeoffs worth naming"
  "❓ Open questions"
  "🎯 Bottom line"
)

# Severity tiers in render order. Append at the appropriate severity
# level. Drop tiers that go unused — the agent renders only tiers
# with content.
declare -a SEVERITY_TIERS=(
  "CRITICAL"
  "HIGH"
  "MEDIUM"
  "LOW"
)

# Supported lenses. Used by `audit.sh lenses` and the scaffold's
# Lens line. Add a new audit lens by appending here AND adding a
# stanza to the auditor agent's system prompt.
declare -a LENSES=(
  "code"
  "docs"
  "config"
  "architecture"
  "security"
  "mixed"
)

# Manifest parsers. Format: "<filename-glob>|<parser-fn-name>".
# Parser functions live further down. They emit lines in the form
# `<name>|<version>|<doc-url>`. To support a new manifest type,
# add an entry here and define the parser function.
declare -a MANIFEST_PARSERS=(
  "package.json|parse_npm_manifest"
  "requirements.txt|parse_requirements_manifest"
  "Cargo.toml|parse_cargo_manifest"
  "go.mod|parse_gomod_manifest"
  "Package.swift|parse_swift_manifest"
)

# Files / globs the scope resolver ignores. Add patterns here to
# exclude generated code, vendored deps, etc.
declare -a SCOPE_IGNORE=(
  "node_modules"
  ".git"
  "vendor"
  "dist"
  "build"
  "target"
  ".venv"
  "__pycache__"
)

# ============================================================
# Help + entry points
# ============================================================

usage() {
  cat <<'EOF'
audit.sh — scaffolding + persistence for the /audit skill.

USAGE:
  audit.sh resolve <target>
      Emit key=value scope info for the auditor agent:
        - file list (newline-separated)
        - line count total
        - libraries detected (name|version|url per line)
        - slug for filenames
        - proposed save path

  audit.sh scaffold <target> [--lens <lens>]
      Emit the audit's scaffolded markdown to stdout. The agent
      fills in <to-fill> placeholders and returns the completed
      markdown. The header, library table, and section H2s are
      script-rendered (deterministic).

  audit.sh validate <content-file>
      Check that the agent's completed scaffold has all required
      sections (per AUDIT_SECTIONS) and no remaining <to-fill>
      placeholders. Exit 0 if compliant, 3 if not (caller decides).

  audit.sh save <target> <content-file>
      Persist <content-file> to docs/audits/<YYYY-MM-DD>-<slug>.md
      (with -2, -3 collision suffixes). Echo the saved path.

  audit.sh lenses
      List supported lenses (read from LENSES at top of script).

EXIT CODES:
  0  success
  1  operational error (not in a git repo, file not found)
  2  usage error (bad flags, missing args)
  3  refused / validation failed
EOF
}

# ============================================================
# Helpers — project / repo
# ============================================================

# Worktree root — the user's current view of files. Unlike save/load
# (which use git-common-dir for project-scoped, branch-independent
# state), audit reads CODE which differs per branch / per worktree.
# Audits should reflect what the user is looking at right now.
project_root() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "error: not inside a git repo" >&2
    return 1
  }
  # Resolve symlinks physically (consistent with other kit scripts).
  ( cd -P "$top" 2>/dev/null && pwd -P )
}

# Slug from target: lowercase, alphanumeric+hyphen, kebab-case.
target_slug() {
  local raw="$1"
  echo "$raw" \
    | tr '/' '-' \
    | tr -cd 'a-zA-Z0-9-' \
    | tr 'A-Z' 'a-z' \
    | sed -E 's/^-+|-+$//g; s/-+/-/g' \
    | cut -c1-80
}

# ============================================================
# Scope resolution
# ============================================================

# Echo each in-scope file path on its own line.
enumerate_files() {
  local root="$1" target="$2"
  local fullpath="$root/$target"

  # Build a find prune expression for the ignored paths.
  local prune_expr=""
  for ig in "${SCOPE_IGNORE[@]}"; do
    if [ -n "$prune_expr" ]; then
      prune_expr="$prune_expr -o"
    fi
    prune_expr="$prune_expr -name $ig"
  done

  if [ -d "$fullpath" ]; then
    # Directory target — recurse, prune ignored, files only.
    find "$fullpath" \( $prune_expr \) -prune -o -type f -print 2>/dev/null \
      | sed "s|^$root/||"
  elif [ -f "$fullpath" ]; then
    echo "$target"
  else
    # Try as a glob from root.
    ( cd "$root" && \
      find . -path './node_modules' -prune -o \
             -path './.git' -prune -o \
             -name "$target" -type f -print 2>/dev/null \
      | sed 's|^\./||' )
  fi
}

# Sum line counts across the given files (paths relative to root).
total_lines() {
  local root="$1"
  shift
  local total=0 f
  for f in "$@"; do
    [ -f "$root/$f" ] || continue
    local n
    n="$(wc -l < "$root/$f" 2>/dev/null | tr -d ' ')"
    total=$(( total + ${n:-0} ))
  done
  echo "$total"
}

# ============================================================
# Library / manifest parsers
# ============================================================
# Each parser emits lines in the form:
#   <name>|<version>|<doc-url>
# Best-effort. Skip silently if jq/etc not available.

parse_npm_manifest() {
  local f="$1"
  command -v jq >/dev/null 2>&1 || {
    # Fallback to grep-based parse for top-level "deps" only.
    grep -E '^\s*"[^"]+":\s*"[^"]+"' "$f" 2>/dev/null \
      | sed -E 's/^\s*"([^"]+)":\s*"([^"]+)".*$/\1|\2|/' \
      | grep -v -E '^(name|version|description|main|scripts|repository|license|author|engines|keywords|homepage|bugs|files|type)\|' \
      | head -40
    return
  }
  jq -r '
    (.dependencies // {}) + (.devDependencies // {}) // {}
    | to_entries[]
    | "\(.key)|\(.value)|https://www.npmjs.com/package/\(.key)"
  ' "$f" 2>/dev/null
}

parse_requirements_manifest() {
  local f="$1"
  grep -v -E '^\s*(#|$)' "$f" 2>/dev/null \
    | sed -E 's/^([a-zA-Z0-9_.-]+)([<>=!~].*)?$/\1|\2|https:\/\/pypi.org\/project\/\1\//' \
    | sed 's/||/|unspecified|/'
}

parse_cargo_manifest() {
  local f="$1"
  # Best-effort: parse the [dependencies] section.
  awk '
    /^\[dependencies\]/ { in_deps = 1; next }
    /^\[/ { in_deps = 0 }
    in_deps && /^[a-zA-Z]/ {
      split($0, parts, "=")
      name = parts[1]
      gsub(/[[:space:]]/, "", name)
      version = parts[2]
      gsub(/[[:space:]"]/, "", version)
      print name "|" version "|https://crates.io/crates/" name
    }
  ' "$f" 2>/dev/null
}

parse_gomod_manifest() {
  local f="$1"
  awk '
    /^require / { in_req = 1; if (NF >= 3) { print $2 "|" $3 "|https://pkg.go.dev/" $2 } next }
    /^require \(/ { in_req_block = 1; next }
    in_req_block && /^\)/ { in_req_block = 0; next }
    in_req_block && NF >= 2 {
      gsub(/^[[:space:]]+/, "")
      print $1 "|" $2 "|https://pkg.go.dev/" $1
    }
  ' "$f" 2>/dev/null
}

parse_swift_manifest() {
  local f="$1"
  # Best-effort: pull package URLs and versions from .package lines.
  grep -E 'url:\s*"' "$f" 2>/dev/null \
    | sed -E 's/.*url:\s*"([^"]+)".*from:\s*"([^"]+)".*/__URL__\1|\2|\1/' \
    | grep '^__URL__' \
    | sed 's/^__URL__//' \
    | awk -F'|' '{
        split($1, parts, "/")
        name = parts[length(parts)]
        gsub(/\.git$/, "", name)
        print name "|" $2 "|" $3
      }'
}

# Detect manifests in the project and emit aggregated dependency
# lines (name|version|url).
detect_libraries() {
  local root="$1"
  local entry pattern parser found
  for entry in "${MANIFEST_PARSERS[@]}"; do
    pattern="${entry%%|*}"
    parser="${entry##*|}"
    found="$(find "$root" -maxdepth 3 -name "$pattern" \
      -not -path '*/node_modules/*' -not -path '*/vendor/*' \
      -not -path '*/.git/*' 2>/dev/null | head -3)"
    if [ -n "$found" ]; then
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        "$parser" "$f" 2>/dev/null
      done <<< "$found"
    fi
  done
}

# ============================================================
# Scaffold rendering
# ============================================================

render_scaffold() {
  local target="$1" lens="${2:-auto}"
  local root files line_count libs file_count
  root="$(project_root)" || return 1
  files="$(enumerate_files "$root" "$target" | head -50)"
  if [ -z "$files" ]; then
    file_count=0
    line_count=0
  else
    file_count="$(echo "$files" | wc -l | tr -d ' ')"
    line_count="$(total_lines "$root" $files 2>/dev/null || echo "?")"
  fi
  libs="$(detect_libraries "$root" 2>/dev/null | head -30)"

  cat <<EOF
# Audit — ${target}

> **TL;DR.** <to-fill — one specific sentence on the overall read.
> Not "looks good" — something specific. e.g. "Solid read-side,
> write-side is half-built and inconsistent across modules.">

**Target.** \`${target}\`
**Scope.** ${file_count} file(s), ~${line_count} lines
**Lens.** ${lens} <to-confirm — if auto, declare which lens(es) actually applied>
**Confidence.** <to-fill — high / mixed / low + one-line why>

EOF

  if [ -n "$libs" ]; then
    cat <<EOF
### External libraries detected in scope

| Library | Version | Docs |
|---|---|---|
EOF
    while IFS='|' read -r name version url; do
      [ -z "$name" ] && continue
      [ -z "$version" ] && version="(unspecified)"
      [ -z "$url" ] && url="—"
      echo "| \`${name}\` | \`${version}\` | [${url}](${url}) |"
    done <<< "$libs"
    echo ""
  fi

  echo "---"
  echo ""

  # Render each section H2 with a single <to-fill> placeholder below.
  # Findings gets special treatment (severity scheme is part of the contract).
  local section
  for section in "${AUDIT_SECTIONS[@]}"; do
    echo "## ${section}"
    echo ""
    if [[ "$section" == *"Findings"* ]]; then
      echo "<to-fill — render only severity tiers with findings."
      echo "If zero findings across all tiers, render \"No findings across"
      echo "all severity tiers.\" Severity scheme: $(IFS=,; echo "${SEVERITY_TIERS[*]}").>"
      echo ""
      echo "Format for each finding (inside a code fence):"
      echo ""
      echo '```'
      echo '▌ <TIER> · <path:line>'
      echo '  <what is wrong>'
      echo '  └─ <what to do about it>'
      echo '```'
    else
      echo "<to-fill>"
    fi
    echo ""
  done

  cat <<EOF
---

*Audit produced by \`auditor\` agent on $(date '+%Y-%m-%d %H:%M %Z').*
EOF
}

# ============================================================
# Validation
# ============================================================

cmd_validate() {
  local f="$1"
  if [ ! -f "$f" ]; then
    echo "error: validate target not found: $f" >&2
    return 1
  fi

  local missing=0 section
  for section in "${AUDIT_SECTIONS[@]}"; do
    if ! grep -qF "## ${section}" "$f" 2>/dev/null; then
      echo "missing section: ${section}" >&2
      missing=$(( missing + 1 ))
    fi
  done

  # Check for remaining <to-fill> placeholders (agent didn't complete).
  local unfilled
  unfilled="$(grep -c '<to-fill' "$f" 2>/dev/null || echo 0)"
  unfilled="${unfilled//$'\n'/}"
  if [ "${unfilled:-0}" -gt 0 ]; then
    echo "${unfilled} <to-fill> placeholder(s) remaining — agent did not complete" >&2
    missing=$(( missing + 1 ))
  fi

  if [ "$missing" -gt 0 ]; then
    return 3
  fi
  echo "ok"
  return 0
}

# ============================================================
# Persistence
# ============================================================

cmd_save() {
  local target="$1" content_file="$2"

  if [ ! -f "$content_file" ]; then
    echo "error: content file not found: $content_file" >&2
    return 1
  fi

  local root slug date_str dest n=2
  root="$(project_root)" || return 1
  slug="$(target_slug "$target")"
  date_str="$(date '+%Y-%m-%d')"

  local audits_dir="$root/docs/audits"
  mkdir -p "$audits_dir"

  dest="$audits_dir/${date_str}-${slug}.md"
  while [ -e "$dest" ]; do
    dest="$audits_dir/${date_str}-${slug}-${n}.md"
    n=$(( n + 1 ))
  done

  cp "$content_file" "$dest"
  # Echo the saved path relative to repo root for clean reporting.
  echo "${dest#$root/}"
}

# ============================================================
# Resolve (scope info as key=value lines)
# ============================================================

cmd_resolve() {
  local target="$1"
  local root files line_count libs slug file_count
  root="$(project_root)" || return 1
  files="$(enumerate_files "$root" "$target")"
  if [ -z "$files" ]; then
    file_count=0
    line_count=0
  else
    file_count="$(echo "$files" | wc -l | tr -d ' ')"
    line_count="$(total_lines "$root" $files 2>/dev/null || echo 0)"
  fi
  libs="$(detect_libraries "$root" 2>/dev/null)"
  slug="$(target_slug "$target")"

  echo "target=${target}"
  echo "slug=${slug}"
  echo "file_count=${file_count}"
  echo "line_count=${line_count}"
  echo "save_path=docs/audits/$(date '+%Y-%m-%d')-${slug}.md"
  echo ""
  echo "[files]"
  if [ -n "$files" ]; then echo "$files"; fi
  echo ""
  echo "[libraries]"
  if [ -n "$libs" ]; then echo "$libs"; fi
}

# ============================================================
# Main dispatch
# ============================================================

cmd_scaffold() {
  local target="$1"
  shift
  local lens="auto"
  while [ $# -gt 0 ]; do
    case "$1" in
      --lens) lens="${2:-auto}"; shift 2 ;;
      --lens=*) lens="${1#--lens=}"; shift ;;
      *) shift ;;
    esac
  done
  render_scaffold "$target" "$lens"
}

cmd_lenses() {
  local lens
  for lens in "${LENSES[@]}"; do
    echo "$lens"
  done
}

main() {
  local action="${1:-}"
  shift || true

  case "$action" in
    -h|--help|help|"") usage; return 0 ;;
  esac

  case "$action" in
    resolve)
      [ $# -ge 1 ] || { echo "error: resolve needs <target>" >&2; return 2; }
      cmd_resolve "$@"
      ;;
    scaffold)
      [ $# -ge 1 ] || { echo "error: scaffold needs <target>" >&2; return 2; }
      cmd_scaffold "$@"
      ;;
    validate)
      [ $# -ge 1 ] || { echo "error: validate needs <content-file>" >&2; return 2; }
      cmd_validate "$1"
      ;;
    save)
      [ $# -ge 2 ] || { echo "error: save needs <target> <content-file>" >&2; return 2; }
      cmd_save "$1" "$2"
      ;;
    lenses)
      cmd_lenses
      ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
