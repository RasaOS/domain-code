#!/usr/bin/env bash
# runtime.sh — preflight + env management for .claude/runtimes/<name>.md
#
# Reads runtime stamps, validates env vars are set, runs depends_on
# check commands, reports the same diagnostic format as the
# /audit pattern.
#
# Language note: uses python3 + PyYAML. PyYAML is the only realistic
# YAML parser in Python — stdlib doesn't ship one. Script fails with
# a clear install hint if pyyaml is missing.

set -euo pipefail

usage() {
  cat <<'EOF'
runtime.sh — preflight + env validation for .claude/runtimes/<name>.md

USAGE:
  runtime.sh list
      List runtimes in .claude/runtimes/ (skipping _template-*).

  runtime.sh show <name>
      Print the full runtime file (stamp + body).

  runtime.sh check <name> [--env <profile>]
      Validate env vars + dependencies. Exit 0 if ready, 3 if not.
      --env defaults to env.file from the stamp (typically ".env").

  runtime.sh env <name> [--env <profile>]
      Print env coverage only — which required/optional vars are
      set or missing. Doesn't run dep checks.

  runtime.sh preflight <name> [--env <profile>]
      Alias for `check` with a "ready to run with: <command>"
      verdict line.

EXIT CODES:
  0  success / ready
  1  operational error (file not found, missing python/pyyaml)
  2  usage error
  3  not ready (missing env vars or unreachable deps)
EOF
}

# Resolve worktree root.
project_root() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "error: not inside a git repo" >&2
    return 1
  }
  ( cd -P "$top" 2>/dev/null && pwd -P )
}

require_python3_yaml() {
  command -v python3 >/dev/null 2>&1 || {
    echo "error: runtime.sh requires python3" >&2
    return 1
  }
  python3 -c 'import yaml' 2>/dev/null || {
    echo "error: runtime.sh requires PyYAML — install with: pip install pyyaml" >&2
    return 1
  }
}

# Resolve runtime <name> → file path.
runtime_file() {
  local name="$1"
  local root
  root="$(project_root)" || return 1
  local candidates=(
    "$root/.claude/runtimes/${name}.md"
    "$root/.claude/runtimes/${name}"
  )
  local c
  for c in "${candidates[@]}"; do
    if [ -f "$c" ]; then
      echo "$c"
      return 0
    fi
  done
  echo "error: runtime '$name' not found in .claude/runtimes/" >&2
  return 1
}

cmd_list() {
  local root
  root="$(project_root)" || return 1
  local dir="$root/.claude/runtimes"

  if [ ! -d "$dir" ]; then
    echo "no .claude/runtimes/ directory in this project."
    return 0
  fi

  local found=0 f
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    local base
    base="$(basename "$f" .md)"
    case "$base" in
      _template-*|README) continue ;;
    esac
    found=1
    echo "$base"
  done

  if [ "$found" -eq 0 ]; then
    echo "(no runtimes declared yet — copy a _template-*.md and rename)"
  fi
}

cmd_show() {
  local name="$1"
  local file
  file="$(runtime_file "$name")" || return 1
  cat "$file"
}

