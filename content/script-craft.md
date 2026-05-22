# Script Craft

How we create, update, and run scripts in the kit. Read this file
before writing any script — whether it ships inside a skill folder
(`kit/skills/<name>/<name>.sh`), inside `bin/`, or anywhere else.

Sits alongside `task-rules.md` (process) and `craft-rules.md` (code
quality). This file is specifically about **scripts as a way to lock
down the mechanics of an operation** so the AI doesn't re-interpret
plumbing on every invocation.

> **Why this file exists.** A skill that the AI re-interprets every
> time will drift. The mechanics — where files go, what order, what
> archive policy, what exit codes — are exactly the kind of thing
> that should be *deterministic*, not *re-derived*. Scripts make
> the mechanics binding. The AI's job becomes synthesis and routing;
> the script's job becomes plumbing. Same outcome every run.

## The split

- **Script owns:** state mutations, file plumbing, archive policy,
  timestamps, format generation, validation, anything with a
  deterministic right answer.
- **AI owns:** synthesis, judgment, prose, anything requiring
  reasoning about content.
- **AI routes:** when the script needs a choice (e.g. "archive or
  replace?"), the AI asks the user in chat and passes the chosen
  flag to the script. The script never prompts interactively.

Canonical example: `kit/skills/save/save.sh` + `kit/skills/save/SKILL.md`.
Script handles SAVED.md/TIMELINE.md plumbing; AI synthesizes the
snapshot content; the SKILL.md routes the archive-mode decision.

## CREATE

### When to write a script

- The skill performs **deterministic mechanics** — file moves,
  archive policy, timestamp-driven naming, format generation,
  validation that has a right answer.
- The same plumbing runs **every invocation** — if you'd otherwise
  paste a paragraph of "AI, do this every time," it's a script.
- The mechanics have a **public interface** — distinct subcommands
  or flags that callers reason about.

### When NOT to write a script

- The skill is pure **synthesis or judgment** — `/brainstorm`,
  `/decision`, `/regret`, `/plan`. A script can't replace AI
  reasoning, and pretending otherwise produces fragile templates.
- The operation is **one-off** — a script that runs once and gets
  deleted is just a comment with extra steps.

### Where it lives

- **Inside a skill folder** if the script is the mechanics of one
  skill: `kit/skills/<name>/<name>.sh`. After `/sync`, it lands at
  `.claude/skills/<name>/<name>.sh` in projects.
- **In `bin/`** if it's a kit operator tool (e.g. `bin/init`,
  `bin/lint`). These are not synced to projects — they're for
  operating the kit itself.

### Naming

- **Filename matches the skill name.** `save.sh` for `/save`,
  `audit.sh` for `/audit`. Kebab-case if multi-word. No
  underscores.
- **Use subcommands, not flag-soup.** `save.sh write <file>` beats
  `save.sh --action=write --file=<file>`. Subcommands are verbs;
  flags modify them.

### Language

- **Bash by default.** Universal, no install needed, fits the
  shell-ops nature of most plumbing.
- **Python only when bash is genuinely clumsy** — JSON-heavy
  transforms, complex date math, non-trivial parsing. Document the
  language choice in a header comment.
- **Other languages need a real reason.** Adding Node/Deno/Go is a
  dependency tax on every project that pulls the script. Justify it.

### Skeleton

Every bash script in the kit follows this shape (lifted from
`save.sh`, which is the working reference):

```bash
#!/usr/bin/env bash
# <name>.sh — <one-line purpose>
#
# <2-3 lines: what plumbing this handles vs. what the AI handles.>

set -euo pipefail

usage() {
  cat <<'EOF'
<name>.sh — <one-line purpose>

USAGE:
  <name>.sh <subcommand> [options]

SUBCOMMANDS:
  status              <one-line description>
  <other>             <one-line description>

EXIT CODES:
  0  success
  1  operational error
  2  usage error
  3  refused
EOF
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    echo "error: not inside a git repo" >&2
    return 1
  }
}

# ... subcommand handlers ...

main() {
  local action="${1:-}"
  shift || true

  case "$action" in
    -h|--help|help|"") usage; return 0 ;;
  esac

  local root
  root="$(repo_root)" || return 1

  case "$action" in
    status)  cmd_status ;;
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
```

### Mandatory practices

- **Shebang `#!/usr/bin/env bash`.** Portable across macOS and Linux.
- **`set -euo pipefail`.** Strict mode. Fail loud on errors, undefined
  variables, and broken pipes. No silent failures.
