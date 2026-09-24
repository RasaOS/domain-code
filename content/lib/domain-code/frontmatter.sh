#!/usr/bin/env bash
# frontmatter.sh — the ONE reader/writer for record files, and the ONE actor.
#
# Every ledger this Element writes (deploy and env-transfer records, run
# records, task stamps, contract stamps, env-var stamps, the release tracker)
# is a markdown file that opens with a `---` block. Before 0.54.0 each script
# carried its own awk for it, and they disagreed. Three defect classes:
#   W1  a trailing space on the closing fence: writers never saw the close and
#       rewrote body lines that looked like `key:` lines, exit 0.
#   W2  a BOM or CRLF: line 1 was never exactly `---`, so a close silently did
#       nothing (a deploy stayed in-flight, rc 0).
#   W3  a newline in a value forged keys — through a raw `echo "k: $v"`, or
#       `awk -v`, which also expands a literal `\n` into a real one.
# This file is the contract; test/frontmatter/ and bin/check-frontmatter are
# its proof, and frontmatter.py is its Python twin.
#
# Installed to .claude/lib/domain-code/. Not executable. A skill sources it
# relative to its own path — never through project-root resolution:
#
#   _rfm="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
#   [ -f "$_rfm" ] || { echo "error: the shared frontmatter library is missing — re-run the Element's bin/init" >&2; exit 70; }
#   . "$_rfm"; rfm_require 1 || exit 70
#
# bash 3.2; awk is any POSIX awk (BWK, gawk, mawk, busybox), run with LC_ALL=C
# so substr() counts bytes. Values reach awk through ENVIRON, never `awk -v`.
#
# READ contract
#   R1  one UTF-8 BOM on line 1 and one CR at the end of any line are ignored.
#   R2  the opening fence is line 1: `---` then only blanks. Anything else on
#       line 1 means the file has NO frontmatter — a later `---` is body.
#   R3  the block ends at the next fence line. No closing fence = malformed.
#   R4  a key is a column-0 `KEY:` (blanks allowed before the colon), matched
#       literally, never as a regex. The FIRST occurrence wins.
#   R5  a value is the rest of the line, blanks trimmed at both ends. rfm_get
#       returns it verbatim — `#` is a literal character, as in
#       .claude/task-rules.md. rfm_get_scalar is the older convention some
#       stamps were written in: it unquotes and drops a ` # comment`.
#   rc  0 found · 1 key absent · 2 usage · 3 no/malformed frontmatter · 4 unreadable
#
# WRITE contract
#   V1  a value may not contain CR, LF, NUL or any other control character,
#       and may not begin or end with a blank (a reader would trim it): the
#       writers refuse it (rc 2) before touching anything. rfm_clean turns
#       free text into an acceptable single line.
#   V2  values are written VERBATIM, never quoted — the bytes a record held
#       before 0.54.0 are the bytes it holds after. (A value YAML would
#       misread, such as one containing `: `, is written as-is, exactly as
#       every writer here always has. Quoting is a separate, later release.)
#   V3  rfm_set upserts: it rewrites the first matching line or inserts the
#       key before the closing fence; it refuses a key that occurs twice.
#   V4  every byte it does not mean to change is preserved (BOM, CRLF, body,
#       file mode).
#   V5  a write is a same-directory temp file, checked, renamed, read back.
#       A refusal or failure before the rename leaves the file untouched and
#       returns non-zero — a caller must never print success after a failed
#       write.

[ -n "${RFM_LIB_VERSION:-}" ] && return 0
RFM_LIB_VERSION=1
RFM_BOM="$(printf '\357\273\277')"; export RFM_BOM

# rfm_require <n> — a caller asserts the lib it sourced is new enough.
rfm_require() {
  [ "${RFM_LIB_VERSION:-0}" -ge "${1:-1}" ] 2>/dev/null && return 0
  echo "error: .claude/lib/domain-code/frontmatter.sh is v${RFM_LIB_VERSION:-?}, need v$1 — re-run the Element's bin/init" >&2
  return 70
}

