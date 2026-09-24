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

# The shared record library — rasa_root, the frontmatter reader and writer,
# rasa_actor. Found relative to this script (content/lib/domain-code/ in the
# Element, .claude/lib/domain-code/ in an install), never through the project
# root it exists to resolve.
_rfm="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib/domain-code" 2>/dev/null && pwd)/frontmatter.sh"
[ -f "$_rfm" ] || { echo "error: $(basename "$0"): .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; exit 70; }
# shellcheck source=../../lib/domain-code/frontmatter.sh
. "$_rfm"
rfm_require 1 || exit 70

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
  4  refused: a frontmatter key appears more than once — repair by hand
EOF
}

# ── helpers ──────────────────────────────────────────────────────
# The project this install serves — its ledgers and .claude/ live here.
# rasa_root (the shared library) walks up to the install's lockfile and
# never past the repository top; see its comment for the order.
repo_root() { rasa_root; }

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

# ── frontmatter ──────────────────────────────────────────────────
# 0.52.1 held the frontmatter rules here, in a private copy: a BOM and a CR
# ignored when matching and kept when writing; a fence is `---` plus blanks
# on line 1; the first occurrence of a key wins and a writer refuses a
# duplicate; values reach awk through ENVIRON; a write is a same-directory
# temp file, renamed, read back. Since 0.54.0 those rules are the shared
# library's, for every writer (frontmatter.sh — its READ and WRITE contracts).
# These wrappers keep this script's names and exit codes.

# fm_value_ok <value> — no control character, C1 control or Unicode line or
# paragraph separator. A leading or trailing blank is not refused here: a
# reader trims it, and fm_set trims before it writes.
fm_value_ok() { rfm_value_ok "$1" || [ $? -eq 3 ]; }

# fm_clean <text> — free text for the LEDGER (--why, the actor) as one line.
fm_clean() { rfm_clean "$1"; }

# fm_get <file> <key> — rc 0 found (the value may be empty), 1 absent, 3 no
# readable frontmatter. With FM_STRICT=1 a key that appears twice is rc 4:
# used for is_locked, where first-wins and a YAML reader's last-wins would
# disagree about the same bytes.
fm_get() { RFM_STRICT="${FM_STRICT:-0}" rfm_get "$1" "$2"; }

# fm_set <file> <key> <value> — upsert one key: rewritten in place, or
# inserted before the closing fence when absent (0.52.0 had no insert branch,
# which is how `lock` ledgered a lock that never happened). Blanks at either
# end are trimmed. rc 2 a control character, 3 no readable frontmatter, 4 the
# key already appears twice; the file is untouched on every refusal.
fm_set() {
  local val
  val="$(printf '%s' "$3" | sed 's/^[ 	]*//; s/[ 	]*$//')"
  rfm_set "$1" "$2" "$val"
}

# stamp_rewrite <file> <bodyfile> — replace everything after the closing
# fence with <bodyfile> and stamp last_updated, in ONE rename. 0.52.0 copied
# the whole file when it could not find the fences (CRLF, a trailing space on
# the fence) and then APPENDED the new body: rc 0, old and new body both kept.
stamp_rewrite() { rfm_rewrite "$1" "$2" last_updated "$(now_date)"; }

# lock_state <name> — locked | unlocked | missing | invalid | duplicate |
# damaged | none.
#   missing    the frontmatter is readable but has no is_locked key
#   invalid    is_locked holds something other than true/false
#   duplicate  is_locked appears more than once (readers could disagree)
#   damaged    no readable frontmatter block at all
lock_state() {
  local file val rc=0
  file="$(stamp_path "$1")"
  [ -f "$file" ] || { echo none; return 0; }
  # The library answers rc 4 for an unreadable file too; that is damage,
  # not a duplicated key.
  [ -r "$file" ] || { echo damaged; return 0; }
  val="$(FM_STRICT=1 fm_get "$file" is_locked)" || rc=$?
  case "$rc" in
    0) ;;
    1) echo missing; return 0 ;;
    4) echo duplicate; return 0 ;;
    *) echo damaged; return 0 ;;
  esac
  case "$val" in
    true)  echo locked ;;
    false) echo unlocked ;;
    *)     echo invalid ;;
  esac
}

