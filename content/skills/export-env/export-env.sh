#!/usr/bin/env bash
# export-env.sh — generate .env-template (or filtered variants) from env/stamps/
#
# Inverse of import-env.sh. Reads stamp metadata, emits a .env-template
# with placeholder values grouped by stamp.group, with inline comments
# encoding required/optional + purpose + type + description.
#
# Pure bash. Never reads existing .env* values — placeholders only.
# Output is deterministic: stamps sorted by group, then by var_name.

set -euo pipefail

# ─── Paths ─────────────────────────────────────────────────────────────────
project_root() {
  local d
  d="$(pwd)"
  while [[ "$d" != "/" ]]; do
    if [[ -d "$d/env/stamps" ]] || [[ -d "$d/.claude" ]]; then
      echo "$d"; return 0
    fi
    d="$(dirname "$d")"
  done
  pwd
}

# ─── Stamp field readers (frontmatter only) ────────────────────────────────
stamp_field() {
  local file="$1" field="$2"
  awk -v field="$field" '
    /^---$/ { f++; next }
    f == 1 && $0 ~ "^"field":" {
      sub("^"field":[[:space:]]*", "");
      print; exit
    }
  ' "$file"
}

usage() {
  cat <<'EOF'
export-env.sh — generate .env-template from env/stamps/

USAGE:
  export-env.sh build [opts]
      Generate a template file from stamps. Writes to --output (default
      .env-template at project root).
      Options:
        --profile <name>          only stamps where environments[] contains <name>
        --runtime <name>          only stamps where used_by.runtimes contains <name>
        --cloud <name>            only stamps where used_by.clouds contains <name>
        --group <pattern>         only stamps where group matches (substring)
        --required-only           skip optional vars
        --include-deprecated      include status: deprecated (default: skip)
        --include-retired         include status: retired (default: skip)
        --output <path>           default: .env-template
        --force                   overwrite without prompting
        --stdout                  write to stdout instead of file

  export-env.sh preview [opts]
      Same filters as build, but always writes to stdout. Doesn't touch
      the filesystem.

  export-env.sh diff <env-file> [opts]
      Compare actual <env-file> against what build would generate.
      Reports: missing keys (in template, not file), extra keys (in
      file, not template), required-vs-optional mismatches.

  export-env.sh list-profiles
      List every profile name referenced by any stamp's environments[].

  export-env.sh help
      This message.

EXIT CODES:
  0  success
  1  operational error
  2  usage error
  3  diff drift detected

PLACEHOLDER VALUES (in generated templates):
  required, type=string         → __SET_ME__
  required, purpose=secret      → __SECRET__
  required, type=url            → __URL__
  required, type=int            → 0
  required, type=bool           → false
  required, type=list           → __COMMA_SEPARATED__
  required, type=json           → {}
  optional (with default)       → the stamp's default value
  optional (no default)         → (empty after =)

NEVER reads values from any .env file. Template is pure metadata.
EOF
}

# ─── Map (var_name → placeholder value) based on stamp metadata ────────────
placeholder_for() {
  local required="$1" purpose="$2" type="$3" default_val="$4"

  if [[ "$required" == "false" ]]; then
    if [[ -n "$default_val" && "$default_val" != "null" ]]; then
      echo "$default_val"
    else
      echo ""
    fi
    return
  fi

  # required: true
  case "$purpose" in
    secret)
      echo "__SECRET__"; return
      ;;
  esac
  case "$type" in
    int)    echo "0" ;;
    bool)   echo "false" ;;
    url)    echo "__URL__" ;;
    list)   echo "__COMMA_SEPARATED__" ;;
    json)   echo "{}" ;;
    *)      echo "__SET_ME__" ;;
  esac
}

