#!/usr/bin/env bash
# contract.sh — system-contract registry: stamp, version, lock, ledger.
#
# Owns the deterministic mechanics of a project's `contracts/` folder:
# scaffolding it, writing/reading contract stamps, version + date
# stamping, the lock flag, the append-only LEDGER, and the index
# rollup. SKILL.md routes the verb + synthesizes contract bodies;
# this script owns every file mutation so the ledger never lies.
#
# The guard:
#   `init` installs a PreToolUse hook (.claude/settings.json, shared)
#   that denies Edit/Write/MultiEdit anywhere under `contracts/`. All
#   mutation goes through this script, which runs via Bash and is not
#   intercepted. A locked contract is additionally refused by the
#   script itself (exit 3) — belt and suspenders.

set -euo pipefail

# Claude Code hook the init/off toggle installs. Shared settings so
# every contributor's session enforces the contract discipline.
CC_TARGET=".claude/settings.json"
CC_EVENT="PreToolUse"
CC_MATCHER="Edit|Write|MultiEdit"
CC_COMMAND="bash .claude/skills/contract/contract.sh guard"

VALID_KINDS="schema endpoint doc"

usage() {
  cat <<'EOF'
contract.sh — system-contract registry: stamp, version, lock, ledger.

USAGE:
  contract.sh init
      Scaffold contracts/ (CONTRACTS.md, LEDGER.md, stamps/) if
      missing, and install the PreToolUse guard hook. Idempotent.

  contract.sh off
      Remove the guard hook. Leaves contracts/ and contents intact.

  contract.sh status
      List every contract — name, kind, version, status, lock —
      and report whether the guard hook is installed.

  contract.sh new <name> --kind <schema|endpoint|doc> --why <reason>
                         [--from <body-file>] [--owner <name>]
      Create contracts/stamps/<name>.md. Body from --from, else a
      stub. Ledgers a 'created' entry. Refuses if <name> exists.

  contract.sh update <name> --from <body-file> --why <reason>
      Replace an existing contract's body. Refused (exit 3) if the
      contract is locked. Bumps last_updated. Ledgers 'updated'.

  contract.sh bump <name> <major|minor|patch> --why <reason>
      Bump the version. Refused if locked. Ledgers 'version'.

  contract.sh lock <name> --why <reason>
      Set is_locked: true. Ledgers 'locked'.

  contract.sh unlock <name> --why <reason>
      Set is_locked: false. Ledgers 'unlocked'.

  contract.sh check <path>
      Exit 0 if <path> is not a locked contract; exit 3 if it is.
      For task scripts and manual pre-flight checks.

  contract.sh guard
      PreToolUse hook handler — reads hook JSON on stdin, denies
      edits under contracts/. Called by the hook, not by hand.

EXIT CODES:
  0  success / clean
  1  operational error (missing file, no python3, write failure)
  2  usage error (bad flag, missing argument, bad value)
  3  refused (contract locked, name collision, precondition unmet)
EOF
}

# ── helpers ──────────────────────────────────────────────────────
repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    echo "error: not inside a git repo" >&2
    return 1
  }
}

now_date()  { date '+%Y-%m-%d'; }
now_stamp() { date '+%Y-%m-%d %H:%M'; }

# Who is making the change — for the ledger.
actor() {
  local a
  a="$(git config user.name 2>/dev/null || true)"
  [ -n "$a" ] || a="${USER:-unknown}"
  printf '%s' "$a"
}

# Resolve this script's absolute path (synced project or kit repo).
self_path() {
  local root; root="$(repo_root)" || return 1
  if   [ -f "$root/.claude/skills/contract/contract.sh" ]; then
    echo "$root/.claude/skills/contract/contract.sh"
  elif [ -f "$root/kit/skills/contract/contract.sh" ]; then
    echo "$root/kit/skills/contract/contract.sh"
  else
    echo "error: contract.sh not found in expected locations" >&2
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
    echo "error: install-hook.sh not found — contract needs it" >&2
    return 1
  fi
}

contracts_dir() { echo "$(repo_root)/contracts"; }
stamp_path()    { echo "$(contracts_dir)/stamps/$1.md"; }

# Validate a contract name — kebab-case, lowercase.
valid_name() {
  case "$1" in
    "" ) return 1 ;;
    *[!a-z0-9-]* ) return 1 ;;
    -* | *- ) return 1 ;;
    * ) return 0 ;;
  esac
}

