#!/usr/bin/env bash
# release.sh — the release plan and the release archive.
#
# Owns the deterministic mechanics of tasks/RELEASES.md so the skills can
# stay prose. Per content/script-craft.md, the script owns parsing and
# rewriting; SKILL.md owns judgement.
#
# TWO LAYERS, AND THE WHOLE POINT IS THAT THEY ARE SEPARATE SECTIONS
#
#   ### Targeted   fluid. Any task status. Freely moved between releases.
#                  NEVER read by /release. Cannot ship by accident.
#   ### Bundled    committed. Requires tasks/completed/<ID>-*.md.
#                  This is the release manifest.
#
# Separate sections, not two labels on one list: that is what makes the
# ship-time logic structurally unable to touch the fluid layer.
#
# WHY THIS FILE EXISTS AT ALL
#
# The tracker was broken on install in two independent ways. The seed
# shipped a forward-looking 📋 Planned grammar; release-rules.md said that
# state "is gone" and specified a 🚧 Next accumulator. So /release-add hit
# "the file is in an unexpected shape" on its FIRST run in every fresh
# project — and /peer-review shipped a workaround that downgraded it to a
# non-blocking note, so nothing was ever tracked and nobody saw an error.
# The seed's `{{NEXT}}` placeholder was never substituted either.
#
# Verbs:
#   release.sh check                     validate; 0 clean, 3 drift
#   release.sh manifest <version>        print the bundled bullets
#   release.sh list                      render the plan
#   release.sh state <version>           print Planned | Next | Shipped
#   release.sh find <ID>                 where an id sits
#   release.sh create <version> [--theme T] [--target D]
#   release.sh target <ID> <version> [--title T]
#   release.sh untarget <ID>
#   release.sh bundle <ID> <version> [--title T] [--approved-by WHO]
#   release.sh ship <version> --tag T --sha S [--date D]
#
# Exit: 0 ok · 1 error · 2 usage · 3 drift/refused
#
# Portability: bash 3.2 (stock macOS). awk for parsing; no python3.

set -euo pipefail

GLYPH_PLANNED='📋'
GLYPH_NEXT='🚧'
GLYPH_SHIPPED='✅'

repo_root() {
  local d
  if d="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$d"; return 0
  fi
  echo "error: not inside a git repo" >&2; return 1
}
ROOT="$(repo_root)" || exit 1
LEDGER="$ROOT/tasks/RELEASES.md"

# Every read strips CR. A CRLF file otherwise matches no heading and the
# whole tracker silently reads as empty.
ledger_text() { tr -d '\r' < "$LEDGER"; }

require_ledger() {
  [ -f "$LEDGER" ] && return 0
  echo "error: $LEDGER does not exist." >&2
  echo "       Create a release with: /release-plan v<X.Y.Z>" >&2
  return 1
}

# An id is matched as a WHOLE token. `grep TASK-018` also matches
# TASK-018a, and roadmap/SKILL.md mandates letter suffixes, so a naive
# match silently moves the wrong task.
id_bullet_re() { printf -- '^- %s — ' "$1"; }

valid_version() {
  case "$1" in
    v[0-9]*.[0-9]*.[0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

valid_id() {
  case "$1" in
    TASK-[0-9]*|HOTFIX-[0-9]*|phase-[0-9]*|Phase\ [0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------------ read

# Print the body of one release section (everything under its heading).
section_body() {
  local version="$1"
  ledger_text | awk -v v="## $version " '
    index($0, v) == 1 { inside = 1; next }
    /^## v/          { if (inside) exit }
    inside           { print }
  '
}

# Print the bullets under one subsection of one release.
subsection() {
  local version="$1" want_sub="$2"
  section_body "$version" | awk -v s="### $want_sub" '
    $0 == s   { inside = 1; next }
    /^### /   { if (inside) exit }
    /^## /    { if (inside) exit }
    inside && /^- / { print }
  '
}

cmd_manifest() {
  require_ledger || return 1
  local version="$1"
  grep -q "^## $version " <<EOF2 || { echo "error: no release $version in $LEDGER" >&2; return 1; }
$(ledger_text)
EOF2
  subsection "$version" "Bundled"
}

cmd_state() {
  require_ledger || return 1
  local line
  line="$(ledger_text | grep "^## $1 " || true)"
  [ -n "$line" ] || { echo "error: no release $1" >&2; return 1; }
  case "$line" in
    *"$GLYPH_SHIPPED"*) echo "Shipped" ;;
    *"$GLYPH_NEXT"*)    echo "Next" ;;
    *"$GLYPH_PLANNED"*) echo "Planned" ;;
    *)                  echo "unknown" ;;
  esac
}

