#!/usr/bin/env bash
# pr-manifest.sh — the merge manifest: the machine-read block every pull
# request body carries, saying what the PR is part of, how it merges and what
# happens once it is in.
#
# One parser, four readers: the pr-manifest CI workflow (is the body
# complete?), /open-pr (write it, check it), /peer-review (which merge method)
# and /auto-merge (may this merge unattended, and what runs after). A reader
# that re-parsed the block by eye would drift from the others; they all call
# this.
#
# The block, fenced exactly like this, anywhere in the body:
#
#   ```yaml merge-manifest
#   kind: task                 # task | chore | release | hotfix
#   tasks: [TASK-042]          # the ledger ids this PR carries; [] for none
#   phase: P3                  # the roadmap phase, or none
#   release: v1.4.0            # the release it is targeted at, or none
#   merge: manual              # auto (with the auto-merge label) | manual
#   method: squash             # squash | merge | rebase
#   after: []                  # PRs that must merge first, e.g. [#41]
#   on_merge: hold             # hold | deploy:<env> | release:<version>
#   migrations: none           # none, or what runs and whether it reverses
#   rollback: revert           # how to undo it once it is in
#   ```
#
# Usage:
#   pr-manifest.sh parse  <source>           key=value per field (lists space-joined)
#   pr-manifest.sh get    <key> <source>     one field's value
#   pr-manifest.sh check  <source> [--manifest-only]
#                                            the manifest is valid and, unless
#                                            --manifest-only, the body's
#                                            human sections are written
#   pr-manifest.sh block  [--kind K] [--tasks "A B"] [--phase P] [--release V]
#                         [--merge M] [--method M] [--after "41 42"]
#                         [--on-merge X] [--migrations T] [--rollback T]
#                                            print a manifest block (defaults:
#                                            chore, none, manual, squash, hold)
#
#   <source> is a file, `-` for stdin, or `--pr <N>` (read through gh).
#
# Exit: 0 ok · 1 error · 2 usage · 3 invalid (every problem is listed)
#
# Portability: bash 3.2 (stock macOS). python3 for the parse. Standalone on
# purpose — the CI workflow runs it with nothing else installed.

set -euo pipefail

usage() { sed -n '28,45p' "$0" | sed 's/^# \{0,1\}//'; }

# The contract, once. Section headings the body must fill (prefix match, case
# insensitive; "and" may stand for "&").
SECTIONS="What & why|Part of|How I verified|Risk & rollback|After merge"

# read_source <args...> — the body on stdout.
read_source() {
  case "${1:-}" in
    "") echo "error: no source — a file, - for stdin, or --pr <N>" >&2; exit 2 ;;
    -) cat ;;
    --pr)
      [ -n "${2:-}" ] || { echo "error: --pr needs a number" >&2; exit 2; }
      command -v gh >/dev/null 2>&1 || { echo "error: --pr needs gh; pass the body as a file instead" >&2; exit 1; }
      gh pr view "${2#\#}" --json body -q .body 2>/dev/null \
        || { echo "error: could not read PR ${2} from the remote" >&2; exit 1; } ;;
    *)
      [ -f "$1" ] || { echo "error: no such file: $1" >&2; exit 1; }
      cat "$1" ;;
  esac
}

# The parser and validator. argv: <op> [<key>]; the body on stdin.
manifest_py() {
  SECTIONS="$SECTIONS" python3 -c '
import os, re, sys

op = sys.argv[1]
arg = sys.argv[2] if len(sys.argv) > 2 else ""
body = sys.stdin.read().replace("\r\n", "\n")

KEYS = ["kind", "tasks", "phase", "release", "merge", "method",
        "after", "on_merge", "migrations", "rollback"]
LISTS = ("tasks", "after")
problems = []

blocks = re.findall(r"(?ms)^```[ \t]*ya?ml[ \t]+merge-manifest[ \t]*\n(.*?)^```[ \t]*$", body)
if not blocks:
    print("invalid: no merge manifest — the body needs one ```yaml merge-manifest block", file=sys.stderr)
    sys.exit(3)
if len(blocks) > 1:
    problems.append("%d merge-manifest blocks; there must be exactly one" % len(blocks))

fields = {}
for n, raw in enumerate(blocks[0].split("\n"), 1):
    line = re.sub(r"\s+#(\s.*)?$", "", raw).rstrip()
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*)[ \t]*:[ \t]*(.*)$", line)
    if not m:
        problems.append("line %d is not `key: value`: %s" % (n, raw.strip()[:60]))
        continue
    k, v = m.group(1), m.group(2).strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"\x27":
        v = v[1:-1]
    if k not in KEYS:
        problems.append("unknown key `%s` (keys: %s)" % (k, ", ".join(KEYS)))
        continue
    if k in fields:
        problems.append("`%s` appears twice" % k)
    fields[k] = v

