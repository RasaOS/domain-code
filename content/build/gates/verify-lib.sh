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

# vl_source — the SOURCE FINGERPRINT the whole chain is keyed on: a hash of
# HEAD's committed tree with the bookkeeping left out (builds/, tests/runs/,
# deploys/, tasks/, the legacy deploy log). Keyed on this, not the commit,
# because ordinary work moves the commit without changing what is built:
# committing the chain's own records, a ledger transition, or /release's
# merge commit whose tree equals the one staging ran. Any change to shipped
# source changes the fingerprint. rc 1 with no commits.
vl_source() {
  vl_head >/dev/null || return 1
  VL_PFX="$(git rev-parse --show-prefix 2>/dev/null)" \
  git ls-tree -r --full-tree HEAD 2>/dev/null \
    | VL_PFX="$(git rev-parse --show-prefix 2>/dev/null)" awk -F'\t' '{
        p = ENVIRON["VL_PFX"]; path = $2
        if (index(path, p) == 1) {
          rel = substr(path, length(p) + 1)
          if (rel ~ /^(builds|tests\/runs|deploys|tasks)\// || rel == "build/deploy-log.md") next
        }
        print
      }' \
    | git hash-object --stdin
}

# vl_source_dirty — what differs from HEAD, as `git status --porcelain` lines.
# Untracked files count: a new source file not yet committed is still source.
# Excluded: the chain's own records and the bookkeeping git-clean already
# treats as not-dirtiness (deploys/, the legacy deploy log, tasks/).
#
# REPOSITORY-wide, from the top: in a monorepo the build may read ../shared,
# and an uncommitted edit there is as much "not this commit" as one here. The
# exclusions are anchored to this project's own path. Also reported: files
# hidden from `git status` with --skip-worktree / --assume-unchanged, whose
# local edits would otherwise ship as if committed.
vl_source_dirty() {
  local top pfx
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  pfx="$(git rev-parse --show-prefix 2>/dev/null)"
  ( cd "$top" && git status --porcelain -- . \
      ":(exclude)${pfx}builds/" ":(exclude)${pfx}tests/runs/" ":(exclude)${pfx}deploys/" \
      ":(exclude)${pfx}build/deploy-log.md" ":(exclude)${pfx}tasks/" 2>/dev/null
    git ls-files -v 2>/dev/null | awk '/^(S|[a-z]) / { print "hidden " substr($0, 3) }' )
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
import hashlib, os, re, stat, sys
LABEL = re.compile(r"^[a-z][a-z0-9_-]*=[^/\s]+$")
root = os.path.realpath(".")

def fail(rc, msg):
    print("error: " + msg, file=sys.stderr)
    sys.exit(rc)

def inside(p):
    r = os.path.realpath(p)
    return r == root or r.startswith(root + os.sep)

def raise_err(e):
    raise e

items = []
for raw in open(sys.argv[1], encoding="utf-8", errors="replace"):
    e = raw.strip()
    if not e or e.startswith("#"):
        continue
    # A label (`image=sha256:…`) is recorded verbatim. Anything else is a
    # path: `dist/app-build=42.tar.gz` that does not exist must FAIL, not
    # pass as a label.
    if LABEL.match(e):
        items.append((hashlib.sha256(e.encode()).hexdigest(), e))
        continue
    p = os.path.normpath(e)
    if p.startswith("..") or os.path.isabs(p) or p == ".":
        fail(3, "artifact path must name something inside the project: %s" % e)
    if not os.path.lexists(p):
        fail(1, "declared artifact does not exist: %s" % e)
    if not inside(p):
        fail(3, "declared artifact resolves outside the project: %s" % e)
    h = hashlib.sha256()

    art = os.path.realpath(p)

    def within_artifact(path):
        r = os.path.realpath(path)
        return r == art or r.startswith(art + os.sep)

    def entry(path, rel):
        # Every entry is hashed by KIND, so a symlink cannot hide what it
        # points at and a FIFO cannot hang the hash.
        st = os.lstat(path)
        if stat.S_ISLNK(st.st_mode):
            target = os.readlink(path)
            # The link is hashed as a link — so what it points at must be
            # INSIDE this artifact, where the walk hashes it. A link to
            # anywhere else (../vendor, /etc) would let that content change
            # after the test with the fingerprint unmoved.
            if not within_artifact(path):
                fail(3, "symlink in an artifact points outside it — its target would not be fingerprinted: %s -> %s" % (path, target))
            h.update(b"L\0" + rel.encode() + b"\0" + target.encode() + b"\n")
        elif stat.S_ISREG(st.st_mode):
            h.update(b"F\0" + rel.encode() + b"\0" + oct(st.st_mode & 0o777).encode() + b"\0")
            with open(path, "rb") as fh:
                h.update(hashlib.sha256(fh.read()).digest())
        elif stat.S_ISDIR(st.st_mode):
            h.update(b"D\0" + rel.encode() + b"\n")
        else:
            fail(3, "artifact holds something that is not a file, directory or symlink: %s" % path)

    top = os.path.realpath(p) if os.path.islink(p) else p
    if os.path.isdir(top):
        for base, dirs, files in os.walk(top, onerror=raise_err):
            dirs.sort()
            for name in sorted(dirs + files):
                full = os.path.join(base, name)
                entry(full, os.path.relpath(full, top))
    else:
        entry(top, os.path.basename(p))
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
  # ALWAYS a two-digit sequence: <prefix>-<utc>-01, -02 … An unsuffixed first
  # id sorted AFTER its own -2 (`-` < `.`), so within one second "newest"
  # picked the oldest record — and an earlier pass outvoted a later failure.
  f="$base-01.md"
  while ! ( set -C; : > "$f" ) 2>/dev/null; do
    n=$((n + 1))
    [ "$n" -lt 100 ] || { echo "error: cannot reserve a record in $dir" >&2; return 1; }
    f="$base-$(printf '%02d' "$n").md"
  done
  printf '%s\n' "$f"
}

