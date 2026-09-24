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
#   peer-review.sh verdict <report>   read an auditor report -> accept | reject
#
# Exit: 0 ok · 1 error · 2 usage · 3 reject (verdict only)
#
# Portability: bash 3.2 (stock macOS). Requires `gh` for `scope` only.

set -euo pipefail

usage() { sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; }

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
rollup = meta.get('statusCheckRollup') or []
failing = [c.get('name', '?') for c in rollup
           if str(c.get('conclusion', '')).upper() not in ('SUCCESS', 'NEUTRAL', 'SKIPPED', '')]
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
print(f"failing_checks={','.join(failing)}")
print("[files]")
for f in files:
    print(f"{f.get('path','')}\t+{f.get('additions',0)}\t-{f.get('deletions',0)}")
PYEOF
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
    verdict)
      [ $# -ge 1 ] || { echo "error: verdict needs a report file" >&2; return 2; }
      cmd_verdict "$1" ;;
    -h|--help|help|"") usage ;;
    *) echo "error: unknown action: $action" >&2; return 2 ;;
  esac
}

main "$@"
