#!/usr/bin/env bash
# deploy-sync-lib.sh — "deploys never go backwards", shared by
# gates/trunk-sync.sh, gates/live-contained.sh and the standalone checker
# .claude/skills/deploy/deploy-check.sh. Sourced, never executed.
#
# THE TWO RULES (pipeline-rules.md, "Deploys never go backwards")
#
#   1. Sync with the trunk first. Fetch the trunk right before deploying.
#      Production ships exactly the trunk tip; a lower environment ships a
#      commit that contains the trunk tip.
#   2. Never drop what another session shipped. The commit live in the
#      environment right now must be an ancestor of the commit being
#      deployed. A deploy replaces the whole target, so deploying a tree that
#      lacks the live commit silently removes someone else's work.
#
# WHY. Two sessions, one site: session A deployed its own merge commit
# minutes after session B had merged and deployed a newer one on top of it.
# A's tree did not contain B's merge, the deploy replaced the whole site, and
# B's live feature disappeared until someone noticed. Nothing was "wrong"
# with either commit; the deploy went backwards.
#
# FUNCTIONS (all report to stderr; machine lines `key=value` go to stdout)
#
#   ds_init <project-dir>          set DS_PROJECT and DS_PFX
#   ds_env_class <env>             prod | staging | dev | unclassified
#   ds_trunk_check <env> <class>   rule 1. rc 0 pass, 1 refuse
#   ds_live_check <env> <class>    rule 2. rc 0 pass, 1 refuse
#
# INPUTS (environment)
#
#   DEPLOY_TRUNK          the trunk, `origin/main` or `main`. Else
#                         build/pipeline-config.toml `[git] trunk`, else the
#                         remote's HEAD, else `main`.
#   RELEASE_PR=<n>        /release's integration path: production accepts a
#                         commit that CONTAINS the trunk tip (not only the
#                         tip itself) because release PR #n merges exactly
#                         that commit after the deploy. Recorded.
#   LIVE_SHA=<sha|none>   the live commit, given directly (the checker's
#                         --live-sha). Wins over every other source.
#   LIVE_SHA_CMD          a command printing the live commit. Also settable
#                         in build/environments/<env>/env.sh, beside the
#                         preferred hook: a `live_sha` function there.
#   ALLOW_BEHIND_TRUNK=1  override rule 1 (loud, recorded)
#   ALLOW_DROP_LIVE=1     override rule 2 (loud, recorded)
#   LIVE_SHA_UNKNOWN_OK=1 production with no way to know what is live
#                         (first deploy, no hook, no record) — recorded
#
# A hook prints the live commit (7–40 hex characters), or `none` when the
# environment has never been deployed. Anything else is "unknown".
#
# Portability: bash 3.2 (stock macOS), POSIX tools, git.

# The shared record library (rfm_get), found beside an install
# (.claude/lib/domain-code) or in the Element tree (content/lib/domain-code).
_ds_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ds_rfm=""
for _ds_d in "$_ds_here/../../.claude/lib/domain-code" "$_ds_here/../../lib/domain-code"; do
  if [ -f "$_ds_d/frontmatter.sh" ]; then _ds_rfm="$_ds_d/frontmatter.sh"; break; fi
done
[ -n "$_ds_rfm" ] || { echo "error: .claude/lib/domain-code/frontmatter.sh is missing — re-run the Element's bin/init" >&2; return 70 2>/dev/null || exit 70; }
# shellcheck source=/dev/null
. "$_ds_rfm"
unset _ds_d

DS_PROJECT=""
DS_PFX=""
DS_REMOTE=""
DS_BRANCH=""
DS_TRUNK_REF=""
DS_LIVE=""
DS_LIVE_SRC=""
DS_CAP=20

ds_init() {
  DS_PROJECT="$(cd "$1" && pwd -P)" || return 2
  DS_PFX="$(git -C "$DS_PROJECT" rev-parse --show-prefix 2>/dev/null || true)"
  git -C "$DS_PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "✗ deploy-sync: $DS_PROJECT is not inside a git repository" >&2
    return 2
  }
}

