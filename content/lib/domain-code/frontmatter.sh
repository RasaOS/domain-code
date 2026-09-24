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

# The directory of the script that sourced this library, resolved NOW —
# before the script can `cd` — for rasa_root's install walk.
RFM_CALLER_DIR=""
if [ -n "${BASH_SOURCE[1]:-}" ]; then
  RFM_CALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[1]}")" 2>/dev/null && pwd -P || true)"
fi

# rfm_require <n> — a caller asserts the lib it sourced is new enough.
rfm_require() {
  [ "${RFM_LIB_VERSION:-0}" -ge "${1:-1}" ] 2>/dev/null && return 0
  echo "error: .claude/lib/domain-code/frontmatter.sh is v${RFM_LIB_VERSION:-?}, need v$1 — re-run the Element's bin/init" >&2
  return 70
}

# The temp file of a write in flight, or empty. It sits beside the record, so
# an interrupted write would leave a hidden .rfm.* in the ledger: a script
# with no traps of its own calls rfm_trap_cleanup once; one with its own traps
# calls rfm_cleanup from them.
RFM_TMP=""

# rfm_cleanup — remove the write in flight, if any. Never fails, so a trap
# can call it without changing the exit status.
rfm_cleanup() {
  if [ -n "${RFM_TMP:-}" ]; then rm -f "$RFM_TMP" "$RFM_TMP.nr" 2>/dev/null || true; fi
  RFM_TMP=""
}

rfm_trap_cleanup() {
  trap 'rfm_cleanup' EXIT
  trap 'rfm_cleanup; trap - EXIT; exit 130' INT
  trap 'rfm_cleanup; trap - EXIT; exit 143' TERM
}

# ── values ───────────────────────────────────────────────────────────────────
# rfm_value_ok <value> — V1, checked bytewise (C locale) so the verdict does
# not depend on the caller's locale. Returns 1 for a control character — C0,
# DEL, the C1 controls U+0080–U+009F (NEL among them, a line break to a
# YAML 1.1 reader) and the Unicode line and paragraph separators U+2028 and
# U+2029 — and 3 for a leading or trailing blank. Ordinary non-ASCII text
# (é, —, CJK) passes. The C1 and separator rules are the contract lock's
# (0.52.1), now every writer's.
rfm_value_ok() {
  local LC_ALL=C
  case "$1" in
    *[[:cntrl:]]*|*$'\302'[$'\200'-$'\237']*|*$'\342\200\250'*|*$'\342\200\251'*) return 1 ;;
  esac
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

# rfm_check <key> <value> — rfm_value_ok with the refusal message, rc 2. For
# callers that validate every value BEFORE reserving a record, so a refusal
# never leaves a half-written file behind.
rfm_check() { rfm_value_ok "$2" || { _rfm_refuse "$1" "" "$2"; return 2; }; }

# rfm_clean <text> — free text to one acceptable line: line breaks (CR, LF,
# NEL, U+2028, U+2029) and tabs become one space, every other control
# character (C0, DEL, C1) is dropped, runs of spaces collapse, the ends are
# trimmed. Bytewise throughout, so text after an invalid UTF-8 byte is kept
# rather than silently cut.
rfm_clean() {
  local nel ls ps c1a c1b
  nel="$(printf '\302\205')"; ls="$(printf '\342\200\250')"; ps="$(printf '\342\200\251')"
  c1a="$(printf '\302\200')"; c1b="$(printf '\302\237')"
  printf '%s' "$1" | LC_ALL=C tr '\r\n\t' '   ' | LC_ALL=C tr -d '\000-\037\177' \
    | LC_ALL=C sed "s/$nel/ /g; s/$ls/ /g; s/$ps/ /g" \
    | LC_ALL=C awk -v a="$c1a" -v b="$c1b" '{  # rfm-ok: constant byte bounds
        out = ""; n = length($0)
        for (i = 1; i <= n; i++) {
          c = substr($0, i, 2)
          if (length(c) == 2 && c >= a && c <= b) { i++; continue }
          out = out substr($0, i, 1)
        }
        printf "%s", out }' \
    | LC_ALL=C sed 's/  */ /g; s/^ //; s/ $//'
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

