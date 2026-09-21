#!/usr/bin/env bash
# suite-lib.sh — the ONE parser for test suites and test stamps.
#
# Sourced by both gates/tests-required.sh and stages/30-test.sh so the gate and
# the stage can never disagree about what "empty" means. Before this existed
# they used different code, and the stage's awk understood only block-sequence
# YAML: `tests: [auth, api-health]` — the obvious way to arm the gate — parsed
# as ZERO tests and exited 0, silently.
#
# Not executable on its own. Source it:
#     . "$(dirname "${BASH_SOURCE[0]}")/suite-lib.sh"
#
# bash 3.2 compatible (no associative arrays, no mapfile, no ${x^^}).

# ── suite_file_for_class <suites-dir> <env-class> ─────────────────────────────
# Echoes the suite file that applies. rc=1 when none exists.
#
# Selection is first-match-on-existence, by FILENAME — suite_kind and runs_for
# are advisory metadata and are deliberately not read here. This is also why
# the Element ships no prod-gate.md: an empty one dropped beside a populated
# pre-deploy.md would win and REMOVE production coverage.
suite_file_for_class() {
  _sl_dir="$1"; _sl_class="$2"
  if [ "$_sl_class" = "prod" ] && [ -f "$_sl_dir/prod-gate.md" ]; then
    printf '%s\n' "$_sl_dir/prod-gate.md"; return 0
  fi
  if [ -f "$_sl_dir/pre-deploy.md" ]; then
    printf '%s\n' "$_sl_dir/pre-deploy.md"; return 0
  fi
  return 1
}

# ── suite_tests <suite-file> ──────────────────────────────────────────────────
# Prints one member name per line. rc=0 with no output means a genuinely empty
# list. rc=3 means the `tests:` key exists in a form this parser will not guess
# at — a hard failure at prod rather than a silent zero. rc=4 means no python3.
#
# Accepts, deliberately:
#   tests:            (bare key, or only comments beneath) -> zero
#   tests: []                                              -> zero
#   tests: [a, b]     inline flow                          -> a, b
#   tests:\n  - a     block, any indent including zero and tab
# Comment lines beneath the key are ignored, so the shipped `#  - your-stamp`
# placeholder counts as zero.
suite_tests() {
  _sl_file="$1"
  command -v python3 >/dev/null 2>&1 || return 4
  python3 - "$_sl_file" <<'PY'
import sys, re
try:
    raw = open(sys.argv[1], encoding='utf-8', errors='replace').read()
except OSError:
    sys.exit(1)
lines = raw.splitlines()
# first frontmatter block only
if not lines or lines[0].strip() != '---':
    sys.exit(0)
try:
    end = next(i for i in range(1, len(lines)) if lines[i].strip() == '---')
except StopIteration:
    sys.exit(0)
fm = lines[1:end]

key = None
for i, ln in enumerate(fm):
    if re.match(r'^tests\s*:', ln):
        key = i
        break
if key is None:
    sys.exit(0)                      # no tests: key at all -> empty

rest = fm[key].split(':', 1)[1].strip()
rest = re.sub(r'\s+#.*$', '', rest).strip()

if rest.startswith('['):             # inline flow
    if not rest.endswith(']'):
        sys.exit(3)                  # spans lines / malformed — do not guess
    inner = rest[1:-1].strip()
    if not inner:
        sys.exit(0)
    out = [t.strip().strip('"\'') for t in inner.split(',')]
    out = [t for t in out if t]
    print('\n'.join(out))
    sys.exit(0)

if rest:                             # a bare scalar: tests: something
    sys.exit(3)

# block sequence: consume following lines until a new top-level key
out = []
for ln in fm[key+1:]:
    s = ln.strip()
    if not s or s.startswith('#'):
        continue
    if s.startswith('- '):
        out.append(s[2:].strip().strip('"\''))
        continue
    if s == '-':
        continue
    if re.match(r'^[A-Za-z_][A-Za-z0-9_-]*\s*:', s):
        break                        # next key ends the list
    sys.exit(3)                      # something else under tests: — refuse
print('\n'.join(out))
PY
}

# ── stamp_field <stamp-file> <key> ────────────────────────────────────────────
# Echoes a frontmatter scalar from the FIRST block, with surrounding quotes and
# trailing ` # comment` stripped. Unquoting matters: `run_command: "exit 0"`
# previously ran `bash -c '"exit 0"'` and died with 127.
stamp_field() {
  _sl_sf="$1"; _sl_key="$2"
  awk -v key="$_sl_key" '
    /^---[[:space:]]*$/ { f++; if (f==2) exit; next }
    f==1 {
      if ($0 ~ "^"key"[[:space:]]*:") {
        sub("^"key"[[:space:]]*:[[:space:]]*", "")
        sub(/[[:space:]]+#.*$/, "")
        sub(/[[:space:]]+$/, "")
        gsub(/^"|"$/, ""); gsub(/^'"'"'|'"'"'$/, "")
        print; exit
      }
    }
  ' "$_sl_sf"
}

# ── stamp_for <stamps-dir> <name> ─────────────────────────────────────────────
# Echoes the stamp file whose `name:` is EXACTLY <name>. rc=1 none, rc=2 many.
#
# Never `head -1`. The old lookup used `grep -lE "^name:[[:space:]]*NAME\b" |
# head -1`, and \b treats a hyphen as a word boundary — so a suite listing
# `alpha` matched an `alpha-extended` stamp too and head -1 took whichever
# sorted first. Measured: the gate printed "✓ pass" while the real `alpha`
# stamp (exit 7) never ran. A false PASS inside the gate is worse than an
# empty one.
stamp_for() {
  _sl_dir="$1"; _sl_name="$2"
  [ -d "$_sl_dir" ] || return 1
  _sl_hits=""; _sl_n=0
  for _sl_f in "$_sl_dir"/*.md; do
    [ -f "$_sl_f" ] || continue
    _sl_got="$(stamp_field "$_sl_f" name)"
    if [ "$_sl_got" = "$_sl_name" ]; then
      _sl_hits="$_sl_hits$_sl_f
"
      _sl_n=$((_sl_n + 1))
    fi
  done
  [ "$_sl_n" -eq 0 ] && return 1
  [ "$_sl_n" -gt 1 ] && { printf '%s' "$_sl_hits"; return 2; }
  printf '%s' "$_sl_hits"
  return 0
}
