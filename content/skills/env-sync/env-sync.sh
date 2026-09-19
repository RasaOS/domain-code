#!/usr/bin/env bash
# env-sync.sh — move per-environment config between YOUR machines.
#
# THE PROBLEM
#
# Credentials live in gitignored per-env dotfiles (.env, .env.staging,
# .env.production — see .claude/env-rules.md). That is simple and it
# works, right up to the second machine, where the file does not exist
# and nothing in the repo can tell you what was in it. /import-env and
# /export-env move variable NAMES and stamps; they never move values, by
# construction. This moves the values.
#
# SAFETY PROPERTIES — structural, not promises
#
# 1. This script NEVER prints file contents. Not on status, not on
#    parity, not on error. Its stdout is safe to put in an AI's context.
#    The AI orchestrates a byte-mover it cannot see through.
# 2. The destination is an argument. It is never inferred from git
#    remotes, ssh config, known_hosts, or anything found by reading.
#    No argument, no transfer.
# 3. It refuses to touch a path `git check-ignore` does not claim. You
#    cannot transport a file that is committable — that is the check
#    that stops a secret becoming a commit.
# 4. Bytes go host-to-host over ssh/scp only. Never a third party,
#    never a paste site, never a bucket.
# 5. Fingerprints are whole-file digests plus a key-name/set-or-empty
#    map. There is deliberately NO per-key value digest: secrets are
#    low-entropy enough that a per-key hash is brute-forceable, so a
#    "helpful" per-key fingerprint would be a value oracle. The cost is
#    that parity can tell you THAT two files differ, not WHERE.
#
# Key NAMES are not secret — they are already in the committed
# .env-template. Values never leave the file.
#
# Usage:
#   env-sync.sh protect                      ensure .gitignore covers env files
#   env-sync.sh status                       local env files: present? ignored? digest
#   env-sync.sh fingerprint <env>            digest + key map for one env
#   env-sync.sh command push|pull <env> <user@host:path>
#                                            PRINT the command, run nothing
#   env-sync.sh push <env> <user@host:path>  send (scp, follows symlinks)
#   env-sync.sh pull <env> <user@host:path>  receive
#   env-sync.sh parity <env> <user@host>     compare digests over ssh
#
# Exit: 0 ok · 1 error · 2 usage · 3 mismatch/not-ignored
#
# Portability: bash 3.2 (stock macOS).

set -euo pipefail

umask 077   # anything this script creates is 0600 from birth

# --------------------------------------------------------------- paths
repo_root() {
  local d
  if d="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s\n' "$d"; return 0
  fi
  echo "error: not inside a git repo" >&2; return 1
}
ROOT="$(repo_root)" || exit 1

# env name -> file, per the convention in .claude/env-rules.md:
#   .env-template  committed, names + placeholders only
#   .env           gitignored, default/local
#   .env.<profile> gitignored, named profiles
env_file_for() {
  case "$1" in
    local|default|"") printf '%s\n' ".env" ;;
    *)                printf '%s\n' ".env.$1" ;;
  esac
}

digest() {
  # -L: follow the symlink. /secrets points .env at an out-of-repo store,
  # and a digest (or an rsync) that does not follow it silently reports on
  # a symlink rather than on the credentials.
  local f="$1"
  [ -e "$f" ] || { printf 'absent\n'; return 0; }
  if command -v shasum >/dev/null 2>&1; then
    cat -- "$f" | shasum -a 256 | awk '{print substr($1,1,16)}'
  else
    cat -- "$f" | sha256sum | awk '{print substr($1,1,16)}'
  fi
}