cmd_find() {
  require_ledger || return 1
  local id="$1" v found=0
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    if subsection "$v" "Bundled" | grep -q "$(id_bullet_re "$id")"; then
      printf '%s\tbundled\n' "$v"; found=1
    elif subsection "$v" "Targeted" | grep -q "$(id_bullet_re "$id")"; then
      printf '%s\ttargeted\n' "$v"; found=1
    fi
  done < <(ledger_text | sed -n 's/^## \(v[0-9][^ ]*\) .*/\1/p')
  [ "$found" -eq 1 ] || { echo "(not in any release)"; return 3; }
}

cmd_list() {
  require_ledger || return 1
  local v state t b
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    state="$(cmd_state "$v")"
    t="$(subsection "$v" "Targeted" | grep -c . || true)"
    b="$(subsection "$v" "Bundled" | grep -c . || true)"
    printf '%-12s %-8s  targeted:%-3s bundled:%-3s %s\n' \
      "$v" "$state" "${t:-0}" "${b:-0}" \
      "$(section_body "$v" | sed -n 's/^\*\*Theme\.\*\* //p' | head -1)"
  done < <(ledger_text | sed -n 's/^## \(v[0-9][^ ]*\) .*/\1/p')
}

# ----------------------------------------------------------------- check
cmd_check() {
  local findings=0 warnings=0
  if [ ! -f "$LEDGER" ]; then
    echo "no tasks/RELEASES.md yet — nothing to check."
    return 0
  fi
  local text; text="$(ledger_text)"

  # Legacy tracker: the pre-v0.48.0 file, which never worked.
  if printf '%s' "$text" | grep -q '{{NEXT}}' \
     || printf '%s' "$text" | grep -q 'scope declared, not yet building toward it'; then
    echo "✗ tasks/RELEASES.md is the pre-v0.48.0 tracker (never worked; see CHANGELOG v0.48.0)." >&2
    echo "    mv tasks/RELEASES.md tasks/RELEASES.legacy.md" >&2
    echo "    then start the new one with: /release-plan v<X.Y.Z>" >&2
    echo "  Nothing is rewritten automatically — your history stays intact and readable." >&2
    return 3
  fi

  local versions; versions="$(printf '%s' "$text" | sed -n 's/^## \(v[0-9][^ ]*\) .*/\1/p')"

  # Duplicate versions.
  local dupes
  dupes="$(printf '%s\n' "$versions" | sort | uniq -d | grep -c . || true)"
  if [ "${dupes:-0}" -gt 0 ]; then
    echo "✗ duplicate release heading(s):" >&2
    printf '%s\n' "$versions" | sort | uniq -d | sed 's/^/    /' >&2
    findings=$(( findings + 1 ))
  fi

  local v state seen_ids="" id
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    valid_version "$v" || {
      echo "✗ $v is not a v<semver> heading" >&2; findings=$(( findings + 1 )); }
    state="$(cmd_state "$v" 2>/dev/null || echo unknown)"
    if [ "$state" = "unknown" ]; then
      echo "✗ $v has no state glyph (expected $GLYPH_PLANNED / $GLYPH_NEXT / $GLYPH_SHIPPED)" >&2
      findings=$(( findings + 1 ))
    fi

    # A shipped release must record how it shipped.
    if [ "$state" = "Shipped" ]; then
      section_body "$v" | grep -q '^\*\*Shipped\.\*\*' || {
        echo "✗ $v is $GLYPH_SHIPPED but has no **Shipped.** line (date · tag · sha)" >&2
        findings=$(( findings + 1 )); }
      section_body "$v" | grep -q '^\*\*Approved\.\*\*' || {
        echo "✗ $v is $GLYPH_SHIPPED but has no **Approved.** line" >&2
        findings=$(( findings + 1 )); }
      # Tag presence depends on fetch state in a fresh clone — warn only.
      local tag
      tag="$(section_body "$v" | sed -n 's/.*tag `\([^`]*\)`.*/\1/p' | head -1)"
      if [ -n "$tag" ] && ! git -C "$ROOT" rev-parse -q --verify "$tag^{}" >/dev/null 2>&1; then
        echo "  ⚠ $v names tag $tag, which does not resolve here (fetch state?)" >&2
        warnings=$(( warnings + 1 ))
      fi
    fi

    # 🚧 means "has bundled work" — it is derived, not declared.
    local nb
    nb="$(subsection "$v" "Bundled" | grep -c . || true)"
    if [ "$state" = "Next" ] && [ "${nb:-0}" -eq 0 ]; then
      echo "✗ $v is $GLYPH_NEXT but has nothing bundled — $GLYPH_NEXT is derived from bundled work" >&2
      findings=$(( findings + 1 ))
    fi
    if [ "$state" = "Planned" ] && [ "${nb:-0}" -gt 0 ]; then
      echo "✗ $v is $GLYPH_PLANNED but has bundled work — it should be $GLYPH_NEXT" >&2
      findings=$(( findings + 1 ))
    fi

    # An id may appear once, in one layer, across the whole file.
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      case " $seen_ids " in
        *" $id "*)
          echo "✗ $id appears more than once (see $v)" >&2
          findings=$(( findings + 1 )) ;;
        *) seen_ids="$seen_ids $id" ;;
      esac
    done < <({ subsection "$v" "Targeted"; subsection "$v" "Bundled"; } \
               | sed -n 's/^- \([A-Za-z][A-Za-z0-9 -]*[0-9]\) — .*/\1/p')
  done < <(printf '%s\n' "$versions")

  # More than one open accumulator is legal but worth naming.
  local opens
  opens="$(printf '%s' "$text" | grep -c "^## v.*$GLYPH_NEXT" || true)"
  if [ "${opens:-0}" -gt 1 ]; then
    echo "  ⚠ $opens releases are $GLYPH_NEXT — /release will ask which one." >&2
    warnings=$(( warnings + 1 ))
  fi

  echo ""
  [ "${warnings:-0}" -gt 0 ] && echo "$warnings warning(s)."
  if [ "$findings" -gt 0 ]; then
    echo "release.sh check: $findings finding(s) in tasks/RELEASES.md." >&2
    return 3
  fi
  echo "release.sh check: tasks/RELEASES.md is well-formed."
  return 0
}

