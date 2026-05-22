#!/usr/bin/env bash
# secrets.sh — provision project secrets without the AI ever touching a value.
#
# Owns the deterministic mechanics of: materializing the central
# secret store, the in-repo `.env` symlink, the guided-form skeleton
# the user fills in, the value-free completeness check, and the two
# opt-in hooks that keep secrets away from the AI.
#
# The cardinal rule: this script may READ a value (to tell `set` from
# `empty`), but it MUST NEVER print one. Every code path that emits
# text emits keys, never values. A path that would print a value is
# a bug — treat it as one.
#
# Central store (outside any repo, per the kit's user-separation
# convention — personal state lives under ~/.claude/projects/<key>/):
#   ~/.claude/projects/<project-key>/secrets/env      file, 0600
# In-repo:
#   <repo>/.env  ->  symlink to the store             gitignored
# All worktrees of one project share a single store.
#
# Hooks installed by `hooks on` (Claude Code, per-machine, gitignored
# in .claude/settings.local.json):
#   PreToolUse [Read|Bash]  -> guard-read    deny AI reads of secrets
#   UserPromptSubmit        -> guard-prompt  block secret-shaped pastes

set -euo pipefail

# ── tunables (env-overridable) ───────────────────────────────────
SECRETS_EDITOR="${SECRETS_EDITOR:-}"   # force a specific editor command
# Escape hatch for the prompt guard — deliberate, NOT a config knob:
#   prefix a chat message with `!secret-ok` to send it through as-is.

CC_TARGET=".claude/settings.local.json"
# Hook commands assume the synced-project layout (.claude/skills/…),
# which is where these hooks actually run.
SELF_CC=".claude/skills/secrets/secrets.sh"

usage() {
  cat <<'EOF'
secrets.sh — provision project secrets without the AI touching a value.

USAGE:
  secrets.sh provision [--keys K1,K2,…]   Build/refresh the store + symlink,
                                          open it in an editor.
  secrets.sh check [--keys K1,K2,…]       Report set/empty/missing per key.
  secrets.sh path                         Print the store file path.
  secrets.sh migrate                      Adopt an existing real .env into
                                          the store, replace it with a symlink.
  secrets.sh hooks on | off | status      Manage the two opt-in guard hooks.

HOOK HANDLERS (called by hooks — not for direct use):
  guard-read     PreToolUse: deny AI reads of .env* / the store.
  guard-prompt   UserPromptSubmit: block secret-shaped pastes.

KEY SOURCE (provision / check), in priority order:
  --keys explicit list  >  <repo>/.env-template  >  env/stamps/*.md

EXIT CODES:
  0  success / all keys set
  1  operational error
  2  usage error
  3  refused, or required keys still unfilled
EOF
}

# ── helpers ──────────────────────────────────────────────────────
die()  { echo "error: $*" >&2; exit 1; }
note() { echo "secrets: $*" >&2; }

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null \
    || die "not inside a git repo"
}

# The shared .git dir, absolute — correct inside worktrees.
git_common_dir() {
  local d
  d="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  ( cd -P "$d" 2>/dev/null && pwd -P )
}

# The MAIN worktree root — parent of the shared .git dir. All
# worktrees of a project resolve to the same value, so they share
# one secret store.
main_root() {
  local common
  common="$(git_common_dir)" || die "not inside a git repo"
  case "$common" in
    */.git) dirname "$common" ;;
    *)      repo_root ;;          # bare/unusual layout — fall back
  esac
}

# Project key — the absolute main-root path with / -> -, matching the
# ~/.claude/projects/<key>/ convention the memory system already uses.
project_key() {
  printf '%s' "$(main_root)" | tr '/' '-'
}

store_dir()  { printf '%s/.claude/projects/%s/secrets' "$HOME" "$(project_key)"; }
store_file() { printf '%s/env' "$(store_dir)"; }
env_link()   { printf '%s/.env' "$(repo_root)"; }