# Key NAMES and whether each has a value. Never a value, and never a
# fragment of one.
#
# The hard part is multi-line values. A PEM key in a .env is written as
#
#   PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
#   MIIEowIBAAKCAQEA...
#   -----END RSA PRIVATE KEY-----"
#
# and a naive `-F=` parser treats every continuation line as its own
# assignment, printing the key material as a "key name". This function
# used to do exactly that, into the output SKILL.md tells the agent to
# use INSTEAD of cat. So it tracks quote continuation and skips the body.
#
# A line-shape guard alone is NOT enough: base64 padding means a line like
# `MIIEowIBAAKCAQEA==` matches `IDENT=` and would still print a prefix of
# the key. The quote state machine is what actually closes it.
key_map() {
  local f="$1"
  [ -e "$f" ] || return 0
  awk '
    BEGIN { incont = 0; q = "" }
    {
      line = $0
      # Inside a multi-line value: emit nothing until the quote closes.
      if (incont) {
        if (index(line, q) > 0) { incont = 0; q = "" }
        next
      }
      if (line ~ /^[ \t]*#/)  next
      if (line ~ /^[ \t]*$/)  next
      # Must look like a real assignment, anchored at the start.
      if (line !~ /^[ \t]*(export[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*=/) next

      k = line
      sub(/^[ \t]*/, "", k)
      sub(/^export[ \t]+/, "", k)
      eq  = index(k, "=")
      key = substr(k, 1, eq - 1);  sub(/[ \t]+$/, "", key)
      v   = substr(k, eq + 1);     sub(/^[ \t]+/, "", v)

      # An opening quote with no closing quote on the same line starts a
      # continuation. Report the key, then swallow the body.
      if (substr(v, 1, 1) == "\"" || substr(v, 1, 1) == "\x27") {
        q    = substr(v, 1, 1)
        rest = substr(v, 2)
        if (index(rest, q) == 0) { incont = 1; printf "%s=set\n", key; next }
      }
      gsub(/^["\x27]|["\x27]$/, "", v)
      sub(/[ \t]+$/, "", v)
      printf "%s=%s\n", key, (v == "" ? "empty" : "set")
    }
  ' "$f"
}

is_ignored() {
  git -C "$ROOT" check-ignore -q -- "$1" 2>/dev/null
}


# ---------------------------------------------------------------- ledger
# Record THAT a transfer happened, to which NAMED host, when, and the
# non-reversible digest. Never the contents, never the remote path (a path
# leaks deployment structure and buys nothing for parity).
record_transfer() {
  local direction="$1" name="$2" host="$3" dig="$4" status="$5"
  local records="$ROOT/deploys/records"
  mkdir -p "$records" 2>/dev/null || return 0
  local stamp id n
  stamp="$(date -u '+%Y%m%d-%H%M%S')"
  id="ENV-${stamp}-${name}"; n=1
  while ! ( set -C; : > "$records/.$id.lock" ) 2>/dev/null; do
    n=$(( n + 1 )); id="ENV-${stamp}-${name}-${n}"
    [ "$n" -lt 100 ] || return 0
  done
  {
    echo "---"
    echo "id: $id"
    echo "kind: env-transfer"
    echo "environment: $name"
    echo "class: config"
    echo "tag: $dig"
    echo "direction: $direction"
    echo "peer_host: $host"
    echo "sha: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "branch: $(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    echo "user: $(whoami)"
    echo "host: $(hostname -s 2>/dev/null || echo unknown)"
    echo "started: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "finished: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "status: $status"
    echo "duration_s: "
    echo "error_stage: "
    echo "approval: invocation"
    echo "task_refs: "
    echo "---"
    echo ""
    echo "# $id"
    echo ""
    echo "Config for **$name** ${direction}ed with \`$host\`. Digest \`$dig\`."
    echo ""
    echo "No contents, no remote path, and no per-key digest are recorded."
  } > "$records/$id.md"
  rm -f "$records/.$id.lock"
  local ds="$ROOT/.claude/skills/deploys/deploys.sh"
  [ -f "$ds" ] && bash "$ds" index >/dev/null 2>&1 || true
  echo "  recorded: $id"
}

# ------------------------------------------------------------- protect
# Idempotent. Runs before every verb that touches a file: the whole model
# rests on these files being uncommittable, and secrets.sh only ever adds
# the literal `.env`, leaving .env.staging and .env.production exposed.
cmd_protect() {
  local gi="$ROOT/.gitignore" added=0
  [ -f "$gi" ] || : > "$gi"
  local want
  for want in '.env' '.env.*' '!.env-template'; do
    if ! grep -qxF "$want" "$gi" 2>/dev/null; then
      if [ "$added" -eq 0 ]; then
        printf '\n# env profiles — values never get committed (env-sync)\n' >> "$gi"
        added=1
      fi
      printf '%s\n' "$want" >> "$gi"
      echo "  + .gitignore: $want"
    fi
  done
  [ "$added" -eq 1 ] || echo "  .gitignore already covers env profiles"
}

require_ignored() {
  local rel="$1"
  is_ignored "$rel" && return 0

  # A TRACKED file is a different problem from an unignored one, and
  # `protect` does not fix it: the bytes are already in history, on every
  # clone and every fork. Saying "run protect" there would be useless
  # advice at the exact moment it matters.
  if git -C "$ROOT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
    echo "✗ refusing: '$rel' is TRACKED by git." >&2
    echo "" >&2
    echo "  Those credentials are already in history — on every clone and" >&2
    echo "  every fork. Moving the file to another machine does not undo" >&2
    echo "  that and adding it to .gitignore does not either." >&2
    echo "" >&2
    echo "  Treat them as compromised: rotate the values, then remove the" >&2
    echo "  file from tracking (git rm --cached '$rel'), then run" >&2
    echo "  'env-sync.sh protect'. Transport the NEW values afterwards." >&2
    return 3
  fi

  echo "✗ refusing: '$rel' is not gitignored." >&2
  echo "  Transporting a committable secret is how it ends up in history." >&2
  echo "  Run: env-sync.sh protect" >&2
  return 3
}

# -------------------------------------------------------------- status
cmd_status() {
  printf '%-22s %-9s %-9s %s\n' "FILE" "PRESENT" "IGNORED" "DIGEST"
  local name f rel present ignored
  for name in local test staging production; do
    rel="$(env_file_for "$name")"
    f="$ROOT/$rel"
    present="no"; [ -e "$f" ] && present="yes"
    ignored="no"; is_ignored "$rel" && ignored="yes"
    printf '%-22s %-9s %-9s %s\n' "$rel" "$present" "$ignored" "$(digest "$f")"
  done
  echo ""
  echo "Digest is the first 16 hex of a sha256 over the file contents"
  echo "(symlinks followed). Equal digests mean identical files."
}

# --------------------------------------------------------- fingerprint
cmd_fingerprint() {
  local rel f; rel="$(env_file_for "$1")"; f="$ROOT/$rel"
  if [ ! -e "$f" ]; then
    echo "file: $rel"; echo "state: absent"; return 0
  fi
  echo "file: $rel"
  echo "digest: $(digest "$f")"
  echo "keys:"
  key_map "$f" | sed 's/^/  /'
}

# ------------------------------------------------------------- command
# Printing the command the human runs is a first-class outcome, not a
# fallback: it is the only path that works when the destination needs a
# passphrase, a hardware key, a jump host or a VPN this process has not got.
cmd_command() {
  local dir="$1" name="$2" dest="$3"
  local rel; rel="$(env_file_for "$name")"
  case "$dir" in
    push) echo "scp -p -- '$ROOT/$rel' '$dest'" ;;
    pull) echo "scp -p -- '$dest' '$ROOT/$rel'" ;;
    *) echo "error: direction must be push or pull" >&2; return 2 ;;
  esac
  echo ""
  echo "# scp follows symlinks, so a .env managed by /secrets sends its"
  echo "# contents rather than the link. The receiving side gets a real"
  echo "# file — do not point /secrets at it afterwards without migrating."
  echo "# Verify afterwards with: env-sync.sh parity $name <user@host>"
}

# ---------------------------------------------------------- push / pull
cmd_push() {
  local name="$1" dest="$2"
  local rel; rel="$(env_file_for "$name")"
  [ -e "$ROOT/$rel" ] || { echo "✗ no such env file: $rel" >&2; return 1; }
  require_ignored "$rel" || return 3
  case "$dest" in *:*) ;; *) echo "✗ destination must be user@host:/path" >&2; return 2 ;; esac
  echo "→ $rel  ⇒  $dest"
  echo "  digest before: $(digest "$ROOT/$rel")"
  if scp -p -- "$ROOT/$rel" "$dest"; then
    record_transfer push "$name" "${dest%%:*}" "$(digest "$ROOT/$rel")" success
    echo "✓ sent. Verify with: env-sync.sh parity $name ${dest%%:*}"
  else
    record_transfer push "$name" "${dest%%:*}" "$(digest "$ROOT/$rel")" failed
    echo "✗ transfer failed." >&2; return 1
  fi
}

