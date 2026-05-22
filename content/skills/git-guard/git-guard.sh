#!/usr/bin/env bash
# git-guard.sh — git-hygiene lockdown + multi-machine work safety.
#
# Owns the deterministic mechanics of: installing/removing the hook
# set, the auto-WIP-capture, the abandoned-work audit, the secret
# scan, and the trunk-protection guards. SKILL.md routes the on/off/
# status choice; everything else is hook-driven and runs unattended.
#
# Hooks installed by `on`:
#   Claude Code (.claude/settings.local.json, per-user, gitignored):
#     SessionStart -> audit        (fetch, ff-pull, surface abandoned work)
#     Stop         -> checkpoint   (autosave if the change threshold tripped)
#     PreCompact   -> autosave     (capture before context compaction)
#     SessionEnd   -> session-end  (final capture + leftover warning)
#   Git ($GIT_COMMON_DIR/hooks/, per-repo, per-machine):
#     pre-commit   -> guard-commit (reject trunk commits + staged secrets)
#     pre-push     -> guard-push   (reject pushes to trunk)
#   Plus: git config pull.ff only.

set -euo pipefail

# ── tunables (env-overridable) ───────────────────────────────────
# Autosave fires when ANY threshold trips. The time backstop is the
# one that catches forgetfulness — a small change left abandoned.
GIT_GUARD_LINES="${GIT_GUARD_LINES:-80}"      # changed lines (ins+del)
GIT_GUARD_FILES="${GIT_GUARD_FILES:-5}"       # changed files
GIT_GUARD_MINUTES="${GIT_GUARD_MINUTES:-20}"  # minutes since last save
GIT_GUARD_MAX_MB="${GIT_GUARD_MAX_MB:-5}"     # skip untracked files bigger than this
GIT_GUARD_PUSH="${GIT_GUARD_PUSH:-1}"         # 0 = commit only, never push
# Escape hatches — deliberate overrides, NOT --no-verify (forbidden):
#   GIT_GUARD_ALLOW_MAIN=1    permit a commit/push to the trunk branch
#   GIT_GUARD_ALLOW_SECRET=1  permit a commit with a secret-shaped file

# Claude Code hooks the on/off toggle installs. "<Event>|<command>".
declare -a CC_HOOKS=(
  "SessionStart|bash .claude/skills/git-guard/git-guard.sh audit"
  "Stop|bash .claude/skills/git-guard/git-guard.sh checkpoint"
  "PreCompact|bash .claude/skills/git-guard/git-guard.sh autosave"
  "SessionEnd|bash .claude/skills/git-guard/git-guard.sh session-end"
)
# Git hooks the on/off toggle installs. "<hook-file>|<subcommand>".
declare -a GIT_HOOKS=(
  "pre-commit|guard-commit"
  "pre-push|guard-push"
)
CC_TARGET=".claude/settings.local.json"

usage() {
  cat <<'EOF'
git-guard.sh — git-hygiene lockdown + multi-machine work safety.

USAGE:
  git-guard.sh on | off | status

  on        Install all hooks (Claude Code + git) and `pull.ff only`.
  off       Remove everything git-guard installed.
  status    Report ON / OFF / PARTIAL.

HOOK HANDLERS (called by hooks — not for direct use):
  audit         SessionStart: fetch, ff-pull, surface abandoned work.
  checkpoint    Stop: autosave if a change threshold tripped.
  autosave      Capture the working tree as a wip: commit + push.
  session-end   SessionEnd: final capture + warn on leftovers.
  guard-commit  pre-commit: block trunk commits + staged secrets.
  guard-push    pre-push: block pushes to trunk.
  scan-secrets [--staged]   Scan tracked (or staged) files for secrets.

EXIT CODES:
  0  success / clean
  1  operational error
  2  usage error
  3  refused (guard rejected the operation)
EOF
}

# ── helpers ──────────────────────────────────────────────────────
repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    echo "error: not inside a git repo" >&2
    return 1
  }
}

