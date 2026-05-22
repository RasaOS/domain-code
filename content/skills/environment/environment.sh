#!/usr/bin/env bash
# environment.sh — read and manage the project's environment registry.
#
# The registry (.claude/environments.json) is the single source of truth
# for this project's environments. This script reads it, tracks the
# current working environment (a machine-local pointer, shared across
# the project's worktrees), and builds the canonical version string
# v<semver>-<shortsha>-<env>.
#
# Language note: uses python3 to parse environments.json. JSON parsing
# in pure bash is not worth the fragility; python3 ships everywhere and
# the kit already depends on it (bin/init, runtime.sh).

set -euo pipefail

usage() {
  cat <<'EOF'
environment.sh — environment registry, current-env pointer, version string

USAGE:
  environment.sh list
      List environments declared in .claude/environments.json,
      marking the current working environment.

  environment.sh show <env>
      Print one environment's full configuration.

  environment.sh get <env> <field>
      Print one field's raw value for one environment — machine-readable,
      for stage scripts. Fields: description, env_file, publish_to,
      deploy_to. Empty output when the field is unset.

  environment.sh current
      Print the current working environment name. Falls back to the
      registry's `default` when no pointer has been set.

  environment.sh use <env>
      Set the current working environment. Writes a machine-local
      pointer (~/.claude/projects/<key>/current-env), shared across
      this project's worktrees. Never committed to the repo.

  environment.sh version [<env>] [--semver <vX.Y.Z>]
      Print the canonical build stamp: v<semver>-<shortsha>-<env>.
      <env> defaults to the current working environment.
      --semver sets the version explicitly (used by /release). Without
      it, the semver is the nearest reachable release tag, or v0.0.0
      before the first release.

  environment.sh validate
      Check that every environment name used by runtime stamps, cloud
      stamps, env-var stamps, and build/pipeline-config.toml is a key
      in the registry. Exit 3 on drift.

EXIT CODES:
  0  success
  1  operational error (registry missing, not a git repo, no PyYAML)
  2  usage error (unknown environment, bad flag)
  3  refused, or `validate` found environment-name drift
EOF
}

# Current worktree root — for locating .claude/environments.json.
repo_root() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "error: not inside a git repo" >&2
    return 1
  }
  ( cd -P "$top" 2>/dev/null && pwd -P )
}

# Project key for ~/.claude/projects/<key>/ — derived from the *main*
# repo root via --git-common-dir, so all worktrees of one project share
# a single current-env pointer. Mirrors save.sh.
project_key() {
  local common_dir abs_common root
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || {
    echo "error: not inside a git repo" >&2
    return 1
  }
  abs_common="$(cd -P "$common_dir" 2>/dev/null && pwd -P)" || return 1
  root="$(dirname "$abs_common")"
  echo "${root//\//-}"
}

registry_path() {
  local root
  root="$(repo_root)" || return 1
  local f="$root/.claude/environments.json"
  if [ ! -f "$f" ]; then
    echo "error: no .claude/environments.json — run bin/init, or create the registry" >&2
    return 1
  fi
  echo "$f"
}

pointer_path() {
  local key
  key="$(project_key)" || return 1
  echo "$HOME/.claude/projects/$key/current-env"
}