# ─── Filter predicate — returns 0 if stamp passes filters ──────────────────
# Reads filter vars from caller scope: profile, runtime, cloud, group_filter,
# required_only, include_deprecated, include_retired
stamp_passes() {
  local f="$1"

  local status environments runtimes clouds group required
  status="$(stamp_field "$f" status)"
  environments="$(stamp_field "$f" environments)"
  group="$(stamp_field "$f" group)"
  required="$(stamp_field "$f" required)"
  # used_by.runtimes / clouds are nested — extract from indented lines
  runtimes="$(awk '/^---$/{f++; next} f==1 && /^used_by:/{u=1; next} f==1 && u && /^  runtimes:/{sub(/^  runtimes:[[:space:]]*/, ""); print; exit} f==1 && u && /^[a-zA-Z]/{exit}' "$f")"
  clouds="$(awk   '/^---$/{f++; next} f==1 && /^used_by:/{u=1; next} f==1 && u && /^  clouds:/{sub(/^  clouds:[[:space:]]*/, ""); print; exit}   f==1 && u && /^[a-zA-Z]/{exit}' "$f")"

  # Status filter
  case "$status" in
    deprecated) [[ "$include_deprecated" == true ]] || return 1 ;;
    retired)    [[ "$include_retired" == true ]] || return 1 ;;
  esac

  # Required-only filter
  if [[ "$required_only" == true && "$required" != "true" ]]; then return 1; fi

  # Profile filter — environments is a YAML array string like "[local, staging, production]"
  if [[ -n "$profile" ]]; then
    if ! echo "$environments" | grep -qE "\\b$profile\\b"; then return 1; fi
  fi

  # Runtime filter
  if [[ -n "$runtime" ]]; then
    if ! echo "$runtimes" | grep -qE "\\b$runtime\\b"; then return 1; fi
  fi

  # Cloud filter
  if [[ -n "$cloud" ]]; then
    if ! echo "$clouds" | grep -qE "\\b$cloud\\b"; then return 1; fi
  fi

  # Group filter
  if [[ -n "$group_filter" ]]; then
    if [[ "$group" != *"$group_filter"* ]]; then return 1; fi
  fi

  return 0
}

