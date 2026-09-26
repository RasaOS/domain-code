#!/usr/bin/env bash
# reconcile.sh — the deterministic half of /reconcile: compare the task ledger
# with what actually happened (branches, commits, pull requests, time), and say
# what each open task's stage should be.
#
# The ledger drifts because a transition is a separate act from the work: a
# PR merges and nobody runs `pass`, a branch is abandoned and the task sits in
# active/ for months. This script is the evidence; the skill applies it; the
# `check` modes are the enforcement that keeps it from drifting again.
#
# Usage:
#   reconcile.sh scan [--json] [--no-gh]   evidence + classification, every open task
#   reconcile.sh check --session           one-paragraph report for SessionStart (never fails)
#   reconcile.sh check --start --actor A   exit 1 if A may not start new work (stale / WIP)
#   reconcile.sh check --release           exit 1 if merged work sits unpassed, or work is stale
#   reconcile.sh check --ci                exit 1 if anything is stale (for CI)
#
# CLASSES of action:
#   certain   the evidence decides it; /reconcile applies it without asking:
#               pass-after-gate  review/ (or active/), PR merged → run the
#                                done-gate on the trunk, then pass (or reject)
#               reject           review/, PR closed without merging
#               submit           active/, PR open and ready
#   judgment  a person decides; /reconcile proposes it in one batch:
#               stale-active, stale-review, no-pr, stale-blocked,
#               stale-triage, stale-stub, closed-unmerged-active
#   ok        nothing to do
#
# Thresholds: .claude/task-hygiene.json (days; see the seed template).
# PR evidence needs `gh`; without it (or with --no-gh) merge state is inferred
# from the trunk's history and is never "certain".
#
# Exit: 0 ok · 1 check failed · 2 usage · 70 environment
# Portability: bash 3.2; python3.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_rfm="$(cd "$here/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
[ -f "$_rfm" ] || { echo "error: $(basename "$0"): .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; exit 70; }
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
rfm_require 1 || exit 70

usage() { sed -n '6,31p' "$0" | sed 's/^# \{0,1\}//'; }

ROOT="$(rasa_root 2>/dev/null)" || { echo "error: not inside an installed project" >&2; exit 70; }
cd "$ROOT"

trunk() {
  local t
  t="$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$t" ]; then echo "${t#origin/}"; return; fi
  if git show-ref --verify -q refs/heads/main; then echo main; return; fi
  if git show-ref --verify -q refs/heads/master; then echo master; return; fi
  echo main
}