# Read a frontmatter value: fm_get <file> <key>.
fm_get() {
  local file="$1" key="$2"
  awk -v k="$key" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm {
      if ($0 ~ "^"k":[[:space:]]*") {
        sub("^"k":[[:space:]]*", "")
        print
        exit
      }
    }
  ' "$file"
}

# Rewrite a frontmatter value in place: fm_set <file> <key> <value>.
# Only touches lines inside the frontmatter block.
fm_set() {
  local file="$1" key="$2" val="$3" tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$val" '
    NR==1 && $0=="---" { infm=1; print; next }
    infm && $0=="---"  { infm=0; print; next }
    infm && $0 ~ "^"k":" { print k": "v; next }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Replace a stamp body (everything after the frontmatter) from a file.
body_replace() {
  local file="$1" bodyfile="$2" tmp
  tmp="$(mktemp)"
  awk '
    NR==1 && $0=="---" { fm=1; print; next }
    fm==1 && $0=="---" { print; exit }
    { print }
  ' "$file" > "$tmp"
  printf '\n' >> "$tmp"
  cat "$bodyfile" >> "$tmp"
  mv "$tmp" "$file"
}

is_locked() {
  local file; file="$(stamp_path "$1")"
  [ -f "$file" ] && [ "$(fm_get "$file" is_locked)" = "true" ]
}

contract_exists() { [ -f "$(stamp_path "$1")" ]; }

# Bump a semver string: bump_semver <x.y.z> <major|minor|patch>.
bump_semver() {
  local ver="$1" part="$2" major minor patch
  IFS=. read -r major minor patch <<< "$ver"
  major="${major:-0}"; minor="${minor:-0}"; patch="${patch:-0}"
  case "$part" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *) return 2 ;;
  esac
  echo "$major.$minor.$patch"
}

# Append an entry to the ledger: ledger_append <name> <action> <what> <why>.
ledger_append() {
  local name="$1" action="$2" what="$3" why="$4"
  local ledger; ledger="$(contracts_dir)/LEDGER.md"
  {
    printf '\n## %s · %s · %s\n' "$(now_stamp)" "$name" "$action"
    printf -- '- **Who.** %s\n'  "$(actor)"
    printf -- '- **What.** %s\n' "$what"
    printf -- '- **Why.** %s\n'  "$why"
  } >> "$ledger"
}