_ds_git() { git -C "$DS_PROJECT" "$@"; }
_ds_say() { echo "$*" >&2; }
_ds_short() { printf '%s' "$1" | cut -c1-12; }

# _ds_list <range> — `git log --oneline` of a range, capped, indented.
_ds_list() {
  local n
  n="$(_ds_git rev-list --count "$1" 2>/dev/null || echo 0)"
  _ds_git log --oneline --no-decorate -n "$DS_CAP" "$1" 2>/dev/null | sed 's/^/      /' >&2
  [ "$n" -le "$DS_CAP" ] || _ds_say "      … and $((n - DS_CAP)) more"
}

# ds_env_class <env> — ENV_CLASS when the caller set it (build/deploy does);
# else the registry; else the escalate-only name heuristic class-guard uses.
ds_env_class() {
  local e="$1" c="" envsh lower tok
  case "${ENV_CLASS:-}" in dev|staging|prod) printf '%s' "$ENV_CLASS"; return 0 ;; esac
  envsh="$DS_PROJECT/.claude/skills/environment/environment.sh"
  if [ -f "$envsh" ]; then c="$(bash "$envsh" class "$e" 2>/dev/null || true)"; fi
  case "$c" in dev|staging|prod) printf '%s' "$c"; return 0 ;; esac
  lower="$(printf '%s' "$e" | tr '[:upper:]' '[:lower:]')"
  c="unclassified"
  case "$lower" in
    *preprod*|*pre-prod*|*pre_prod*|*nonprod*|*non-prod*|*non_prod*|*notprod*|*not-prod*|*not_prod*) ;;
    *) for tok in $(printf '%s' "$lower" | tr '\-_.' '   '); do
         case "$tok" in prod*|live*) c="prod" ;; esac
       done ;;
  esac
  printf '%s' "$c"
}