# ── key sources ──────────────────────────────────────────────────
# Emit one KEY per line. Never emits a value.

keys_from_template() {
  local tmpl="$1"
  { grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$tmpl" 2>/dev/null || true; } \
    | sed 's/=$//'
}

keys_from_stamps() {
  local dir="$1" f v
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    v="$(grep -m1 -E '^var_name:' "$f" 2>/dev/null \
          | sed -E 's/^var_name:[[:space:]]*//' \
          | tr -d '"'\''[:space:]' || true)"
    [ -n "$v" ] && printf '%s\n' "$v"
  done
}

# Resolve the ordered, de-duplicated key list for this project.
resolve_keys() {
  local explicit="${1:-}" root tmpl stamps
  if [ -n "$explicit" ]; then
    printf '%s\n' "$explicit" | tr ',' '\n' | sed '/^[[:space:]]*$/d' \
      | awk '!seen[$0]++'
    return 0
  fi
  root="$(repo_root)"
  tmpl="$root/.env-template"
  stamps="$root/env/stamps"
  if [ -f "$tmpl" ]; then
    keys_from_template "$tmpl" | awk '!seen[$0]++'
  elif [ -d "$stamps" ]; then
    keys_from_stamps "$stamps" | awk '!seen[$0]++'
  else
    die "no key source — need <repo>/.env-template, env/stamps/, or --keys.
       Run /export-env or /import-env first, or pass --keys K1,K2."
  fi
}

# ── guided-form rendering ────────────────────────────────────────
# Render the comment block for one key. Pulls from an env-var stamp
# when present; falls back to a bare header. Comments only — never a
# value. A stamp body line beginning "Get it:" or "Source:" is
# surfaced verbatim so the user knows where to obtain the value.
render_comment() {
  local key="$1" root stamp desc req purpose typ hint
  root="$(repo_root)"
  stamp="$(grep -rls -E "^var_name:[[:space:]]*[\"']?${key}[\"']?[[:space:]]*$" \
            "$root/env/stamps" 2>/dev/null | head -1 || true)"
  echo   "# ─────────────────────────────────────────────"
  if [ -n "$stamp" ]; then
    desc="$(grep -m1 -E '^description:' "$stamp" | sed -E 's/^description:[[:space:]]*//')"
    req="$(grep -m1 -E '^required:' "$stamp"     | sed -E 's/^required:[[:space:]]*//')"
    purpose="$(grep -m1 -E '^purpose:' "$stamp"  | sed -E 's/^purpose:[[:space:]]*//')"
    typ="$(grep -m1 -E '^type:' "$stamp"         | sed -E 's/^type:[[:space:]]*//')"
    hint="$(grep -m1 -E '^[[:space:]]*\**(Get it|Source):' "$stamp" \
             | sed -E 's/^[[:space:]]*\**//; s/\**[[:space:]]*$//' || true)"
    printf '# %-22s %s\n' "$key" "$([ "$req" = "true" ] && echo 'required' || echo 'optional') · ${purpose:-secret}"
    [ -n "$desc" ] && echo "# What:   $desc"
    [ -n "$typ"  ] && echo "# Type:   $typ"
    [ -n "$hint" ] && echo "# $hint"
  else
    printf '# %-22s %s\n' "$key" "secret"
    echo "# What:   (no env-var stamp — run /import-env to register this var)"
  fi
  echo   "# ─────────────────────────────────────────────"
}

# ── store + symlink materialization ──────────────────────────────
ensure_store_dir() {
  local d; d="$(store_dir)"
  mkdir -p "$d"
  chmod 700 "$d" 2>/dev/null || true
}

# Keys already present in the store (one per line). Reads the file —
# the script may; it just never prints the value half.
keys_in_store() {
  local sf="$1"
  [ -f "$sf" ] || return 0
  { grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$sf" 2>/dev/null || true; } \
    | sed 's/=$//'
}

# Append-only: never rewrites or reorders existing lines, so a filled
# value can never be clobbered by a re-run.
append_missing_keys() {
  local sf="$1"; shift
  local keys=("$@") have key
  have="$(keys_in_store "$sf" | tr '\n' '|')"
  for key in "${keys[@]}"; do
    case "|$have" in
      *"|$key|"*) continue ;;          # already in store — leave it
    esac
    {
      echo ""
      render_comment "$key"
      echo "$key="
    } >> "$sf"
  done
}

ensure_symlink() {
  local link store; link="$(env_link)"; store="$1"
  if [ -L "$link" ]; then
    local tgt; tgt="$(readlink "$link")"
    [ "$tgt" = "$store" ] && return 0
    note "WARNING: $link is a symlink to $tgt (not the store). Leaving it."
    return 0
  fi
  if [ -e "$link" ]; then
    die "<repo>/.env is a real file, not a symlink.
       Run 'secrets.sh migrate' to adopt it into the store safely."
  fi
  ln -s "$store" "$link"
  note "linked .env -> $store"
}

ensure_gitignore() {
  local gi; gi="$(repo_root)/.gitignore"
  if [ -f "$gi" ] && grep -qxE '\.env' "$gi"; then return 0; fi
  printf '\n# secret store symlink — never commit\n.env\n' >> "$gi"
  note "added .env to .gitignore"
}

# ── editor ───────────────────────────────────────────────────────
# Resolve a GUI editor that can jump to a line. A terminal editor is
# never launched — it would hang inside a Claude Code session.
open_in_editor() {
  local file="$1" line="${2:-1}" ed
  for ed in $SECRETS_EDITOR code cursor subl zed; do
    [ -n "$ed" ] && command -v "$ed" >/dev/null 2>&1 || continue
    case "$ed" in
      code|cursor) "$ed" -g "$file:$line" >/dev/null 2>&1 && return 0 ;;
      subl|zed)    "$ed" "$file:$line"    >/dev/null 2>&1 && return 0 ;;
      *)           "$ed" "$file"          >/dev/null 2>&1 && return 0 ;;
    esac
  done
  if [ "$(uname -s)" = "Darwin" ] && command -v open >/dev/null 2>&1; then
    open -t "$file" >/dev/null 2>&1 && return 0
  fi
  return 1
}