# ── values ───────────────────────────────────────────────────────────────────
# rfm_value_ok <value> — V1. Returns 1 for a control character, 3 for a
# leading or trailing blank.
rfm_value_ok() {
  case "$1" in *[[:cntrl:]]*) return 1 ;; esac
  case "$1" in ' '*|*' ') return 3 ;; esac
  return 0
}

rfm_key_ok() {
  case "$1" in
    ''|[!A-Za-z_]*|*[!A-Za-z0-9_.-]*) return 1 ;;
  esac
  return 0
}

# _rfm_refuse <key> <where> <value> — one message per V1 failure; rc 2.
_rfm_refuse() {
  local why="a newline or control character"
  rfm_value_ok "$3" || [ $? -ne 3 ] || why="a leading or trailing blank, which a reader would drop"
  echo "error: refusing to write '$1'$2 — its value contains $why" >&2
  return 2
}

# rfm_clean <text> — free text to one acceptable line: CR/LF/TAB runs become
# one space, other control characters are dropped, the ends are trimmed.
rfm_clean() {
  printf '%s' "$1" | tr '\r\n\t' '   ' | LC_ALL=C tr -d '\000-\037\177' \
    | sed 's/  */ /g; s/^ //; s/ $//'
}

# ── the shared awk preamble ─────────────────────────────────────────────────
# `line` is $0 normalised for matching (R1); `raw` is what a writer prints;
# `cr` is the line's own EOL so an inserted line matches its neighbours (V4).
RFM_AWK='
  { raw = $0; line = $0
    if (NR == 1 && substr(line, 1, 3) == ENVIRON["RFM_BOM"]) line = substr(line, 4)
    cr = ""; if (line ~ /\r$/) { cr = "\r"; sub(/\r$/, "", line) } }
  function is_fence(l) { return l ~ /^---[ \t]*$/ }
  function key_is(l, k,   r) {
    if (substr(l, 1, length(k)) != k) return 0
    r = substr(l, length(k) + 1)
    return (r ~ /^[ \t]*:/)
  }
  function value_of(l) { sub(/^[^:]*:[ \t]*/, "", l); sub(/[ \t]+$/, "", l); return l }
'

_rfm_readable() {
  [ -f "$1" ] && [ -r "$1" ] && return 0
  echo "error: cannot read $1" >&2
  return 4
}

# ── readers ──────────────────────────────────────────────────────────────────
# rfm_block <file> — the normalised frontmatter lines, fences excluded.
rfm_block() {
  _rfm_readable "$1" || return 4
  LC_ALL=C awk "$RFM_AWK"'
    NR == 1 { if (!is_fence(line)) exit 3; open = 1; next }
    open && is_fence(line) { closed = 1; exit }
    open { buf = buf line "\n" }
    END { if (!closed) exit 3; printf "%s", buf }
  ' "$1"
}

rfm_has() { rfm_block "$1" >/dev/null 2>&1; }

# rfm_get <file> <key> — the value, verbatim (R5).
rfm_get() {
  rfm_key_ok "${2:-}" || { echo "error: rfm_get: bad key '${2:-}'" >&2; return 2; }
  _rfm_readable "$1" || return 4
  RFM_K="$2" LC_ALL=C awk "$RFM_AWK"'
    NR == 1 { if (!is_fence(line)) exit 3; open = 1; next }
    open && is_fence(line) { closed = 1; exit }
    open && !found && key_is(line, ENVIRON["RFM_K"]) { val = value_of(line); found = 1 }
    END { if (!closed) exit 3; if (!found) exit 1; print val }
  ' "$1"
}

# rfm_get_scalar <file> <key> — rfm_get, then the older stamp convention: a
# quoted value is unquoted (\" and \\ unescaped inside double quotes);
# otherwise a trailing ` # comment` is dropped. For readers of stamps written
# with trailing comments (`owner: unassigned   # accountable …`).
rfm_get_scalar() {
  local v rc=0
  v="$(rfm_get "$@")" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  case "$v" in
    \"*)
      v="${v#\"}"
      v="$(printf '%s' "$v" | LC_ALL=C awk '{
        out = ""; n = length($0)
        for (i = 1; i <= n; i++) {
          c = substr($0, i, 1)
          if (c == "\\" && i < n) { i++; out = out substr($0, i, 1); continue }
          if (c == "\"") break
          out = out c
        }
        printf "%s", out }')" ;;
    \'*)
      v="${v#\'}"; v="${v%%\'*}" ;;
    *)
      v="$(printf '%s' "$v" | sed 's/[ 	][ 	]*#.*$//; s/^#.*$//')" ;;
  esac
  printf '%s\n' "$v"
}

