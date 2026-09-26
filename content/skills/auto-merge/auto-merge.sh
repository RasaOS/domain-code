#!/usr/bin/env bash
# auto-merge.sh: the deterministic half of /auto-merge. It merges open pull
# requests unattended, once each one has opted in and proven itself.
#
# The script owns everything that must not be judgment: whether the skill is
# on, which PRs are eligible and why the rest are not, the run lock, what a
# merged PR's manifest says to do next, and whether that is allowed to run
# unattended. The review and the merge itself are /peer-review's: its
# context-isolated auditor, its CI gate, and its pass of the task inside the
# PR. SKILL.md drives the loop.
#
# A PR is eligible only when ALL of these hold:
#   - it carries the opt-in label (.claude/auto-merge.json `label`)
#     and no hold label
#   - it is not a draft, and it targets the trunk
#   - its body's merge manifest is valid and says `merge: auto`
#   - every PR in the manifest's `after` list has merged
#   - GitHub says it is mergeable (no conflict)
#   - its CI is green (peer-review.sh's classifier: pending, failing
#     and "no checks" all say no)
#
# Usage:
#   auto-merge.sh status                     config, lock, the last runs
#   auto-merge.sh on | off                   flip `enabled` in .claude/auto-merge.json
#   auto-merge.sh plan [--json] [--from-json <file>]
#                                            classify every open PR; no writes
#   auto-merge.sh run  [--json] [--from-json <file>]
#                                            refuse unless enabled; take the run
#                                            lock; print the plan
#   auto-merge.sh finish                     release the run lock
#   auto-merge.sh after <N> [--execute]      a merged PR's on_merge: what runs,
#                                            and, with --execute, run it (non-prod
#                                            deploys only) and comment on the PR
#   auto-merge.sh log <N> <event> [detail]   append to the run log
#
#   --from-json reads the open-PR list from a file in `gh pr list --json`
#   shape (number, title, url, isDraft, baseRefName, headRefOid, labels,
#   mergeable, body, statusCheckRollup), for a session with no gh.
#
# Exit: 0 ok · 1 error · 2 usage · 3 refused (off, locked, not merged, dirty
#       tree) · 4 no gh (use --from-json) · 7 the post-merge deploy failed
#
# Portability: bash 3.2 (stock macOS). python3 for JSON; gh for the remote.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The shared record library: rasa_root, to work from the install's root.
_rfm="$(cd "$here/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
[ -f "$_rfm" ] || { echo "error: $(basename "$0"): .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; exit 70; }
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
rfm_require 1 || exit 70

usage() { sed -n '22,44p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "auto-merge: $*" >&2; exit 1; }
refuse() { echo "auto-merge: refused: $*" >&2; exit 3; }

MANIFEST="$here/pr-manifest.sh"
PEER="$here/../peer-review/peer-review.sh"
ENVSH="$here/../environment/environment.sh"
CFG=".claude/auto-merge.json"
LOCK_STALE_SECS=7200

# cfg <key> — a setting, with the seed's defaults when the file or key is
# missing. Lists print space-joined.
cfg() {
  python3 -c '
import json, sys
d = {"enabled": False, "label": "auto-merge", "hold_labels": ["hold", "do-not-merge", "wip", "blocked"],
     "max_per_run": 5, "check_wait_secs": 900, "deploy": True, "interval": "30m"}
try:
    d.update(json.load(open(sys.argv[1])))
except (OSError, ValueError):
    pass
v = d.get(sys.argv[2])
if isinstance(v, bool): print("true" if v else "false")
elif isinstance(v, list): print(" ".join(str(x) for x in v))
else: print("" if v is None else v)
' "$CFG" "$1"
}

trunk_branch() {
  local t
  t="$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$t" ]; then echo "${t#origin/}"; return 0; fi
  if git show-ref --verify -q refs/heads/main;   then echo main;   return 0; fi
  if git show-ref --verify -q refs/heads/master; then echo master; return 0; fi
  echo main
}

state_dir() {
  local d
  d="$(git rev-parse --git-common-dir 2>/dev/null)" || die "not inside a git repository"
  d="$(cd "$d" && pwd -P)/auto-merge"
  mkdir -p "$d"
  echo "$d"
}

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

cmd_log() {
  local n="${1#\#}" event="$2" detail="${3:-}"
  printf '%s\t%s\t%s\t%s\n' "$(now)" "$n" "$event" "$(printf '%s' "$detail" | tr '\t\n' '  ')" \
    >> "$(state_dir)/log.tsv"
}

# ── on / off / status ──────────────────────────────────────────────────

cmd_switch() {
  local want="$1"
  [ -f "$CFG" ] || die "$CFG is missing — re-run the Element's bin/init"
  WANT="$want" python3 -c '
import os, re, sys
p = sys.argv[1]
s = open(p).read()
t, n = re.subn(r"(\"enabled\"\s*:\s*)(true|false)", lambda m: m.group(1) + os.environ["WANT"], s, count=1)
if not n:
    sys.exit("auto-merge: %s has no \"enabled\" key" % p)
open(p, "w").write(t)
' "$CFG"
  echo "enabled=$want"
  if [ "$want" = "true" ]; then
    cat <<EOF
next:
  1. Land the change on the trunk through a PR: a scheduled run reads
     $CFG from the trunk.
  2. Schedule the runs. Pick one; two schedulers race for the same PRs:
     - in this session:  /loop $(cfg interval) /auto-merge run
     - unattended:       a Claude routine (hourly at most) whose prompt is
                         "/auto-merge run" in a fresh session on this repo
  3. Opt PRs in: \`merge: auto\` in the merge manifest AND the
     '$(cfg label)' label (/open-pr --merge auto does both).
EOF
  else
    echo "next: land the change through a PR, and stop the /loop or routine that runs /auto-merge"
  fi
}

cmd_status() {
  local d lock
  d="$(state_dir)"
  echo "enabled=$(cfg enabled)"
  echo "label=$(cfg label)"
  echo "hold_labels=$(cfg hold_labels)"
  echo "max_per_run=$(cfg max_per_run)"
  echo "deploy=$(cfg deploy) (non-prod only; prod and releases are always queued for a person)"
  echo "trunk=$(trunk_branch)"
  lock="$d/run.lock"
  if [ -d "$lock" ]; then echo "lock=held ($(cat "$lock/owner" 2>/dev/null || echo unknown))"; else echo "lock=free"; fi
  echo "gh=$(command -v gh >/dev/null 2>&1 && echo yes || echo no)"
  if [ -s "$d/log.tsv" ]; then
    echo "[last runs]"
    tail -10 "$d/log.tsv"
  fi
}

# ── plan ───────────────────────────────────────────────────────────────

# plan_py — classify the open-PR list on stdin. Every rule is here, in one
# ordered list, so "why was #N skipped" has exactly one answer.
plan_py() {
  MANIFEST="$MANIFEST" PEER="$PEER" TRUNK="$(trunk_branch)" LABEL="$(cfg label)" \
  HOLD="$(cfg hold_labels)" MAX="$(cfg max_per_run)" JSON_OUT="$1" \
  HAVE_GH="$(command -v gh >/dev/null 2>&1 && echo 1 || echo 0)" python3 -c '
import json, os, subprocess, sys

E = os.environ
prs = json.load(sys.stdin)
if isinstance(prs, dict):
    prs = prs.get("pullRequests") or prs.get("items") or []
open_nums = {int(p["number"]) for p in prs}
hold = set(E["HOLD"].split())
label = E["LABEL"]
max_run = int(E["MAX"] or 5)

def run(cmd, data):
    p = subprocess.run(cmd, input=data, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr

dep_cache = {}
def dep_state(n):
    if n in open_nums:
        return "OPEN"
    if n not in dep_cache:
        st = "UNKNOWN"
        if E["HAVE_GH"] == "1":
            rc, out, _ = run(["gh", "pr", "view", str(n), "--json", "state"], "")
            if rc == 0:
                try: st = json.loads(out).get("state", "UNKNOWN")
                except ValueError: pass
        dep_cache[n] = st
    return dep_cache[n]

rows = []
for p in sorted(prs, key=lambda x: int(x["number"])):
    n = int(p["number"])
    labels = {(l.get("name") if isinstance(l, dict) else str(l)) for l in (p.get("labels") or [])}
    row = {"pr": n, "title": p.get("title", ""), "url": p.get("url", ""),
           "head": p.get("headRefOid", ""), "state": "skip", "reason": ""}
    rows.append(row)
    if label not in labels:
        row["reason"] = "not opted in (no %s label)" % label; continue
    held = sorted(labels & hold)
    if held:
        row["reason"] = "held by label: " + ", ".join(held); continue
    if p.get("isDraft"):
        row["reason"] = "draft"; continue
    if p.get("baseRefName") != E["TRUNK"]:
        row["reason"] = "targets %s, not the trunk (%s)" % (p.get("baseRefName"), E["TRUNK"]); continue
    rc, out, err = run(["bash", E["MANIFEST"], "parse", "-"], p.get("body") or "")
    if rc != 0:
        first = [l.strip()[2:] for l in err.splitlines() if l.strip().startswith("- ")]
        lead = err.strip().splitlines()[0].replace("invalid: ", "", 1) if err.strip() else "unreadable"
        row["reason"] = "manifest invalid: " + (first[0] if first else lead)
        continue
    m = dict(l.split("=", 1) for l in out.splitlines() if "=" in l)
    row.update({"method": m["method"], "on_merge": m["on_merge"], "kind": m["kind"],
                "tasks": m["tasks"], "release": m["release"]})
    if m["merge"] != "auto":
        row["reason"] = "manifest says merge: %s" % m["merge"]; continue
    waits = []
    for d in [int(x) for x in m["after"].split()]:
        st = dep_state(d)
        if st != "MERGED":
            waits.append("#%d (%s)" % (d, st.lower()))
    if waits:
        row["reason"] = "waits for " + ", ".join(waits); continue
    mg = str(p.get("mergeable") or "UNKNOWN").upper()
    if mg == "CONFLICTING":
        row["reason"] = "merge conflict with the trunk"; continue
    if mg != "MERGEABLE":
        row["reason"] = "mergeability not computed yet (%s)" % mg; continue
    rc, out, _ = run(["bash", E["PEER"], "classify"], json.dumps({"statusCheckRollup": p.get("statusCheckRollup") or []}))
    c = dict(l.split("=", 1) for l in out.splitlines() if "=" in l)
    if rc == 4:
        row["reason"] = "checks failing: " + (c.get("failing_checks") or "?"); continue
    if rc == 5:
        row["reason"] = "checks still running: " + (c.get("pending_checks") or "?"); continue
    if rc != 0:
        row["reason"] = "no checks reported; nothing verified it"; continue
    row["state"] = "eligible"

# One run merges at most max_per_run, and never a PR whose `after` names
# another PR merging in the same run: it waits for the next run, when that
# merge is proven.
chosen = 0
for r in rows:
    if r["state"] != "eligible":
        continue
    if chosen >= max_run:
        r["state"], r["reason"] = "skip", "over max_per_run (%d); next run" % max_run
        continue
    chosen += 1

eligible = [r["pr"] for r in rows if r["state"] == "eligible"]
if E["JSON_OUT"] == "1":
    print(json.dumps({"trunk": E["TRUNK"], "label": label, "eligible": eligible, "prs": rows}, indent=2))
else:
    print("auto-merge plan: %d open PR(s), %d eligible (label: %s, trunk: %s)" % (len(rows), len(eligible), label, E["TRUNK"]))
    for r in rows:
        if r["state"] == "eligible":
            print("pr=%d state=eligible method=%s on_merge=%s head=%s title=%s"
                  % (r["pr"], r["method"], r["on_merge"], r["head"][:12], r["title"]))
        else:
            print("pr=%d state=skip reason=%s" % (r["pr"], r["reason"]))
    print("eligible=" + " ".join(str(n) for n in eligible))
'
}

cmd_plan() {
  local json=0 from=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json=1; shift ;;
      --from-json) from="${2:-}"; [ -n "$from" ] || { echo "error: --from-json needs a file" >&2; exit 2; }; shift 2 ;;
      *) echo "error: unknown flag: $1" >&2; exit 2 ;;
    esac
  done
  if [ -n "$from" ]; then
    [ -f "$from" ] || die "no such file: $from"
    plan_py "$json" < "$from"
  else
    command -v gh >/dev/null 2>&1 || {
      echo "auto-merge: no gh — list the open PRs with the session's GitHub tooling, save them as JSON" >&2
      echo "  (number, title, url, isDraft, baseRefName, headRefOid, labels, mergeable, body," >&2
      echo "  statusCheckRollup) and run: auto-merge.sh plan --from-json <file>" >&2
      exit 4
    }
    gh pr list --state open --limit 100 \
      --json number,title,url,isDraft,baseRefName,headRefOid,labels,mergeable,body,statusCheckRollup \
      2>/dev/null | plan_py "$json" || die "could not list the open PRs"
  fi
}

# ── run / finish: the lock ─────────────────────────────────────────────

# One run at a time on this machine. A mkdir is atomic; the owner file names
# who holds it and since when; a lock older than LOCK_STALE_SECS belongs to a
# run that died and is taken over. Two schedulers on two machines are not
# serialised by this lock, and `on` says to pick one. What keeps a race safe
# anyway is /peer-review's merge with --match-head-commit, and the deploy
# chain's own lock.
lock_take() {
  local lock="$1" since age
  if mkdir "$lock" 2>/dev/null; then
    printf '%s pid=%s since=%s\n' "$(now)" "$$" "$(date +%s)" > "$lock/owner"
    return 0
  fi
  since="$(sed -n 's/.*since=\([0-9][0-9]*\).*/\1/p' "$lock/owner" 2>/dev/null || true)"
  age=$(( $(date +%s) - ${since:-0} ))
  if [ "$age" -gt "$LOCK_STALE_SECS" ]; then
    rm -rf "$lock"
    mkdir "$lock" 2>/dev/null || return 1
    printf '%s pid=%s since=%s (took over a stale lock)\n' "$(now)" "$$" "$(date +%s)" > "$lock/owner"
    return 0
  fi
  return 1
}

cmd_run() {
  [ "$(cfg enabled)" = "true" ] \
    || refuse "auto-merge is off ($CFG enabled: false). Turn it on with: auto-merge.sh on, then land that through a PR"
  local lock
  lock="$(state_dir)/run.lock"
  lock_take "$lock" \
    || refuse "another run holds the lock ($(cat "$lock/owner" 2>/dev/null || echo unknown)); it is released by: auto-merge.sh finish"
  echo "lock=taken"
  cmd_log - run-start ""
  cmd_plan "$@" || { rm -rf "$lock"; exit 1; }
}

cmd_finish() {
  local lock
  lock="$(state_dir)/run.lock"
  rm -rf "$lock"
  cmd_log - run-end "${1:-}"
  echo "lock=released"
}

# ── after: what a merged PR says to do next ────────────────────────────

cmd_after() {
  local n="${1#\#}" execute="" meta state url oid body action env="" reason="" klass
  shift
  case "${1:-}" in
    "") ;; --execute) execute=1 ;;
    *) echo "error: unknown flag: $1 (only --execute)" >&2; exit 2 ;;
  esac
  command -v gh >/dev/null 2>&1 || { echo "auto-merge: no gh — read PR $n's state and manifest with the session's GitHub tooling" >&2; exit 4; }
  meta="$(gh pr view "$n" --json state,url,body,mergeCommit 2>/dev/null)" || die "could not read PR $n"
  state="$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("state",""))')"
  url="$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("url",""))')"
  oid="$(printf '%s' "$meta" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("mergeCommit") or {}).get("oid",""))')"
  [ "$state" = "MERGED" ] || refuse "PR $n is $state, not merged — nothing runs after a merge that did not happen"
  body="$(printf '%s' "$meta" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("body") or "")')"
  local on_merge
  on_merge="$(printf '%s\n' "$body" | bash "$MANIFEST" get on_merge - 2>/dev/null)" \
    || { on_merge=""; }

  case "$on_merge" in
    "") action=queue; reason="the merged PR has no valid merge manifest; a person decides what follows" ;;
    hold) action=hold; reason="the manifest says hold: the work ships with its release" ;;
    release:*) action=queue; reason="release ${on_merge#release:} is cut by a person with /release, never unattended" ;;
    deploy:*)
      env="${on_merge#deploy:}"
      klass="$(bash "$ENVSH" class "$env" 2>/dev/null || true)"
      if [ "$(cfg deploy)" != "true" ]; then
        action=queue; reason="post-merge deploys are off ($CFG deploy: false)"
      else
        case "$klass" in
          dev|staging) action=deploy; reason="$env is $klass-class" ;;
          prod)        action=queue;  reason="$env is prod-class: production goes through /release, by a person" ;;
          "")          action=queue;  reason="$env is not in the environment registry" ;;
          *)           action=queue;  reason="$env is $klass: only a dev- or staging-class environment deploys unattended" ;;
        esac
      fi ;;
    *) action=queue; reason="unrecognised on_merge: $on_merge" ;;
  esac
  echo "pr=$n"
  echo "merge_commit=${oid:-unknown}"
  echo "on_merge=${on_merge:-none}"
  echo "action=$action"
  [ -n "$env" ] && echo "env=$env"
  echo "reason=$reason"
  [ -n "$execute" ] || return 0

  local result rc=0 trunk comment
  case "$action" in
    hold)  result="held — nothing runs on merge" ;;
    queue) result="queued for a person: $reason" ;;
    deploy)
      trunk="$(trunk_branch)"
      [ -z "$(git status --porcelain --untracked-files=no 2>/dev/null)" ] \
        || refuse "uncommitted changes to tracked files — the deploy runs from a clean trunk"
      [ -x ./build/build ] && [ -x ./build/test ] && [ -x ./build/deploy ] \
        || { result="queued for a person: no build → test → deploy chain here (./build/*; see /setup-deploy)"; action=queue; }
      if [ "$action" = deploy ]; then
        git fetch -q origin "$trunk" 2>/dev/null || die "could not fetch $trunk"
        git checkout -q "$trunk" 2>/dev/null || die "could not check out $trunk"
        git merge -q --ff-only "origin/$trunk" 2>/dev/null || die "the local $trunk has diverged from origin/$trunk"
        if [ -n "$oid" ] && ! git merge-base --is-ancestor "$oid" HEAD 2>/dev/null; then
          die "the trunk does not contain PR $n's merge commit $oid"
        fi
        if ./build/build >&2 && ./build/test >&2 && ./build/deploy --env="$env" --intent=deploy >&2; then
          result="deployed $(git rev-parse --short HEAD) to $env (build → test → deploy)"
        else
          rc=7; result="deploy to $env FAILED — see the build, test and deploy records; the merge stands"
        fi
      fi ;;
  esac
  echo "result=$result"
  cmd_log "$n" "after:$action" "$result"
  comment="**/auto-merge:** merged. After merge (\`on_merge: ${on_merge:-none}\`): $result."
  gh pr comment "$n" --body "$comment" >/dev/null 2>&1 \
    || echo "auto-merge: could not comment on PR $n" >&2
  return "$rc"
}

main() {
  local action="${1:-}" root; [ $# -gt 0 ] && shift
  case "$action" in
    -h|--help|help|"") ;;
    *)
      if [ "$action" = plan ] || [ "$action" = run ]; then
        # --from-json takes a path relative to where it was called from.
        local a out=() prev=""
        for a in "$@"; do
          if [ "$prev" = "--from-json" ] && [ -f "$a" ]; then a="$(cd "$(dirname "$a")" && pwd -P)/$(basename "$a")"; fi
          out+=("$a"); prev="$a"
        done
        [ ${#out[@]} -gt 0 ] && set -- "${out[@]}"
      fi
      root="$(rasa_root)" || die "not inside an installed project"; cd "$(cd "$root" && pwd -P)" ;;
  esac
  case "$action" in
    status) cmd_status ;;
    on)     cmd_switch true ;;
    off)    cmd_switch false ;;
    plan)   cmd_plan "$@" ;;
    run)    cmd_run "$@" ;;
    finish) cmd_finish "$@" ;;
    after)  [ $# -ge 1 ] || { usage >&2; exit 2; }; cmd_after "$@" ;;
    log)    [ $# -ge 2 ] || { usage >&2; exit 2; }; cmd_log "$@"; echo "logged" ;;
    -h|--help|help|"") usage ;;
    *) echo "error: unknown action: $action" >&2; exit 2 ;;
  esac
}

main "$@"