# First store line whose value is empty — where the cursor should land.
first_blank_line() {
  local sf="$1"
  [ -f "$sf" ] || { echo 1; return; }
  grep -nE '^[A-Za-z_][A-Za-z0-9_]*=[[:space:]]*$' "$sf" 2>/dev/null \
    | head -1 | cut -d: -f1 | grep -E '^[0-9]+$' || echo 1
}

# ── subcommands ──────────────────────────────────────────────────
cmd_provision() {
  local explicit="" keys=() sf line
  [ "${1:-}" = "--keys" ] && { explicit="${2:-}"; }
  while IFS= read -r k; do keys+=("$k"); done < <(resolve_keys "$explicit")
  [ "${#keys[@]}" -gt 0 ] || die "no keys to provision"

  ensure_store_dir
  sf="$(store_file)"
  [ -f "$sf" ] || { : > "$sf"; }
  chmod 600 "$sf" 2>/dev/null || true
  append_missing_keys "$sf" "${keys[@]}"
  ensure_symlink "$sf"
  ensure_gitignore

  line="$(first_blank_line "$sf")"
  echo "store:  $sf"
  echo "edit:   $(env_link)  (symlink — writes through to the store)"
  if [ -n "$explicit" ]; then
    cmd_check --keys "$explicit" || true
  else
    cmd_check || true
  fi

  if open_in_editor "$(env_link)" "$line"; then
    echo "opened: editor at the first blank field (line $line)"
  else
    echo "NOTE:   no GUI editor found — open this file yourself:"
    echo "        $(env_link)"
  fi
}