# evidence <use-gh 0|1> — one JSON object per open task, classified.
evidence() {
  local use_gh="$1"
  [ "$use_gh" = "1" ] && ! command -v gh >/dev/null 2>&1 && use_gh=0
  python3 -B - "$ROOT" "$(trunk)" "$use_gh" <<'PY'
import datetime, json, os, re, subprocess, sys

root, trunk, use_gh = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
os.chdir(root)
today = datetime.date.today()

# ── thresholds ────────────────────────────────────────────────────────────
cfg = {"thresholds": {"active_days": 7, "review_idle_days": 14, "blocked_days": 14,
                      "triage_days": 14, "backlog_stub_days": 90},
       "wip_limit": 3, "block_start": True, "release_gate": True}
try:
    user = json.load(open(".claude/task-hygiene.json"))
    cfg["thresholds"].update(user.get("thresholds") or {})
    for k in ("wip_limit", "block_start", "release_gate"):
        if k in user:
            cfg[k] = user[k]
except FileNotFoundError:
    pass
except ValueError as e:
    print("error: .claude/task-hygiene.json is not valid JSON: %s" % e, file=sys.stderr)
    sys.exit(70)
T = cfg["thresholds"]

def git(*a):
    r = subprocess.run(["git"] + list(a), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return r.stdout.decode(errors="replace") if r.returncode == 0 else ""

# ── ledger: open tasks and when each entered its stage ────────────────────
OPEN = ("triage", "backlog", "active", "review", "blocked")
tasks = []
for stage in OPEN:
    d = os.path.join("tasks", stage)
    if not os.path.isdir(d):
        continue
    for name in sorted(os.listdir(d)):
        m = re.match(r"^([A-Z][A-Z0-9]*-\d+)-.*\.md$", name)
        if not m:
            continue
        text = open(os.path.join(d, name), encoding="utf-8", errors="replace").read()
        t = re.search(r"(?m)^#\s+[A-Z][A-Z0-9]*-\d+:\s*(.+)$", text)
        crit = re.search(r"(?ims)^##\s+acceptance criteria[^\n]*\n(.*?)(?=^##\s|\Z)", text)
        # A stub has no acceptance criterion of its own. Every template carries
        # "The done-gate passes" and empty `- [ ]` placeholders; neither counts.
        boxes = [b for b in re.findall(r"(?m)^[ \t]*-[ \t]+\[[ xX]\][ \t]+(\S.*)$", crit.group(1) if crit else "")
                 if "done-gate" not in b.lower()]
        tasks.append({"id": m.group(1), "stage": stage, "path": os.path.join(d, name),
                      "title": t.group(1).strip() if t else "", "stub": not boxes})

entered, actor = {}, {}
if os.path.exists("tasks/history.tsv"):
    for ln in open("tasks/history.tsv", encoding="utf-8", errors="replace"):
        p = ln.rstrip("\n").split("\t")
        if len(p) < 5 or p[0] == "date":
            continue
        date, tid, _frm, to, who = p[:5]
        entered[(tid, to)] = date          # the LAST time it entered that stage wins
        if to == "active":
            actor[tid] = who

def days_since(date):
    try:
        return (today - datetime.date.fromisoformat(date)).days
    except (TypeError, ValueError):
        return None

# ── git: branches carrying each id, and their last commit ─────────────────
refs = []
for ln in git("for-each-ref", "--format=%(refname:short)\t%(committerdate:short)",
              "refs/heads", "refs/remotes").splitlines():
    if "\t" in ln:
        n, dt = ln.split("\t", 1)
        refs.append((n, dt))

def branches_for(tid):
    pat = re.compile(r"(^|[/_-])" + re.escape(tid) + r"($|[/_-])", re.I)
    return [(n, dt) for n, dt in refs if pat.search(n) and not n.endswith("/HEAD")]

trunk_ref = "origin/" + trunk if git("rev-parse", "--verify", "-q", "origin/" + trunk) else trunk

def trunk_mentions(tid):
    # A commit on the trunk whose SUBJECT starts with the id — the §10 PR title
    # shape, which a squash merge keeps. A mention elsewhere is not a merge.
    out = git("log", trunk_ref, "--format=%h\t%cs\t%s", "-E", "--grep=^" + tid + "[: ]", "-n", "1")
    return out.strip().split("\t") if out.strip() else None

# ── GitHub: the PR for each id ────────────────────────────────────────────
def pr_for(tid):
    if not use_gh:
        return None
    r = subprocess.run(["gh", "pr", "list", "--state", "all", "--limit", "10", "--search", tid + " in:title",
                        "--json", "number,state,isDraft,mergedAt,title,headRefName,updatedAt"],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
    if r.returncode != 0:
        return {"error": "gh failed"}
    try:
        prs = json.loads(r.stdout or b"[]")
    except ValueError:
        return {"error": "gh output unreadable"}
    pat = re.compile(r"^\s*" + re.escape(tid) + r"\b", re.I)
    mine = [p for p in prs if pat.match(p.get("title", "")) or tid.lower() in p.get("headRefName", "").lower()]
    if not mine:
        return {}
    mine.sort(key=lambda p: ({"OPEN": 2, "MERGED": 1}.get(p.get("state"), 0), p.get("updatedAt", "")), reverse=True)
    return mine[0]

# ── classify ──────────────────────────────────────────────────────────────
out = []
for t in tasks:
    tid, stage = t["id"], t["stage"]
    since = entered.get((tid, stage))
    age = days_since(since)
    br = branches_for(tid)
    last = max((dt for _, dt in br), default=None)
    idle = days_since(last) if last else age
    pr = pr_for(tid) if stage in ("active", "review") else None
    merged_local = trunk_mentions(tid) if stage in ("active", "review") else None
    action, cls, why = "ok", "ok", ""

    state = (pr or {}).get("state")
    if stage == "review":
        if state == "MERGED":
            action, cls, why = "pass-after-gate", "certain", "PR #%s merged" % pr["number"]
        elif state == "CLOSED":
            action, cls, why = "reject", "certain", "PR #%s closed without merging" % pr["number"]
        elif state == "OPEN":
            upd = days_since((pr.get("updatedAt") or "")[:10])
            if upd is not None and upd > T["review_idle_days"]:
                action, cls, why = "stale-review", "judgment", "PR #%s idle %d days" % (pr["number"], upd)
        elif merged_local:
            action, cls, why = "pass-after-gate", "judgment", "trunk has %s \"%s\" (no gh: merge not proven)" % (merged_local[0], merged_local[2][:60])
        elif pr == {} and age is not None and age > T["review_idle_days"]:
            action, cls, why = "no-pr", "judgment", "in review %d days and no PR names it" % age
    elif stage == "active":
        if state == "MERGED":
            action, cls, why = "pass-after-gate", "certain", "PR #%s merged while the task was still active" % pr["number"]
        elif state == "OPEN" and not pr.get("isDraft"):
            action, cls, why = "submit", "certain", "PR #%s is open and ready" % pr["number"]
        elif state == "CLOSED":
            action, cls, why = "closed-unmerged-active", "judgment", "PR #%s closed without merging" % pr["number"]
        elif merged_local:
            action, cls, why = "pass-after-gate", "judgment", "trunk has %s \"%s\" (no gh: merge not proven)" % (merged_local[0], merged_local[2][:60])
        elif idle is not None and idle > T["active_days"]:
            action, cls, why = "stale-active", "judgment", ("no commit on %s for %d days" % (br[0][0], idle)) if br else ("active %d days with no branch and no PR" % idle)
    elif stage == "blocked":
        if age is not None and age > T["blocked_days"]:
            action, cls, why = "stale-blocked", "judgment", "blocked %d days" % age
    elif stage == "triage":
        if age is not None and age > T["triage_days"]:
            action, cls, why = "stale-triage", "judgment", "in triage %d days" % age
    elif stage == "backlog":
        if t["stub"] and age is not None and age > T["backlog_stub_days"]:
            action, cls, why = "stale-stub", "judgment", "a stub untouched %d days" % age

    out.append({"id": tid, "stage": stage, "title": t["title"], "path": t["path"],
                "days_in_stage": age, "since": since, "started_by": actor.get(tid, ""),
                "branches": [n for n, _ in br], "last_commit": last,
                "pr": ({k: pr.get(k) for k in ("number", "state", "isDraft", "mergedAt", "updatedAt")} if pr else None),
                "action": action, "class": cls, "why": why})

print(json.dumps({"trunk": trunk, "gh": use_gh, "config": cfg, "tasks": out}))
PY
}

cmd_scan() {
  local json=0 gh=1
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1 ;;
      --no-gh) gh=0 ;;
      *) echo "error: unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
  done
  local ev; ev="$(evidence "$gh")" || exit $?
  if [ "$json" = "1" ]; then printf '%s\n' "$ev"; return 0; fi
  printf '%s' "$ev" | python3 -c '
import json, sys
d = json.load(sys.stdin)
rows = d["tasks"]
print("LEDGER RECONCILE — trunk %s, PR evidence: %s" % (d["trunk"], "gh" if d["gh"] else "none (git only)"))
for cls, head in (("certain", "CERTAIN — applied by /reconcile without asking"),
                  ("judgment", "NEEDS A DECISION — proposed in one batch"),
                  ("ok", "OK")):
    sel = [r for r in rows if r["class"] == cls]
    if not sel:
        continue
    print("\n%s (%d)" % (head, len(sel)))
    for r in sel:
        age = "" if r["days_in_stage"] is None else " %dd" % r["days_in_stage"]
        pr = " PR #%s %s" % (r["pr"]["number"], r["pr"]["state"].lower()) if r.get("pr") and r["pr"].get("number") else ""
        extra = "  → %s: %s" % (r["action"], r["why"]) if cls != "ok" else ""
        print("  %-10s %-8s%s%s  %s%s" % (r["id"], r["stage"], age, pr, r["title"][:50], extra))
'
}

