#!/usr/bin/env bash
# open-pr.sh — the deterministic half of /open-pr: hand one task from build
# to review, in the shape code-task-rules.md §10 requires.
#
# The script owns the mechanics — reading the task through bin/task, the
# branch name, the PR body's skeleton, checking a filled body against the
# spec, opening the PR (idempotently), and `task submit`. The SKILL.md owns
# the prose: the commit message, "what changed", "How I verified". Commit and
# push go through /push's push.sh, unchanged — one staging path, one secret
# guard.
#
# Usage:
#   open-pr.sh plan   <TASK-ID>                 what a run would do; no writes
#   open-pr.sh branch <TASK-ID> --slug <slug>   get onto the task's branch
#   open-pr.sh body   <TASK-ID>                 print the PR body skeleton
#   open-pr.sh check  <TASK-ID> <body-file> [--draft]
#                                               is the filled body submittable?
#   open-pr.sh open   <TASK-ID> <body-file> [--draft]
#                                               check, open the PR, submit
#   open-pr.sh submit <TASK-ID> --pr <url>      submit after a PR opened elsewhere
#
# Exit: 0 ok · 1 error · 2 usage · 3 refused (a precondition failed; nothing
#       written) · 4 no `gh` — open the PR with the session's GitHub tooling,
#       then run `submit`
#
# Portability: bash 3.2 (stock macOS). python3 for text; `gh` for `open`.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The shared record library — rasa_root, to work from the install's root.
# Found relative to this script
# (content/lib/domain-code/ in the Element, .claude/lib/domain-code/ in an
# install), never through the project root it exists to resolve.
_rfm="$(cd "$here/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
[ -f "$_rfm" ] || { echo "error: $(basename "$0"): .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; exit 70; }
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
rfm_require 1 || exit 70

usage() { sed -n '3,27p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "open-pr: $*" >&2; exit 1; }
refuse() { echo "open-pr: refused — $*" >&2; exit 3; }

TASK_BIN="$here/../../bin/task"
ENFORCE="$here/../task-enforce/task-enforce.sh"

task_cli() { python3 "$TASK_BIN" "$@"; }

actor() {
  if [ -f "$ENFORCE" ]; then bash "$ENFORCE" who 2>/dev/null || echo unknown
  else echo unknown; fi
}

# task_field <id> <field> — stage | title | path | type | priority, from
# `task show`. bin/task is the one reader of the ledger; this never opens a
# task's frontmatter itself.
task_field() {
  local id="$1" field="$2"
  task_cli show "$id" 2>/dev/null | python3 -c '
import re, sys
want = sys.argv[1]
text = sys.stdin.read()
if want == "stage":
    m = re.search(r"^\S+\s+\[(\w+)\]", text, re.M)
else:
    m = re.search(r"^\s+" + re.escape(want) + r":\s*(.*?)\s*$", text, re.M)
print(m.group(1) if m else "")
' "$field"
}

current_branch() { git symbolic-ref --short -q HEAD 2>/dev/null || true; }

# Default branch: origin/HEAD, else main, else master — push.sh's rule.
trunk_branch() {
  local t
  t="$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$t" ]; then echo "${t#origin/}"; return 0; fi
  if git show-ref --verify -q refs/heads/main;   then echo main;   return 0; fi
  if git show-ref --verify -q refs/heads/master; then echo master; return 0; fi
  echo main
}

# The §10 prefix: hotfix/ for a `priority: now` defect, task/ otherwise.
branch_prefix() {
  local id="$1"
  if [ "$(task_field "$id" type)" = "defect" ] && [ "$(task_field "$id" priority)" = "now" ]; then
    echo hotfix
  else
    echo task
  fi
}

require_task() {
  local id="$1"
  [ -n "$(task_field "$id" stage)" ] || die "no task $id in this project's ledger (task show $id found nothing)"
}

# existing_pr — the URL of an open PR whose head is the current branch, or
# nothing. Never an error: no gh, no remote, no PR all print nothing.
existing_pr() {
  command -v gh >/dev/null 2>&1 || return 0
  gh pr view "$(current_branch)" --json url,state 2>/dev/null \
    | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except ValueError: sys.exit(0)
print(d.get("url","") if d.get("state")=="OPEN" else "")' 2>/dev/null || true
}

cmd_plan() {
  local id="$1" stage branch trunk dirty ahead pr
  require_task "$id"
  stage="$(task_field "$id" stage)"
  branch="$(current_branch)"; trunk="$(trunk_branch)"
  dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  ahead=0
  if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  fi
  pr="$(existing_pr)"
  echo "task=$id"
  echo "title=$(task_field "$id" title)"
  echo "type=$(task_field "$id" type)"
  echo "stage=$stage"
  echo "path=$(task_field "$id" path)"
  echo "branch=${branch:-(detached)}"
  echo "trunk=$trunk"
  echo "expected_branch=$(branch_prefix "$id")/$id-<slug>"
  echo "dirty_paths=$dirty"
  echo "unpushed=$ahead"
  echo "open_pr=${pr:-none}"
  echo "gh=$(command -v gh >/dev/null 2>&1 && echo yes || echo no)"
  case "$stage" in
    active) echo "plan=branch, commit and push, open the PR, submit" ;;
    review) echo "plan=nothing — already submitted${pr:+ ($pr)}" ;;
    *)      echo "plan=refuse — the task is in $stage/, not active/. Start it first: task start $id" ;;
  esac
}