def as_list(k, v):
    if v in ("none", "[]"):
        return []
    if not (v.startswith("[") and v.endswith("]")):
        problems.append("`%s` must be a [list] (or [] / none), got: %s" % (k, v))
        return []
    return [x.strip() for x in v[1:-1].split(",") if x.strip()]

val = {}
for k in KEYS:
    if k not in fields:
        problems.append("`%s` is missing" % k)
        continue
    v = fields[k]
    if v == "" or "<" in v:
        problems.append("`%s` is unfilled: %s" % (k, v or "(empty)"))
        continue
    val[k] = as_list(k, v) if k in LISTS else v

def need(k, ok, msg):
    if k in val and not ok(val[k]):
        problems.append("`%s: %s` — %s" % (k, val[k] if k not in LISTS else "[" + ", ".join(val[k]) + "]", msg))

SEMVER = r"v?\d+\.\d+\.\d+([-+.][0-9A-Za-z.+-]*)?"
need("kind", lambda v: v in ("task", "chore", "release", "hotfix"), "one of task | chore | release | hotfix")
need("tasks", lambda v: all(re.match(r"^[A-Z][A-Z0-9]*-\d+$", t) for t in v), "task ids like TASK-042")
need("phase", lambda v: v == "none" or re.match(r"^[A-Za-z0-9._-]+$", v), "a phase id, or none")
need("release", lambda v: v == "none" or re.match("^" + SEMVER + "$", v), "a version like v1.4.0, or none")
need("merge", lambda v: v in ("auto", "manual"), "auto | manual")
need("method", lambda v: v in ("squash", "merge", "rebase"), "squash | merge | rebase")
need("after", lambda v: all(re.match(r"^#?\d+$", p) for p in v), "PR numbers like [#41, #42]")
need("on_merge", lambda v: v == "hold" or re.match(r"^deploy:[A-Za-z0-9._-]+$", v) or re.match("^release:" + SEMVER + "$", v),
     "hold | deploy:<env> | release:<version>")
need("migrations", lambda v: len(v) >= 4, "none, or say what runs and whether it reverses")
need("rollback", lambda v: len(v) >= 4, "revert, or the steps to undo it")

if "kind" in val and val["kind"] in ("task", "hotfix") and "tasks" in val and not val["tasks"]:
    problems.append("a %s PR names its task: `tasks: [TASK-NNN]`" % val["kind"])
if "on_merge" in val and val["on_merge"].startswith("release:") and "release" in val:
    target = val["on_merge"].split(":", 1)[1]
    if val["release"] == "none":
        problems.append("`on_merge: %s` but `release: none` — name the release" % val["on_merge"])
    elif val["release"].lstrip("v") != target.lstrip("v"):
        problems.append("`on_merge: %s` disagrees with `release: %s`" % (val["on_merge"], val["release"]))
if "migrations" in val and val["migrations"] != "none" and val.get("rollback") == "revert":
    problems.append("a PR with migrations cannot roll back by `revert` alone — say how the schema is undone")
if "after" in val:
    val["after"] = [p.lstrip("#") for p in val["after"]]

if op == "check" and arg != "--manifest-only":
    heads = [(m.start(), m.group(1).strip()) for m in re.finditer(r"(?m)^##[ \t]+(.+?)[ \t]*$", body)]
    def norm(s):
        return re.sub(r"\s+", " ", s.lower().replace(" and ", " & "))
    for want in os.environ["SECTIONS"].split("|"):
        hit = [i for i, (_, h) in enumerate(heads) if norm(h).startswith(norm(want))]
        if not hit:
            problems.append("section `## %s` is missing" % want)
            continue
        i = hit[0]
        start = body.index("\n", heads[i][0]) + 1 if "\n" in body[heads[i][0]:] else len(body)
        end = heads[i + 1][0] if i + 1 < len(heads) else len(body)
        text = re.sub(r"(?s)<!--.*?-->", "", body[start:end]).strip()
        if len(text) < 10:
            problems.append("section `## %s` is empty — write it" % want)