# A lock that cannot be read is treated as LOCKED. Only an explicit
# `is_locked: false` is unlocked. 0.52.0 compared `= "true"`, so a BOM, CRLF,
# a missing key or a value like `yes` all read as UNLOCKED and `update`
# overwrote a frozen contract with rc 0.
is_locked() {
  local st; st="$(lock_state "$1")"
  case "$st" in
    unlocked|none) return 1 ;;
    locked) return 0 ;;
    missing|invalid)
      echo "⚠ contract '$1': lock state is '$st' — treating it as LOCKED." >&2
      echo "  To repair: /contract unlock $1 --why \"<reason>\"  (or: lock, to re-assert)" >&2
      return 0 ;;
    *)
      echo "⚠ contract '$1': lock state is '$st' — treating it as LOCKED." >&2
      echo "  Repair by hand: /contract off, fix the frontmatter, /contract init (see contract-rules.md)." >&2
      return 0 ;;
  esac
}

lock_label() {
  case "$(lock_state "$1")" in
    locked)   printf '🔒 locked' ;;
    unlocked) printf 'unlocked' ;;
    *)        printf '⚠ unreadable (treated as locked)' ;;
  esac
}

contract_exists() { [ -f "$(stamp_path "$1")" ]; }

# Every verb that takes a <name> builds a path from it, so a name like
# `../../x` must never reach stamp_path (0.52.0 validated only in `new`).
require_name() {
  valid_name "$1" || {
    echo "error: contract name must be kebab-case (lowercase, digits, hyphens)" >&2
    return 2; }
}

# contract_mutex — one mutating /contract command at a time per project.
# Without it, an `update` racing a `lock` could rename the pre-lock
# frontmatter over the locked stamp: the ledger said "locked", the stamp was
# not. mkdir is atomic and needs no flock (which stock macOS lacks).
CONTRACT_MUTEX=""

# contract_cleanup — never fails, so it can never rewrite the exit status
# of the verb it runs after (set -e applies inside traps too).
contract_cleanup() {
  rfm_cleanup   # the library's write in flight, if any
  if [ -n "$CONTRACT_MUTEX" ]; then rmdir "$CONTRACT_MUTEX" 2>/dev/null || true; fi
  CONTRACT_MUTEX=""
}

contract_mutex() {
  local cdir d i=0
  cdir="$(contracts_dir 2>/dev/null)" || return 0
  [ -d "$cdir/stamps" ] || return 0      # not initialized — the verb reports it
  d="$cdir/.contract.lock.d"
  until mkdir "$d" 2>/dev/null; do
    if [ ! -d "$d" ]; then               # not contention: cannot create at all
      echo "error: cannot create the /contract lock $d — is contracts/ writable?" >&2
      return 1
    fi
    i=$((i + 1))
    if [ "$i" -ge 50 ]; then
      echo "error: another /contract command is running (lock: $d)." >&2
      echo "  If none is, a crashed run left it behind — remove it: rmdir \"$d\"" >&2
      return 1
    fi
    sleep 0.1 2>/dev/null || sleep 1
  done
  CONTRACT_MUTEX="$d"
  trap 'contract_cleanup' EXIT
  trap 'contract_cleanup; trap - EXIT; exit 130' INT
  trap 'contract_cleanup; trap - EXIT; exit 143' TERM
}

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
  # Every field is collapsed to one line: a newline in --why (or in a git
  # user.name) used to append a forged `## … · unlocked` entry to an
  # append-only ledger.
  {
    printf '\n## %s · %s · %s\n' "$(now_stamp)" "$name" "$action"
    printf -- '- **Who.** %s\n'  "$(fm_clean "$(actor)")"
    printf -- '- **What.** %s\n' "$(fm_clean "$what")"
    printf -- '- **Why.** %s\n'  "$(fm_clean "$why")"
  } >> "$ledger"
}

