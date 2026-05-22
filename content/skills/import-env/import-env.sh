#!/usr/bin/env bash
# import-env.sh — parse .env files into env-var stamps without exposing values
#
# Security primitive: values NEVER leave this script. Every subcommand
# reads keys only. Values are discarded at the read line; nothing
# returns them to stdout, stderr, or any log. The orchestrating Claude
# skill (SKILL.md) calls this script and never sees a single value.
#
# Language: pure bash. No YAML parser needed — stamp frontmatter is
# scanned with grep/awk for the simple fields this script uses.

set -euo pipefail

# ─── Paths ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

project_root() {
  # Walk up from cwd until we find env/stamps/ or hit /
  local d
  d="$(pwd)"
  while [[ "$d" != "/" ]]; do
    if [[ -d "$d/env/stamps" ]] || [[ -d "$d/.claude" ]]; then
      echo "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  # Fallback: cwd
  pwd
}

usage() {
  cat <<'EOF'
import-env.sh — parse .env files into env-var stamps (values stay local)

USAGE:
  import-env.sh parse <env-file>
      List every KEY in the file, one per line. Values are discarded.
      Skips empty lines, comments, malformed lines.

  import-env.sh diff <env-file>
      Compare keys in <env-file> vs stamps under env/stamps/.
      Output sections: NEW, KNOWN, MISSING.

  import-env.sh suggest <key>
      Output heuristic defaults for a key as `field=value` lines.
      Fields: group, purpose, type, required, kebab_name.

  import-env.sh add <key> [opts]
      Generate a stamp at env/stamps/<kebab-name>.md.
      Options:
        --required <true|false>          (default: true)
        --group <slash-path>             (default: 'misc')
        --purpose <enum>                 (default: 'config')
        --type <enum>                    (default: 'string')
        --default <value>                (default: empty)
        --description <text>             (default: 'TODO — describe')
        --environments <comma,list>      (default: 'local')
        --used-by-runtimes <comma,list>  (default: empty)
        --used-by-clouds <comma,list>    (default: empty)
        --tags <comma,list>              (default: empty)
        --force                          (overwrite existing stamp)

  import-env.sh add-profile <key> <profile-name>
      Append <profile-name> to an existing stamp's environments[].
      No-op if already present.

  import-env.sh list [--required-only] [--group <pattern>]
      List existing stamps with var_name, required, group, purpose.

  import-env.sh validate
      Coverage check: every key in .env-template has a stamp;
      every required stamp's var_name appears in .env-template.
      Exit 0 if clean, 3 if drift detected.

  import-env.sh help
      This message.

EXIT CODES:
  0  success
  1  operational error (file not found, write failed)
  2  usage error
  3  validation failed

VALUES NEVER LEAVE THIS SCRIPT. If you see a value in this script's
output, that's a bug — please report it.
EOF
}

# ─── parse ─────────────────────────────────────────────────────────────────
# Read a .env file, emit one KEY per line. Skip blank/comment/malformed.
# Values are discarded at the read line — not echoed, not stored.
cmd_parse() {
  local file="${1:?usage: parse <env-file>}"
  if [[ ! -f "$file" ]]; then
    echo "error: file not found: $file" >&2
    return 1
  fi

  # Match: optional whitespace, valid env-var name, =, anything.
  # Capture group 1 = the KEY. Value (after =) is discarded.
  local line key
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip blank lines
    [[ -z "${line// }" ]] && continue
    # Skip comments (lines starting with optional whitespace + #)
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    # Match KEY=anything; extract KEY only
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)= ]]; then
      key="${BASH_REMATCH[2]}"
      echo "$key"
    fi
    # Lines without = are silently skipped (malformed)
  done < "$file"
}

