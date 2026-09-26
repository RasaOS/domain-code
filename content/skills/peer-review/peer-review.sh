#!/usr/bin/env bash
# peer-review.sh — the deterministic half of /peer-review.
#
# Follows the /audit split: the script does mechanics, the agent does judgment.
# The point of the split here is narrower and load-bearing — the REVIEWER'S
# SCOPE MUST NOT COME FROM THE AUTHOR. If the calling model decides which files
# matter and narrates them into the subagent's prompt, the author's framing is
# reproduced inside the reviewer's window and the isolation buys nothing. This
# script derives scope from the remote instead.
#
# It also exists because v0.48.0 (72f1149) deleted /peer-review's Process
# section, and with it the only instruction that fetched the PR at all. After
# that, "read the diff" was satisfied by the authoring session's memory of
# having written it.
#
# Usage:
#   peer-review.sh scope <N>          resolve the PR, write the diff, emit scope
#   peer-review.sh checks <N>         re-read CI right before a merge -> pass | not
#   peer-review.sh verdict <report>   read an auditor report -> accept | reject
#
# Exit: 0 ok · 1 error · 2 usage · 3 reject (verdict only)
#       checks only: 0 pass · 4 failing · 5 pending · 6 no checks reported
#
# Portability: bash 3.2 (stock macOS). Requires `gh` for `scope` and `checks`.

set -euo pipefail

usage() { sed -n '3,24p' "$0" | sed 's/^# \{0,1\}//'; }

need_gh() {
  command -v gh >/dev/null 2>&1 || {
    echo "error: gh is required to fetch the PR" >&2
    echo "  the whole point of this step is reading the pushed artifact rather" >&2
    echo "  than trusting the calling session's memory of it — so there is no" >&2
    echo "  offline fallback here, deliberately." >&2
    return 1
  }
}

cmd_scope() {
  local n="$1"
  need_gh || return 1
  n="${n#\#}"

  local meta
  meta="$(gh pr view "$n" --json number,title,author,baseRefName,headRefName,files,statusCheckRollup 2>/dev/null)" || {
    echo "error: could not read PR $n from the remote" >&2
    return 1
  }

  local diff_file
  diff_file="$(mktemp "${TMPDIR:-/tmp}/pr-${n}-diff.XXXXXX")"
  gh pr diff "$n" > "$diff_file" 2>/dev/null || {
    echo "error: could not fetch the diff for PR $n" >&2
    rm -f "$diff_file"
    return 1
  }

  # The diff goes to a FILE the auditor reads with its Read tool, rather than
  # the auditor being handed a PR number. auditor.md restricts Bash to
  # read-only diagnostics and does not grant `gh`; handing it "PR #142" makes
  # it either refuse or fetch a branch — a network and refs write — while
  # believing itself read-only. A path keeps that contract intact.
  python3 - "$meta" "$diff_file" <<'PYEOF'
import json, sys, os
meta = json.loads(sys.argv[1])
diff = sys.argv[2]
files = meta.get('files') or []
print(f"pr={meta.get('number','')}")
print(f"title={meta.get('title','')}")
# The PR author is a GitHub login. It is a FOREIGN identity: it does not share
# a namespace with the library's rasa_actor (RASA_ACTOR / git name / OS user),
# so the two must never be compared for equality. Labelled, never asserted
# against.
print(f"pr_author_github={(meta.get('author') or {}).get('login','')}")
print(f"base={meta.get('baseRefName','')}")
print(f"head={meta.get('headRefName','')}")
print(f"file_count={len(files)}")
print(f"diff_file={diff}")
print(f"diff_bytes={os.path.getsize(diff)}")
print("[files]")
for f in files:
    print(f"{f.get('path','')}\t+{f.get('additions',0)}\t-{f.get('deletions',0)}")
PYEOF
  printf '%s' "$meta" | summarize_checks
}

