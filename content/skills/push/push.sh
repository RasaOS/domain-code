#!/usr/bin/env bash
# push.sh — commit and push the working tree in one step.
#
# The "save my work" button: one command, no questions. The script
# owns the git plumbing — branch logic, staging (with the
# secret-shaped skip), commit, push. The SKILL.md synthesizes the
# commit message and, when on the trunk, the new branch name.
#
# Branch logic:
#   on the trunk      -> create a new branch, commit there, push it
#                        PR-ready. The PR itself is NOT opened.
#   on a side branch  -> commit and push to that branch.
#
# Nothing is ever committed or pushed to the trunk directly.

set -euo pipefail

PUSH_MAX_MB="${PUSH_MAX_MB:-5}"   # skip untracked files larger than this

usage() {
  cat <<'EOF'
push.sh — commit and push the working tree in one step.

USAGE:
  push.sh status
      Report what a run would do — branch, trunk-or-not, dirty
      count, unpushed count, and the plan.

  push.sh run --message <msg> [--branch <name>]
      Commit all changes and push.
        - On the trunk: create <name> (or a fallback), commit, push.
        - On a side branch: commit and push to it.
      --message is required. --branch is used only when on the
      trunk; ignored otherwise.

EXIT CODES:
  0  success
  1  operational error (not a repo, push failed)
  2  usage error
  3  refused (rebase/merge in progress)
EOF
}

# ── helpers ──────────────────────────────────────────────────────
repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    echo "error: not inside a git repo" >&2
    return 1
  }
}

current_branch() { git symbolic-ref --short -q HEAD 2>/dev/null || true; }

# Default branch: origin/HEAD, else main, else master, else "main".
trunk_branch() {
  local t
  t="$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$t" ]; then echo "${t#origin/}"; return 0; fi
  if git show-ref --verify -q refs/heads/main;   then echo main;   return 0; fi
  if git show-ref --verify -q refs/heads/master; then echo master; return 0; fi
  echo main
}

has_remote() { [ -n "$(git remote 2>/dev/null | head -1)" ]; }

host_tag() {
  local h
  h="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo host)"
  printf '%s' "$h" | tr -cd 'A-Za-z0-9._-'
}

# True when a rebase/merge/cherry-pick/revert/bisect is mid-flight.
op_in_progress() {
  local g
  g="$(git rev-parse --git-dir 2>/dev/null)" || return 1
  [ -d "$g/rebase-merge" ] || [ -d "$g/rebase-apply" ] \
    || [ -f "$g/MERGE_HEAD" ] || [ -f "$g/CHERRY_PICK_HEAD" ] \
    || [ -f "$g/REVERT_HEAD" ] || [ -f "$g/BISECT_LOG" ]
}