cmd_check() {
  local mode="" who=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --session|--start|--release|--ci) mode="${1#--}" ;;
      --actor) who="${2:-}"; shift ;;
      *) echo "error: unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
  done
  [ -n "$mode" ] || { echo "error: check needs --session, --start, --release or --ci" >&2; exit 2; }
  # The session report and the start guard run inside hooks: local evidence
  # only (no network), and fast. The release and CI gates ask GitHub.
  local gh=0
  case "$mode" in release|ci) gh=1 ;; esac
  local ev rc=0
  ev="$(evidence "$gh")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    [ "$mode" = "session" ] && exit 0
    echo "✗ reconcile: could not read the ledger (rc $rc)" >&2; exit 1
  fi
  printf '%s' "$ev" | python3 -c '
import json, sys
mode, who = sys.argv[1], sys.argv[2]
d = json.load(sys.stdin); rows = d["tasks"]; cfg = d["config"]
stale = [r for r in rows if r["class"] != "ok"]
merged = [r for r in rows if r["action"] == "pass-after-gate"]
fmt = lambda r: "%s (%s, %s)" % (r["id"], r["stage"], r["why"])

if mode == "session":
    if stale:
        print("⚠ Task ledger: %d task(s) need reconciling — run /reconcile before starting new work:" % len(stale))
        for r in stale[:8]:
            print("  · " + fmt(r))
        if len(stale) > 8:
            print("  · … and %d more (reconcile.sh scan)" % (len(stale) - 8))
    sys.exit(0)