# Regenerate CONTRACTS.md from every stamp.
regen_index() {
  local cdir index f name kind ver status locked rows=""
  cdir="$(contracts_dir)"
  index="$cdir/CONTRACTS.md"
  for f in "$cdir"/stamps/*.md; do
    [ -e "$f" ] || continue
    name="$(fm_get "$f" name)"
    kind="$(fm_get "$f" kind)"
    ver="$(fm_get "$f" version)"
    status="$(fm_get "$f" status)"
    if [ "$(fm_get "$f" is_locked)" = "true" ]; then
      locked="🔒 locked"
    else
      locked="unlocked"
    fi
    rows+="| $name | $kind | $ver | $status | $locked |"$'\n'
  done
  [ -n "$rows" ] || rows="| _(none yet)_ | | | | |"$'\n'
  cat > "$index" <<EOF
# Contracts

System-level contracts for this project — schemas, endpoints, and
system docs that other code (and other repos) depend on. Each is a
versioned, date-stamped stamp under \`contracts/stamps/\`.

> **Managed by \`/contract\`.** Do not hand-edit anything under
> \`contracts/\` — the guard hook blocks it. Every change is
> recorded in \`LEDGER.md\`. A locked contract cannot change until
> it is explicitly unlocked.

| Contract | Kind | Version | Status | Lock |
|---|---|---|---|---|
${rows}
---

_Regenerated by \`/contract\`. Last: $(now_stamp)._
EOF
}

# ── init / off / status ──────────────────────────────────────────
cmd_init() {
  local root cdir install_hook
  root="$(repo_root)" || return 1
  cdir="$root/contracts"

  mkdir -p "$cdir/stamps"
  [ -f "$cdir/stamps/.gitkeep" ] || : > "$cdir/stamps/.gitkeep"

  if [ ! -f "$cdir/LEDGER.md" ]; then
    cat > "$cdir/LEDGER.md" <<EOF
# Contract ledger

Append-only audit of every change under \`contracts/\` — who, what,
why, when. Newest entries at the bottom. Written by \`/contract\`;
do not hand-edit.
EOF
  fi

  regen_index

  install_hook="$(install_hook_script)" || return 1
  bash "$install_hook" add "$CC_EVENT" "$CC_COMMAND" \
    --target "$CC_TARGET" --matcher "$CC_MATCHER" >/dev/null

  cat <<EOF

contract: INITIALIZED
  Folder:    contracts/  (CONTRACTS.md, LEDGER.md, stamps/)
  Guard:     $CC_EVENT hook in $CC_TARGET
             denies Edit/Write/MultiEdit under contracts/
  Mutation:  all changes go through /contract — never hand-edit.

The guard hook takes effect on the NEXT session start.
Add your first contract with: /contract new <name> --kind <kind>
EOF
}

cmd_off() {
  local install_hook
  install_hook="$(install_hook_script)" || return 1
  bash "$install_hook" remove "$CC_EVENT" "$CC_COMMAND" \
    --target "$CC_TARGET" >/dev/null
  echo ""
  echo "contract: guard hook removed. contracts/ left intact."
}

cmd_status() {
  local root cdir target hook_state f count=0
  root="$(repo_root)" || return 1
  cdir="$root/contracts"
  target="$root/$CC_TARGET"

  if [ -f "$target" ] && grep -qF "$CC_COMMAND" "$target" 2>/dev/null; then
    hook_state="installed"
  else
    hook_state="NOT installed (run /contract init)"
  fi

  echo ""
  echo "contract: guard hook — $hook_state"

  if [ ! -d "$cdir/stamps" ]; then
    echo "  contracts/ not initialized — run /contract init"
    return 0
  fi

  echo ""
  printf '  %-22s %-9s %-9s %-10s %s\n' NAME KIND VERSION STATUS LOCK
  for f in "$cdir"/stamps/*.md; do
    [ -e "$f" ] || continue
    count=$((count + 1))
    local lk="—"
    [ "$(fm_get "$f" is_locked)" = "true" ] && lk="LOCKED"
    printf '  %-22s %-9s %-9s %-10s %s\n' \
      "$(fm_get "$f" name)" \
      "$(fm_get "$f" kind)" \
      "$(fm_get "$f" version)" \
      "$(fm_get "$f" status)" \
      "$lk"
  done
  [ "$count" -eq 0 ] && echo "  (no contracts yet)"
  echo ""
  echo "  $count contract(s) · see contracts/CONTRACTS.md · history in contracts/LEDGER.md"
}

# ── flag parsing ─────────────────────────────────────────────────
# Sets globals F_FROM F_WHY F_KIND F_OWNER. Resets every call.
F_FROM=""; F_WHY=""; F_KIND=""; F_OWNER=""
parse_flags() {
  F_FROM=""; F_WHY=""; F_KIND=""; F_OWNER=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --from)  F_FROM="${2:-}";  shift 2 || return 2 ;;
      --why)   F_WHY="${2:-}";   shift 2 || return 2 ;;
      --kind)  F_KIND="${2:-}";  shift 2 || return 2 ;;
      --owner) F_OWNER="${2:-}"; shift 2 || return 2 ;;
      *) echo "error: unknown flag: $1" >&2; return 2 ;;
    esac
  done
}

require_init() {
  if [ ! -d "$(contracts_dir)/stamps" ]; then
    echo "error: contracts/ not initialized — run /contract init first" >&2
    return 1
  fi
}

# ── new ──────────────────────────────────────────────────────────
cmd_new() {
  local name="${1:-}"; shift || true
  parse_flags "$@" || return 2
  require_init || return 1

  valid_name "$name" || {
    echo "error: contract name must be kebab-case (lowercase, digits, hyphens)" >&2
    return 2
  }
  case " $VALID_KINDS " in
    *" $F_KIND "*) : ;;
    *) echo "error: --kind must be one of: $VALID_KINDS" >&2; return 2 ;;
  esac
  [ -n "$F_WHY" ] || { echo "error: --why <reason> is required" >&2; return 2; }
  if contract_exists "$name"; then
    echo "error: contract '$name' already exists — use /contract update" >&2
    return 3
  fi
  if [ -n "$F_FROM" ] && [ ! -f "$F_FROM" ]; then
    echo "error: --from file not found: $F_FROM" >&2
    return 1
  fi

  local file today owner
  file="$(stamp_path "$name")"
  today="$(now_date)"
  owner="${F_OWNER:-—}"

  {
    echo "---"
    echo "name: $name"
    echo "kind: $F_KIND"
    echo "version: 0.1.0"
    echo "status: draft"
    echo "is_locked: false"
    echo "created: $today"
    echo "last_updated: $today"
    echo "owner: $owner"
    echo "consumers: []"
    echo "references: []"
    echo "tags: []"
    echo "---"
    echo ""
    if [ -n "$F_FROM" ]; then
      cat "$F_FROM"
    else
      echo "# $name"
      echo ""
      echo "<!-- Contract body — fill via: /contract update $name -->"
    fi
  } > "$file"

  ledger_append "$name" "created" \
    "Created contract '$name' (kind: $F_KIND) at v0.1.0." "$F_WHY"
  regen_index
  echo "contract: created '$name' ($F_KIND) v0.1.0 — status draft, unlocked."
}

# ── update ───────────────────────────────────────────────────────
cmd_update() {
  local name="${1:-}"; shift || true
  parse_flags "$@" || return 2
  require_init || return 1

  contract_exists "$name" || {
    echo "error: no contract named '$name'" >&2; return 1; }
  [ -n "$F_WHY" ] || { echo "error: --why <reason> is required" >&2; return 2; }
  [ -n "$F_FROM" ] || { echo "error: --from <body-file> is required" >&2; return 2; }
  [ -f "$F_FROM" ] || { echo "error: --from file not found: $F_FROM" >&2; return 1; }

  if is_locked "$name"; then
    cat >&2 <<EOF
✗ contract: '$name' is LOCKED — refusing to update.
  A locked contract cannot change until it is explicitly unlocked.
  This is the block: resolve with the user, then:
      /contract unlock $name --why "<reason>"
  …and re-run the update.
EOF
    return 3
  fi

  local file; file="$(stamp_path "$name")"
  body_replace "$file" "$F_FROM"
  fm_set "$file" last_updated "$(now_date)"
  ledger_append "$name" "updated" \
    "Replaced the body of '$name'." "$F_WHY"
  regen_index
  echo "contract: updated '$name' — body replaced, last_updated $(now_date)."
}

# ── bump ─────────────────────────────────────────────────────────
cmd_bump() {
  local name="${1:-}" level="${2:-}"; shift 2 2>/dev/null || shift $#
  parse_flags "$@" || return 2
  require_init || return 1

  contract_exists "$name" || {
    echo "error: no contract named '$name'" >&2; return 1; }
  case "$level" in
    major|minor|patch) : ;;
    *) echo "error: bump level must be major, minor, or patch" >&2; return 2 ;;
  esac
  [ -n "$F_WHY" ] || { echo "error: --why <reason> is required" >&2; return 2; }

  if is_locked "$name"; then
    echo "✗ contract: '$name' is LOCKED — unlock it before bumping the version." >&2
    return 3
  fi

  local file old new
  file="$(stamp_path "$name")"
  old="$(fm_get "$file" version)"
  new="$(bump_semver "$old" "$level")"
  fm_set "$file" version "$new"
  fm_set "$file" last_updated "$(now_date)"
  ledger_append "$name" "version" \
    "Bumped version $old → $new ($level)." "$F_WHY"
  regen_index
  echo "contract: '$name' version $old → $new."
}

# ── lock / unlock ────────────────────────────────────────────────
cmd_lock() {
  local name="${1:-}"; shift || true
  parse_flags "$@" || return 2
  require_init || return 1

  contract_exists "$name" || {
    echo "error: no contract named '$name'" >&2; return 1; }
  [ -n "$F_WHY" ] || { echo "error: --why <reason> is required" >&2; return 2; }

  if is_locked "$name"; then
    echo "contract: '$name' is already locked — no change."
    return 0
  fi
  local file ver; file="$(stamp_path "$name")"
  ver="$(fm_get "$file" version)"
  fm_set "$file" is_locked true
  ledger_append "$name" "locked" \
    "Locked '$name' at v$ver." "$F_WHY"
  regen_index
  echo "contract: 🔒 LOCKED '$name' (v$ver). Changes blocked until unlocked."
}

cmd_unlock() {
  local name="${1:-}"; shift || true
  parse_flags "$@" || return 2
  require_init || return 1

  contract_exists "$name" || {
    echo "error: no contract named '$name'" >&2; return 1; }
  [ -n "$F_WHY" ] || { echo "error: --why <reason> is required" >&2; return 2; }

  if ! is_locked "$name"; then
    echo "contract: '$name' is already unlocked — no change."
    return 0
  fi
  local file ver; file="$(stamp_path "$name")"
  ver="$(fm_get "$file" version)"
  fm_set "$file" is_locked false
  ledger_append "$name" "unlocked" \
    "Unlocked '$name' (v$ver)." "$F_WHY"
  regen_index
  echo "contract: 🔓 unlocked '$name' (v$ver). Changes permitted."
}

# ── check ────────────────────────────────────────────────────────
cmd_check() {
  local path="${1:-}"
  [ -n "$path" ] || { echo "error: check needs a <path>" >&2; return 2; }
  local root abs cdir stamps name
  root="$(repo_root)" || return 1
  # pwd -P to match git rev-parse, which reports the physical path
  # (matters on macOS where /tmp is a symlink to /private/tmp).
  abs="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)/$(basename "$path")" \
    || abs="$path"
  cdir="$root/contracts/"
  case "$abs" in
    "$cdir"*) : ;;
    *) echo "not a contract path: $path"; return 0 ;;
  esac
  stamps="$root/contracts/stamps/"
  case "$abs" in
    "$stamps"*.md)
      name="$(basename "$abs" .md)"
      if is_locked "$name"; then
        echo "LOCKED contract: $name"
        return 3
      fi
      echo "unlocked contract: $name"
      return 0
      ;;
    *)
      echo "contracts/ path (not a stamp): $path"
      return 0
      ;;
  esac
}

# ── guard (PreToolUse hook handler) ──────────────────────────────
cmd_guard() {
  # Hook-safe: on any uncertainty, allow (exit 0). The script-level
  # lock check is the hard guarantee; this hook catches the common
  # case — an agent reaching for Edit/Write on a contract file.
  local root; root="$(repo_root 2>/dev/null)" || exit 0
  command -v python3 >/dev/null 2>&1 || exit 0

  # Read the PreToolUse payload from stdin here — the heredoc below
  # is python's program, so it can't also be python's stdin. Pass
  # the payload as an argv string instead.
  local payload; payload="$(cat)"

  python3 - "$root" "$payload" <<'PY'
import json, os, re, sys

root = os.path.realpath(sys.argv[1])
try:
    data = json.loads(sys.argv[2])
except Exception:
    sys.exit(0)  # unparseable — allow, don't break the session

tool_input = data.get("tool_input") or {}
fp = tool_input.get("file_path") or ""
if not fp:
    sys.exit(0)

# realpath resolves symlinks so the prefix check is reliable
# (e.g. macOS /tmp -> /private/tmp).
ap = os.path.realpath(fp if os.path.isabs(fp) else os.path.join(root, fp))
cdir = os.path.join(root, "contracts") + os.sep
if not ap.startswith(cdir):
    sys.exit(0)  # not a contract file — allow

# It's under contracts/. Deny — but give the right message.
stamps = os.path.join(root, "contracts", "stamps") + os.sep
locked_name = None
if ap.startswith(stamps) and ap.endswith(".md"):
    name = os.path.basename(ap)[:-3]
    try:
        with open(ap, encoding="utf-8") as fh:
            txt = fh.read()
        m = re.search(r"^is_locked:\s*(\S+)", txt, re.M)
        if m and m.group(1).strip() == "true":
            locked_name = name
    except FileNotFoundError:
        pass

if locked_name:
    reason = (
        f"Contract '{locked_name}' is LOCKED. It cannot be changed "
        "until the user explicitly unlocks it. Stop this task, tell "
        "the user the contract is locked and why the change is "
        "needed, and wait. To proceed they must run: "
        f"/contract unlock {locked_name} --why \"<reason>\"."
    )
else:
    reason = (
        "Files under contracts/ are managed through /contract so "
        "every change is versioned and recorded in the ledger. Do "
        "not hand-edit. Use /contract new|update|bump|lock|unlock "
        "instead — write the body to a temp file and pass --from."
    )

print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": reason,
}}))
PY
  exit 0
}

# ── dispatch ─────────────────────────────────────────────────────
main() {
  local action="${1:-}"
  shift || true

  case "$action" in
    -h|--help|help|"") usage; return 0 ;;
    guard) cmd_guard ;;  # reads stdin; no repo-root preamble noise
  esac

  case "$action" in
    init)    cmd_init ;;
    off)     cmd_off ;;
    status)  cmd_status ;;
    new)     cmd_new "$@" ;;
    update)  cmd_update "$@" ;;
    bump)    cmd_bump "$@" ;;
    lock)    cmd_lock "$@" ;;
    unlock)  cmd_unlock "$@" ;;
    check)   cmd_check "$@" ;;
    guard)   ;;  # handled above
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