# ── the trunk ───────────────────────────────────────────────────────────────
# Sets DS_REMOTE (may be empty: no remote), DS_BRANCH, DS_TRUNK_REF.
ds_trunk_resolve() {
  local spec="${DEPLOY_TRUNK:-}" cfg r
  if [ -z "$spec" ]; then
    cfg="$DS_PROJECT/build/pipeline-config.toml"
    if [ -f "$cfg" ]; then
      spec="$(LC_ALL=C awk '
        /^[ \t]*\[/ { sec = $0; gsub(/[ \t\[\]]/, "", sec); next }
        sec == "git" && /^[ \t]*trunk[ \t]*=/ {
          v = $0; sub(/^[^=]*=[ \t]*/, "", v); sub(/[ \t]*(#.*)?$/, "", v)
          gsub(/^["\047]|["\047]$/, "", v); print v; exit
        }' "$cfg" 2>/dev/null || true)"
    fi
  fi
  DS_REMOTE=""; DS_BRANCH=""
  case "$spec" in
    */*)
      r="${spec%%/*}"
      if _ds_git remote get-url "$r" >/dev/null 2>&1; then DS_REMOTE="$r"; DS_BRANCH="${spec#*/}"; fi ;;
  esac
  if [ -z "$DS_BRANCH" ]; then
    DS_BRANCH="$spec"
    _ds_git remote get-url origin >/dev/null 2>&1 && DS_REMOTE="origin"
  fi
  if [ -z "$DS_BRANCH" ] && [ -n "$DS_REMOTE" ]; then
    r="$(_ds_git symbolic-ref --short -q "refs/remotes/$DS_REMOTE/HEAD" 2>/dev/null || true)"
    DS_BRANCH="${r#"$DS_REMOTE"/}"
  fi
  DS_BRANCH="${DS_BRANCH:-main}"
  if [ -n "$DS_REMOTE" ]; then
    DS_TRUNK_REF="refs/remotes/$DS_REMOTE/$DS_BRANCH"
  else
    DS_TRUNK_REF="refs/heads/$DS_BRANCH"
  fi
}

# ds_trunk_name — how the trunk is written to a person.
ds_trunk_name() { if [ -n "$DS_REMOTE" ]; then printf '%s/%s' "$DS_REMOTE" "$DS_BRANCH"; else printf '%s' "$DS_BRANCH"; fi; }

_ds_override() {
  # $1 = override name, $2 = variable that allowed it, rest = what it hides
  local name="$1" var="$2"; shift 2
  _ds_say ""
  _ds_say "⚠⚠⚠ $var=1 — OVERRIDING the refusal above. ⚠⚠⚠"
  while [ $# -gt 0 ]; do _ds_say "    $1"; shift; done
  _ds_say "    This is recorded in the ship log (overrides: $name)."
  _ds_say ""
  printf 'override=%s\n' "$name"
}

# ds_trunk_check <env> <class>
ds_trunk_check() {
  local env="$1" class="$2" head tip name missing extra fetched=1 err
  ds_trunk_resolve
  name="$(ds_trunk_name)"
  head="$(_ds_git rev-parse --verify -q HEAD 2>/dev/null)" || {
    _ds_say "✗ trunk-sync: this repository has no commits to deploy"; return 1; }

  if [ -n "$DS_REMOTE" ]; then
    err="$(_ds_git fetch -q "$DS_REMOTE" "+refs/heads/$DS_BRANCH:refs/remotes/$DS_REMOTE/$DS_BRANCH" 2>&1)" || fetched=0
    if [ "$fetched" = 0 ]; then
      if [ "$class" = "prod" ]; then
        _ds_say "✗ trunk-sync: REFUSED — could not fetch $name, so the trunk tip is unknown."
        _ds_say "    $(printf '%s' "$err" | head -1)"
        _ds_say "    Production ships exactly the fetched trunk tip. Get online, then deploy."
        if [ "${ALLOW_BEHIND_TRUNK:-0}" = "1" ]; then
          _ds_override behind-trunk ALLOW_BEHIND_TRUNK "Shipping to production without knowing the trunk tip."
          return 0
        fi
        return 1
      fi
      _ds_say "⚠ trunk-sync: could not fetch $name ($(printf '%s' "$err" | head -1))."
      _ds_say "    Comparing with the last fetched $name, which may be stale."
    fi
  else
    _ds_say "  trunk-sync: no remote — comparing with the local '$DS_BRANCH'."
  fi

  tip="$(_ds_git rev-parse --verify -q "$DS_TRUNK_REF^{commit}" 2>/dev/null || true)"
  if [ -z "$tip" ]; then
    if [ "$class" = "prod" ]; then
      _ds_say "✗ trunk-sync: REFUSED — the trunk '$name' does not exist here. Set DEPLOY_TRUNK"
      _ds_say "    (or [git] trunk in build/pipeline-config.toml) to the branch production ships from."
      if [ "${ALLOW_BEHIND_TRUNK:-0}" = "1" ]; then
        _ds_override behind-trunk ALLOW_BEHIND_TRUNK "Shipping to production with no trunk to check against."
        return 0
      fi
      return 1
    fi
    _ds_say "⚠ trunk-sync: the trunk '$name' does not exist here — nothing to check against."
    return 0
  fi
  printf 'trunk_sha=%s\n' "$tip"

  if [ "$head" = "$tip" ]; then
    _ds_say "✓ trunk-sync: HEAD is the tip of $name ($(_ds_short "$tip"))"
    return 0
  fi

  if _ds_git merge-base --is-ancestor "$tip" "$head" 2>/dev/null; then
    if [ "$class" != "prod" ]; then
      _ds_say "✓ trunk-sync: HEAD contains the tip of $name ($(_ds_short "$tip")) — synced"
      return 0
    fi
    case "${RELEASE_PR:-}" in
      ''|*[!0-9]*) ;;
      *)
        _ds_say "✓ trunk-sync: HEAD contains the tip of $name ($(_ds_short "$tip")); release PR #$RELEASE_PR"
        _ds_say "    merges exactly this commit after the deploy (land.sh fresh pins it)."
        printf 'override=release-pr-%s\n' "$RELEASE_PR"
        return 0 ;;
    esac
    extra="$(_ds_git rev-list --count "$tip..$head")"
    _ds_say ""
    _ds_say "✗ trunk-sync: REFUSED — production ships exactly the tip of $name, and HEAD"
    _ds_say "    carries $extra commit(s) that are not on it:"
    _ds_list "$tip..$head"
    _ds_say ""
    _ds_say "    Fix: land them through a PR first, then deploy from $name"
    _ds_say "    (git checkout --detach $name). /release passes RELEASE_PR=<n> for its"
    _ds_say "    own release PR, which merges exactly the commit it deploys."
    if [ "${ALLOW_BEHIND_TRUNK:-0}" = "1" ]; then
      _ds_override behind-trunk ALLOW_BEHIND_TRUNK "Shipping commits to production that are not on $name."
      return 0
    fi
    return 1
  fi

  missing="$(_ds_git rev-list --count "$head..$tip")"
  _ds_say ""
  _ds_say "✗ trunk-sync: REFUSED — HEAD is $missing commit(s) behind $name ($(_ds_short "$tip"))."
  _ds_say "    Deploying it would ship a tree without them:"
  _ds_list "$head..$tip"
  _ds_say ""
  if [ "$class" = "prod" ]; then
    _ds_say "    Fix: deploy from $name (git checkout --detach $name), never from an older commit."
  else
    _ds_say "    Fix: git merge $name (then build and test again), and deploy that."
  fi
  if [ "${ALLOW_BEHIND_TRUNK:-0}" = "1" ]; then
    _ds_override behind-trunk ALLOW_BEHIND_TRUNK "Deploying a tree that is $missing commit(s) behind $name."
    return 0
  fi
  return 1
}

# ── the live commit ─────────────────────────────────────────────────────────
# _ds_pick — the first token of stdin that is `none` or a commit id.
_ds_pick() {
  # `; echo`: a value given without a trailing newline is still read.
  { cat; echo; } | tr '[:upper:]' '[:lower:]' | tr -s ' \t\r' '\n\n\n' | while IFS= read -r t; do
    case "$t" in
      none) printf 'none'; break ;;
      *[!0-9a-f]*|'') ;;
      *) [ "${#t}" -ge 7 ] && [ "${#t}" -le 40 ] && { printf '%s' "$t"; break; } ;;
    esac
  done
}