- **Repo root via `git rev-parse --show-toplevel`.** Works inside
  worktrees, robust to caller's `pwd`. Never `pwd`-relative.
- **Helper functions, not inline globs.** A 200-line script with no
  functions is a maintenance hazard.

## UPDATE

### What counts as the public interface

The contract callers (SKILL.md, bin/init, user typing in shell)
depend on:

- **Subcommand names** — `write`, `status`, `archive`
- **Flag names and values** — `--mode auto|archive|replace`
- **Exit codes** — `0` success, `1` operational, `2` usage, `3` refused
- **Output format** — what goes to stdout, what to stderr

Anything in that list is the public interface. Renaming, removing,
or changing the meaning of any of it is a **breaking change**.

### Breaking changes need CHANGELOG entries

When a script's public interface changes in a non-additive way, the
release CHANGELOG entry includes one of the structural-change
phrases `/sync` already scans for (`"Structural change worth
flagging"`, `"breaking change"`, `"BREAKING:"`). This makes the
delta visible to every project that runs `/sync` after the change
lands.

### SKILL.md lockstep

A script's interface section in its SKILL.md is part of the
interface. The AI calls what the SKILL.md says. Out-of-sync SKILL.md
is worse than no SKILL.md — it makes the AI confidently call
something that no longer exists.

**Rule:** every commit that changes the script's interface also
updates the corresponding SKILL.md interface section. Same commit.

### Testing

Every behavior path is verified in a sandbox **before commit.**
Pattern that works:

```bash
cd /tmp && rm -rf <name>-test && mkdir <name>-test && cd <name>-test
git init -q
cp <path-to-script> ./
chmod +x ./<name>.sh

# Test the happy path, the archive path, each error path, edge cases.
# Surface what each path produced; verify exit codes.
```

A passing manual test is sufficient — the kit doesn't have a test
runner yet. But "I ran it once and it didn't crash" is not enough.
Run every subcommand, exercise every error branch, verify the exit
code is what the contract says it is.

## RUN

### Invocation

- **From SKILL.md**, always `bash <skill-dir>/<name>.sh ...` — never
  `./<name>.sh`. The executable bit is not guaranteed to survive
  `/sync` unless the sync skill explicitly chmod's (which it now
  does — see `kit/skills/sync/SKILL.md` Step 6). `bash <script>`
  works regardless of file mode, so it's the canonical call form.
- **From `bin/`**, files are invoked by name (`bin/init`,
  `bin/lint`). `bin/init` is responsible for ensuring its own
  exec bit; user-invoked tools can be either chmod'd or run with
  `bash bin/<name>` as a fallback.

### Exit code contract

- **`0`** — success. Stdout has the result.
- **`1`** — operational error (missing file, write failure, repo
  not found). Stderr has a short error message.
- **`2`** — usage error (bad flag, missing required argument, bad
  flag value). Stderr has the error; usage text follows.
- **`3`** — refused (preconditions not met — e.g. archive
  requested on an empty file). Stderr has the refusal reason.

Callers (SKILL.md, AI) surface stderr verbatim on non-zero. Don't
re-interpret; the script already said what was wrong.

### I/O discipline

- **stdout = result.** What the caller wants to use.
- **stderr = errors and diagnostics.** What the caller surfaces to
  the user on failure.
- **No chatter.** A successful run prints the result line and exits.
  No "Starting...", no "Done!", no progress bars unless gated behind
  a `--verbose` flag (which most scripts don't need).

### Portability

- **BSD/macOS + GNU/Linux required.** The kit runs on these.
- **Windows out of scope.** WSL or git-bash works incidentally, but
  no script optimizes for it.
- **Test cross-platform commands.** `date -r` (BSD) vs `stat -c %y`
  (GNU). `sed -i` (BSD requires `''` after `-i`). Use conditionals
  or pick a portable subset.

## Reference: `save.sh` as the canonical example

`kit/skills/save/save.sh` is the working reference for everything
above. When in doubt about how a piece should look, read save.sh
first.

It demonstrates:

- The skeleton (shebang, strict mode, usage, subcommand dispatch)
- Repo-root resolution via `git rev-parse --show-toplevel`
- Subcommand verbs (`status`, `write`, `archive`)
- Exit codes (0, 1, 2, 3) used the way this doc specifies
- I/O discipline (stdout for results, stderr for errors)
- Portable date handling (BSD/GNU branch)
- Defensive practices (`has_content`, collision suffixes, file
  existence checks)

When writing a new script: open save.sh side-by-side, mirror the
shape, fill in the mechanics.