# rfm_get <file> <key> — the value, verbatim (R5). With RFM_STRICT=1 a key
# that occurs twice is rc 4 instead of first-wins: for a value where a
# first-wins reader and a last-wins (YAML) reader would disagree about the
# same bytes, such as the contract lock's is_locked.
rfm_get() {
  rfm_key_ok "${2:-}" || { echo "error: rfm_get: bad key '${2:-}'" >&2; return 2; }
  _rfm_readable "$1" || return 4
  RFM_K="$2" RFM_STRICT="${RFM_STRICT:-0}" LC_ALL=C awk "$RFM_AWK"'
    NR == 1 { if (!is_fence(line)) exit 3; open = 1; next }
    open && is_fence(line) { closed = 1; exit }
    open && key_is(line, ENVIRON["RFM_K"]) { if (found++) next; val = value_of(line) }
    END {
      if (!closed) exit 3
      if (!found) exit 1
      if (found > 1 && ENVIRON["RFM_STRICT"] == "1") exit 4
      print val
    }
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

# _rfm_rewrite <file> <bodyfile|""> [RFM_K1=k RFM_V1=v ...] — the one write
# path (V3-V5). awk rewrites the frontmatter ONLY and stops at the closing
# fence; the body is then copied byte-for-byte by tail — or, with a
# <bodyfile>, replaced by it after one blank line in the file's own line
# ending. (Streaming the body through awk lost everything after a NUL byte on
# BWK awk.) The temp starts as a copy of the file, so the mode survives, and a
# read-only file is written and then made read-only again. Values have been
# validated by the caller.
_rfm_rewrite() {
  local file="$1" body="$2"; shift 2
  local n=$(( $# / 2 )) dir tmp nrf ro="" rc=0 k
  dir="$(dirname "$file")"
  tmp="$(mktemp "$dir/.rfm.XXXXXX")" || { echo "error: cannot create a temp file in $dir" >&2; return 1; }
  RFM_TMP="$tmp"; nrf="$tmp.nr"
  [ "$(ls -ld "$file" | cut -c3)" = "-" ] && ro=1   # the owner write bit, not access
  cp -p "$file" "$tmp" 2>/dev/null || true
  chmod u+w "$tmp" 2>/dev/null || true
  env "$@" RFM_N="$n" RFM_NRF="$nrf" RFM_SEP="${body:+1}" LC_ALL=C awk "$RFM_AWK"'
    BEGIN { n = ENVIRON["RFM_N"] + 0
            for (i = 1; i <= n; i++) { K[i] = ENVIRON["RFM_K" i]; V[i] = ENVIRON["RFM_V" i] } }
    NR == 1 { if (!is_fence(line)) { bad = 3; exit } ; open = 1; print raw; next }
    open && is_fence(line) {
      for (i = 1; i <= n; i++) if (!done[i]) print K[i] ": " V[i] cr
      print raw
      if (ENVIRON["RFM_SEP"] == "1") printf "%s\n", cr
      f = ENVIRON["RFM_NRF"]; print NR > f; closed = 1; exit
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
  if [ "$rc" -eq 0 ]; then
    k="$(cat "$nrf" 2>/dev/null)"
    case "$k" in ''|*[!0-9]*) rc=1 ;; esac
  fi
  if [ "$rc" -eq 0 ]; then
    if [ -n "$body" ]; then cat "$body" >> "$tmp" || rc=1
    else tail -n +"$((k + 1))" "$file" >> "$tmp" || rc=1
    fi
  fi
  rm -f "$nrf"
  if [ "$rc" -ne 0 ]; then
    rm -f "$tmp"; RFM_TMP=""
    case "$rc" in
      3) echo "error: $file has no readable frontmatter block — nothing written" >&2 ;;
      5) echo "error: $file declares a key more than once — refusing to guess which is real; nothing written" >&2; rc=4 ;;
      *) echo "error: rewriting $file failed — nothing written" >&2; rc=1 ;;
    esac
    return "$rc"
  fi
  [ -z "$ro" ] || chmod u-w "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$file" || { rm -f "$tmp"; RFM_TMP=""; echo "error: cannot replace $file" >&2; return 1; }
  RFM_TMP=""
  return 0
}