# ds_live_from_hook <env> — DS_LIVE, DS_LIVE_SRC; rc 0 found, 1 no hook,
# 2 a hook that failed or printed no commit.
ds_live_from_hook() {
  local env="$1" envsh out rc
  envsh="$DS_PROJECT/build/environments/$env/env.sh"
  DS_LIVE=""; DS_LIVE_SRC=""
  if [ -n "${LIVE_SHA:-}" ]; then
    DS_LIVE="$(printf '%s' "$LIVE_SHA" | _ds_pick)"; DS_LIVE_SRC="LIVE_SHA"
    [ -n "$DS_LIVE" ] && return 0
    _ds_say "  live-contained: LIVE_SHA='$LIVE_SHA' is not a commit id or 'none'"; return 2
  fi
  # Sourced in a subshell: the hook may be a function, which an exported
  # environment cannot carry from build/deploy to this gate.
  out="$(cd "$DS_PROJECT" && {
          if [ -f "$envsh" ]; then . "$envsh" >/dev/null 2>&1 || true; fi
          if [ "$(type -t live_sha 2>/dev/null)" = "function" ]; then
            echo "@src=env.sh live_sha"; live_sha "$env"
          elif [ -n "${LIVE_SHA_CMD:-}" ]; then
            echo "@src=LIVE_SHA_CMD"; bash -c "$LIVE_SHA_CMD"
          else
            echo "@src="
          fi; } 2>/dev/null)" && rc=0 || rc=$?
  DS_LIVE_SRC="$(printf '%s\n' "$out" | sed -n 's/^@src=//p' | head -1)"
  [ -n "$DS_LIVE_SRC" ] || return 1
  if [ "$rc" -ne 0 ]; then
    _ds_say "  live-contained: the live hook ($DS_LIVE_SRC) failed (exit $rc)"; return 2
  fi
  DS_LIVE="$(printf '%s\n' "$out" | sed '/^@src=/d' | _ds_pick)"
  [ -n "$DS_LIVE" ] && return 0
  _ds_say "  live-contained: the live hook ($DS_LIVE_SRC) printed no commit id"
  return 2
}

