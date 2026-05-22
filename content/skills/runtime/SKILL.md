---
name: runtime
description: Preflight + env management for `.claude/runtimes/<name>.md` stamps. Validates env vars are set, runs `depends_on` check commands, reports a clean diagnostic with severity-tagged failures and a VERDICT: READY / NOT READY. Supports named env profiles (`--env local|test|production`). Subcommands: `list`, `show`, `check`, `env`, `preflight`. Triggered when the user wants to verify a runtime can start — e.g. "preflight api", "check the API can run", "is dev ready?", "what env vars am I missing?", "/runtime check <name>".
---

# /runtime — Preflight + env management for runtime stamps

Reads a runtime reference stamp (`.claude/runtimes/<name>.md`),
validates its declared environment variables are set, runs its
`depends_on` check commands, and reports an actionable diagnostic.

The output answers: **"can I start this runtime right now?"**

Per CLAUDE.md ethos: blunt, calibrated, no fabricated success.
The verdict is binary — READY or NOT READY. If something's missing,
the report tells you exactly what.

## Behavior contract

- **Read-only.** Parses stamps, reads env files, runs dependency
  check commands. Doesn't start runtimes, doesn't write files,
  doesn't commit.
- **The script's stdout IS the user-facing output. Pass it verbatim.**
  Same load-bearing rule as `/status`. No summary, no preamble.
- **Three subcommands users touch:** `list`, `check`, `env`.
  `show` is a utility (basically `cat`); `preflight` is an alias
  for `check`.
- **Exit codes are load-bearing.** `0` = READY. `3` = NOT READY
  (missing env / unreachable deps). Skills calling /runtime can
  branch on the exit code.

## The script

Lives at `kit/skills/runtime/runtime.sh` (or
`.claude/skills/runtime/runtime.sh` in synced projects). Uses
python3 + PyYAML for stamp parsing — see "Dependencies" below.

### Interface

```text
bash <skill-dir>/runtime.sh list
    List runtimes in .claude/runtimes/ (skipping _template-*).

bash <skill-dir>/runtime.sh show <name>
    Print the full runtime file (stamp + body). Like `cat`.

bash <skill-dir>/runtime.sh check <name> [--env <profile>]
    Validate env vars + dependencies. Exit 0 if ready, 3 if not.
    --env defaults to the stamp's `env.file` (typically ".env").

bash <skill-dir>/runtime.sh env <name> [--env <profile>]
    Env coverage only — which required / optional vars are set
    or missing. Doesn't run dep checks. Faster.

bash <skill-dir>/runtime.sh preflight <name> [--env <profile>]
    Alias for `check`.
```

Exit codes: `0` ready, `1` operational error (file not found,
PyYAML missing), `2` usage error, `3` not ready.

### Dependencies

The script uses **python3 + PyYAML**. PyYAML is the only realistic
YAML parser for Python — stdlib doesn't ship one. The script fails
fast with `error: requires PyYAML — install with: pip install pyyaml`
if it's not available.

Most Python projects already have PyYAML installed. For Node /
mobile-only projects, install once:

```sh
pip3 install pyyaml
# or in a venv if you have one
```

Per `script-craft.md` policy ("Python only when bash is clumsy"),
YAML parsing in bash is genuinely clumsy — Python + PyYAML is the
right tool.

## Named env profiles

The runtime stamp can declare named profiles:

```yaml
env:
  template: .env-template
  file: .env
  environments:
    local: .env
    test: .env.test
    production: .env.production
  required: [JWT_SECRET, POSTGRES_DB_HOST, REDIS_DB_HOST]
```

Then:

```sh
runtime.sh check api                       # uses env.file (.env)
runtime.sh check api --env test            # uses .env.test
runtime.sh check api --env production      # uses .env.production
```

If you pass `--env <profile>` and the profile isn't declared in
`env.environments`, the script exits 2 with the list of declared
profiles.

## Process

### Step 1 — Identify the request

Map user intent:
- "preflight api" / "check api" → `runtime.sh check api`
- "is the API ready?" → `runtime.sh check api`
- "what env vars am I missing?" → `runtime.sh env <name>`
- "list runtimes" → `runtime.sh list`
- "show me the api runtime" → `runtime.sh show api`

If the user names a runtime that doesn't exist, the script returns
exit 1 with the right error. Surface it and stop.

### Step 2 — Run the subcommand

```bash
bash .claude/skills/runtime/runtime.sh check <name> [--env <profile>]
```

### Step 3 — Surface stdout verbatim

The script's output is the user-facing report. Same rule as
`/status` and `/audit`:

**MUST NOT:**
- Summarize the report ("looks like Redis is down")
- Paraphrase any section
- Drop sections that look uninteresting (e.g. the env section
  when everything's set — the "all green" is the answer)
- Add preamble or closing chat

**MAY:**
- Add a follow-up question *below* the script output if there's a
  clear next step ("Want me to file a TASK for the missing env
  vars?"). The report itself is sacrosanct.

### Step 4 — Branch on exit code (for other skills calling /runtime)

A skill that wants to start a runtime should preflight first:

```bash
if bash .claude/skills/runtime/runtime.sh check api >&2; then
  # READY — proceed to start the runtime
  source .venv/bin/activate
  python api.py
else
  # NOT READY — the preflight output already showed why
  exit 1
fi
```

## Output structure

The script renders this shape (placeholders filled per invocation):

```text
runtime: api (dev-server, python)
env file: .env (loaded)
profile:  default

env vars:
  ✓ JWT_SECRET                       set (mysecret)
  ✓ POSTGRES_DB_HOST                 set (192.168.1.6)
  ✗ REDIS_DB_HOST                    NOT SET (required)
  ✗ OPENAI_API_KEYS                  NOT SET (required)
  · LOG_LEVEL                        not set (optional, default: 'INFO')

dependencies:
  ✓ postgres                         reachable
    └─ /var/run/postgresql:5432 - accepting connections
  ✗ redis                            UNREACHABLE
    └─ redis-cli ping
       Could not connect to Redis at 127.0.0.1:6379: Connection refused

VERDICT: NOT READY
  - 2 required env vars missing
  - 1 dependency unreachable
```

Or for a passing run:

```text
runtime: api (dev-server, python)
env file: .env (loaded)
profile:  default

env vars:
  ✓ JWT_SECRET                       set (mysecret)
  ✓ POSTGRES_DB_HOST                 set (localhost)
  ✓ REDIS_DB_HOST                    set (localhost)
  ✓ OPENAI_API_KEYS                  set (sk-test...)
  · LOG_LEVEL                        not set (optional, default: 'INFO')

dependencies:
  ✓ postgres                         reachable
  ✓ redis                            reachable

VERDICT: READY
  start with: uvicorn app.main:app --reload --port 8000
```

## Style rules

- **The script enforces the style.** Skills calling /runtime
  surface its output verbatim. Don't reformat.
- **Glyphs:** `✓` = pass, `✗` = fail (required missing or unreachable),
  `·` = optional not set, `?` = unknown / couldn't determine.
- **Severity:** missing required vars and unreachable deps are
  both shown — neither is "louder." The user fixes both before
  the runtime starts.
- **No recommendations beyond the start command.** The script
  reports state; the user decides whether to install Postgres,
  fix the .env, etc.

## What you must NOT do

- **Don't paraphrase the report.** Same as /status — pass it
  verbatim.
- **Don't try to fix the failures.** /runtime reports; the user
  fixes (or files a /task).
- **Don't run `runtime.sh check` to "make sure" a runtime works
  before doing some other task** unless the user asked. It's not
  a free check — it runs each `depends_on` command, which costs
  real time (curl, pg_isready, etc.).
- **Don't fabricate a READY verdict.** If the script said NOT
  READY, that's the answer.

## Edge cases

- **Runtime file doesn't exist.** Script exits 1 with `error: runtime
  '<name>' not found in .claude/runtimes/`. Surface and stop.
- **PyYAML missing.** Script exits 1 with the install instruction.
  Run `pip install pyyaml` and retry.
- **Env file doesn't exist.** Script proceeds and renders all
  required vars as NOT SET. Diagnostic is still useful — tells
  the user to copy from `env.template`.
- **Stamp has malformed YAML frontmatter.** PyYAML raises; script
  surfaces the parse error and exits 1.
- **Profile declared but not in `env.environments`.** Exit 2,
  shows the declared profile list.
- **Dependency check command takes > 10s.** Script timeouts the
  check with `TIMEOUT (>10s)`. Doesn't hang the whole report.
- **Env var defined in `optional` but also has a real value in the
  loaded env file.** Renders as "set (value)" — the optional
  default is shown only when the real value is missing.

## When NOT to use this skill

- **Want to actually start the runtime** → preflight first, then
  run the `commands.dev` from the stamp manually (no skill ships
  for "start" yet; future `/run` skill).
- **Looking at all runtimes at once for a dashboard view** →
  `/status` (future integration).
- **Want to inspect the cloud setup, not local runtime** →
  `.claude/clouds/` files; `/runtime` is for the local-dev side.
- **Want to add or generate a new runtime** → copy a template
  from `.claude/runtimes/_template-*.md` and rename.

## What "done" looks like for a /runtime session

The user reads the diagnostic. They either:
- Saw `VERDICT: READY` → they run the dev command and proceed.
- Saw `VERDICT: NOT READY` → they fix the missing things (env
  vars, services), re-run check, eventually get to READY.

No files modified. No commits. Pure read-only verification with
an actionable report.
