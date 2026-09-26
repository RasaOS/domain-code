#!/usr/bin/env bash
# sync.sh — the deterministic half of /sync: bring this project up to the
# Element's current release through the Element's own bin/init.
#
# bin/init is the update path. It is manifest-driven, honours the
# lockfile's overrides[], never overwrites a seed that exists, restamps the
# pin, and — from rasa.domain.code 0.53.0 — migrates a pre-1.0 task ledger.
# This script adds what a person needs around it: a fresh clone, a plan of
# what will change, protection for local edits bin/init would overwrite,
# and cleanup of files the Element retired.
#
# Verbs:
#   sync.sh fetch                      clone the Element fresh; print its path
#   sync.sh plan    <src>              what the update would do (no writes)
#   sync.sh keep    <path>...          record paths in overrides[] (permanent)
#   sync.sh apply   <src> [--hold]     archive local edits and retired files,
#                                      then run bin/init
#                                      --hold: leave local edits untouched
#                                      this run only (no override recorded)
#
# <src> is the path `fetch` printed. Run from the project root.
# Exit: 0 ok · 1 error · 2 usage · 3 plan found something that needs a person
#
# Portability: bash 3.2. python3 for JSON and byte comparison.

set -euo pipefail

# The shared record library — rasa_root, the frontmatter reader and writer,
# rasa_actor. Found relative to this script (content/lib/domain-code/ in the
# Element, .claude/lib/domain-code/ in an install), never through the project
# root it exists to resolve.
_rfm="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
[ -f "$_rfm" ] || { echo "error: $(basename "$0"): .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; exit 70; }
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
rfm_require 1 || exit 70

LOCK=".claude/rasa.lock.json"
LEGACY_LOCK=".claude/foundation.json"

die() { echo "sync: $*" >&2; exit 1; }

# The project this install serves — its ledgers and .claude/ live here.
# rasa_root (the shared library) walks up to the install's lockfile and
# never past the repository top; see its comment for the order.
project_root() { rasa_root; }

# lock_field <key>  — element.repo | element.branch | pinned_sha
# Reads the canonical lockfile, falling back to the pre-canon one.
lock_field() {
  local root; root="$(project_root)"
  python3 - "$root/$LOCK" "$root/$LEGACY_LOCK" "$1" <<'PY'
import json, os, sys
lock, legacy, key = sys.argv[1:4]
d = None
for p, shape in ((lock, "canon"), (legacy, "legacy")):
    if os.path.isfile(p):
        try:
            d = json.load(open(p)); break
        except ValueError:
            sys.exit("unparseable: %s" % p)
if d is None:
    sys.exit(0)
el = d.get("element") or d.get("kit") or {}
val = {"element.repo": el.get("repo"), "element.branch": el.get("branch"),
       "pinned_sha": d.get("pinned_sha")}.get(key)
print(val or "")
PY
}

# canonical_repo <url> — the RasaOS GitHub org was renamed from rasa-os;
# the old URL no longer resolves, and lockfiles written before the rename
# still carry it. bin/init restamps the correct one on apply.
canonical_repo() {
  printf '%s\n' "$1" | sed 's#github\.com/rasa-os/#github.com/RasaOS/#'
}

cmd_fetch() {
  local root repo branch name tmp dst
  root="$(project_root)"
  [ -f "$root/$LOCK" ] || [ -f "$root/$LEGACY_LOCK" ] \
    || die "no $LOCK here — this project was not installed from an Element. Install with the Element's bin/init."
  repo="$(canonical_repo "$(lock_field element.repo)")"
  branch="$(lock_field element.branch)"; [ -n "$branch" ] || branch="main"
  [ -n "$repo" ] || die "$LOCK names no element.repo"
  # The clone's folder name is the repository's name: bin/init derives
  # kit/<folder>/ from it, so a temp-sounding name would land there.
  name="$(basename "$repo" .git)"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/rasa-sync.XXXXXX")"
  dst="$tmp/$name"
  if ! git clone --quiet --branch "$branch" "$repo" "$dst" >/dev/null 2>"$tmp/clone.err"; then
    cat "$tmp/clone.err" >&2
    die "could not clone $repo ($branch). No fallback to a stale copy."
  fi
  printf '%s\n' "$dst"
}

cmd_plan() {
  local src="$1" root
  root="$(project_root)"
  [ -f "$src/rasa.json" ] || die "$src is not an Element checkout (no rasa.json)"
  python3 - "$src" "$root" "$(lock_field pinned_sha)" <<'PY'
import json, os, re, subprocess, sys

src, root, pinned = sys.argv[1:4]
lockp = os.path.join(root, ".claude", "rasa.lock.json")
overrides = set()
if os.path.isfile(lockp):
    try:
        overrides = {os.path.normpath(o) for o in (json.load(open(lockp)).get("overrides") or [])}
    except ValueError:
        pass


def git(*a):
    r = subprocess.run(["git", "-C", src] + list(a), stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL)
    return r.stdout if r.returncode == 0 else None


head = git("rev-parse", "HEAD").decode().strip()
pin_ok = bool(pinned) and git("cat-file", "-e", pinned + "^{commit}") is not None
manifest_head = json.load(open(os.path.join(src, "rasa.json")))
manifest_pin = None
if pin_ok:
    raw = git("show", pinned + ":rasa.json")
    if raw:
        try:
            manifest_pin = json.loads(raw)
        except ValueError:
            manifest_pin = None


def expand(manifest, at):
    """dest path -> source path, for every element.files[] entry at a commit."""
    out = {}
    for e in (manifest or {}).get("element", {}).get("files", []):
        if e.get("policy") not in ("file-replace", "directory-mirror"):
            continue
        frm, to = e["from"].rstrip("/"), e["to"].rstrip("/")
        if e["policy"] == "file-replace":
            out[os.path.normpath(to)] = frm
            continue
        listing = git("ls-tree", "-r", "--name-only", at, frm + "/")
        for p in (listing or b"").decode().splitlines():
            out[os.path.normpath(to + p[len(frm):])] = p
    return out


def blob(at, path):
    return git("show", "%s:%s" % (at, path))


def local(dest):
    p = os.path.join(root, dest)
    return open(p, "rb").read() if os.path.isfile(p) else None


def protected(dest):
    return dest in overrides or any(dest.startswith(o.rstrip("/") + "/") for o in overrides)


now = expand(manifest_head, "HEAD")
then = expand(manifest_pin, pinned) if manifest_pin else {}
groups = {k: [] for k in ("update", "new", "local", "kept", "retire", "retired-edited")}
current = 0
for dest, frm in sorted(now.items()):
    up = blob("HEAD", frm)
    mine = local(dest)
    base = blob(pinned, then[dest]) if dest in then else None
    if protected(dest):
        if mine != up:
            groups["kept"].append(dest)
        continue
    if mine is None:
        groups["new"].append(dest)
    elif mine == up:
        current += 1
    elif base is not None and mine == base:
        groups["update"].append(dest)
    else:
        groups["local"].append(dest)
for dest, frm in sorted(then.items()):
    if dest in now or protected(dest):
        continue
    mine = local(dest)
    if mine is None:
        continue
    groups["retire" if mine == blob(pinned, frm) else "retired-edited"].append(dest)


def version_at(at):
    raw = git("show", at + ":rasa.json")
    try:
        return json.loads(raw).get("version", "?") if raw else "?"
    except ValueError:
        return "?"


print("SYNC PLAN — %s" % manifest_head.get("name"))
print("  pinned : %s  (v%s)" % ((pinned or "none")[:12], version_at(pinned) if pin_ok else "?"))
print("  latest : %s  (v%s)" % (head[:12], manifest_head.get("version")))
if pinned and not pin_ok:
    print("  ! the pinned commit is not in the Element's history — no baseline, so every")
    print("    file that differs is treated as a possible local edit.")

# Releases between the pin and HEAD, newest first, with breaking flags.
if pin_ok and pinned != head:
    cl = open(os.path.join(src, "CHANGELOG.md"), encoding="utf-8", errors="replace").read()
    pin_ver = version_at(pinned)
    sections = re.split(r"(?m)^## ", cl)[1:]
    print("\nRELEASES SINCE YOUR PIN")
    for sec in sections:
        headline = sec.split("\n", 1)[0].strip()
        m = re.match(r"v?(\d+\.\d+\.\d+)", headline)
        if not m:
            continue
        if m.group(1) == pin_ver:
            break
        flag = "  ⚠ BREAKING" if re.search(r"BREAKING|[Bb]reaking change|Structural change worth flagging", sec) else ""
        print("  %s%s" % (headline[:90], flag))
        # A breaking release's migration steps, printed where the decision is
        # made. They used to exist only in CHANGELOG.md, which nobody running
        # /sync reads. The block is the entry's "To migrate" list.
        if flag:
            m = re.search(r"(?ms)^[^\n]*[Tt]o migrate[^\n]*\n((?:\d+\. [^\n]*\n(?:   [^\n]*\n)*)+)", sec)
            if m:
                print("      to migrate:")
                for ln in m.group(1).rstrip().splitlines():
                    print("        " + ln.strip())

labels = [
    ("update", "update — upstream changed, your copy is untouched"),
    ("new", "new — added by the Element"),
    ("local", "LOCAL EDIT — differs from the pin and from upstream; bin/init would overwrite it"),
    ("kept", "kept — in overrides[], upstream differs; left alone"),
    ("retire", "retired — removed by the Element, your copy unmodified; apply archives + removes it"),
    ("retired-edited", "RETIRED BUT EDITED — removed by the Element, your copy has changes"),
]
# apply and retire parse these lists, so they ask for every line.
limit = None if os.environ.get("SYNC_PLAN_ALL") else 40
for key, label in labels:
    items = groups[key]
    if not items:
        continue
    print("\n%s (%d)" % (label, len(items)))
    for d in items[:limit]:
        print("  %s" % d)
    if limit and len(items) > limit:
        print("  … and %d more (SYNC_PLAN_ALL=1 lists all)" % (len(items) - limit))
print("\ncurrent — already identical: %d file(s)" % current)

# The task ledger: bin/init migrates a pre-1.0 one, and only over a clean tasks/.
tasks = os.path.join(root, "tasks")
ledger = "none"
if os.path.isdir(tasks):
    cfg = os.path.join(tasks, "tasks.config.yml")
    if os.path.isfile(cfg) and "schema: rasa.module.tasks/1.0.0" in open(cfg, errors="replace").read():
        ledger = "v1"
    elif any(os.path.isdir(os.path.join(tasks, s)) for s in
             ("triage", "backlog", "active", "review", "blocked", "completed", "done")):
        ledger = "legacy"
dirty = ""
if ledger == "legacy":
    r = subprocess.run(["git", "-C", root, "status", "--porcelain", "--", "tasks"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    dirty = r.stdout.decode().strip()
print("\nTASK LEDGER")
if ledger == "legacy":
    if not os.path.isfile(os.path.join(src, "bin", "migrate-ledger")):
        print("  pre-1.0 — this Element version does not migrate it")
    elif dirty:
        print("  pre-1.0 — MIGRATION WILL BE REFUSED: tasks/ has uncommitted changes.")
        print("  Commit or stash them first; bin/init then holds back every tasks/ seed.")
    else:
        print("  pre-1.0 — bin/init will migrate it to rasa.module.tasks v1.0.0 (uncommitted).")
        print("  Preview:  %s/bin/migrate-ledger %s" % (src, root))
elif ledger == "v1":
    print("  rasa.module.tasks v1.0.0 — nothing to migrate")
else:
    print("  none — bin/init seeds a new one")

needs_person = groups["local"] or groups["retired-edited"] or (ledger == "legacy" and dirty)
sys.exit(3 if needs_person else 0)
PY
}

cmd_keep() {
  local root; root="$(project_root)"
  [ -f "$root/$LOCK" ] || die "no $LOCK — nothing to record overrides in"
  python3 - "$root/$LOCK" "$@" <<'PY'
import json, os, sys
p = sys.argv[1]
d = json.load(open(p))
ov = d.setdefault("overrides", [])
for path in sys.argv[2:]:
    path = os.path.normpath(path)
    if path not in ov:
        ov.append(path)
        print("keep: %s (recorded in overrides[])" % path)
json.dump(d, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
}

# archive <dest> — copy a project file into .claude/_archive/ before it is
# overwritten or removed. Append-only: never overwrite an earlier archive.
archive() {
  local root="$1" dest="$2" day base out n=0
  day="$(date +%Y-%m-%d)"
  base="$(printf '%s' "$dest" | sed 's#/#__#g; s#^\.*##')"
  mkdir -p "$root/.claude/_archive"
  out="$root/.claude/_archive/$base.$day"
  while [ -e "$out" ]; do n=$((n + 1)); out="$root/.claude/_archive/$base.$day.$n"; done
  cp -p "$root/$dest" "$out"
  printf '%s\n' "${out#$root/}"
}

list_group() {
  # list_group <plan-output> <header-prefix> — the paths under one plan group
  printf '%s\n' "$1" | SYNC_H="$2" awk 'index($0, ENVIRON["SYNC_H"]) == 1 {on=1; next} /^$/ {on=0} on && /^  / {sub(/^  /, ""); print}'
}

cmd_apply() {
  local src="$1" hold="${2:-}" root plan_out rc=0 held="" d edits retired
  root="$(project_root)"
  [ -f "$src/bin/init" ] || die "$src has no bin/init"
  # One plan, taken BEFORE bin/init: bin/init moves the pin to the new
  # commit, and a retired file can only be recognised against the old one.
  set +e
  plan_out="$(SYNC_PLAN_ALL=1 cmd_plan "$src" 2>/dev/null)"
  set -e
  edits="$(list_group "$plan_out" "LOCAL EDIT")"
  retired="$(list_group "$plan_out" "retired — ")"

  if [ -n "$edits" ]; then
    if [ "$hold" = "--hold" ]; then
      # Hold = protect for THIS run only: add to overrides[], run bin/init,
      # take them back out. Nothing is lost and no standing decision is made.
      held="$edits"
      # One path per line; no word-splitting on spaces, no globbing.
      local oldifs="$IFS"
      set -f; IFS='
'
      # shellcheck disable=SC2086
      cmd_keep $held >/dev/null
      IFS="$oldifs"; set +f
      echo "held this run (local edits left untouched):"
      printf '%s\n' "$held" | sed 's/^/  /'
    else
      echo "archiving local edits bin/init is about to overwrite:"
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        echo "  $d → $(archive "$root" "$d")"
      done <<EOF
$edits
EOF
    fi
  fi

  if [ -n "$retired" ]; then
    echo "retiring files the Element removed (unmodified since your pin):"
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      echo "  $d → $(archive "$root" "$d")"
      rm -f "$root/$d"
    done <<EOF
$retired
EOF
  fi

  set +e
  bash "$src/bin/init" "$root"
  rc=$?
  set -e
  if [ -n "$held" ]; then
    python3 - "$root/$LOCK" "$held" <<'PY'
import json, os, sys
p, held = sys.argv[1], {os.path.normpath(x) for x in sys.argv[2].split("\n") if x}
d = json.load(open(p))
d["overrides"] = [o for o in d.get("overrides", []) if os.path.normpath(o) not in held]
json.dump(d, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
  fi
  return "$rc"
}

main() {
  local verb="${1:-}"; [ $# -gt 0 ] && shift
  case "$verb" in
    fetch)  cmd_fetch ;;
    plan)   [ $# -ge 1 ] || { echo "usage: sync.sh plan <src>" >&2; exit 2; }; cmd_plan "$1" ;;
    keep)   [ $# -ge 1 ] || { echo "usage: sync.sh keep <path>..." >&2; exit 2; }; cmd_keep "$@" ;;
    apply)  [ $# -ge 1 ] || { echo "usage: sync.sh apply <src> [--hold]" >&2; exit 2; }; cmd_apply "$@" ;;
    -h|--help|help|"") sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "sync: unknown verb: $verb" >&2; exit 2 ;;
  esac
}

main "$@"