if mode == "start":
    if not cfg.get("block_start", True):
        sys.exit(0)
    mine_active = [r for r in rows if r["stage"] == "active" and (not who or r["started_by"] in (who, ""))]
    mine_stale = [r for r in mine_active if r["class"] != "ok"]
    problems = []
    if mine_stale:
        problems.append("you hold stale active work: " + "; ".join(fmt(r) for r in mine_stale))
    if merged:
        problems.append("merged work is waiting to be passed: " + "; ".join(r["id"] for r in merged))
    lim = int(cfg.get("wip_limit", 3) or 0)
    if lim and len(mine_active) >= lim:
        problems.append("the WIP limit is %d and you already have %d active: %s" % (lim, len(mine_active), ", ".join(r["id"] for r in mine_active)))
    if problems:
        print("Task start refused — finish, park or close what is open first (run /reconcile):")
        for p in problems:
            print("  · " + p)
        print("Turn this off only deliberately: .claude/task-hygiene.json \"block_start\": false")
        sys.exit(1)
    sys.exit(0)

if mode == "release":
    if not cfg.get("release_gate", True):
        sys.exit(0)
    if merged:
        print("✗ release refused — merged work is not yet passed through the done-gate: " + "; ".join(fmt(r) for r in merged))
        print("  Run /reconcile (it runs the gate and passes them), then release.")
        sys.exit(1)
    sys.exit(0)

if mode == "ci":
    if stale:
        print("✗ task ledger out of date — %d task(s):" % len(stale))
        for r in stale:
            print("  · " + fmt(r))
        sys.exit(1)
    print("✓ task ledger reconciled")
' "$mode" "$who"
}

main() {
  local action="${1:-}"; [ $# -gt 0 ] && shift
  case "$action" in
    scan)  cmd_scan "$@" ;;
    check) cmd_check "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "error: unknown action: $action" >&2; usage >&2; exit 2 ;;
  esac
}
main "$@"