# rfm_get_child <file> <parent> <child> — one level of nesting:
#   used_by:
#     runtimes: [api]
rfm_get_child() {
  rfm_key_ok "${2:-}" && rfm_key_ok "${3:-}" || { echo "error: rfm_get_child: bad key" >&2; return 2; }
  _rfm_readable "$1" || return 4
  RFM_P="$2" RFM_C="$3" LC_ALL=C awk "$RFM_AWK"'
    NR == 1 { if (!is_fence(line)) exit 3; open = 1; next }
    open && is_fence(line) { closed = 1; exit }
    open && line ~ /^[^ \t]/ { inp = (!found && key_is(line, ENVIRON["RFM_P"])); next }
    open && inp && !found {
      l = line; sub(/^[ \t]+/, "", l)
      if (key_is(l, ENVIRON["RFM_C"])) { val = value_of(l); found = 1 }
    }
    END { if (!closed) exit 3; if (!found) exit 1; print val }
  ' "$1"
}

# rfm_body <file> — everything after the closing fence, bytes untouched. A
# file with no frontmatter is all body; a malformed block is rc 3.
rfm_body() {
  _rfm_readable "$1" || return 4
  LC_ALL=C awk "$RFM_AWK"'
    NR == 1 { if (!is_fence(line)) { nofm = 1; print raw; next } ; open = 1; next }
    nofm { print raw; next }
    open && is_fence(line) { open = 0; closed = 1; next }
    open { next }
    { print raw }
    END { if (!nofm && !closed) exit 3 }
  ' "$1"
}

# rfm_title <file> — the first `# ` heading below the frontmatter, CR-free.
rfm_title() {
  rfm_body "$1" 2>/dev/null | LC_ALL=C awk '{ sub(/\r$/, "") } /^# / { sub(/^#[ \t]+/, ""); print; exit }'
}

# ── writers ──────────────────────────────────────────────────────────────────
# rfm_line <key> <value> — one frontmatter line for a NEW record, verbatim.
# Validate every value a record needs BEFORE reserving its id or file: a
# refusal must leave nothing behind.
rfm_line() {
  rfm_key_ok "$1" || { echo "error: bad frontmatter key '$1'" >&2; return 2; }
  rfm_value_ok "$2" || { _rfm_refuse "$1" "" "$2"; return 2; }
  printf '%s: %s\n' "$1" "$2"
}