# vl_field <record> <key> — one frontmatter value, or empty.
vl_field() { rfm_get_scalar "$1" "$2" 2>/dev/null || true; }

# vl_latest <dir> <prefix> <source> <status> — the newest record in <dir> for
# source fingerprint <source> with status <status>. Ids sort by time, so the
# last match wins.
vl_latest() {
  local dir="$1" prefix="$2" src="$3" want="$4" f hit=""
  [ -d "$dir" ] || return 1
  for f in "$dir/$prefix"-*.md; do
    [ -f "$f" ] || continue
    [ "$(vl_field "$f" source)" = "$src" ] || continue
    [ "$(vl_field "$f" status)" = "$want" ] || continue
    hit="$f"
  done
  [ -n "$hit" ] || return 1
  printf '%s\n' "$hit"
}

# vl_newest <dir> <prefix> <source> — the newest record for source
# fingerprint <source>, whatever its status. The deploy gate reads THIS, not
# the newest passing one: an earlier pass must not outvote a later failure.
vl_newest() {
  local dir="$1" prefix="$2" src="$3" f hit=""
  [ -d "$dir" ] || return 1
  for f in "$dir/$prefix"-*.md; do
    [ -f "$f" ] || continue
    [ "$(vl_field "$f" source)" = "$src" ] || continue
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

# ── locks ──────────────────────────────────────────────────────────────────
# vl_lock <lock-dir> <what> — one build, one test run, one deploy per
# environment at a time. The lock is a directory (mkdir is atomic) holding an
# `owner` file: pid, host, actor, start. Held by a live process → refuse,
# naming the owner. Held by a dead process on THIS host → stale: taken over,
# with a warning. Held from another host → refused: this machine cannot tell
# whether that run is alive. Across machines, use your CI's concurrency group
# too — a file lock only protects one checkout.
VL_LOCKS=""
vl_lock() {
  local lock="$1" what="$2" owner pid host me stale
  me="$(hostname 2>/dev/null || echo unknown)"
  mkdir -p "$(dirname "$lock")" || return 1
  if ! mkdir "$lock" 2>/dev/null; then
    owner="$(cat "$lock/owner" 2>/dev/null || true)"
    pid="$(printf '%s' "$owner" | sed -n 's/^pid=//p')"
    host="$(printf '%s' "$owner" | sed -n 's/^host=//p')"
    if [ "$host" = "$me" ] && [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      # Take over ATOMICALLY: rename the dead lock away first. Two runs that
      # both saw the dead pid race on the rename; exactly one wins, and the
      # loser never deletes the winner's fresh lock.
      stale="$lock.stale.$$"
      if mv "$lock" "$stale" 2>/dev/null && mkdir "$lock" 2>/dev/null; then
        rm -rf "$stale"
        echo "⚠ $what: took over a stale lock left by pid $pid ($(printf '%s' "$owner" | sed -n 's/^started=//p'))" >&2
      else
        echo "✗ $what: lost the race for the stale lock $lock — another run took it" >&2
        return 1
      fi
    else
      {
        echo "✗ $what: another run holds the lock ($lock):"
        printf '%s\n' "$owner" | sed 's/^/    /'
        [ "$host" = "$me" ] || echo "  It is from another host — remove $lock by hand once you know that run is gone."
      } >&2
      return 1
    fi
  fi
  printf 'pid=%s\nhost=%s\nactor=%s\nstarted=%s\n' "$$" "$me" "$(rasa_actor 2>/dev/null || echo unknown)" \
    "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" > "$lock/owner"
  VL_LOCKS="$VL_LOCKS $lock"
}
# vl_unlock — release every lock this process took.
vl_unlock() {
  local l
  for l in $VL_LOCKS; do
    [ "$(sed -n 's/^pid=//p' "$l/owner" 2>/dev/null)" = "$$" ] && rm -rf "$l"
  done
  VL_LOCKS=""
}