# ----------------------------------------------------------------- write
# Every mutation writes through a temp file and moves it into place, so an
# interrupted run cannot leave a half-written tracker.
replace_ledger() { mv "$1" "$LEDGER"; }

cmd_create() {
  local version="$1"; shift
  local theme="" target="next"
  while [ $# -gt 0 ]; do
    case "$1" in
      --theme)  theme="${2:-}"; shift 2 ;;
      --target) target="${2:-}"; shift 2 ;;
      *) echo "error: unknown arg: $1" >&2; return 2 ;;
    esac
  done
  valid_version "$version" || { echo "error: '$version' is not v<semver>" >&2; return 2; }

  mkdir -p "$ROOT/tasks"
  if [ ! -f "$LEDGER" ]; then
    { echo "# Releases"; echo ""
      echo "The release plan and the release archive. One section per release,"
      echo "newest first."; echo ""
      echo "- \`/release-plan\` creates a release and targets phases/tasks at it."
      echo "- \`/release-add\` bundles completed work into one."
      echo "- \`/release\` ships it and stamps this file."; echo ""
      echo "States: $GLYPH_PLANNED Planned · $GLYPH_NEXT Next (has bundled work) · $GLYPH_SHIPPED Shipped."
      echo "Format reference: \`.claude/release-rules.md\`."
      echo "Validate with \`.claude/skills/release/release.sh check\`."; echo ""
    } > "$LEDGER"
  fi

  if ledger_text | grep -q "^## $version "; then
    echo "error: $version already has an entry" >&2; return 3
  fi

  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/rel.XXXXXX")"
  awk -v ver="$version" -v glyph="$GLYPH_PLANNED" -v theme="$theme" -v target="$target" '
    BEGIN { placed = 0 }
    /^## v/ && !placed {
      print "## " ver " — " glyph " Planned"
      print ""
      if (theme != "") print "**Theme.** " theme
      print "**Target.** " target
      print ""
      print "### Targeted"
      print "_(nothing yet)_"
      print ""
      print "### Bundled"
      print "_(nothing yet)_"
      print ""
      placed = 1
    }
    { print }
    END {
      if (!placed) {
        print "## " ver " — " glyph " Planned"
        print ""
        if (theme != "") print "**Theme.** " theme
        print "**Target.** " target
        print ""
        print "### Targeted"
        print "_(nothing yet)_"
        print ""
        print "### Bundled"
        print "_(nothing yet)_"
      }
    }
  ' < <(ledger_text) > "$tmp"
  replace_ledger "$tmp"
  echo "created $version ($GLYPH_PLANNED Planned)"
}