# Regenerate CONTRACTS.md from every stamp.
regen_index() {
  local cdir index f name kind ver status locked rows=""
  cdir="$(contracts_dir)"
  index="$cdir/CONTRACTS.md"
  for f in "$cdir"/stamps/*.md; do
    [ -e "$f" ] || continue
    name="$(fm_get "$f" name || true)"
    kind="$(fm_get "$f" kind || true)"
    ver="$(fm_get "$f" version || true)"
    status="$(fm_get "$f" status || true)"
    locked="$(lock_label "$(basename "$f" .md)")"
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
    case "$(lock_state "$(basename "$f" .md)")" in
      unlocked) lk="—" ;;
      locked)   lk="LOCKED" ;;
      *)        lk="UNREADABLE (treated as LOCKED)" ;;
    esac
    printf '  %-22s %-9s %-9s %-10s %s\n' \
      "$(fm_get "$f" name || true)" \
      "$(fm_get "$f" kind || true)" \
      "$(fm_get "$f" version || true)" \
      "$(fm_get "$f" status || true)" \
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
  fm_value_ok "$owner" || {
    echo "error: --owner may not contain a newline or control character" >&2
    return 2; }

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
  require_name "$name" || return 2

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
  stamp_rewrite "$file" "$F_FROM" || return $?
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
  require_name "$name" || return 2

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

  local file old new k krc part
  file="$(stamp_path "$name")"
  # Both keys this verb writes must appear at most once BEFORE anything is
  # written: a duplicate found by the second write used to leave the first
  # applied and nothing ledgered, so every retry bumped again.
  for k in version last_updated; do
    krc=0; FM_STRICT=1 fm_get "$file" "$k" >/dev/null || krc=$?
    case "$krc" in
      3) echo "✗ contract: '$name' has no readable frontmatter — refusing to bump." >&2; return 3 ;;
      4) echo "✗ contract: '$name' declares '$k' more than once — refusing to bump; repair by hand." >&2; return 4 ;;
    esac
  done
  old="$(fm_get "$file" version)" || old=""
  case "$old" in
    *[!0-9.]*|""|.*|*.|*..*) old="" ;;
  esac
  if [ -n "$old" ] && [ "$(printf '%s' "$old" | tr -cd . | wc -c | tr -d ' ')" = 2 ]; then
    # No leading zeros (bash would read 010 as octal) and no part so long
    # that the arithmetic overflows.
    for part in $(printf '%s' "$old" | tr . ' '); do
      case "$part" in 0?*) old="" ;; esac
      [ "${#part}" -le 9 ] || old=""
    done
  else
    old=""
  fi
  if [ -z "$old" ]; then
    echo "✗ contract: '$name' has no readable x.y.z version — refusing to bump." >&2
    echo "  0.52.0 bumped from an empty read and ledgered a change that never happened." >&2
    return 3
  fi
  new="$(bump_semver "$old" "$level")"
  fm_set "$file" version "$new" || return $?
  fm_set "$file" last_updated "$(now_date)" || return $?
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
  require_name "$name" || return 2

  contract_exists "$name" || {
    echo "error: no contract named '$name'" >&2; return 1; }
  [ -n "$F_WHY" ] || { echo "error: --why <reason> is required" >&2; return 2; }

  local st note=""; st="$(lock_state "$name")"
  case "$st" in
    locked)  echo "contract: '$name' is already locked — no change."; return 0 ;;
    damaged) echo "✗ contract: '$name' has no readable frontmatter — cannot lock; repair by hand (see contract-rules.md)." >&2
             return 3 ;;
    duplicate) echo "✗ contract: '$name' declares is_locked more than once — treated as LOCKED; repair by hand (see contract-rules.md)." >&2
             return 3 ;;
    missing) note=" (repaired: is_locked was absent)" ;;
    invalid) note=" (repaired: is_locked was '$(fm_get "$(stamp_path "$name")" is_locked || true)')" ;;
  esac
  local file ver; file="$(stamp_path "$name")"
  ver="$(fm_get "$file" version || true)"
  fm_set "$file" is_locked true || return $?
  [ "$(lock_state "$name")" = locked ] || { echo "error: lock did not take" >&2; return 1; }
  ledger_append "$name" "locked" \
    "Locked '$name' at v$ver$note." "$F_WHY"
  regen_index
  echo "contract: 🔒 LOCKED '$name' (v$ver). Changes blocked until unlocked."
}

cmd_unlock() {
  local name="${1:-}"; shift || true
  parse_flags "$@" || return 2
  require_init || return 1
  require_name "$name" || return 2

  contract_exists "$name" || {
    echo "error: no contract named '$name'" >&2; return 1; }
  [ -n "$F_WHY" ] || { echo "error: --why <reason> is required" >&2; return 2; }

  local st note=""; st="$(lock_state "$name")"
  case "$st" in
    unlocked) echo "contract: '$name' is already unlocked — no change."; return 0 ;;
    damaged)  echo "✗ contract: '$name' has no readable frontmatter — cannot unlock safely; repair by hand (see contract-rules.md)." >&2
              return 3 ;;
    duplicate) echo "✗ contract: '$name' declares is_locked more than once — treated as LOCKED; repair by hand (see contract-rules.md)." >&2
              return 3 ;;
    missing)  note=" (repaired: is_locked was absent)" ;;
    invalid)  note=" (repaired: is_locked was '$(fm_get "$(stamp_path "$name")" is_locked || true)')" ;;
  esac
  local file ver; file="$(stamp_path "$name")"
  ver="$(fm_get "$file" version || true)"
  fm_set "$file" is_locked false || return $?
  [ "$(lock_state "$name")" = unlocked ] || { echo "error: unlock did not take" >&2; return 1; }
  ledger_append "$name" "unlocked" \
    "Unlocked '$name' (v$ver)$note." "$F_WHY"
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
  # Hook-safe: an unparseable payload, or a path outside contracts/, is
  # allowed (exit 0). The script-level lock check is the hard guarantee;
  # this hook catches the common case — an agent reaching for Edit/Write on
  # a contract file. Once a payload points under contracts/, every failure —
  # including python failing to start — must still DENY.
  local root; root="$(repo_root 2>/dev/null)" || exit 0
  command -v python3 >/dev/null 2>&1 || exit 0

  # The payload travels on python's STDIN, never in argv: until v0.52.1 it
  # was an argv string, and a Write of more than ARG_MAX (~1 MB on macOS,
  # 128 KiB per argument on Linux) failed to exec python — no decision was
  # printed, and the edit went through. The program itself is small.
  local prog payload out prc=0
  IFS= read -r -d '' prog <<'PY' || true
import json, os, re, sys

root = os.path.realpath(sys.argv[1])
try:
    data = json.loads(sys.stdin.read())
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
    # Any failure to read the stamp must still reach the deny below: until
    # v0.52.1 a stamp that was not valid UTF-8 raised UnicodeDecodeError,
    # the hook crashed without printing a decision, and the edit went
    # through. The deny itself never depended on this read.
    try:
        with open(ap, encoding="utf-8", errors="replace") as fh:
            txt = fh.read()
        m = re.search(r"^is_locked:\s*(\S+)", txt, re.M)
        if m and m.group(1).strip() == "true":
            locked_name = name
    except Exception:
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

  payload="$(cat)"
  out="$(printf '%s' "$payload" | python3 -c "$prog" "$root" 2>/dev/null)" || prc=$?
  if [ "$prc" -eq 0 ]; then
    [ -z "$out" ] || printf '%s\n' "$out"
    exit 0
  fi
  # python could not decide. Fail CLOSED for anything that names contracts/.
  case "$payload" in
    *contracts/*)
      printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "The contract guard could not evaluate this edit of a path under contracts/, so it is denied. Files under contracts/ are managed through /contract: use /contract new|update|bump|lock|unlock with --from."}}'
      ;;
  esac
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
    new|update|bump|lock|unlock) contract_mutex || return 1 ;;
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