cmd_pull() {
  local name="$1" src="$2"
  local rel; rel="$(env_file_for "$name")"
  cmd_protect >/dev/null
  require_ignored "$rel" || return 3
  case "$src" in *:*) ;; *) echo "✗ source must be user@host:/path" >&2; return 2 ;; esac
  if [ -L "$ROOT/$rel" ]; then
    echo "✗ $rel is a symlink (managed by /secrets)." >&2
    echo "  Pulling would replace the link with a real file and orphan the store." >&2
    echo "  Write to the store instead, or run: secrets.sh migrate" >&2
    return 1
  fi
  if [ -e "$ROOT/$rel" ]; then
    local bak="$ROOT/$rel.backup-$(date -u '+%Y%m%d-%H%M%S')"
    cp -p -- "$ROOT/$rel" "$bak"
    echo "  existing file backed up: $(basename "$bak")"
  fi
  if scp -p -- "$src" "$ROOT/$rel"; then
    chmod 600 "$ROOT/$rel" 2>/dev/null || true
    record_transfer pull "$name" "${src%%:*}" "$(digest "$ROOT/$rel")" success
    echo "✓ received. digest now: $(digest "$ROOT/$rel")"
  else
    record_transfer pull "$name" "${src%%:*}" absent failed
    echo "✗ transfer failed." >&2; return 1
  fi
}