# Add a bullet under <version>/<sub>, first removing the id from the given
# layers of every release so an id can never appear twice.
_place() {
  local id="$1" title="$2" version="$3" want_sub="$4" strip_sub="$5"
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/rel.XXXXXX")"
  # NOTE: the awk variable is `want`, not `sub` — `sub` is a reserved awk
  # FUNCTION name and BSD awk rejects it as a variable outright.
  #
  # The bullet is APPENDED at the end of its section, not inserted after
  # the heading: release-add/SKILL.md keeps merge order, and a manifest
  # that reads backwards is a manifest people stop trusting.
  awk -v id="$id" -v title="$title" -v ver="## $version " -v want="### $want_sub" \
      -v strip="$strip_sub" '
    function is_target_line(l) { return index(l, "- " id " — ") == 1 }
    function flush_pending() {
      if (insub && !placed) { print "- " id " — " title; placed = 1 }
    }
    BEGIN { inver = 0; insub = 0; instrip = 0; placed = 0 }
    {
      line = $0
      if (index(line, "## ") == 1 || index(line, "### ") == 1) {
        # Leaving a section: emit the pending bullet before the next heading.
        flush_pending()
        if (index(line, "## v") == 1) { inver = (index(line, ver) == 1); insub = 0; instrip = 0 }
        else {
          insub   = (inver && line == want)
          instrip = (line == "### " strip || (strip == "both" && (line == "### Targeted" || line == "### Bundled")))
        }
        print line
        next
      }
      if (instrip && is_target_line(line)) next
      if (insub && line == "_(nothing yet)_") next
      print line
    }
    END { flush_pending() }
  ' < <(ledger_text) > "$tmp"
  replace_ledger "$tmp"
  # Restore a placeholder in any layer we emptied.
  _reflow
}

# A section with no bullets gets its placeholder back, so the file always
# reads cleanly and `check` has an unambiguous empty state.
_reflow() {
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/rel.XXXXXX")"
  awk '
    BEGIN { n = 0 }
    { buf[n++] = $0 }
    END {
      for (i = 0; i < n; i++) {
        # Exactly one blank line before a heading (never at the top).
        if ((index(buf[i], "## ") == 1 || index(buf[i], "### ") == 1) && i > 0) {
          if (buf[i-1] != "") print ""
        }
        # Never a blank line directly under a section heading.
        if (i > 0 && buf[i] == "" && index(buf[i-1], "### ") == 1) continue
        print buf[i]
        if (buf[i] == "### Targeted" || buf[i] == "### Bundled") {
          # look ahead for a bullet before the next heading
          has = 0
          for (j = i + 1; j < n; j++) {
            if (index(buf[j], "### ") == 1 || index(buf[j], "## ") == 1) break
            if (index(buf[j], "- ") == 1) { has = 1; break }
            if (buf[j] == "_(nothing yet)_") { has = 1; break }
          }
          if (!has) print "_(nothing yet)_"
        }
      }
    }
  ' < "$LEDGER" > "$tmp"
  replace_ledger "$tmp"
}