# JSON operations on the registry.  _registry_py <registry-file> <op> [args...]
_registry_py() {
  python3 - "$@" <<'PY'
import json, sys

reg_path = sys.argv[1]
op = sys.argv[2]
args = sys.argv[3:]

try:
    reg = json.load(open(reg_path))
except (OSError, ValueError) as exc:
    print("error: cannot read %s: %s" % (reg_path, exc), file=sys.stderr)
    sys.exit(1)

envs = reg.get("environments", {})
if not isinstance(envs, dict):
    print("error: environments.json: 'environments' must be an object", file=sys.stderr)
    sys.exit(1)
default = reg.get("default", "")

if op == "names":
    for k in envs:
        print(k)
elif op == "default":
    print(default)
elif op == "has":
    sys.exit(0 if args[0] in envs else 1)
elif op == "field":
    env = envs.get(args[0])
    if env is None:
        print("error: unknown environment '%s'" % args[0], file=sys.stderr)
        sys.exit(2)
    val = env.get(args[1])
    print("" if val is None else val)
elif op == "list":
    current = args[0] if args else ""
    if not envs:
        print("(no environments declared in .claude/environments.json)")
        sys.exit(0)
    print("environments:")
    for k, e in envs.items():
        mark = "→" if k == current else " "
        print("  %s %-9s %s" % (mark, k, (e or {}).get("description", "")))
    print()
    print("current: %s" % (current or "(unset)"))
elif op == "show":
    env = envs.get(args[0])
    if env is None:
        print("error: unknown environment '%s'" % args[0], file=sys.stderr)
        sys.exit(2)
    print("environment: %s" % args[0])
    for f in ("description", "env_file", "publish_to", "deploy_to"):
        val = env.get(f)
        if val is None:
            val = "(none)"
        elif isinstance(val, bool):
            val = "true" if val else "false"
        print("  %-18s %s" % (f, val))
else:
    print("error: internal: unknown op '%s'" % op, file=sys.stderr)
    sys.exit(1)
PY
}

# Effective current environment: the pointer if set and valid, else the
# registry default. A stale pointer warns (stderr) and falls back.
resolve_current() {
  local reg="$1" ptr val default
  ptr="$(pointer_path)" || return 1
  default="$(_registry_py "$reg" default)"
  if [ -f "$ptr" ]; then
    val="$(tr -d '[:space:]' < "$ptr")"
    if [ -n "$val" ]; then
      if _registry_py "$reg" has "$val"; then
        echo "$val"
        return 0
      fi
      echo "warning: current-env pointer holds '$val', not in the registry; using default '$default'" >&2
    fi
  fi
  echo "$default"
}

cmd_get() {
  local reg="$1" env="$2" field="$3"
  if ! _registry_py "$reg" has "$env"; then
    echo "error: '$env' is not a declared environment" >&2
    return 2
  fi
  _registry_py "$reg" field "$env" "$field"
}

cmd_use() {
  local reg="$1" env="$2" ptr
  if ! _registry_py "$reg" has "$env"; then
    echo "error: '$env' is not a declared environment" >&2
    echo "       declared: $(_registry_py "$reg" names | paste -sd' ' -)" >&2
    return 2
  fi
  ptr="$(pointer_path)" || return 1
  mkdir -p "$(dirname "$ptr")"
  printf '%s\n' "$env" > "$ptr"
  echo "current environment → $env"
}

cmd_version() {
  local reg="$1"
  shift
  local env="" semver=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --semver)
        semver="${2:-}"
        shift 2 || { echo "error: --semver needs a value" >&2; return 2; }
        ;;
      --semver=*)
        semver="${1#--semver=}"
        shift
        ;;
      -*)
        echo "error: unknown flag: $1" >&2
        return 2
        ;;
      *)
        if [ -z "$env" ]; then
          env="$1"
          shift
        else
          echo "error: unexpected argument: $1" >&2
          return 2
        fi
        ;;
    esac
  done

  [ -n "$env" ] || env="$(resolve_current "$reg")"
  if ! _registry_py "$reg" has "$env"; then
    echo "error: '$env' is not a declared environment" >&2
    return 2
  fi

  if [ -z "$semver" ]; then
    semver="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
    semver="${semver%%-*}"
    [ -n "$semver" ] || semver="v0.0.0"
  fi
  case "$semver" in
    v*) ;;
    *)  semver="v$semver" ;;
  esac

  local sha
  sha="$(git rev-parse --short HEAD 2>/dev/null || echo 0000000)"

  printf '%s-%s-%s\n' "$semver" "$sha" "$env"
}