cmd_branch() {
  local id="$1" slug="" branch trunk target
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --slug) slug="${2:-}"; shift 2 || exit 2 ;;
      *) echo "error: unknown flag: $1" >&2; exit 2 ;;
    esac
  done
  require_task "$id"
  branch="$(current_branch)"; trunk="$(trunk_branch)"
  if [ -n "$branch" ] && [ "$branch" != "$trunk" ]; then
    # Already on a side branch (a /mission feat/ branch, or one the user
    # cut): keep it. Renaming a pushed branch orphans its upstream.
    echo "branch=$branch"
    case "$branch" in
      *"$id"*) ;;
      *) echo "note: '$branch' does not carry $id — kept; name the task in the PR title instead" ;;
    esac
    return 0
  fi
  [ -n "$slug" ] || { echo "error: on the trunk — --slug <kebab-slug> is required to name the branch" >&2; exit 2; }
  case "$slug" in
    *[!a-z0-9-]*|-*|*-) echo "error: --slug must be kebab-case (a-z, 0-9, -)" >&2; exit 2 ;;
  esac
  target="$(branch_prefix "$id")/$id-$slug"
  git checkout -q -b "$target" 2>/dev/null || die "could not create branch '$target'"
  echo "branch=$target"
}

# The body skeleton: the task path, its criteria with ☑/☐ carried over from
# the task file, the files changed against the spec's expected list, and the
# two sections the author must write. Written to a temp file OUTSIDE the
# repository and its path printed: push.sh stages untracked files, so a body
# drafted in the worktree would be committed onto the PR it describes.
cmd_body() {
  local id="$1" path trunk out
  require_task "$id"
  out="$(mktemp "${TMPDIR:-/tmp}/pr-body-$id.XXXXXX")" || die "could not create a temp file"
  path="$(task_field "$id" path)"
  trunk="$(trunk_branch)"
  local base
  base="$(git merge-base "origin/$trunk" HEAD 2>/dev/null || git merge-base "$trunk" HEAD 2>/dev/null || true)"
  local changed=""
  [ -n "$base" ] && changed="$(git diff --name-only "$base" HEAD 2>/dev/null || true)"
  python3 - "$path" "$id" "$changed" > "$out" <<'PY'
import os, re, sys
path, tid, changed = sys.argv[1], sys.argv[2], [c for c in sys.argv[3].splitlines() if c]
text = open(path, encoding="utf-8").read()

def section(name):
    m = re.search(r"(?ims)^##\s+" + name + r"[^\n]*\n(.*?)(?=^##\s|\Z)", text)
    return m.group(1) if m else ""

crit = re.findall(r"(?m)^\s*-\s+\[( |x|X)\]\s+(.+?)\s*$", section("acceptance criteria"))
arts = section("artifacts expected to change")
expected = sorted(set(t for t in re.findall(r"`([^`\s]+)`", arts) if "/" in t or "." in t))

# Named by id and file name, not by stage path: `task submit` moves the
# file from active/ to review/, and a path in the PR body would go stale.
print("**Task:** `%s` · `%s`" % (tid, os.path.basename(path)))
print()
print("## What changed")
print()
print("<!-- one to three sentences: what this PR does and why -->")
print()
print("## Acceptance criteria")
print()
for mark, line in crit:
    print("- %s %s" % ("☑" if mark.lower() == "x" else "☐", line))
if not crit:
    print("<!-- the task file has no acceptance criteria — it is a stub, not a spec -->")
print()
print("## Files changed")
print()
for c in changed:
    hit = any(e == c or c.endswith(e) or e.endswith(c) or c.startswith(e.rstrip("/") + "/") for e in expected)
    print("- `%s`%s" % (c, "" if hit else " — **not in the expected list**"))
missed = [e for e in expected if not any(e == c or c.endswith(e) or e.endswith(c) or c.startswith(e.rstrip("/") + "/") for c in changed)]
for e in missed:
    print("- `%s` — **expected, unchanged**" % e)
if not changed:
    print("<!-- nothing differs from the trunk yet — commit and push first -->")
print()
print("Deviations: <!-- explain every bold line above, or write: none -->")
print()
print("## How I verified")
print()
print("<!-- the commands you ran and their real output: the unfiltered headless")
print("     test run (counts, time), the build. Never just \"tests pass\". -->")
PY
  echo "body_file=$out"
}