# ─── build / preview ───────────────────────────────────────────────────────
cmd_build() {
  # Defaults
  local profile="" runtime="" cloud="" group_filter=""
  local required_only=false include_deprecated=false include_retired=false
  local output="" force=false to_stdout=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)             profile="$2"; shift 2 ;;
      --runtime)             runtime="$2"; shift 2 ;;
      --cloud)               cloud="$2"; shift 2 ;;
      --group)               group_filter="$2"; shift 2 ;;
      --required-only)       required_only=true; shift ;;
      --include-deprecated)  include_deprecated=true; shift ;;
      --include-retired)     include_retired=true; shift ;;
      --output)              output="$2"; shift 2 ;;
      --force)               force=true; shift ;;
      --stdout)              to_stdout=true; shift ;;
      *) echo "error: unknown flag $1" >&2; return 2 ;;
    esac
  done

  local root stamps_dir
  root="$(project_root)"
  stamps_dir="$root/env/stamps"

  if [[ ! -d "$stamps_dir" ]]; then
    echo "error: no env/stamps/ directory at $root" >&2
    return 1
  fi

  # Default output path
  if [[ -z "$output" && "$to_stdout" != true ]]; then
    output="$root/.env-template"
  fi

  # Confirm overwrite if not --force or --stdout
  if [[ "$to_stdout" != true && -e "$output" && "$force" != true ]]; then
    echo "error: $output exists. Re-run with --force to overwrite, --stdout to print, or pick a different --output." >&2
    return 1
  fi

  # Collect passing stamps with sort key: group||var_name
  local lines=""
  local f
  for f in "$stamps_dir"/*.md; do
    [[ -f "$f" ]] || continue
    if stamp_passes "$f"; then
      local group var_name
      group="$(stamp_field "$f" group)"
      var_name="$(stamp_field "$f" var_name)"
      lines+="${group}|${var_name}|${f}"$'\n'
    fi
  done

  # Build template body via a tmp file (so we can write atomically)
  local tmp
  tmp="$(mktemp)"
  trap "rm -f '$tmp'" EXIT

  # Header
  cat > "$tmp" <<EOF
# .env-template — generated from env/stamps/ by export-env.sh
#
# Regenerate: /export-env  OR  ./kit/skills/export-env/export-env.sh build
# Values shown are placeholders. Copy this file to .env (or
# .env.<profile>) and replace placeholders with real values. Real
# values must never appear in committed files.
#
# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
EOF
  [[ -n "$profile"      ]] && echo "# Filter: profile=$profile"          >> "$tmp"
  [[ -n "$runtime"      ]] && echo "# Filter: runtime=$runtime"          >> "$tmp"
  [[ -n "$cloud"        ]] && echo "# Filter: cloud=$cloud"              >> "$tmp"
  [[ -n "$group_filter" ]] && echo "# Filter: group~=$group_filter"      >> "$tmp"
  [[ "$required_only"      == true ]] && echo "# Filter: required-only"      >> "$tmp"
  [[ "$include_deprecated" == true ]] && echo "# Filter: include-deprecated" >> "$tmp"
  [[ "$include_retired"    == true ]] && echo "# Filter: include-retired"    >> "$tmp"

  if [[ -z "$lines" ]]; then
    echo "" >> "$tmp"
    echo "# (no stamps match the current filters)" >> "$tmp"
  else
    # Sort by group, then var_name
    local sorted current_group=""
    sorted="$(echo "$lines" | sort -t '|' -k1,1 -k2,2)"

    while IFS='|' read -r group var_name file; do
      [[ -z "$group" ]] && continue

      # Group header break
      if [[ "$group" != "$current_group" ]]; then
        echo "" >> "$tmp"
        echo "# ─── $group ──────────────────────────────────────────────" >> "$tmp"
        current_group="$group"
      fi

      local required purpose type default_val description
      required="$(stamp_field   "$file" required)"
      purpose="$(stamp_field    "$file" purpose)"
      type="$(stamp_field       "$file" type)"
      default_val="$(stamp_field "$file" default)"
      description="$(stamp_field "$file" description)"

      local placeholder
      placeholder="$(placeholder_for "$required" "$purpose" "$type" "$default_val")"

      # Build inline comment: required/optional, purpose, type, description
      local meta
      if [[ "$required" == "true" ]]; then
        meta="required, $purpose, $type"
      else
        if [[ -n "$default_val" && "$default_val" != "null" ]]; then
          meta="optional, $purpose, $type, default=$default_val"
        else
          meta="optional, $purpose, $type"
        fi
      fi

      [[ -n "$description" ]] && meta="$meta — $description"

      printf "%s=%s    # %s\n" "$var_name" "$placeholder" "$meta" >> "$tmp"
    done <<< "$sorted"
  fi

  # Emit
  if [[ "$to_stdout" == true ]]; then
    cat "$tmp"
  else
    mv "$tmp" "$output"
    trap - EXIT
    echo "wrote: $output"
    local count
    count="$(grep -cE '^[A-Z_][A-Z0-9_]*=' "$output" || true)"
    echo "       ($count vars)"
  fi
}

cmd_preview() {
  cmd_build "$@" --stdout
}

# ─── diff — compare actual .env* file against stamps ───────────────────────
cmd_diff() {
  local file="${1:?usage: diff <env-file> [filters]}"
  shift || true

  if [[ ! -f "$file" ]]; then
    echo "error: file not found: $file" >&2
    return 1
  fi

  # Parse keys from the file (reuse import-env.sh's parse if available)
  local import_script
  import_script="$(dirname "${BASH_SOURCE[0]}")/../import-env/import-env.sh"
  if [[ -x "$import_script" ]]; then
    local file_keys
    file_keys="$("$import_script" parse "$file" | sort -u)"
  else
    # Inline fallback
    local file_keys=""
    local line key
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "${line// }" ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)= ]]; then
        file_keys+="${BASH_REMATCH[2]}"$'\n'
      fi
    done < "$file"
    file_keys="$(echo "$file_keys" | sort -u)"
  fi

  # Generate what the template would have (same filters)
  local profile="" runtime="" cloud="" group_filter=""
  local required_only=false include_deprecated=false include_retired=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile)             profile="$2"; shift 2 ;;
      --runtime)             runtime="$2"; shift 2 ;;
      --cloud)               cloud="$2"; shift 2 ;;
      --group)               group_filter="$2"; shift 2 ;;
      --required-only)       required_only=true; shift ;;
      --include-deprecated)  include_deprecated=true; shift ;;
      --include-retired)     include_retired=true; shift ;;
      *) echo "error: unknown flag $1" >&2; return 2 ;;
    esac
  done

  local root stamps_dir
  root="$(project_root)"
  stamps_dir="$root/env/stamps"

  local stamp_keys=""
  local required_keys=""
  local f
  for f in "$stamps_dir"/*.md; do
    [[ -f "$f" ]] || continue
    if stamp_passes "$f"; then
      local var_name required
      var_name="$(stamp_field "$f" var_name)"
      required="$(stamp_field "$f" required)"
      stamp_keys+="$var_name"$'\n'
      [[ "$required" == "true" ]] && required_keys+="$var_name"$'\n'
    fi
  done
  stamp_keys="$(echo "$stamp_keys" | sort -u | grep -v '^$' || true)"
  required_keys="$(echo "$required_keys" | sort -u | grep -v '^$' || true)"

  local missing extra missing_required
  missing="$(comm -23 <(echo "$stamp_keys") <(echo "$file_keys"))"
  extra="$(comm -13 <(echo "$stamp_keys") <(echo "$file_keys"))"
  missing_required="$(comm -23 <(echo "$required_keys") <(echo "$file_keys"))"

  local drift=0

  if [[ -n "$missing_required" ]]; then
    echo "✗ Required vars missing from $file:"
    echo "$missing_required" | sed 's/^/    /'
    drift=1
  fi

  if [[ -n "$missing" && -z "$missing_required" ]]; then
    echo "⚠ Stamps not present in $file (may be optional or this profile doesn't need them):"
    echo "$missing" | sed 's/^/    /'
  elif [[ -n "$missing" && -n "$missing_required" ]]; then
    local optional_missing
    optional_missing="$(comm -23 <(echo "$missing") <(echo "$missing_required"))"
    if [[ -n "$optional_missing" ]]; then
      echo ""
      echo "⚠ Optional stamps not in $file:"
      echo "$optional_missing" | sed 's/^/    /'
    fi
  fi

  if [[ -n "$extra" ]]; then
    echo ""
    echo "⚠ In $file but no stamp:"
    echo "$extra" | sed 's/^/    /'
    echo "    (run /import-env to register these)"
  fi

  if [[ "$drift" == 0 ]]; then
    [[ -z "$missing" && -z "$extra" ]] && echo "✓ $file matches stamps cleanly"
  fi

  return "$drift"
}

# ─── list-profiles ─────────────────────────────────────────────────────────
cmd_list_profiles() {
  local root stamps_dir
  root="$(project_root)"
  stamps_dir="$root/env/stamps"
  [[ -d "$stamps_dir" ]] || { echo "no env/stamps/"; return 0; }

  local all_profiles=""
  local f
  for f in "$stamps_dir"/*.md; do
    [[ -f "$f" ]] || continue
    local environments
    environments="$(stamp_field "$f" environments)"
    # Strip brackets, split on commas, trim whitespace
    environments="${environments#[}"
    environments="${environments%]}"
    local IFS=','
    for p in $environments; do
      p="${p# }"; p="${p% }"
      [[ -n "$p" ]] && all_profiles+="$p"$'\n'
    done
  done

  echo "Profiles referenced across all stamps:"
  echo "$all_profiles" | sort -u | grep -v '^$' | sed 's/^/  /' || true
}

# ─── dispatch ──────────────────────────────────────────────────────────────
cmd="${1:-help}"
shift || true

case "$cmd" in
  build)         cmd_build         "$@" ;;
  preview)       cmd_preview       "$@" ;;
  diff)          cmd_diff          "$@" ;;
  list-profiles) cmd_list_profiles "$@" ;;
  help|-h|--help) usage ;;
  *) echo "error: unknown command '$cmd'" >&2; usage >&2; exit 2 ;;
esac