# ds_live_from_records <env> — the newest successful (not dry-run) ship-log
# record for <env>, from this checkout's deploys/records/ and from the trunk's
# committed ones. DS_LIVE, DS_LIVE_SRC; rc 0 found, 1 none.
ds_live_from_records() {
  local env="$1" dir="$DS_PROJECT/deploys/records" rel tmp names f src st es sha
  DS_LIVE=""; DS_LIVE_SRC=""
  rel="${DS_PFX}deploys/records"
  tmp="$(mktemp "${TMPDIR:-/tmp}/ds-rec.XXXXXX")" || return 1
  # Newest first by name (DEP-<utc>-<env>[-n]); `.md` is cut before sorting so
  # a same-second `-2` sorts above its base. The checkout's copy wins a tie.
  names="$( {
      if [ -d "$dir" ]; then (cd "$dir" && ls -1 2>/dev/null) | sed 's/^/W /' || true; fi
      if [ -n "${DS_TRUNK_REF:-}" ]; then
        _ds_git ls-tree --name-only "$DS_TRUNK_REF:$rel" 2>/dev/null | sed 's/^/T /' || true
      fi
    } | sed -n 's/\.md$//p' | LC_ALL=C sort -k2,2r -k1,1r)" || names=""
  while IFS=' ' read -r src f; do
    [ -n "$f" ] || continue
    f="$f.md"
    case "$f" in "DEP-"*"-$env.md"|"DEP-"*"-$env-"[0-9]*.md) ;; *) continue ;; esac
    if [ "$src" = "W" ]; then cp "$dir/$f" "$tmp" 2>/dev/null || continue
    else _ds_git show "$DS_TRUNK_REF:$rel/$f" > "$tmp" 2>/dev/null || continue; fi
    [ "$(rfm_get "$tmp" environment 2>/dev/null)" = "$env" ] || continue
    st="$(rfm_get "$tmp" status 2>/dev/null || true)"
    es="$(rfm_get "$tmp" error_stage 2>/dev/null || true)"
    sha="$(rfm_get "$tmp" sha 2>/dev/null || true)"
    [ "$st" = "success" ] && [ "$es" != "dry-run" ] || continue
    case "$sha" in ''|unknown) continue ;; esac
    DS_LIVE="$(printf '%s' "$sha" | _ds_pick)"
    [ -n "$DS_LIVE" ] || continue
    if [ "$src" = "W" ]; then DS_LIVE_SRC="ship log $f"; else DS_LIVE_SRC="ship log $f (on $(ds_trunk_name))"; fi
    break
  done <<EOF
$names
EOF
  rm -f "$tmp"
  [ -n "$DS_LIVE" ]
}