# ─── diff ──────────────────────────────────────────────────────────────────
# Compare file's keys against existing stamps. Output three sections.
cmd_diff() {
  local file="${1:?usage: diff <env-file>}"
  local root
  root="$(project_root)"
  local stamps_dir="$root/env/stamps"

  # Get keys in file (one per line, sorted unique)
  local file_keys
  file_keys=$(cmd_parse "$file" | sort -u)

  # Get var_names from existing stamps
  local stamp_keys=""
  if [[ -d "$stamps_dir" ]]; then
    stamp_keys=$(
      for f in "$stamps_dir"/*.md; do
        [[ -f "$f" ]] || continue
        awk '/^---$/{f++; next} f==1 && /^var_name:/{sub(/^var_name:[[:space:]]*/, ""); print; exit}' "$f"
      done | sort -u
    )
  fi

  # Three sets: NEW (in file, no stamp), KNOWN (both), MISSING (stamp, not in file)
  local new_keys known_keys missing_keys
  new_keys=$(comm -23 <(echo "$file_keys") <(echo "$stamp_keys"))
  known_keys=$(comm -12 <(echo "$file_keys") <(echo "$stamp_keys"))
  missing_keys=$(comm -13 <(echo "$file_keys") <(echo "$stamp_keys"))

  echo "NEW:"
  [[ -n "$new_keys" ]] && echo "$new_keys" | sed 's/^/  /' || echo "  (none)"
  echo ""
  echo "KNOWN:"
  [[ -n "$known_keys" ]] && echo "$known_keys" | sed 's/^/  /' || echo "  (none)"
  echo ""
  echo "MISSING (stamp exists but not in this file):"
  [[ -n "$missing_keys" ]] && echo "$missing_keys" | sed 's/^/  /' || echo "  (none)"
}

# ─── suggest ───────────────────────────────────────────────────────────────
# Emit heuristic defaults for a given KEY based on naming patterns.
# Output format: one `field=value` per line for shell parsing.
cmd_suggest() {
  local key="${1:?usage: suggest <KEY>}"

  # Derive kebab-name (lowercase, _ → -)
  local kebab
  kebab="$(echo "$key" | tr '[:upper:]_' '[:lower:]-')"

  # Defaults
  local group="misc"
  local purpose="config"
  local type="string"
  local required="true"

  # Pattern matches — order matters; specific patterns first
  case "$key" in
    # Connections
    POSTGRES_*|PG_*)
      group="database/postgres"; purpose="connection"
      [[ "$key" == *PASSWORD* || "$key" == *SECRET* ]] && purpose="secret"
      [[ "$key" == *USER* || "$key" == *USERNAME* ]] && purpose="credential"
      [[ "$key" == *PORT* ]] && type="int"
      ;;
    MYSQL_*|MARIADB_*)
      group="database/mysql"; purpose="connection"
      [[ "$key" == *PASSWORD* ]] && purpose="secret"
      [[ "$key" == *USER* ]] && purpose="credential"
      [[ "$key" == *PORT* ]] && type="int"
      ;;
    MONGO*|MONGODB_*)
      group="database/mongodb"; purpose="connection"
      [[ "$key" == *URI* || "$key" == *URL* ]] && { purpose="url"; type="url"; }
      [[ "$key" == *PASSWORD* || "$key" == *SECRET* ]] && purpose="secret"
      ;;
    REDIS_*)
      group="database/redis"; purpose="connection"
      [[ "$key" == *URL* ]] && { purpose="url"; type="url"; }
      [[ "$key" == *PORT* ]] && type="int"
      ;;
    CHROMA_*|CHROMADB_*)
      group="database/chromadb"; purpose="connection"
      [[ "$key" == *PORT* ]] && type="int"
      ;;
    # External APIs
    OPENAI_*)            group="external-apis/openai"; purpose="secret" ;;
    ANTHROPIC_*)         group="external-apis/anthropic"; purpose="secret" ;;
    STRIPE_*)            group="external-apis/stripe"; purpose="secret" ;;
    TWILIO_*)            group="external-apis/twilio"; purpose="secret" ;;
    SENDGRID_*)          group="external-apis/sendgrid"; purpose="secret" ;;
    # Auth
    JWT_*)               group="auth/jwt"; purpose="secret" ;;
    OAUTH_*)             group="auth/oauth"
                         [[ "$key" == *SECRET* || "$key" == *KEY* ]] && purpose="secret"
                         [[ "$key" == *ID* || "$key" == *CLIENT* ]] && purpose="credential"
                         ;;
    SESSION_*)           group="auth/session"
                         [[ "$key" == *SECRET* ]] && purpose="secret"
                         ;;
    # Cloud
    AWS_*)               group="cloud/aws"
                         [[ "$key" == *SECRET* || "$key" == *KEY* ]] && purpose="secret"
                         [[ "$key" == *REGION* ]] && purpose="config"
                         ;;
    AZURE_*)             group="cloud/azure"
                         [[ "$key" == *SECRET* || "$key" == *KEY* ]] && purpose="secret"
                         [[ "$key" == *CLIENT_ID* || "$key" == *TENANT* || "$key" == *SUBSCRIPTION* ]] && purpose="credential"
                         ;;
    GCP_*|GOOGLE_*)      group="cloud/gcp"
                         [[ "$key" == *SECRET* || "$key" == *KEY* ]] && purpose="secret"
                         ;;
    # Feature flags
    FEATURE_*|ENABLE_*|DISABLE_*)
                         group="feature-flags"; purpose="feature-flag"; type="bool"; required="false"
                         ;;
    # Logging / observability
    LOG_*|DEBUG_*)       group="logging"; purpose="config"; required="false"
                         [[ "$key" == LOG_LEVEL ]] && type="string"
                         ;;
    SENTRY_*)            group="logging/sentry"
                         [[ "$key" == *DSN* ]] && { purpose="url"; type="url"; required="false"; }
                         [[ "$key" == *KEY* ]] && purpose="secret"
                         ;;
    DATADOG_*|OTEL_*)    group="logging/observability"; required="false" ;;
    # Generic suffix heuristics
    *_URL|*_ENDPOINT|*_URI|*_DSN)
                         purpose="url"; type="url"
                         ;;
    *_PORT)              purpose="connection"; type="int" ;;
    *_HOST|*_HOSTNAME|*_SERVER)
                         purpose="connection"
                         ;;
    *_PASSWORD|*_SECRET|*_TOKEN|*_API_KEY|*_PRIVATE_KEY)
                         purpose="secret"
                         ;;
    *_KEY)               purpose="secret" ;;
    *_USER|*_USERNAME)   purpose="credential" ;;
    *_ENABLED|*_DISABLED)
                         purpose="feature-flag"; type="bool"; required="false"
                         ;;
  esac

  cat <<EOF