# is_secret_shaped <path> — 0 if the file looks credential-bearing.
# Conservative: a false positive costs one skipped file + a warning;
# a false negative pushes a secret. Mirrors git-guard's bouncer.
is_secret_shaped() {
  local path="$1" base
  base="$(basename "$path")"
  # This script necessarily contains secret-detection patterns as
  # literals — never flag the push skill's own files.
  case "$path" in
    */skills/push/*) return 1 ;;
  esac
  case "$base" in
    .env-template|.env.example|.env-example|.env.sample) return 1 ;;
    .env|.env.*|*.env) return 0 ;;
    *service[-_]account*|*credential*|*secret*|*.secrets) return 0 ;;
    id_rsa*|id_dsa*|id_ecdsa*|id_ed25519*) return 0 ;;
    *.pem|*.key|*.p12|*.pfx|*.pkcs12|*.keystore|*.jks) return 0 ;;
  esac
  if grep -Ilq -E \
    'BEGIN [A-Z ]*PRIVATE KEY|"private_key"[[:space:]]*:|AKIA[0-9A-Z]{16}|aws_secret_access_key' \
    "$path" 2>/dev/null; then
    return 0
  fi
  return 1
}

file_too_big() {
  local path="$1" bytes
  bytes="$(wc -c < "$path" 2>/dev/null || echo 0)"
  [ "$bytes" -gt $(( PUSH_MAX_MB * 1024 * 1024 )) ]
}

dirty_count() { git status --porcelain 2>/dev/null | wc -l | tr -d ' '; }

# Commits on HEAD not on its upstream (0 if no upstream).
unpushed_count() {
  if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0
  else
    echo 0
  fi
}

# Stage tracked changes + untracked files, skipping secret-shaped and
# oversized ones. Skipped paths are reported on stderr. Never fails.
SKIPPED=()
stage_changes() {
  SKIPPED=()
  git add -u 2>/dev/null || true
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if is_secret_shaped "$f"; then SKIPPED+=("$f (secret-shaped)"); continue; fi
    if file_too_big "$f";    then SKIPPED+=("$f (>${PUSH_MAX_MB}MB)"); continue; fi
    git add -- "$f" 2>/dev/null || true
  done < <(git ls-files --others --exclude-standard 2>/dev/null)

  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    echo "push: NOT included (review by hand):" >&2
    printf '  - %s\n' "${SKIPPED[@]}" >&2
  fi
}

# ── status ───────────────────────────────────────────────────────
cmd_status() {
  repo_root >/dev/null || return 1
  local branch trunk dirty ahead
  branch="$(current_branch)"
  trunk="$(trunk_branch)"
  dirty="$(dirty_count)"
  ahead="$(unpushed_count)"

  echo "push: status"
  echo "  branch        ${branch:-(detached)}"
  echo "  dirty paths   $dirty"
  echo "  unpushed      $ahead commit(s)"
  if [ -z "$branch" ] || [ "$branch" = "$trunk" ]; then
    if [ "$dirty" -eq 0 ] && [ "$ahead" -eq 0 ]; then
      echo "  plan          nothing to do — clean and nothing unpushed"
    else
      echo "  plan          on the trunk → create a branch, commit, push (PR-ready)"
    fi
  else
    if [ "$dirty" -eq 0 ] && [ "$ahead" -eq 0 ]; then
      echo "  plan          nothing to do — clean and nothing unpushed"
    else
      echo "  plan          commit and push to '$branch'"
    fi
  fi
}

# ── run ──────────────────────────────────────────────────────────
cmd_run() {
  repo_root >/dev/null || return 1

  local message="" want_branch=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --message) message="${2:-}"; shift 2 || return 2 ;;
      --branch)  want_branch="${2:-}"; shift 2 || return 2 ;;
      *) echo "error: unknown flag: $1" >&2; usage >&2; return 2 ;;
    esac
  done
  [ -n "$message" ] || { echo "error: --message <msg> is required" >&2; return 2; }

  if op_in_progress; then
    echo "✗ push: a rebase/merge/cherry-pick is in progress — finish it first." >&2
    return 3
  fi

  local branch trunk dirty ahead created=0 staged=0
  branch="$(current_branch)"
  trunk="$(trunk_branch)"
  dirty="$(dirty_count)"
  ahead="$(unpushed_count)"

  if [ "$dirty" -eq 0 ] && [ "$ahead" -eq 0 ]; then
    echo "push: nothing to do — working tree clean, nothing unpushed."
    return 0
  fi

  # Stage first — staging is not committing, so it's safe on the
  # trunk, and the staged index follows a later `checkout -b`.
  if [ "$dirty" -gt 0 ]; then
    stage_changes
    git diff --cached --quiet 2>/dev/null || staged=1
  fi

  # If nothing got staged and nothing was already unpushed, there's
  # genuinely nothing to push — don't create a branch, don't push.
  if [ "$staged" -eq 0 ] && [ "$ahead" -eq 0 ]; then
    echo "push: nothing to push — the changes present are all skipped"
    echo "      (secret-shaped / oversized) or git-ignored."
    return 0
  fi

  # On the trunk (or detached): move onto a branch first. Never
  # commit or push the trunk directly. The staged index comes along.
  if [ -z "$branch" ] || [ "$branch" = "$trunk" ]; then
    local target="$want_branch"
    [ -n "$target" ] || target="chore/push-$(host_tag)-$(date '+%Y%m%d-%H%M')"
    if ! git checkout -q -b "$target" 2>/dev/null; then
      echo "✗ push: could not create branch '$target'." >&2
      return 1
    fi
    branch="$target"
    created=1
    echo "push: on the trunk → moved work onto new branch '$branch'."
  fi

  # Commit whatever is staged.
  if [ "$staged" -eq 1 ]; then
    git commit -q -m "$message" || {
      echo "✗ push: commit failed." >&2; return 1; }
    echo "push: committed — \"$message\""
  fi

  # Push.
  if ! has_remote; then
    echo "push: no remote configured — committed locally, not pushed." >&2
    return 0
  fi
  if git push -q -u origin "$branch" 2>/dev/null; then
    echo "push: pushed → origin/$branch"
  else
    echo "push: commit is safe locally, but the push failed (offline?). Re-run /push when back online." >&2
    return 1
  fi

  # A branch cut from the trunk is PR-ready. Surface it; do NOT open it.
  if [ "$created" -eq 1 ]; then
    local url=""
    url="$(git remote get-url origin 2>/dev/null || true)"
    case "$url" in
      git@github.com:*) url="https://github.com/${url#git@github.com:}" ;;
    esac
    url="${url%.git}"
    echo ""
    echo "push: '$branch' is PR-ready. The PR was NOT opened — open it when you're ready:"
    if [ -n "$url" ]; then
      echo "  $url/compare/$branch?expand=1"
    fi
    echo "  or: gh pr create --head $branch"
  fi
}

# ── dispatch ─────────────────────────────────────────────────────
main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    -h|--help|help|"") usage; return 0 ;;
    status) cmd_status ;;
    run)    cmd_run "$@" ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