cmd_target() {
  require_ledger || return 1
  local id="$1" version="$2"; shift 2
  local title=""
  while [ $# -gt 0 ]; do
    case "$1" in --title) title="${2:-}"; shift 2 ;; *) shift ;; esac
  done
  valid_id "$id" || { echo "error: '$id' is not a TASK-/HOTFIX-/Phase id" >&2; return 2; }
  ledger_text | grep -q "^## $version " || { echo "error: no release $version" >&2; return 1; }
  [ "$(cmd_state "$version")" = "Shipped" ] && {
    echo "error: $version is already shipped — a shipped release is frozen" >&2; return 3; }

  # Bundled work moves with /release-add, not here.
  local where; where="$(cmd_find "$id" 2>/dev/null || true)"
  case "$where" in
    *bundled*)
      echo "error: $id is bundled into ${where%%	*} — run /release-add to move it, or unbundle first" >&2
      return 3 ;;
  esac

  [ -n "$title" ] || title="$(_title_for "$id")"
  _place "$id" "$title" "$version" "Targeted" "Targeted"
  echo "targeted $id → $version"
}

cmd_untarget() {
  require_ledger || return 1
  local id="$1"
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/rel.XXXXXX")"
  awk -v id="$id" '
    BEGIN { instrip = 0 }
    {
      if (index($0, "### ") == 1) instrip = ($0 == "### Targeted")
      if (instrip && index($0, "- " id " — ") == 1) next
      print
    }
  ' < <(ledger_text) > "$tmp"
  replace_ledger "$tmp"; _reflow
  echo "untargeted $id"
}

cmd_bundle() {
  require_ledger || return 1
  local id="$1" version="$2"; shift 2
  local title="" approved_by=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --title)       title="${2:-}"; shift 2 ;;
      --approved-by) approved_by="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  ledger_text | grep -q "^## $version " || { echo "error: no release $version" >&2; return 1; }

  # Idempotent FIRST: re-bundling what is already there is a no-op, per
  # release-add's long-standing contract — including on a shipped release,
  # where the honest answer is "yes, it is in there", not an error.
  if subsection "$version" "Bundled" | grep -q "$(id_bullet_re "$id")"; then
    echo "already bundled: $id in $version"; return 0
  fi

  [ "$(cmd_state "$version")" = "Shipped" ] && {
    echo "error: $version is already shipped — a shipped release is frozen" >&2; return 3; }

  # THE COMPLETION GATE. Only completed work is bundled — the directory
  # decides, because task-rules.md calls status and directory "the same
  # fact recorded twice" and a mismatch a bug to fix, not a tiebreak.
  #
  # It lives here rather than only in the skill so that no caller can
  # forget it. /release-add does the active/->completed/ move first when
  # git proves the merge; by the time it calls bundle, this passes.
  #
  # A `Phase N` bullet has no task file and is gated by its members
  # instead — the caller checks ROADMAP membership.
  case "$id" in
    Phase\ *|phase-*) ;;
    *)
      if ! find "$ROOT/tasks/completed" -name "$id-*.md" 2>/dev/null | grep -q .; then
        echo "✗ $id is not completed — only completed work is bundled into a release." >&2
        local elsewhere
        elsewhere="$(find "$ROOT/tasks" -name "$id-*.md" 2>/dev/null | head -1 || true)"
        if [ -n "$elsewhere" ]; then
          echo "  it is at: ${elsewhere#$ROOT/}" >&2
          echo "  if the work is merged:" >&2
          echo "      git mv ${elsewhere#$ROOT/} tasks/completed/    # then set status: completed" >&2
        else
          echo "  no spec file found under tasks/ for $id." >&2
        fi
        return 3
      fi ;;
  esac

  [ -n "$title" ] || title="$(_title_for "$id")"
  # Clears the id from BOTH layers everywhere, then writes it into Bundled.
  _place "$id" "$title" "$version" "Bundled" "both"

  # 🚧 is derived from having bundled work.
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/rel.XXXXXX")"
  sed "s/^## $version — $GLYPH_PLANNED Planned$/## $version — $GLYPH_NEXT Next/" \
    < "$LEDGER" > "$tmp"; replace_ledger "$tmp"

  # Approval is recorded once per release. Invocation IS the approval —
  # the same token the deploy ledger writes, so a grep joins them.
  if ! section_body "$version" | grep -q '^\*\*Approved\.\*\*'; then
    [ -n "$approved_by" ] || approved_by="$(whoami)"
    tmp="$(mktemp "${TMPDIR:-/tmp}/rel.XXXXXX")"
    awk -v ver="## $version " -v who="$approved_by" '
      { print }
      index($0, ver) == 1 { pend = 1; next_blank = 1 }
      pend && /^\*\*Target\.\*\*/ { print "**Approved.** " who " via invocation"; pend = 0 }
    ' < <(ledger_text) > "$tmp"
    replace_ledger "$tmp"
  fi
  echo "bundled $id → $version"
}