# Cross-check environment names used across the project against the
# registry. Uses python3 + PyYAML (stamp frontmatter) and tomllib.
_validate_py() {
  python3 - "$@" <<'PY'
import json, os, re, sys

try:
    import yaml
except ImportError:
    print("error: validate requires PyYAML — install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)
try:
    import tomllib
except ImportError:
    tomllib = None

root, reg_path = sys.argv[1], sys.argv[2]

try:
    reg = json.load(open(reg_path))
except (OSError, ValueError) as exc:
    print("error: cannot read %s: %s" % (reg_path, exc), file=sys.stderr)
    sys.exit(1)
valid = set((reg.get("environments") or {}).keys())

FRONT = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


def frontmatter(path):
    try:
        with open(path) as fh:
            m = FRONT.match(fh.read())
    except OSError:
        return None
    if not m:
        return None
    try:
        return yaml.safe_load(m.group(1)) or {}
    except yaml.YAMLError:
        return None


def md_files(subdir):
    d = os.path.join(root, subdir)
    if not os.path.isdir(d):
        return []
    out = []
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".md"):
            continue
        base = fn[:-3]
        if base.startswith("_template") or base == "README":
            continue
        out.append(os.path.join(d, fn))
    return out


findings = []  # (relpath, sorted names, sorted bad names)


def record(relpath, names):
    names = sorted(set(str(n) for n in names if n))
    bad = sorted(n for n in names if n not in valid)
    findings.append((relpath, names, bad))


for path in md_files(".claude/runtimes"):
    stamp = frontmatter(path)
    if stamp is None:
        continue
    envs = (stamp.get("env") or {}).get("environments") or {}
    if isinstance(envs, dict):
        record(os.path.relpath(path, root), envs.keys())

for subdir in (".claude/clouds", "env/stamps"):
    for path in md_files(subdir):
        stamp = frontmatter(path)
        if stamp is None:
            continue
        envs = stamp.get("environments") or []
        if isinstance(envs, list):
            record(os.path.relpath(path, root), envs)

pc = os.path.join(root, "build/pipeline-config.toml")
if os.path.isfile(pc) and tomllib is not None:
    try:
        with open(pc, "rb") as fh:
            cfg = tomllib.load(fh)
        lst = (cfg.get("environments") or {}).get("list") or []
        if isinstance(lst, list):
            record("build/pipeline-config.toml", lst)
    except Exception:
        pass

print("environment validate")
print()
print("registry: %s" % (", ".join(sorted(valid)) or "(empty)"))
print()

if not findings:
    print("  nothing to check — no runtime/cloud/env-var stamps or")
    print("  pipeline config in this project yet")
    print()
    print("VERDICT: OK")
    sys.exit(0)

drift = 0
for relpath, names, bad in findings:
    if bad:
        drift += len(bad)
        print("  DRIFT  %-36s %s   (not in the registry)" % (relpath, ", ".join(bad)))
    else:
        print("  ok     %-36s %s" % (relpath, ", ".join(names) or "(none)"))
print()

if drift:
    print("VERDICT: DRIFT — %d environment name(s) not in .claude/environments.json" % drift)
    print("  fix: add the environment to the registry, or correct the stamp.")
    sys.exit(3)
print("VERDICT: OK — every environment name is a registry key")
sys.exit(0)
PY
}

cmd_validate() {
  local reg="$1" root
  root="$(repo_root)" || return 1
  python3 -c 'import yaml' 2>/dev/null || {
    echo "error: validate requires PyYAML — install with: pip install pyyaml" >&2
    return 1
  }
  _validate_py "$root" "$reg"
}

main() {
  local action="${1:-}"
  shift || true

  case "$action" in
    -h|--help|help|"") usage; return 0 ;;
  esac

  command -v python3 >/dev/null 2>&1 || {
    echo "error: environment.sh requires python3" >&2
    return 1
  }

  local reg
  reg="$(registry_path)" || return 1

  case "$action" in
    list)
      _registry_py "$reg" list "$(resolve_current "$reg")"
      ;;
    show)
      [ $# -ge 1 ] || { echo "error: show needs <env>" >&2; return 2; }
      _registry_py "$reg" show "$1"
      ;;
    get)
      [ $# -ge 2 ] || { echo "error: get needs <env> and <field>" >&2; return 2; }
      cmd_get "$reg" "$1" "$2"
      ;;
    current)
      resolve_current "$reg"
      ;;
    use)
      [ $# -ge 1 ] || { echo "error: use needs <env>" >&2; return 2; }
      cmd_use "$reg" "$1"
      ;;
    version)
      cmd_version "$reg" "$@"
      ;;
    validate)
      cmd_validate "$reg"
      ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