# _rfm_pairs <file> <key> <value> ... — validate key/value pairs (V1) and set
# RFM_PAIRS (for env), RFM_KEYS and RFM_VALS (for the read-back). rc 2 on the
# first refusal, before anything is written. A key given twice in one call is
# refused: the rewrite would match the first and insert the second, writing
# the very duplicate V3 exists to refuse.
_rfm_pairs() {
  local file="$1" n=0 k v i; shift
  RFM_PAIRS=(); RFM_KEYS=(); RFM_VALS=()
  while [ $# -gt 0 ]; do
    k="$1"; v="${2-}"; shift 2 || { echo "error: need key/value pairs" >&2; return 2; }
    rfm_key_ok "$k" || { echo "error: bad frontmatter key '$k'" >&2; return 2; }
    i=0
    while [ "$i" -lt "${#RFM_KEYS[@]}" ]; do
      [ "${RFM_KEYS[$i]}" != "$k" ] || { echo "error: '$k' is given twice in one write to $file" >&2; return 2; }
      i=$(( i + 1 ))
    done
    rfm_value_ok "$v" || { _rfm_refuse "$k" " to $file" "$v"; return 2; }
    n=$(( n + 1 ))
    RFM_PAIRS[${#RFM_PAIRS[@]}]="RFM_K$n=$k"
    RFM_PAIRS[${#RFM_PAIRS[@]}]="RFM_V$n=$v"
    RFM_KEYS[${#RFM_KEYS[@]}]="$k"; RFM_VALS[${#RFM_VALS[@]}]="$v"
  done
}

# _rfm_readback <file> — what a reader sees must be what was meant.
_rfm_readback() {
  local i=0 got
  while [ "$i" -lt "${#RFM_KEYS[@]}" ]; do
    got="$(rfm_get "$1" "${RFM_KEYS[$i]}")" || got="<unreadable>"
    [ "$got" = "${RFM_VALS[$i]}" ] || {
      echo "error: wrote '${RFM_KEYS[$i]}' to $1 but read back '$got'" >&2; return 1; }
    i=$(( i + 1 ))
  done
}

# rfm_set <file> <key> <value> [<key> <value> ...] — upsert, one rename.
rfm_set() {
  local file="$1"; shift
  [ $# -ge 2 ] && [ $(( $# % 2 )) -eq 0 ] || { echo "error: rfm_set: need key/value pairs" >&2; return 2; }
  _rfm_readable "$file" || return 4
  _rfm_pairs "$file" "$@" || return 2
  _rfm_rewrite "$file" "" "${RFM_PAIRS[@]}" || return $?
  _rfm_readback "$file"
}

# rfm_rewrite <file> <bodyfile> [<key> <value> ...] — replace everything after
# the closing fence with <bodyfile> (one blank line after the fence) and
# upsert the keys, in ONE rename. For a stamp whose body is regenerated whole.
rfm_rewrite() {
  local file="$1" body="${2:-}"; shift 2 || { echo "error: rfm_rewrite: need <file> <bodyfile>" >&2; return 2; }
  [ -f "$body" ] || { echo "error: rfm_rewrite: no body file '$body'" >&2; return 2; }
  [ $(( $# % 2 )) -eq 0 ] || { echo "error: rfm_rewrite: need key/value pairs" >&2; return 2; }
  _rfm_readable "$file" || return 4
  if [ $# -gt 0 ]; then
    _rfm_pairs "$file" "$@" || return 2
    _rfm_rewrite "$file" "$body" "${RFM_PAIRS[@]}" || return $?
    _rfm_readback "$file"
  else
    _rfm_rewrite "$file" "$body"
  fi
}

# rfm_write_atomic <dest> — stdin to <dest> via a same-directory rename. For
# generated views (DEPLOYS.md, CONTRACTS.md) that are rewritten whole. Keeps
# an existing file's mode; a new file gets the umask's, not mktemp's 0600.
rfm_write_atomic() {
  local dest="$1" dir tmp
  dir="$(dirname "$dest")"
  tmp="$(mktemp "$dir/.rfm.XXXXXX")" || { echo "error: cannot create a temp file in $dir" >&2; return 1; }
  if [ -f "$dest" ]; then cp -p "$dest" "$tmp" 2>/dev/null
  else chmod "$(printf '%o' $(( 0666 & ~0$(umask) )))" "$tmp" 2>/dev/null
  fi
  if cat > "$tmp"; then
    mv -f "$tmp" "$dest" && return 0
  fi
  rm -f "$tmp"; echo "error: cannot write $dest" >&2; return 1
}

# ── location ────────────────────────────────────────────────────────────────
# rasa_root [<explicit-root>] — the project this install serves: where its
# ledgers, records and .claude/ configuration live. Resolution order:
#   1. an explicit root argument, else $RASA_ROOT;
#   2. the install that owns the calling script: walk up from the script's
#      own directory to the first directory holding .claude/rasa.lock.json;
#   3. the same walk from the current directory.
# Each walk stops at the enclosing repository's top — the first directory
# holding a .git directory or file — and never crosses it. So a per-package
# install inside a monorepo resolves to its package, and a repository nested
# inside another never resolves to the parent. `git rev-parse
# --show-toplevel` did neither: it answered the monorepo's root, and a
# "nearest ancestor with a lockfile" rule would have walked out of the
# repository. rc 70 when nothing resolves.
rasa_root() {
  local d start
  if [ -n "${1:-}" ] || [ -n "${RASA_ROOT:-}" ]; then
    d="${1:-$RASA_ROOT}"
    [ -d "$d" ] || { echo "error: project root '$d' is not a directory" >&2; return 70; }
    (cd "$d" && pwd -P)
    return
  fi
  for start in "$RFM_CALLER_DIR" "$(pwd -P)"; do
    [ -n "$start" ] || continue
    d="$start"
    while :; do
      if [ -f "$d/.claude/rasa.lock.json" ]; then printf '%s\n' "$d"; return 0; fi
      [ -e "$d/.git" ] && break
      [ "$d" = "/" ] && break
      d="$(dirname "$d")"
    done
  done
  echo "error: no RasaOS install here — no .claude/rasa.lock.json between this script or the current directory and the top of its repository. Run from inside an installed project, or set RASA_ROOT." >&2
  return 70
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