# ds_live_check <env> <class>
ds_live_check() {
  local env="$1" class="$2" head live hrc n
  [ -n "${DS_TRUNK_REF:-}" ] || ds_trunk_resolve
  head="$(_ds_git rev-parse --verify -q HEAD 2>/dev/null)" || {
    _ds_say "✗ live-contained: this repository has no commits to deploy"; return 1; }

  ds_live_from_hook "$env" && hrc=0 || hrc=$?
  if [ "$hrc" = 1 ]; then ds_live_from_records "$env" || true; fi

  if [ -z "$DS_LIVE" ]; then
    if [ "$class" = "prod" ]; then
      _ds_say ""
      _ds_say "✗ live-contained: REFUSED — what is live in '$env' is unknown"
      if [ "$hrc" = 2 ]; then _ds_say "    (its live hook did not answer — see above)."
      else _ds_say "    (no live_sha hook in build/environments/$env/env.sh, no LIVE_SHA_CMD, no ship-log record)."; fi
      _ds_say "    A deploy replaces the whole target; without the live commit nobody can"
      _ds_say "    tell whether this one drops what another session shipped."
      _ds_say "    Fix: add a live_sha hook (pipeline-rules.md), or — first deploy, or after"
      _ds_say "    checking by hand — LIVE_SHA_UNKNOWN_OK=1."
      if [ "${LIVE_SHA_UNKNOWN_OK:-0}" = "1" ]; then
        _ds_say "⚠ LIVE_SHA_UNKNOWN_OK=1 — deploying over an unknown live commit (recorded: live-unknown)."
        printf 'override=live-unknown\n'
        return 0
      fi
      return 1
    fi
    _ds_say "⚠ live-contained: what is live in '$env' is unknown — cannot prove this deploy drops"
    _ds_say "    nothing. Add a live_sha hook to build/environments/$env/env.sh."
    return 0
  fi

  if [ "$DS_LIVE" = "none" ]; then
    _ds_say "✓ live-contained: '$env' has nothing live ($DS_LIVE_SRC)"
    printf 'live_sha=none\n'
    return 0
  fi

  live="$(_ds_git rev-parse --verify -q "$DS_LIVE^{commit}" 2>/dev/null || true)"
  if [ -z "$live" ] && [ -n "$DS_REMOTE" ]; then
    _ds_git fetch -q "$DS_REMOTE" >/dev/null 2>&1 || true
    _ds_git fetch -q "$DS_REMOTE" "$DS_LIVE" >/dev/null 2>&1 || true
    live="$(_ds_git rev-parse --verify -q "$DS_LIVE^{commit}" 2>/dev/null || true)"
  fi
  if [ -z "$live" ]; then
    _ds_say ""
    _ds_say "✗ live-contained: REFUSED — '$env' runs $DS_LIVE ($DS_LIVE_SRC), a commit this"
    _ds_say "    repository does not have, even after fetching. Someone deployed a commit that"
    _ds_say "    is on no branch you have — find it (which session, which branch) before"
    _ds_say "    deploying, or you will remove whatever it shipped."
    if [ "${ALLOW_DROP_LIVE:-0}" = "1" ]; then
      _ds_override drop-live ALLOW_DROP_LIVE "Replacing an unknown live commit $DS_LIVE in '$env'."
      printf 'live_sha=%s\n' "$DS_LIVE"
      return 0
    fi
    return 1
  fi
  printf 'live_sha=%s\n' "$live"

  if _ds_git merge-base --is-ancestor "$live" "$head" 2>/dev/null; then
    _ds_say "✓ live-contained: HEAD contains what is live in '$env' ($(_ds_short "$live"), $DS_LIVE_SRC)"
    return 0
  fi

  n="$(_ds_git rev-list --count "$head..$live")"
  _ds_say ""
  _ds_say "✗ live-contained: REFUSED — '$env' runs $(_ds_short "$live") ($DS_LIVE_SRC), and HEAD"
  _ds_say "    does not contain it. Deploying would drop $n live commit(s):"
  _ds_list "$head..$live"
  _ds_say ""
  _ds_say "    A deploy replaces the whole target. Fix: git fetch, then merge what is live"
  _ds_say "    (git merge $(_ds_short "$live"), or the branch that holds it — usually $(ds_trunk_name)),"
  _ds_say "    build and test again, and deploy that."
  if [ "${ALLOW_DROP_LIVE:-0}" = "1" ]; then
    _ds_override drop-live ALLOW_DROP_LIVE "Removing $n commit(s) that are live in '$env'."
    return 0
  fi
  return 1
}