# rfm_set <file> <key> <value> [<key> <value> ...] — upsert, one rename (V3-V5).
rfm_set() {
  local file="$1"; shift
  [ $# -ge 2 ] && [ $(( $# % 2 )) -eq 0 ] || { echo "error: rfm_set: need key/value pairs" >&2; return 2; }
  _rfm_readable "$file" || return 4
  local n=0 k v
  local -a pairs keys vals
  pairs=(); keys=(); vals=()
  while [ $# -gt 0 ]; do
    k="$1"; v="$2"; shift 2
    rfm_key_ok "$k" || { echo "error: bad frontmatter key '$k'" >&2; return 2; }
    rfm_value_ok "$v" || { _rfm_refuse "$k" " to $file" "$v"; return 2; }
    n=$(( n + 1 ))
    pairs[${#pairs[@]}]="RFM_K$n=$k"
    pairs[${#pairs[@]}]="RFM_V$n=$v"
    keys[${#keys[@]}]="$k"; vals[${#vals[@]}]="$v"
  done
  local dir tmp rc=0
  dir="$(dirname "$file")"
  tmp="$(mktemp "$dir/.rfm.XXXXXX")" || { echo "error: cannot create a temp file in $dir" >&2; return 1; }
  cp -p "$file" "$tmp" 2>/dev/null || true
  env "${pairs[@]}" RFM_N="$n" LC_ALL=C awk "$RFM_AWK"'
    BEGIN { n = ENVIRON["RFM_N"] + 0
            for (i = 1; i <= n; i++) { K[i] = ENVIRON["RFM_K" i]; V[i] = ENVIRON["RFM_V" i] } }
    NR == 1 { if (!is_fence(line)) { bad = 3; exit } ; open = 1; print raw; next }
    open && is_fence(line) {
      for (i = 1; i <= n; i++) if (!done[i]) print K[i] ": " V[i] cr
      open = 0; closed = 1; print raw; next
    }
    open {
      for (i = 1; i <= n; i++) if (key_is(line, K[i])) {
        if (done[i]) { bad = 5; exit }
        print K[i] ": " V[i] cr; done[i] = 1; next
      }
    }
    { print raw }
    END { if (bad) exit bad; if (!closed) exit 3 }
  ' "$file" > "$tmp" || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$tmp"
    case "$rc" in
      3) echo "error: $file has no readable frontmatter block — nothing written" >&2 ;;
      5) echo "error: $file declares a key more than once — refusing to guess which is real; nothing written" >&2; rc=4 ;;
      *) echo "error: rewriting $file failed (rc $rc) — nothing written" >&2 ;;
    esac
    return "$rc"
  fi
  mv -f "$tmp" "$file" || { rm -f "$tmp"; echo "error: cannot replace $file" >&2; return 1; }
  # Read back: what a reader sees must be what we meant to write.
  local i=0 got
  while [ "$i" -lt "$n" ]; do
    got="$(rfm_get "$file" "${keys[$i]}")" || got="<unreadable>"
    [ "$got" = "${vals[$i]}" ] || {
      echo "error: wrote '${keys[$i]}' to $file but read back '$got'" >&2; return 1; }
    i=$(( i + 1 ))
  done
  return 0
}

# rfm_write_atomic <dest> — stdin to <dest> via a same-directory rename. For
# generated views (DEPLOYS.md, CONTRACTS.md) that are rewritten whole. Keeps
# an existing file's mode.
rfm_write_atomic() {
  local dest="$1" dir tmp
  dir="$(dirname "$dest")"
  tmp="$(mktemp "$dir/.rfm.XXXXXX")" || { echo "error: cannot create a temp file in $dir" >&2; return 1; }
  [ -f "$dest" ] && cp -p "$dest" "$tmp" 2>/dev/null
  if cat > "$tmp"; then
    mv -f "$tmp" "$dest" && return 0
  fi
  rm -f "$tmp"; echo "error: cannot write $dest" >&2; return 1
}

# ── identity ────────────────────────────────────────────────────────────────
# rasa_actor — the ONE actor-resolution order (stamps.md, "Stamp: run"):
#   RASA_ACTOR -> the clone's git user.name -> the OS user.
# Refuses (rc 2) an identity carrying a control character or longer than 128
# characters: before 0.54.0, RASA_ACTOR=$'bot\nstatus: success' made an
# in-flight deploy read as a success. Resolve it ONCE, before the first write,
# so a refusal never lands mid-edit.
rasa_actor() {
  local a="${RASA_ACTOR:-}" src="RASA_ACTOR"
  if [ -z "$a" ]; then a="$(git config user.name 2>/dev/null || true)"; src="git user.name"; fi
  if [ -z "$a" ]; then a="$(whoami 2>/dev/null || true)"; src="whoami"; fi
  if [ -z "$a" ]; then a="${USER:-unknown}"; src="USER"; fi
  case "$a" in *[[:cntrl:]]*)
    echo "error: the actor from $src contains a newline or control character — refusing to record it" >&2
    return 2 ;;
  esac
  a="$(printf '%s' "$a" | sed 's/^ *//; s/ *$//')"
  [ "${#a}" -le 128 ] || { echo "error: the actor from $src is longer than 128 characters" >&2; return 2; }
  printf '%s' "$a"
}

# rasa_actor_kind — unchanged from runs.sh 0.50.0: an agent identifies itself
# by setting RASA_ACTOR; otherwise the run is attributed to a human.
rasa_actor_kind() {
  if [ -n "${RASA_ACTOR:-}" ]; then printf 'agent'; else printf 'human'; fi
}