# Shared .git dir — correct inside worktrees (hooks + markers live here).
git_common_dir() {
  local d
  d="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  ( cd -P "$d" 2>/dev/null && pwd -P )
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

# True when a rebase/merge/cherry-pick/revert/bisect is mid-flight —
# autosave must never touch the tree during one.
op_in_progress() {
  local g; g="$(git_common_dir)" || return 1
  [ -d "$g/rebase-merge" ] || [ -d "$g/rebase-apply" ] \
    || [ -f "$g/MERGE_HEAD" ] || [ -f "$g/CHERRY_PICK_HEAD" ] \
    || [ -f "$g/REVERT_HEAD" ] || [ -f "$g/BISECT_LOG" ]
}

host_tag() {
  local h
  h="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo host)"
  printf '%s' "$h" | tr -cd 'A-Za-z0-9._-'
}

marker_file() { echo "$(git_common_dir)/git-guard-last-save"; }

# Resolve this script's absolute path (synced project or kit repo).
self_path() {
  local root; root="$(repo_root)" || return 1
  if   [ -f "$root/.claude/skills/git-guard/git-guard.sh" ]; then
    echo "$root/.claude/skills/git-guard/git-guard.sh"
  elif [ -f "$root/kit/skills/git-guard/git-guard.sh" ]; then
    echo "$root/kit/skills/git-guard/git-guard.sh"
  else
    echo "error: git-guard.sh not found in expected locations" >&2
    return 1
  fi
}

install_hook_script() {
  local root; root="$(repo_root)" || return 1
  if   [ -f "$root/.claude/skills/install-hook/install-hook.sh" ]; then
    echo "$root/.claude/skills/install-hook/install-hook.sh"
  elif [ -f "$root/kit/skills/install-hook/install-hook.sh" ]; then
    echo "$root/kit/skills/install-hook/install-hook.sh"
  else
    echo "error: install-hook.sh not found — git-guard needs it" >&2
    return 1
  fi
}

# is_secret_shaped <path> — 0 if the file looks credential-bearing,
# by name or by content. Conservative: a false positive costs one
# skipped autosave + a warning; a false negative pushes a secret.
is_secret_shaped() {
  local path="$1" base
  base="$(basename "$path")"
  # The git-guard skill itself necessarily contains secret-detection
  # patterns as literals — never flag its own files as secrets.
  case "$path" in
    */skills/git-guard/*) return 1 ;;
  esac
  case "$base" in
    .env-template|.env.example|.env-example|.env.sample) return 1 ;;
    .env|.env.*|*.env) return 0 ;;
    *service[-_]account*|*credential*|*secret*|*.secrets) return 0 ;;
    id_rsa*|id_dsa*|id_ecdsa*|id_ed25519*) return 0 ;;
    *.pem|*.key|*.p12|*.pfx|*.pkcs12|*.keystore|*.jks) return 0 ;;
  esac
  # Content scan — text files only.
  if grep -Ilq -E \
    'BEGIN [A-Z ]*PRIVATE KEY|"private_key"[[:space:]]*:|AKIA[0-9A-Z]{16}|aws_secret_access_key' \
    "$path" 2>/dev/null; then
    return 0
  fi
  return 1
}

# file_too_big <path> — 0 if larger than GIT_GUARD_MAX_MB.
file_too_big() {
  local path="$1" bytes
  bytes="$(wc -c < "$path" 2>/dev/null || echo 0)"
  [ "$bytes" -gt $(( GIT_GUARD_MAX_MB * 1024 * 1024 )) ]
}

# ── git-hook shim install / remove ───────────────────────────────
GG_OPEN="# >>> git-guard >>>"
GG_CLOSE="# <<< git-guard <<<"

_strip_block() {
  local file="$1"
  [ -f "$file" ] || return 0
  awk -v o="$GG_OPEN" -v c="$GG_CLOSE" '
    index($0,o){skip=1}
    !skip{print}
    index($0,c){skip=0}
  ' "$file" > "$file.gg.tmp" && mv "$file.gg.tmp" "$file"
}

install_git_hook() {
  local hook="$1" sub="$2"
  local hooks_dir file self block
  hooks_dir="$(git_common_dir)/hooks"
  mkdir -p "$hooks_dir"
  file="$hooks_dir/$hook"
  self="$(self_path)" || return 1
  block="$(printf '%s\n%s\n%s' \
    "$GG_OPEN" \
    "bash \"$self\" $sub \"\$@\" || exit \$?" \
    "$GG_CLOSE")"

  if [ ! -f "$file" ]; then
    printf '#!/usr/bin/env bash\n%s\n' "$block" > "$file"
  elif grep -qF "$GG_OPEN" "$file"; then
    _strip_block "$file"                       # idempotent: refresh block
    printf '%s\n' "$block" >> "$file"
  else
    { head -n1 "$file"; printf '%s\n' "$block"; tail -n +2 "$file"; } \
      > "$file.gg.tmp" && mv "$file.gg.tmp" "$file"
  fi
  chmod +x "$file"
}

remove_git_hook() {
  local hook="$1"
  local file; file="$(git_common_dir)/hooks/$hook"
  [ -f "$file" ] || return 0
  _strip_block "$file"
  # If only a shebang + blank lines remain, we created it — drop it.
  if ! grep -qvE '^[[:space:]]*(#!.*)?[[:space:]]*$' "$file"; then
    rm -f "$file"
  fi
}

git_hook_installed() {
  local file; file="$(git_common_dir)/hooks/$1"
  [ -f "$file" ] && grep -qF "$GG_OPEN" "$file"
}

# ── on / off / status ────────────────────────────────────────────
cmd_on() {
  local install_hook entry event command hook sub
  install_hook="$(install_hook_script)" || return 1

  for entry in "${CC_HOOKS[@]}"; do
    event="${entry%%|*}"; command="${entry#*|}"
    bash "$install_hook" add "$event" "$command" --target "$CC_TARGET" >/dev/null
  done
  for entry in "${GIT_HOOKS[@]}"; do
    hook="${entry%%|*}"; sub="${entry#*|}"
    install_git_hook "$hook" "$sub"
  done
  git config pull.ff only

  cat <<EOF

git-guard: ON
  Claude Code hooks ($CC_TARGET):
    SessionStart → audit        fetch + ff-pull + surface abandoned work
    Stop         → checkpoint   autosave when the change threshold trips
    PreCompact   → autosave     capture before context compaction
    SessionEnd   → session-end  final capture + leftover warning
  Git hooks ($(git_common_dir)/hooks):
    pre-commit   → block trunk commits + staged secrets
    pre-push     → block pushes to trunk
  git config: pull.ff = only

Claude Code hooks take effect on the NEXT session start.
Toggle off with: bash <skill-dir>/git-guard.sh off
EOF
}

cmd_off() {
  local install_hook entry event command hook
  install_hook="$(install_hook_script)" || return 1

  for entry in "${CC_HOOKS[@]}"; do
    event="${entry%%|*}"; command="${entry#*|}"
    bash "$install_hook" remove "$event" "$command" --target "$CC_TARGET" >/dev/null
  done
  for entry in "${GIT_HOOKS[@]}"; do
    hook="${entry%%|*}"
    remove_git_hook "$hook"
  done
  if [ "$(git config --get pull.ff 2>/dev/null || true)" = "only" ]; then
    git config --unset pull.ff 2>/dev/null || true
  fi
  echo ""
  echo "git-guard: OFF — all hooks removed, pull.ff unset."
}

cmd_status() {
  local root target cc_count cc_total entry event command git_count git_total hook
  root="$(repo_root)" || return 1
  target="$root/$CC_TARGET"
  cc_count=0; cc_total=${#CC_HOOKS[@]}
  for entry in "${CC_HOOKS[@]}"; do
    command="${entry#*|}"
    [ -f "$target" ] && grep -qF "$command" "$target" 2>/dev/null && cc_count=$((cc_count+1))
  done
  git_count=0; git_total=${#GIT_HOOKS[@]}
  for entry in "${GIT_HOOKS[@]}"; do
    hook="${entry%%|*}"
    git_hook_installed "$hook" && git_count=$((git_count+1))
  done

  local ff total have
  ff="$(git config --get pull.ff 2>/dev/null || echo unset)"
  total=$(( cc_total + git_total + 1 ))
  have=$(( cc_count + git_count ))
  [ "$ff" = "only" ] && have=$(( have + 1 ))

  echo "git-guard: Claude Code $cc_count/$cc_total · git hooks $git_count/$git_total · pull.ff=$ff"
  if   [ "$have" -eq "$total" ]; then echo "  ON ($have/$total)"
  elif [ "$have" -eq 0 ];        then echo "  OFF (0/$total)"
  else echo "  PARTIAL ($have/$total) — run 'git-guard on' to fully install"
  fi
}

# ── autosave ─────────────────────────────────────────────────────
cmd_autosave() {
  # Hook-safe: never abort a session. Returns 0 on no-op.
  repo_root >/dev/null 2>&1 || return 0
  op_in_progress && { echo "git-guard: rebase/merge in progress — autosave skipped" >&2; return 0; }
  has_remote || true   # offline / no remote is fine: commit still happens

  local branch trunk host ts
  branch="$(current_branch)"
  trunk="$(trunk_branch)"
  host="$(host_tag)"
  ts="$(date '+%Y-%m-%dT%H:%M')"

  # Rescue off trunk / detached HEAD onto an isolated wip branch.
  if [ -z "$branch" ] || [ "$branch" = "$trunk" ]; then
    local wip="wip/${host}-$(date '+%Y%m%d-%H%M')"
    git checkout -q -b "$wip" 2>/dev/null || git checkout -q "$wip" 2>/dev/null || {
      echo "git-guard: could not move off $trunk — autosave skipped" >&2; return 0; }
    branch="$wip"
    echo "git-guard: rescued work onto isolated branch $wip" >&2
  fi

  git add -u 2>/dev/null || true   # tracked changes

  # Untracked files: add unless secret-shaped or oversized.
  local skipped=() f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if is_secret_shaped "$f"; then skipped+=("$f (secret-shaped)"); continue; fi
    if file_too_big "$f";    then skipped+=("$f (>${GIT_GUARD_MAX_MB}MB)"); continue; fi
    git add -- "$f" 2>/dev/null || true
  done < <(git ls-files --others --exclude-standard 2>/dev/null)

  if [ "${#skipped[@]}" -gt 0 ]; then
    echo "git-guard: NOT autosaved (review by hand):" >&2
    printf '  - %s\n' "${skipped[@]}" >&2
  fi

  if git diff --cached --quiet 2>/dev/null; then
    return 0   # nothing staged — silent no-op
  fi

  if ! git commit -q -m "wip: autosave [$host] $ts" 2>/dev/null; then
    echo "git-guard: autosave commit was blocked (secret in staged content?) — run 'git-guard scan-secrets --staged'" >&2
    return 1
  fi
  date +%s > "$(marker_file)" 2>/dev/null || true

  if [ "$GIT_GUARD_PUSH" != "0" ] && has_remote; then
    git push -q -u origin "$branch" >/dev/null 2>&1 \
      && echo "git-guard: autosaved + pushed → $branch" \
      || echo "git-guard: autosaved → $branch (push deferred — offline?)"
  else
    echo "git-guard: autosaved → $branch (local only)"
  fi
}

# ── checkpoint (Stop hook — threshold-gated autosave) ────────────
cmd_checkpoint() {
  repo_root >/dev/null 2>&1 || return 0
  op_in_progress && return 0

  # Nothing dirty → nothing to do.
  [ -n "$(git status --porcelain 2>/dev/null)" ] || return 0

  local files lines stat marker now last mins
  files="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  stat="$(git diff HEAD --shortstat 2>/dev/null || true)"
  lines=0
  if [ -n "$stat" ]; then
    local ins del
    ins="$(echo "$stat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo 0)"
    del="$(echo "$stat" | grep -oE '[0-9]+ deletion'  | grep -oE '[0-9]+' || echo 0)"
    lines=$(( ${ins:-0} + ${del:-0} ))
  fi

  marker="$(marker_file)"
  now="$(date +%s)"
  if [ -f "$marker" ]; then
    last="$(cat "$marker" 2>/dev/null || echo "$now")"
  else
    echo "$now" > "$marker" 2>/dev/null || true   # start the clock
    last="$now"
  fi
  mins=$(( (now - last) / 60 ))

  if [ "$lines" -ge "$GIT_GUARD_LINES" ] \
     || [ "$files" -ge "$GIT_GUARD_FILES" ] \
     || [ "$mins" -ge "$GIT_GUARD_MINUTES" ]; then
    cmd_autosave
  fi
  return 0
}

# ── session-end (SessionEnd hook) ────────────────────────────────
cmd_session_end() {
  repo_root >/dev/null 2>&1 || return 0
  cmd_autosave || true
  # Anything still uncommitted, or commits not pushed → loud warning.
  local dirty ahead branch
  branch="$(current_branch)"
  dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  ahead=0
  if [ -n "$branch" ] && git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
  fi
  if [ "${dirty:-0}" -gt 0 ] || [ "${ahead:-0}" -gt 0 ]; then
    echo "⚠️  git-guard: session ending with unsaved work —" >&2
    [ "${dirty:-0}" -gt 0 ] && echo "    $dirty path(s) still uncommitted (secret-shaped / oversized?)" >&2
    [ "${ahead:-0}" -gt 0 ] && echo "    $ahead commit(s) not pushed on $branch" >&2
  fi
  return 0
}

# ── audit (SessionStart hook) ────────────────────────────────────
cmd_audit() {
  repo_root >/dev/null 2>&1 || { return 0; }

  local branch trunk report=""
  branch="$(current_branch)"
  trunk="$(trunk_branch)"

  git fetch --quiet --prune --all 2>/dev/null || true

  # Auto ff-pull the current branch when cleanly behind.
  local pulled=0
  if [ -n "$branch" ] && git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    local behind ahead
    behind="$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)"
    ahead="$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    if [ "$behind" -gt 0 ] && [ "$ahead" -eq 0 ] \
       && [ -z "$(git status --porcelain 2>/dev/null)" ]; then
      git merge --ff-only '@{u}' >/dev/null 2>&1 && pulled="$behind"
    fi
  fi
  [ "$pulled" -gt 0 ] && report+="• Fast-forwarded $branch by $pulled commit(s) from origin.\n"

  # Current worktree dirty?
  local dirty
  dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  [ "${dirty:-0}" -gt 0 ] && report+="• Current branch ($branch) has $dirty uncommitted path(s).\n"

  # Local branches with unpushed commits, and wip/ branches.
  local line bn track
  while IFS= read -r line; do
    bn="${line%%|*}"; track="${line#*|}"
    case "$track" in
      *ahead*) report+="• Branch '$bn' has unpushed commits ($track).\n" ;;
    esac
    case "$bn" in
      wip/*) report+="• WIP branch '$bn' exists — leftover autosave; merge or delete it.\n" ;;
    esac
  done < <(git for-each-ref --format='%(refname:short)|%(upstream:track)' refs/heads 2>/dev/null)

  # Other worktrees with dirty trees.
  local wt
  while IFS= read -r wt; do
    [ -n "$wt" ] || continue
    [ "$wt" = "$(repo_root)" ] && continue
    if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
      report+="• Worktree '$wt' has uncommitted changes.\n"
    fi
  done < <(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')

  local body
  if [ -z "$report" ]; then
    body="✅ git-guard: clean — trunk current, no abandoned work detected."
  else
    body="⚠️ **git-guard found work that needs attention:**\n\n${report}\nReconcile before starting new work — commit, push, or clean up the branches above."
  fi

  # Emit as SessionStart additionalContext when python3 is available;
  # otherwise plain stdout (still visible, just not injected).
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$body" <<'PY'
import json, sys
body = sys.argv[1].replace("\\n", "\n")
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": body}}))
PY
  else
    printf '%b\n' "$body"
  fi
  return 0
}

# ── guards (git hooks) ───────────────────────────────────────────
cmd_guard_commit() {
  repo_root >/dev/null 2>&1 || return 0
  local branch trunk
  branch="$(current_branch)"; trunk="$(trunk_branch)"

  if [ "$branch" = "$trunk" ] && [ "${GIT_GUARD_ALLOW_MAIN:-0}" != "1" ]; then
    cat >&2 <<EOF
✗ git-guard: refusing to commit directly to '$trunk'.
  Work belongs on a branch. Move this commit onto one:
      git branch <name> && git reset --soft HEAD@{0} && git checkout <name>
  …or just: git checkout -b <name>
  Deliberate override (rare): GIT_GUARD_ALLOW_MAIN=1 git commit ...
EOF
    return 3
  fi

  # Staged secrets.
  local hits f
  hits=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    is_secret_shaped "$f" && hits+="  - $f"$'\n'
  done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)

  if [ -n "$hits" ] && [ "${GIT_GUARD_ALLOW_SECRET:-0}" != "1" ]; then
    cat >&2 <<EOF
✗ git-guard: refusing to commit — secret-shaped file(s) staged:
$hits  Unstage them and add to .gitignore. If a false positive:
  GIT_GUARD_ALLOW_SECRET=1 git commit ...
EOF
    return 3
  fi
  return 0
}

cmd_guard_push() {
  repo_root >/dev/null 2>&1 || return 0
  local trunk; trunk="$(trunk_branch)"
  [ "${GIT_GUARD_ALLOW_MAIN:-0}" = "1" ] && return 0

  # pre-push feeds "<localref> <localsha> <remoteref> <remotesha>" on stdin.
  local localref localsha remoteref remotesha
  while read -r localref localsha remoteref remotesha; do
    [ -n "$remoteref" ] || continue
    if [ "$remoteref" = "refs/heads/$trunk" ]; then
      cat >&2 <<EOF
✗ git-guard: refusing to push directly to '$trunk'.
  Trunk moves through reviewed PRs, not direct pushes.
  Deliberate override (rare): GIT_GUARD_ALLOW_MAIN=1 git push ...
EOF
      return 3
    fi
  done
  return 0
}

# ── scan-secrets (standalone + used by guard-commit) ─────────────
cmd_scan_secrets() {
  repo_root >/dev/null 2>&1 || { echo "error: not in a git repo" >&2; return 1; }
  local staged=0
  [ "${1:-}" = "--staged" ] && staged=1

  local hits=0 f
  if [ "$staged" -eq 1 ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && [ -f "$f" ] || continue
      is_secret_shaped "$f" && { echo "  secret-shaped: $f"; hits=$((hits+1)); }
    done < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)
  else
    while IFS= read -r f; do
      [ -n "$f" ] && [ -f "$f" ] || continue
      is_secret_shaped "$f" && { echo "  secret-shaped: $f"; hits=$((hits+1)); }
    done < <(git ls-files 2>/dev/null)
  fi

  if [ "$hits" -eq 0 ]; then
    echo "git-guard: no secret-shaped tracked files found."
    return 0
  fi
  echo "git-guard: $hits secret-shaped file(s) tracked — untrack + .gitignore them." >&2
  echo "  history is NOT checked here — run 'gitleaks detect' for a full-history scan." >&2
  return 3
}

# ── dispatch ─────────────────────────────────────────────────────
main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    -h|--help|help|"") usage; return 0 ;;
    on)            cmd_on ;;
    off)           cmd_off ;;
    status)        cmd_status ;;
    audit)         cmd_audit ;;
    checkpoint)    cmd_checkpoint ;;
    autosave)      cmd_autosave ;;
    session-end)   cmd_session_end ;;
    guard-commit)  cmd_guard_commit ;;
    guard-push)    cmd_guard_push ;;
    scan-secrets)  cmd_scan_secrets "$@" ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