cmd_check() {
  local explicit="" gaps=0 key sf have val
  [ "${1:-}" = "--keys" ] && explicit="${2:-}"
  sf="$(store_file)"
  have=""
  [ -f "$sf" ] && have="$(keys_in_store "$sf" | tr '\n' '|')"
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    case "|$have" in
      *"|$key|"*)
        # Key present — classify set vs empty WITHOUT printing the value.
        # Last occurrence wins, matching dotenv parser semantics.
        val="$(grep -E "^${key}=" "$sf" | tail -1 | sed -E "s/^${key}=//")"
        if [ -n "${val//[[:space:]]/}" ]; then
          printf '  set      %s\n' "$key"
        else
          printf '  empty    %s\n' "$key"; gaps=$((gaps+1))
        fi
        ;;
      *)
        printf '  missing  %s\n' "$key"; gaps=$((gaps+1))
        ;;
    esac
  done < <(resolve_keys "$explicit")
  if [ "$gaps" -gt 0 ]; then
    echo "  → $gaps key(s) still need a value"
    return 3
  fi
  echo "  → all keys set"
  return 0
}

cmd_path() { store_file; }

cmd_migrate() {
  local link store; link="$(env_link)"; store="$(store_file)"
  [ -e "$link" ] || die "no <repo>/.env to migrate"
  [ -L "$link" ] && die "<repo>/.env is already a symlink — nothing to migrate"
  [ -e "$store" ] && die "store already exists at $store —
       resolve the conflict by hand (won't blind-merge two secret files)"
  ensure_store_dir
  mv "$link" "$store"
  chmod 600 "$store" 2>/dev/null || true
  ln -s "$store" "$link"
  ensure_gitignore
  note "migrated .env into $store and replaced it with a symlink"
}

# ── hooks ────────────────────────────────────────────────────────
install_hook_script() {
  local root; root="$(repo_root)"
  if   [ -f "$root/.claude/skills/install-hook/install-hook.sh" ]; then
    echo "$root/.claude/skills/install-hook/install-hook.sh"
  elif [ -f "$root/kit/skills/install-hook/install-hook.sh" ]; then
    echo "$root/kit/skills/install-hook/install-hook.sh"
  else
    die "install-hook.sh not found — secrets hooks need it"
  fi
}

cmd_hooks() {
  local action="${1:-}" ih
  ih="$(install_hook_script)"
  case "$action" in
    on)
      bash "$ih" add PreToolUse "bash $SELF_CC guard-read" --matcher 'Read|Bash'
      bash "$ih" add UserPromptSubmit "bash $SELF_CC guard-prompt"
      note "hooks on — AI reads of secrets denied; secret-shaped pastes blocked"
      ;;
    off)
      bash "$ih" remove PreToolUse "bash $SELF_CC guard-read" || true
      bash "$ih" remove UserPromptSubmit "bash $SELF_CC guard-prompt" || true
      note "hooks off"
      ;;
    status)
      bash "$ih" list | grep -i secrets || echo "secrets hooks: not installed"
      ;;
    *) usage; exit 2 ;;
  esac
}

# ── hook handlers ────────────────────────────────────────────────
# Each handler writes its python to a temp file and runs it, so the
# hook's real stdin (the JSON payload) reaches the python process
# intact — a heredoc on python's own stdin would shadow it.

# guard-read — PreToolUse. Deny the AI reading a secret file.
cmd_guard_read() {
  local tmp rc=0
  tmp="$(mktemp)" || die "mktemp failed"
  cat > "$tmp" <<'PY'
import json, re, sys, os
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)                       # can't parse — don't block
tool = data.get("tool_name", "")
inp  = data.get("tool_input", {}) or {}