cmd_ship() {
  require_ledger || return 1
  local version="$1"; shift
  local tag="" sha="" date=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --tag)  tag="${2:-}"; shift 2 ;;
      --sha)  sha="${2:-}"; shift 2 ;;
      --date) date="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$tag" ] || { echo "error: ship needs --tag" >&2; return 2; }
  [ -n "$sha" ] || sha="$(git -C "$ROOT" rev-parse --short HEAD)"
  [ -n "$date" ] || date="$(date -u '+%Y-%m-%d')"
  [ "$(cmd_state "$version")" = "Shipped" ] && {
    echo "error: $version is already shipped" >&2; return 3; }
  local nb; nb="$(subsection "$version" "Bundled" | grep -c . || true)"
  [ "${nb:-0}" -gt 0 ] || {
    echo "error: $version has nothing bundled — a release with an empty manifest is not a release" >&2
    return 3; }

  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/rel.XXXXXX")"
  awk -v ver="## $version " -v g_ship="$GLYPH_SHIPPED" -v stamp="**Shipped.** $date · tag \`$tag\` · sha $sha" '
    BEGIN { inver = 0 }
    {
      line = $0
      if (index(line, "## v") == 1) inver = (index(line, ver) == 1)
      if (inver && index(line, "## v") == 1) {
        sub(/ — .* /, " — " g_ship " ", line); sub(/ — .*$/, " — " g_ship " Shipped", line)
        print line; next
      }
      # A shipped release keeps no fluid layer: targets drain to the next
      # open release by hand, they do not ride along silently.
      if (inver && line == "**Target.**") next
      if (inver && index(line, "**Target.**") == 1) { print stamp; next }
      print line
    }
  ' < <(ledger_text) > "$tmp"
  replace_ledger "$tmp"; _reflow
  echo "shipped $version ($tag)"
}

# Title lookup: completed → active → backlog → triage, else a placeholder.
_title_for() {
  local id="$1" f
  for d in completed active blocked backlog triage; do
    f="$(find "$ROOT/tasks/$d" -name "$id-*.md" 2>/dev/null | head -1 || true)"
    if [ -n "$f" ]; then
      sed -n 's/^# [A-Za-z-]*-[0-9]*: *//p' "$f" | head -1 && return 0
    fi
  done
  printf '<title from spec — fill in later>\n'
}

usage() { sed -n '3,45p' "$0" | sed 's/^# \{0,1\}//'; }

main() {
  local action="${1:-}"; [ $# -gt 0 ] && shift
  case "$action" in
    check)    cmd_check ;;
    manifest) [ $# -ge 1 ] || { echo "error: manifest needs <version>" >&2; return 2; }; cmd_manifest "$1" ;;
    list)     cmd_list ;;
    state)    [ $# -ge 1 ] || { echo "error: state needs <version>" >&2; return 2; }; cmd_state "$1" ;;
    find)     [ $# -ge 1 ] || { echo "error: find needs <ID>" >&2; return 2; }; cmd_find "$1" ;;
    create)   [ $# -ge 1 ] || { echo "error: create needs <version>" >&2; return 2; }; cmd_create "$@" ;;
    target)   [ $# -ge 2 ] || { echo "error: target needs <ID> <version>" >&2; return 2; }; cmd_target "$@" ;;
    untarget) [ $# -ge 1 ] || { echo "error: untarget needs <ID>" >&2; return 2; }; cmd_untarget "$1" ;;
    bundle)   [ $# -ge 2 ] || { echo "error: bundle needs <ID> <version>" >&2; return 2; }; cmd_bundle "$@" ;;
    ship)     [ $# -ge 1 ] || { echo "error: ship needs <version>" >&2; return 2; }; cmd_ship "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "error: unknown action: $action" >&2; usage >&2; return 2 ;;
  esac
}

main "$@"
