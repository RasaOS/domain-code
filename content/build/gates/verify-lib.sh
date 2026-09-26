#!/usr/bin/env bash
# verify-lib.sh — the shared core of the build → test → deploy chain.
#
# Sourced (never executed) by build/build, build/test, gates/verified-build.sh
# and stages/60-verify.sh, so the three phases can never disagree about what a
# commit, a clean tree, an artifact fingerprint or "the latest passing record"
# means.
#
# THE CHAIN
#
#   build/build  → builds/records/BLD-<utc>.md   (+ .artifacts manifest)
#                  commit, clean tree, 20-build.sh's result, the fingerprint
#                  of every artifact the build stage declared.
#   build/test   → tests/runs/TST-<utc>.md
#                  names the BLD it tested; refuses a build whose commit is
#                  not HEAD or whose artifacts no longer match their
#                  fingerprint; runs the gate suite, then the e2e suite with
#                  its runtimes started, health-checked and always stopped.
#   build/deploy → gates/verified-build.sh
#                  refuses staging and prod unless a passing TST for HEAD
#                  names a BLD whose artifacts still match on disk; then the
#                  pipeline deploys THAT build instead of rebuilding.
#
# WHAT THIS IS AND IS NOT. The records are files in the repository. They make
# a skipped or stale step impossible to miss and impossible to ship by
# accident; they are not a defence against someone hand-writing a record.
# That is the approval gate's and branch protection's job.
#
# Portability: bash 3.2. python3 for hashing.

# The shared record library (rfm_* and rasa_actor), found beside an install
# (.claude/lib/domain-code) or in the Element tree (content/lib/domain-code).
_vl_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_vl_rfm=""
for _vl_d in "$_vl_here/../../.claude/lib/domain-code" "$_vl_here/../../lib/domain-code"; do
  if [ -f "$_vl_d/frontmatter.sh" ]; then _vl_rfm="$_vl_d/frontmatter.sh"; break; fi
done
[ -n "$_vl_rfm" ] || { echo "error: .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; return 70 2>/dev/null || exit 70; }
# shellcheck source=/dev/null
. "$_vl_rfm"
unset _vl_d

VL_BUILDS_DIR="builds/records"
VL_RUNS_DIR="tests/runs"

# vl_head — the full commit HEAD names, or rc 1 (no commits yet).
vl_head() { git rev-parse --verify --quiet HEAD 2>/dev/null; }

# vl_source_dirty — what differs from HEAD, as `git status --porcelain` lines.
# Untracked files count: a new source file not yet committed is still source.
# Excluded: the chain's own records and the bookkeeping git-clean already
# treats as not-dirtiness (deploys/, the legacy deploy log, tasks/).
vl_source_dirty() {
  git status --porcelain -- . \
    ':(exclude)builds/' ':(exclude)tests/runs/' ':(exclude)deploys/' \
    ':(exclude)build/deploy-log.md' ':(exclude)tasks/' 2>/dev/null
}

# vl_fingerprint <manifest> — read an artifact manifest, one item per line:
#   <path>            a file or directory, relative to the project (hashed)
#   <label>=<value>   an opaque reference recorded verbatim, e.g.
#                     image=sha256:… for a container the build pushed
# Prints `digest=<sha256>` and `count=<n>`, then one `item\t<sha256>\t<entry>`
# line per entry. rc 1 if a listed path does not exist, rc 3 on a path that
# leaves the project.
vl_fingerprint() {
  python3 -B - "$1" <<'PY'
import hashlib, os, sys
items = []
for raw in open(sys.argv[1], encoding="utf-8", errors="replace"):
    e = raw.strip()
    if not e or e.startswith("#"):
        continue
    if "=" in e and not os.path.exists(e):
        items.append((hashlib.sha256(e.encode()).hexdigest(), e))
        continue
    p = os.path.normpath(e)
    if p.startswith("..") or os.path.isabs(p):
        print("error: artifact path leaves the project: %s" % e, file=sys.stderr)
        sys.exit(3)
    if not os.path.exists(p):
        print("error: declared artifact does not exist: %s" % e, file=sys.stderr)
        sys.exit(1)
    h = hashlib.sha256()
    if os.path.isdir(p):
        for root, dirs, files in os.walk(p):
            dirs.sort()
            for name in sorted(files):
                f = os.path.join(root, name)
                h.update(os.path.relpath(f, p).encode() + b"\0")
                with open(f, "rb") as fh:
                    h.update(hashlib.sha256(fh.read()).digest())
    else:
        with open(p, "rb") as fh:
            h.update(fh.read())
    items.append((h.hexdigest(), e))
total = hashlib.sha256()
for d, e in items:
    total.update(e.encode() + b"\0" + d.encode() + b"\n")
print("digest=%s" % (total.hexdigest() if items else "none"))
print("count=%d" % len(items))
for d, e in items:
    print("item\t%s\t%s" % (d, e))
PY
}

# vl_new_record <dir> <prefix> — reserve <dir>/<prefix>-<utc>[-n].md with
# noclobber (the file itself is the reservation, as in deploys.sh) and print
# its path.
vl_new_record() {
  local dir="$1" prefix="$2" stamp base f n=1
  mkdir -p "$dir" || return 1
  stamp="$(date -u '+%Y%m%d-%H%M%S')"
  base="$dir/$prefix-$stamp"
  f="$base.md"
  while ! ( set -C; : > "$f" ) 2>/dev/null; do
    n=$((n + 1)); f="$base-$n.md"
    [ "$n" -lt 100 ] || { echo "error: cannot reserve a record in $dir" >&2; return 1; }
  done
  printf '%s\n' "$f"
}

# vl_field <record> <key> — one frontmatter value, or empty.
vl_field() { rfm_get_scalar "$1" "$2" 2>/dev/null || true; }

# vl_latest <dir> <prefix> <sha> <status> — the newest record in <dir> for
# commit <sha> with status <status>. Ids sort by time, so the last match wins.
vl_latest() {
  local dir="$1" prefix="$2" sha="$3" want="$4" f hit=""
  [ -d "$dir" ] || return 1
  for f in "$dir/$prefix"-*.md; do
    [ -f "$f" ] || continue
    [ "$(vl_field "$f" sha)" = "$sha" ] || continue
    [ "$(vl_field "$f" status)" = "$want" ] || continue
    hit="$f"
  done
  [ -n "$hit" ] || return 1
  printf '%s\n' "$hit"
}

# vl_build_still_matches <build-record> — rc 0 if the build's declared
# artifacts are on disk with the fingerprint it recorded. A build with no
# declared artifacts matches trivially (and says so).
vl_build_still_matches() {
  local rec="$1" manifest want got
  manifest="${rec%.md}.artifacts"
  want="$(vl_field "$rec" artifacts_digest)"
  if [ "$want" = "none" ]; then return 0; fi
  [ -f "$manifest" ] || { echo "  ✗ $(basename "$rec"): artifact manifest missing ($manifest)" >&2; return 1; }
  got="$(vl_fingerprint "$manifest" 2>&1 | sed -n 's/^digest=//p')"
  if [ "$got" != "$want" ]; then
    echo "  ✗ $(basename "$rec"): artifacts changed since the build (fingerprint ${want:0:12} → ${got:0:12})" >&2
    return 1
  fi
  return 0
}