kebab_name=$kebab
var_name=$key
group=$group
purpose=$purpose
type=$type
required=$required
EOF
}

# ─── add ───────────────────────────────────────────────────────────────────
# Generate a stamp file. All metadata via flags; values never accepted.
cmd_add() {
  local key=""
  local required="true"
  local group="misc"
  local purpose="config"
  local type="string"
  local default=""
  local description="TODO — describe"
  local environments="local"
  local used_by_runtimes=""
  local used_by_clouds=""
  local tags=""
  local force=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --required)            required="$2"; shift 2 ;;
      --group)               group="$2"; shift 2 ;;
      --purpose)             purpose="$2"; shift 2 ;;
      --type)                type="$2"; shift 2 ;;
      --default)             default="$2"; shift 2 ;;
      --description)         description="$2"; shift 2 ;;
      --environments)        environments="$2"; shift 2 ;;
      --used-by-runtimes)    used_by_runtimes="$2"; shift 2 ;;
      --used-by-clouds)      used_by_clouds="$2"; shift 2 ;;
      --tags)                tags="$2"; shift 2 ;;
      --force)               force=true; shift ;;
      --*)                   echo "error: unknown flag $1" >&2; return 2 ;;
      *)                     [[ -z "$key" ]] && key="$1" || { echo "error: extra arg $1" >&2; return 2; }; shift ;;
    esac
  done

  if [[ -z "$key" ]]; then
    echo "error: missing <KEY>. usage: add <KEY> [opts]" >&2
    return 2
  fi

  # Validate enums
  case "$purpose" in
    connection|credential|feature-flag|config|secret|url|derived) ;;
    *) echo "error: invalid --purpose '$purpose'" >&2; return 2 ;;
  esac
  case "$type" in
    string|int|bool|url|list|json) ;;
    *) echo "error: invalid --type '$type'" >&2; return 2 ;;
  esac
  case "$required" in
    true|false) ;;
    *) echo "error: --required must be true or false" >&2; return 2 ;;
  esac

  # Compute paths
  local kebab
  kebab="$(echo "$key" | tr '[:upper:]_' '[:lower:]-')"
  local root
  root="$(project_root)"
  local stamps_dir="$root/env/stamps"
  mkdir -p "$stamps_dir"
  local out="$stamps_dir/$kebab.md"

  if [[ -e "$out" && "$force" != true ]]; then
    echo "error: stamp already exists: $out (use --force to overwrite)" >&2
    return 1
  fi

  # Build YAML arrays
  yaml_array() {
    local csv="$1"
    [[ -z "$csv" ]] && { echo "[]"; return; }
    local IFS=','
    local out="["
    local first=true
    for v in $csv; do
      v="${v# }"; v="${v% }"   # trim
      $first && out+="$v" || out+=", $v"
      first=false
    done
    out+="]"
    echo "$out"
  }

  local envs_yaml runtimes_yaml clouds_yaml tags_yaml
  envs_yaml="$(yaml_array "$environments")"
  runtimes_yaml="$(yaml_array "$used_by_runtimes")"
  clouds_yaml="$(yaml_array "$used_by_clouds")"
  tags_yaml="$(yaml_array "$tags")"

  # `default` is special — null if required, else the literal
  local default_yaml
  if [[ "$required" == "true" ]]; then
    default_yaml="null"
  else
    default_yaml="${default:-null}"
  fi

  local today
  today="$(date '+%Y-%m-%d')"

  cat > "$out" <<EOF