if problems:
    print("invalid: the merge manifest is not complete", file=sys.stderr)
    for p in problems:
        print("  - " + p, file=sys.stderr)
    sys.exit(3)

def show(k):
    return " ".join(val[k]) if k in LISTS else val[k]

if op == "parse":
    for k in KEYS:
        print("%s=%s" % (k, show(k)))
elif op == "get":
    print(show(arg))
else:
    print("manifest: ok (kind=%s merge=%s method=%s on_merge=%s)" % (val["kind"], val["merge"], val["method"], val["on_merge"]))
' "$@"
}

cmd_block() {
  local kind=chore tasks="" phase=none release=none merge=manual method=squash
  local after="" on_merge=hold migrations=none rollback=revert
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind|--tasks|--phase|--release|--merge|--method|--after|--on-merge|--migrations|--rollback)
        [ $# -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 2; }
        case "$1" in
          --kind) kind="$2" ;; --tasks) tasks="$2" ;; --phase) phase="$2" ;;
          --release) release="$2" ;; --merge) merge="$2" ;; --method) method="$2" ;;
          --after) after="$2" ;; --on-merge) on_merge="$2" ;;
          --migrations) migrations="$2" ;; --rollback) rollback="$2" ;;
        esac
        shift 2 ;;
      *) echo "error: unknown flag: $1" >&2; exit 2 ;;
    esac
  done
  local out
  out="$(KIND="$kind" TASKS="$tasks" PHASE="$phase" RELEASE="$release" MERGE="$merge" \
    METHOD="$method" AFTER="$after" ON_MERGE="$on_merge" MIGRATIONS="$migrations" ROLLBACK="$rollback" \
    python3 -c '
import os, re
e = os.environ
def lst(s, hashed=False):
    items = [x for x in re.split(r"[\s,]+", s) if x]
    return "[" + ", ".join(("#" + x.lstrip("#")) if hashed else x for x in items) + "]"
print("```yaml merge-manifest")
print("kind: %-20s # task | chore | release | hotfix" % e["KIND"])
print("tasks: %-19s # the ledger ids this PR carries" % lst(e["TASKS"]))
print("phase: %-19s # roadmap phase, or none" % e["PHASE"])
print("release: %-17s # the release it is targeted at, or none" % e["RELEASE"])
print("merge: %-19s # auto (needs the auto-merge label too) | manual" % e["MERGE"])
print("method: %-18s # squash | merge | rebase" % e["METHOD"])
print("after: %-19s # PRs that must merge first" % lst(e["AFTER"], True))
print("on_merge: %-16s # hold | deploy:<env> | release:<version>" % e["ON_MERGE"])
print("migrations: %s" % e["MIGRATIONS"])
print("rollback: %s" % e["ROLLBACK"])
print("```")
')"
  # Never print a block this script would itself refuse.
  printf '%s\n' "$out" | manifest_py check --manifest-only >/dev/null || exit 3
  printf '%s\n' "$out"
}

main() {
  local action="${1:-}"; [ $# -gt 0 ] && shift
  case "$action" in
    parse)
      [ $# -ge 1 ] || { usage >&2; exit 2; }
      read_source "$@" | manifest_py parse ;;
    get)
      [ $# -ge 2 ] || { usage >&2; exit 2; }
      local key="$1"; shift
      case "$key" in
        kind|tasks|phase|release|merge|method|after|on_merge|migrations|rollback) ;;
        *) echo "error: unknown key: $key" >&2; exit 2 ;;
      esac
      read_source "$@" | manifest_py get "$key" ;;
    check)
      local only="" src=""
      for a in "$@"; do
        case "$a" in --manifest-only) only="--manifest-only" ;; esac
      done
      [ $# -ge 1 ] || { usage >&2; exit 2; }
      case "$1" in
        --pr) [ $# -ge 2 ] || { usage >&2; exit 2; }; read_source --pr "$2" | manifest_py check $only ;;
        --manifest-only) usage >&2; exit 2 ;;
        *) read_source "$1" | manifest_py check $only ;;
      esac ;;
    block) cmd_block "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "error: unknown action: $action" >&2; exit 2 ;;
  esac
}

main "$@"