# Core check logic — env validation + dep checks. Output format
# matches the audit/status pattern: clean, scannable, severity-tagged.
_run_check() {
  local file="$1" profile="$2" mode="$3"   # mode: full | env-only
  local root
  root="$(project_root)" || return 1

  python3 - "$file" "$profile" "$root" "$mode" <<'PY'
import sys, os, subprocess, re

try:
    import yaml
except ImportError:
    print("error: requires PyYAML — install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

file_path, profile, repo_root, mode = sys.argv[1:5]

# Parse frontmatter from the .md file.
with open(file_path) as f:
    content = f.read()

m = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
if not m:
    print(f"error: no YAML frontmatter found in {file_path}", file=sys.stderr)
    sys.exit(1)

try:
    stamp = yaml.safe_load(m.group(1)) or {}
except yaml.YAMLError as e:
    print(f"error: invalid YAML in {file_path}: {e}", file=sys.stderr)
    sys.exit(1)

# Resolve env file from profile.
env_block = stamp.get("env") or {}
if profile:
    environments = env_block.get("environments") or {}
    env_file = environments.get(profile)
    if not env_file:
        decls = ", ".join(environments.keys()) or "(none declared)"
        print(f"error: profile '{profile}' not declared in env.environments.", file=sys.stderr)
        print(f"       declared profiles: {decls}", file=sys.stderr)
        sys.exit(2)
    profile_label = profile
else:
    env_file = env_block.get("file", ".env")
    profile_label = "default"

env_file_path = os.path.join(repo_root, env_file)

# Load env file (simple KEY=VALUE parser).
loaded_env = {}
env_file_exists = os.path.isfile(env_file_path)
if env_file_exists:
    with open(env_file_path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, _, v = line.partition("=")
                # Strip surrounding quotes if present.
                v = v.strip()
                if (v.startswith('"') and v.endswith('"')) or \
                   (v.startswith("'") and v.endswith("'")):
                    v = v[1:-1]
                loaded_env[k.strip()] = v

def field(key, default=None):
    return stamp.get(key, default)

# Header.
name = field("name", "(unnamed)")
kind = field("kind", "?")
language = field("language", "?")
print(f"runtime: {name} ({kind}, {language})")
if env_file_exists:
    print(f"env file: {env_file} (loaded)")
else:
    print(f"env file: {env_file} (NOT FOUND)")
print(f"profile:  {profile_label}")
print()

# === env vars ===
required = env_block.get("required") or []
optional = env_block.get("optional") or {}

env_failures = 0
print("env vars:")
if not required and not optional:
    print("  (none declared)")
else:
    for var in required:
        # Stamp itself can hold the var in env.optional with a default,
        # but `required` always overrides — if it's required, it must be set.
        val = loaded_env.get(var) or os.environ.get(var, "")
        if val:
            preview = val if len(val) <= 28 else val[:25] + "..."
            print(f"  ✓ {var:<32} set ({preview})")
        else:
            print(f"  ✗ {var:<32} NOT SET (required)")
            env_failures += 1
    if isinstance(optional, dict):
        for var, default in optional.items():
            val = loaded_env.get(var) or os.environ.get(var, "")
            if val:
                print(f"  ✓ {var:<32} set ({val})")
            else:
                print(f"  · {var:<32} not set (optional, default: {default!r})")

# Stop here for env-only mode.
if mode == "env-only":
    print()
    if env_failures > 0:
        print(f"env coverage: {env_failures} required var(s) missing")
        sys.exit(3)
    else:
        print("env coverage: all required vars set")
        sys.exit(0)

print()

# === dependencies ===
deps = stamp.get("depends_on") or []
dep_failures = 0
print("dependencies:")
if not deps:
    print("  (none declared)")
else:
    for dep in deps:
        if isinstance(dep, dict):
            dname = dep.get("name", "?")
            check = dep.get("check", "")
        elif isinstance(dep, str):
            dname = dep
            check = ""
        else:
            continue

        if not check:
            print(f"  ? {dname:<32} no check command in stamp")
            continue

        try:
            res = subprocess.run(
                check, shell=True, capture_output=True,
                timeout=10, text=True,
            )
            if res.returncode == 0:
                out = (res.stdout.strip().splitlines() or [""])[0][:60]
                if out:
                    print(f"  ✓ {dname:<32} reachable")
                    print(f"    └─ {out}")
                else:
                    print(f"  ✓ {dname:<32} reachable")
            else:
                err = (
                    res.stderr.strip().splitlines()
                    or res.stdout.strip().splitlines()
                    or ["check failed"]
                )[0][:60]
                print(f"  ✗ {dname:<32} UNREACHABLE")
                print(f"    └─ {check}")
                print(f"       {err}")
                dep_failures += 1
        except subprocess.TimeoutExpired:
            print(f"  ✗ {dname:<32} TIMEOUT (>10s)")
            print(f"    └─ {check}")
            dep_failures += 1
        except Exception as e:
            print(f"  ? {dname:<32} check error: {e}")

print()

# === verdict ===
if env_failures == 0 and dep_failures == 0:
    print("VERDICT: READY")
    dev_cmd = ((field("commands") or {}).get("dev", "")) or ""
    if dev_cmd:
        print(f"  start with: {dev_cmd}")
    sys.exit(0)
else:
    print("VERDICT: NOT READY")
    if env_failures > 0:
        plural = "s" if env_failures != 1 else ""
        print(f"  - {env_failures} required env var{plural} missing")
    if dep_failures > 0:
        plural = "ies" if dep_failures != 1 else "y"
        print(f"  - {dep_failures} dependenc{plural} unreachable")
    sys.exit(3)
PY
}

# Argument parsing for check / env / preflight.
parse_check_flags() {
  _POS_ARGS=()
  _PROFILE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --env)
        _PROFILE="${2:-}"
        shift 2 || { echo "error: --env needs a value" >&2; return 2; }
        ;;
      --env=*)
        _PROFILE="${1#--env=}"
        shift
        ;;
      *)
        _POS_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

cmd_check() {
  parse_check_flags "$@"
  [ "${#_POS_ARGS[@]}" -ge 1 ] || {
    echo "error: check needs <name>" >&2
    return 2
  }
  local file
  file="$(runtime_file "${_POS_ARGS[0]}")" || return 1
  _run_check "$file" "$_PROFILE" "full"
}

cmd_env() {
  parse_check_flags "$@"
  [ "${#_POS_ARGS[@]}" -ge 1 ] || {
    echo "error: env needs <name>" >&2
    return 2
  }
  local file
  file="$(runtime_file "${_POS_ARGS[0]}")" || return 1
  _run_check "$file" "$_PROFILE" "env-only"
}

main() {
  local action="${1:-}"
  shift || true

  case "$action" in
    -h|--help|help|"") usage; return 0 ;;
  esac

  case "$action" in
    list)      cmd_list ;;
    show)
      [ $# -ge 1 ] || { echo "error: show needs <name>" >&2; return 2; }
      cmd_show "$1"
      ;;
    check|preflight)
      require_python3_yaml || return 1
      cmd_check "$@"
      ;;
    env)
      require_python3_yaml || return 1
      cmd_env "$@"
      ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