# check — is a filled body submittable? Mechanical half of the /validate
# short pass /open-pr runs. Fail-closed: every problem is listed, and any one
# refuses.
cmd_check() {
  local id="$1" body="$2" draft="${3:-}"
  require_task "$id"
  [ -f "$body" ] || die "no body file at $body"
  case "$body" in
    "$(pwd -P)"/*) refuse "the body file is inside the repository ($body) — push.sh would commit it onto the PR. Use the path \`body\` printed." ;;
  esac
  local path
  path="$(task_field "$id" path)"
  python3 - "$path" "$body" "$draft" <<'PY'
import os, re, sys
path, body_path, draft = sys.argv[1], sys.argv[2], sys.argv[3] == "--draft"
task = open(path, encoding="utf-8").read()
body = open(body_path, encoding="utf-8").read()
problems = []

m = re.search(r"(?ims)^##\s+acceptance criteria[^\n]*\n(.*?)(?=^##\s|\Z)", task)
crit = re.findall(r"(?m)^\s*-\s+\[( |x|X)\]\s+(.+?)\s*$", m.group(1) if m else "")
if not crit:
    problems.append("the task has no acceptance criteria — a stub cannot be submitted for review")
# The done-gate criterion cannot be true yet: the gate runs after review.
open_ = [line for mark, line in crit if mark == " " and "done-gate" not in line.lower()]
if open_ and not draft:
    for line in open_:
        problems.append("criterion not met in the task file: %s" % line[:90])
    problems.append("  → finish them, or open with --draft (a draft stays in active/)")

marks = len(re.findall(r"[☑☐]", body))
if crit and marks != len(crit):
    problems.append("the body lists %d criteria; the task file has %d" % (marks, len(crit)))
name = os.path.basename(path)
if name not in body:
    problems.append("the body does not name the task file (%s)" % name)
if "<!--" in body:
    problems.append("the body still has unfilled <!-- --> placeholders")
v = re.search(r"(?ims)^##\s+how i verified[^\n]*\n(.*?)(?=^##\s|\Z)", body)
if not v or len(re.sub(r"(?s)<!--.*?-->", "", v.group(1)).strip()) < 20:
    problems.append('"How I verified" is missing or empty — commands and their real output')
if re.search(r"(?i)\*\*(not in the expected list|expected, unchanged)\*\*", body) \
        and re.search(r"(?im)^deviations:\s*(none)?\s*$", body):
    problems.append("files deviate from the expected list but Deviations says none")

if problems:
    print("check: NOT submittable")
    for p in problems:
        print("  - " + p)
    sys.exit(3)
print("check: submittable (%d criteria, %s)" % (len(crit), "draft" if draft else "ready"))
PY
}

# do_submit — `task submit`, then commit the ledger transition onto the PR
# branch and push it. The move active/ → review/ is a change to tracked files;
# left uncommitted it dirties the tree (so a re-run refuses) and, on the next
# branch switch, leaves the task in both active/ and review/ — a duplicate id
# the ledger then refuses every transition over. Only the ledger directory is
# staged: nothing else in the tree rides along.
do_submit() {
  local id="$1" url="$2" ledger
  ledger="$(dirname "$(dirname "$(task_field "$id" path)")")"
  task_cli submit "$id" --by "$(actor)" --note "PR $url" >/dev/null \
    || die "task submit $id failed — the PR is open ($url); run: task submit $id"
  echo "submitted=$id → review/"
  git add -A -- "$ledger" 2>/dev/null || die "could not stage the ledger ($ledger)"
  git diff --cached --quiet 2>/dev/null && return 0
  git commit -q -m "$id: submit for review" -m "PR: $url" \
    || die "could not commit the ledger transition — commit $ledger by hand"
  if git push -q 2>/dev/null; then
    echo "ledger=committed and pushed ($id: submit for review)"
  else
    echo "open-pr: the ledger transition is committed locally but the push failed — push the branch" >&2
    return 1
  fi
}

cmd_open() {
  local id="$1" body="$2" draft="${3:-}" stage branch trunk title url
  require_task "$id"
  stage="$(task_field "$id" stage)"
  [ "$stage" = "active" ] || [ "$stage" = "review" ] \
    || refuse "$id is in $stage/, not active/ — task start $id first"
  branch="$(current_branch)"; trunk="$(trunk_branch)"
  [ -n "$branch" ] && [ "$branch" != "$trunk" ] \
    || refuse "on the trunk — run: open-pr.sh branch $id --slug <slug>"
  [ -z "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] \
    || refuse "uncommitted changes to tracked files — push them first (push.sh run)"
  git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 \
    || refuse "'$branch' has no upstream — push it first (push.sh run)"
  [ "$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 1)" = "0" ] \
    || refuse "'$branch' has unpushed commits — push them first (push.sh run)"
  cmd_check "$id" "$body" "$draft" || exit 3

  url="$(existing_pr)"
  if [ -n "$url" ]; then
    echo "pr=$url (already open — not re-created)"
  else
    command -v gh >/dev/null 2>&1 || {
      echo "open-pr: no gh — open the PR with the session's GitHub tooling:" >&2
      echo "  base=$trunk head=$branch title=\"$id: $(task_field "$id" title)\"${draft:+ draft}" >&2
      echo "  body: $body" >&2
      echo "  then: open-pr.sh submit $id --pr <url>${draft:+   (skip while it is a draft)}" >&2
      exit 4
    }
    title="$id: $(task_field "$id" title)"
    if [ "$draft" = "--draft" ]; then
      url="$(gh pr create --base "$trunk" --head "$branch" --title "$title" --body-file "$body" --draft)" \
        || die "gh pr create failed"
    else
      url="$(gh pr create --base "$trunk" --head "$branch" --title "$title" --body-file "$body")" \
        || die "gh pr create failed"
    fi
    echo "pr=$url"
  fi

  if [ "$draft" = "--draft" ]; then
    echo "submitted=no — a draft stays in active/ (code-task-rules §2); submit when it is marked ready"
  elif [ "$stage" = "review" ]; then
    echo "submitted=already ($id is in review/)"
  else
    do_submit "$id" "$url"
  fi
}

cmd_submit() {
  local id="$1" url=""
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --pr) url="${2:-}"; shift 2 || exit 2 ;;
      *) echo "error: unknown flag: $1" >&2; exit 2 ;;
    esac
  done
  [ -n "$url" ] || { echo "error: submit needs --pr <url>" >&2; exit 2; }
  require_task "$id"
  [ "$(task_field "$id" stage)" = "active" ] || refuse "$id is not in active/"
  do_submit "$id" "$url"
}

# Only `--draft` may follow the body file — anything else would silently
# mean "ready", the less safe reading.
draft_arg() {
  case "${1:-}" in
    ""|--draft) ;;
    *) echo "error: unknown flag: $1 (only --draft)" >&2; exit 2 ;;
  esac
}

main() {
  local action="${1:-}" root; [ $# -gt 0 ] && shift
  # Every verb works from the install's root — bin/task finds the ledger
  # there and the body names paths relative to it — wherever it was called.
  # check and open take a body file: make it absolute before moving.
  case "$action" in
    check|open)
      if [ $# -ge 2 ] && [ -f "$2" ]; then
        local abs; abs="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
        set -- "$1" "$abs" ${3+"$3"}
      fi ;;
  esac
  case "$action" in
    -h|--help|help|"") ;;
    *) root="$(rasa_root)" || die "not inside an installed project"; cd "$(cd "$root" && pwd -P)" ;;
  esac
  case "$action" in
    plan)   [ $# -ge 1 ] || { usage >&2; exit 2; }; cmd_plan "$1" ;;
    branch) [ $# -ge 1 ] || { usage >&2; exit 2; }; cmd_branch "$@" ;;
    body)   [ $# -ge 1 ] || { usage >&2; exit 2; }; cmd_body "$1" ;;
    check)  [ $# -ge 2 ] || { usage >&2; exit 2; }; draft_arg "${3:-}"; cmd_check "$1" "$2" "${3:-}" ;;
    open)   [ $# -ge 2 ] || { usage >&2; exit 2; }; draft_arg "${3:-}"; cmd_open "$1" "$2" "${3:-}" ;;
    submit) [ $# -ge 1 ] || { usage >&2; exit 2; }; cmd_submit "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "error: unknown action: $action" >&2; exit 2 ;;
  esac
}

main "$@"