def is_secret_path(p):
    if not p:
        return False
    b = os.path.basename(p)
    if b in (".env-template", ".env.example", ".env-example", ".env.sample"):
        return False
    if b == ".env" or b.startswith(".env.") or b.endswith(".env"):
        return True
    return "/.claude/projects/" in p and "/secrets/" in p

deny = False
if tool == "Read":
    deny = is_secret_path(inp.get("file_path", ""))
elif tool == "Bash":
    cmd = inp.get("command", "")
    # The secrets skill's own script is allowed to read the store.
    if "secrets.sh" not in cmd and re.search(
            r'\b(cat|less|more|head|tail|bat|xxd|od|strings|nl|'
            r'grep|rg|egrep|fgrep|awk|sed)\b', cmd):
        if re.search(r'(^|[\s=/"\'])\.env($|[\s.\'"])', cmd) \
           or "/secrets/env" in cmd:
            deny = True

if deny:
    sys.stderr.write(
        "Refused: secret files are off-limits to the AI. Use "
        "`bash .claude/skills/secrets/secrets.sh check` to verify keys "
        "without reading values. If a value needs to change, run "
        "`/secrets` so the user edits it directly.\n")
    sys.exit(2)
sys.exit(0)
PY
  python3 "$tmp" || rc=$?
  rm -f "$tmp"
  return "$rc"
}

# guard-prompt — UserPromptSubmit. Block a prompt that carries a
# secret-shaped string before it reaches the model.
cmd_guard_prompt() {
  local tmp rc=0
  tmp="$(mktemp)" || die "mktemp failed"
  cat > "$tmp" <<'PY'
import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
prompt = data.get("prompt", "") or ""

# Deliberate override — user resends prefixed with !secret-ok.
if prompt.lstrip().startswith("!secret-ok"):
    sys.exit(0)

PATTERNS = [
    ("OpenAI/Anthropic-style key", r'sk-(ant-|proj-)?[A-Za-z0-9_-]{16,}'),
    ("AWS access key id",          r'(AKIA|ASIA)[0-9A-Z]{16}'),
    ("GitHub token",               r'gh[pousr]_[A-Za-z0-9]{20,}'),
    ("GitHub fine-grained PAT",    r'github_pat_[A-Za-z0-9_]{30,}'),
    ("Slack token",                r'xox[baprs]-[A-Za-z0-9-]{10,}'),
    ("GitLab PAT",                 r'glpat-[A-Za-z0-9_-]{20,}'),
    ("Google API key",             r'AIza[A-Za-z0-9_-]{30,}'),
    ("Google OAuth token",         r'ya29\.[A-Za-z0-9_-]{20,}'),
    ("private key block",          r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),
    ("secret assignment",
     r'(?i)\b(secret|token|password|passwd|pwd|api[_-]?key)\b'
     r'["\'`]?\s*[:=]\s*["\'`]?[A-Za-z0-9/+_.-]{16,}'),
]
for label, pat in PATTERNS:
    if re.search(pat, prompt):
        sys.stderr.write(
            f"Blocked: that message looks like it contains a {label}. "
            "It was NOT sent to Claude.\n"
            "Run /secrets and paste the value into the editor that opens — "
            "Claude never needs to see it.\n"
            "False positive? Resend the message prefixed with `!secret-ok`.\n")
        sys.exit(2)
sys.exit(0)
PY
  python3 "$tmp" || rc=$?
  rm -f "$tmp"
  return "$rc"
}

# ── dispatch ─────────────────────────────────────────────────────
main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    provision)    cmd_provision "$@" ;;
    check)        cmd_check "$@" ;;
    path)         cmd_path ;;
    migrate)      cmd_migrate ;;
    hooks)        cmd_hooks "$@" ;;
    guard-read)   cmd_guard_read ;;
    guard-prompt) cmd_guard_prompt ;;
    -h|--help|help|"") usage ;;
    *) echo "error: unknown subcommand '$cmd'" >&2; usage; exit 2 ;;
  esac
}

main "$@"