---
name: $kebab
kind: env-var
var_name: $key
group: $group
required: $required
purpose: $purpose
description: $description
type: $type
default: $default_yaml
used_by:
  runtimes: $runtimes_yaml
  clouds: $clouds_yaml
environments: $envs_yaml
created: $today
status: active
tags: $tags_yaml
---

# Env var: $key

$description

EOF

  echo "wrote: $out"
}

# ─── add-profile ───────────────────────────────────────────────────────────
# Append a profile name to an existing stamp's environments[] array.
cmd_add_profile() {
  local key="${1:?usage: add-profile <KEY> <profile>}"
  local profile="${2:?usage: add-profile <KEY> <profile>}"
  local kebab
  kebab="$(echo "$key" | tr '[:upper:]_' '[:lower:]-')"
  local root
  root="$(project_root)"
  local stamp="$root/env/stamps/$kebab.md"

  if [[ ! -f "$stamp" ]]; then
    echo "error: no stamp at $stamp" >&2
    return 1
  fi

  # Read the environments line, check if profile is already there
  local current
  current="$(grep '^environments:' "$stamp" || true)"
  if [[ -z "$current" ]]; then
    echo "error: stamp has no environments line: $stamp" >&2
    return 1
  fi

  if echo "$current" | grep -qE "\\b$profile\\b"; then
    echo "no-op: $profile already in $kebab"
    return 0
  fi

  # Insert profile into the array. Handle both [a, b] and [] cases.
  if echo "$current" | grep -q '\[\]'; then
    # Empty array → [profile]
    sed -i.bak "s/^environments: \[\]/environments: [$profile]/" "$stamp"
  else
    # Non-empty → insert before closing bracket
    sed -i.bak "s/^\(environments: \[.*\)\]/\1, $profile]/" "$stamp"
  fi
  rm -f "$stamp.bak"
  echo "updated: $stamp ($profile added)"
}