# -------------------------------------------------------------- parity
# Compares digests only. It can tell you THAT two files differ; it cannot
# tell you WHICH key differs, and it deliberately will not try — see the
# no-per-key-digest note in the header.
cmd_parity() {
  local name="$1" host="$2" remote_path="${3:-}"
  local rel; rel="$(env_file_for "$name")"
  local local_digest; local_digest="$(digest "$ROOT/$rel")"
  [ -n "$remote_path" ] || remote_path="$rel"

  echo "env:    $name  ($rel)"
  echo "local:  $local_digest"

  local remote_digest
  remote_digest="$(ssh -o BatchMode=yes "$host" \
      "cat -- '$remote_path' 2>/dev/null | shasum -a 256 2>/dev/null | cut -c1-16" \
      2>/dev/null || true)"
  remote_digest="$(printf '%s' "$remote_digest" | tr -d '[:space:]')"
  [ -n "$remote_digest" ] || remote_digest="absent-or-unreachable"
  echo "remote: $remote_digest  ($host:$remote_path)"
  echo ""

  if [ "$local_digest" = "$remote_digest" ]; then
    echo "✓ in parity"
    return 0
  fi
  echo "✗ NOT in parity"
  echo "  Which key differs is not knowable from here by design — a per-key"
  echo "  digest of a low-entropy secret is a brute-forceable value oracle."
  echo "  Compare key NAMES with: env-sync.sh fingerprint $name"
  return 3
}

usage() { sed -n '3,50p' "$0" | sed 's/^# \{0,1\}//'; }

main() {
  local action="${1:-}"; [ $# -gt 0 ] && shift
  case "$action" in
    protect) cmd_protect ;;
    status)  cmd_status ;;
    fingerprint) [ $# -ge 1 ] || { echo "error: fingerprint needs <env>" >&2; return 2; }
                 cmd_fingerprint "$1" ;;
    command) [ $# -ge 3 ] || { echo "error: command needs <push|pull> <env> <dest>" >&2; return 2; }
             cmd_command "$1" "$2" "$3" ;;
    push)    [ $# -ge 2 ] || { echo "error: push needs <env> <user@host:path>" >&2; return 2; }
             cmd_push "$1" "$2" ;;
    pull)    [ $# -ge 2 ] || { echo "error: pull needs <env> <user@host:path>" >&2; return 2; }
             cmd_pull "$1" "$2" ;;
    parity)  [ $# -ge 2 ] || { echo "error: parity needs <env> <user@host> [remote-path]" >&2; return 2; }
             cmd_parity "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "error: unknown action: $action" >&2; usage >&2; return 2 ;;
  esac
}

main "$@"