# summarize_checks — read `gh pr view --json statusCheckRollup` on stdin and
# classify every entry. Emits checks_state (pass | fail | pending | none),
# checks_total, failing_checks and pending_checks.
#
# FAIL-CLOSED. Before 0.55.1 a check counted as passing whenever its
# `conclusion` was not a known failure — and a blank conclusion was on the
# pass list. The rollup carries two shapes: a CheckRun (status + conclusion,
# blank conclusion while it is still running) and a legacy StatusContext
# (state, no conclusion key at all). So a running check AND a failed status
# context both read as green, in the one skill that holds merge authority.
# Now: only an explicit success passes; running is pending; anything
# unrecognised is failing; an empty rollup is `none`, never `pass`.
summarize_checks() {
  python3 -c '
import json, sys
rollup = (json.load(sys.stdin) or {}).get("statusCheckRollup") or []
OK = ("SUCCESS", "NEUTRAL", "SKIPPED")
failing, pending = [], []
for c in rollup:
    kind = str(c.get("__typename", ""))
    if kind == "StatusContext" or ("state" in c and "status" not in c):
        name = c.get("context") or c.get("name") or "?"
        state = str(c.get("state") or "").upper()
        if state == "SUCCESS":
            continue
        (pending if state in ("PENDING", "EXPECTED") else failing).append(name)
    elif kind == "CheckRun" or "status" in c or "conclusion" in c:
        name = c.get("name") or "?"
        if str(c.get("status") or "COMPLETED").upper() != "COMPLETED":
            pending.append(name)
        elif str(c.get("conclusion") or "").upper() not in OK:
            failing.append(name)
    else:
        failing.append(c.get("name") or c.get("context") or "?")
state = ("none" if not rollup else "fail" if failing
         else "pending" if pending else "pass")
print(f"checks_state={state}")
print(f"checks_total={len(rollup)}")
print("failing_checks=" + ",".join(failing))
print("pending_checks=" + ",".join(pending))
'
}

# checks <N> — the merge gate. Re-reads the rollup from the remote at the
# moment of merging (the one `scope` read may be minutes stale) and exits 0
# only on `pass`. Branch protection is not relied on: a repo without it would
# otherwise merge over a red or still-running build.
cmd_checks() {
  local n="${1#\#}" meta out state
  need_gh || return 1
  meta="$(gh pr view "$n" --json statusCheckRollup 2>/dev/null)" || {
    echo "error: could not read PR $n's checks from the remote" >&2
    return 1
  }
  out="$(printf '%s' "$meta" | summarize_checks)" || return 1
  printf '%s\n' "$out"
  state="$(printf '%s\n' "$out" | sed -n 's/^checks_state=//p')"
  case "$state" in
    pass)    return 0 ;;
    fail)    echo "  do not merge: a check is failing" >&2; return 4 ;;
    pending) echo "  do not merge: a check is still running" >&2; return 5 ;;
    *)       echo "  do not merge: no checks reported — nothing verified this PR" >&2; return 6 ;;
  esac
}

# verdict <report-file> — map auditor severities to a merge decision.
#
# CRITICAL blocks. HIGH does NOT: auditor.md defines HIGH as "action this
# batch", a backlog horizon rather than a merge verdict. Blocking on HIGH
# across many repos produces chronic false rejects on pre-existing debt that a
# diff merely brushes, and a mandatory step that cries wolf is the step that
# gets turned off.
#
# Exit 0 = accept, 3 = reject. A missing or unreadable report is exit 1 —
# never a pass. "The reviewer did not run" must not look like "the reviewer
# found nothing".
cmd_verdict() {
  local f="$1"
  [ -f "$f" ] || {
    echo "error: no auditor report at $f — cannot accept without a verdict" >&2
    return 1
  }
  [ -s "$f" ] || {
    echo "error: auditor report is empty — cannot accept without a verdict" >&2
    return 1
  }

  local crit high
  crit="$(grep -c 'CRITICAL' "$f" || true)"
  high="$(grep -c 'HIGH' "$f" || true)"
  crit="${crit:-0}"; high="${high:-0}"

  if [ "$crit" -gt 0 ]; then
    echo "reject: $crit CRITICAL finding(s)"
    echo "  Reject, do not ask. Rule 2's 'invocation is consent' forbids"
    echo "  asking, not stopping — a CRITICAL terminates in a verdict, never"
    echo "  in 'merge anyway?'. Hand the PR back to its author."
    return 3
  fi

  echo "accept: 0 CRITICAL, $high HIGH"
  [ "$high" -gt 0 ] && echo "  Name each HIGH in the approval body as a non-blocking concern."
  return 0
}

main() {
  local action="${1:-}"; [ $# -gt 0 ] && shift
  case "$action" in
    scope)
      [ $# -ge 1 ] || { echo "error: scope needs a PR number" >&2; return 2; }
      cmd_scope "$1" ;;
    checks)
      [ $# -ge 1 ] || { echo "error: checks needs a PR number" >&2; return 2; }
      cmd_checks "$1" ;;
    verdict)
      [ $# -ge 1 ] || { echo "error: verdict needs a report file" >&2; return 2; }
      cmd_verdict "$1" ;;
    -h|--help|help|"") usage ;;
    *) echo "error: unknown action: $action" >&2; return 2 ;;
  esac
}

main "$@"