# ─── list ──────────────────────────────────────────────────────────────────
cmd_list() {
  local required_only=false
  local group_filter=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --required-only) required_only=true; shift ;;
      --group)         group_filter="$2"; shift 2 ;;
      *)               echo "error: unknown flag $1" >&2; return 2 ;;
    esac
  done

  local root stamps_dir
  root="$(project_root)"
  stamps_dir="$root/env/stamps"
  [[ -d "$stamps_dir" ]] || { echo "no env/stamps/ directory"; return 0; }

  printf "%-32s %-10s %-30s %s\n" "VAR_NAME" "REQUIRED" "GROUP" "PURPOSE"
  printf "%-32s %-10s %-30s %s\n" "--------" "--------" "-----" "-------"

  local f var_name required group purpose
  for f in "$stamps_dir"/*.md; do
    [[ -f "$f" ]] || continue
    var_name="$(awk '/^---$/{f++; next} f==1 && /^var_name:/{sub(/^var_name:[[:space:]]*/, ""); print; exit}' "$f")"
    required="$(awk '/^---$/{f++; next} f==1 && /^required:/{sub(/^required:[[:space:]]*/, ""); print; exit}' "$f")"
    group="$(awk '/^---$/{f++; next} f==1 && /^group:/{sub(/^group:[[:space:]]*/, ""); print; exit}' "$f")"
    purpose="$(awk '/^---$/{f++; next} f==1 && /^purpose:/{sub(/^purpose:[[:space:]]*/, ""); print; exit}' "$f")"

    [[ -z "$var_name" ]] && continue
    [[ "$required_only" == true && "$required" != "true" ]] && continue
    [[ -n "$group_filter" && "$group" != *"$group_filter"* ]] && continue

    printf "%-32s %-10s %-30s %s\n" "$var_name" "$required" "$group" "$purpose"
  done
}

# ─── validate ──────────────────────────────────────────────────────────────
# Coverage check between .env-template and env/stamps/.
cmd_validate() {
  local root template
  root="$(project_root)"
  template="$root/.env-template"

  local fail=0

  if [[ ! -f "$template" ]]; then
    echo "WARNING: no .env-template at project root — skipping template coverage check"
  else
    # Keys in template, not as stamps
    local tmpl_keys stamp_keys missing_stamps missing_template
    tmpl_keys="$(cmd_parse "$template" | sort -u)"
    stamp_keys="$(
      for f in "$root"/env/stamps/*.md; do
        [[ -f "$f" ]] || continue
        awk '/^---$/{f++; next} f==1 && /^var_name:/{sub(/^var_name:[[:space:]]*/, ""); print; exit}' "$f"
      done | sort -u
    )"

    missing_stamps="$(comm -23 <(echo "$tmpl_keys") <(echo "$stamp_keys"))"
    if [[ -n "$missing_stamps" ]]; then
      echo "✗ In .env-template but no stamp:"
      echo "$missing_stamps" | sed 's/^/    /'
      fail=1
    fi

    # Required stamps not in template
    missing_template="$(
      for f in "$root"/env/stamps/*.md; do
        [[ -f "$f" ]] || continue
        local req var
        req="$(awk '/^---$/{f++; next} f==1 && /^required:/{sub(/^required:[[:space:]]*/, ""); print; exit}' "$f")"
        [[ "$req" != "true" ]] && continue
        var="$(awk '/^---$/{f++; next} f==1 && /^var_name:/{sub(/^var_name:[[:space:]]*/, ""); print; exit}' "$f")"
        if ! echo "$tmpl_keys" | grep -qx "$var"; then
          echo "$var"
        fi
      done
    )"
    if [[ -n "$missing_template" ]]; then
      echo "✗ Required stamps not in .env-template:"
      echo "$missing_template" | sed 's/^/    /'
      fail=1
    fi
  fi

  if [[ "$fail" == 0 ]]; then
    echo "✓ env stamps validated cleanly"
    return 0
  else
    return 3
  fi
}

# ─── dispatch ──────────────────────────────────────────────────────────────
cmd="${1:-help}"
shift || true

case "$cmd" in
  parse)         cmd_parse        "$@" ;;
  diff)          cmd_diff         "$@" ;;
  suggest)       cmd_suggest      "$@" ;;
  add)           cmd_add          "$@" ;;
  add-profile)   cmd_add_profile  "$@" ;;
  list)          cmd_list         "$@" ;;
  validate)      cmd_validate     "$@" ;;
  help|-h|--help) usage ;;
  *) echo "error: unknown command '$cmd'" >&2; usage >&2; exit 2 ;;
esac
