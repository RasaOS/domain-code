---
name: environment
description: Read and manage the project's environment registry at .claude/environments.json — the single source of truth for environments. Lists environments, shows one environment's config, reports and switches the current working environment (a machine-local pointer), and builds the canonical version string v<semver>-<sha>-<env>. Triggered when the user wants to see or change environments — e.g. "what environment am I in", "switch to staging", "list environments", "use prod", "what's the version string for staging", "/environment".
---

# /environment — environment registry, current-env, version string

Read and manage `.claude/environments.json`, the project's **environment
registry**. The registry is the single source of truth: every
environment name used by runtime stamps, cloud stamps, env-var stamps,
and the deploy pipeline must be a key in it. See `environment-rules.md`
for the full model.

This skill is a thin router over `environment.sh`. The script owns the
mechanics — parsing the registry, the machine-local current-env
pointer, building the version string. The skill maps the user's intent
to a subcommand and surfaces the result.

## Behavior contract

- **The script's stdout is the answer.** For `list`, `show`, `current`,
  and `version`, surface the script output as-is — don't paraphrase or
  reformat it.
- **`use` is a real (but cheap) state change.** It rewrites the
  machine-local current-env pointer. Local and reversible — no
  confirmation gate — but report what the working environment changed
  from and to.
- **Never edit `.claude/environments.json` to satisfy a request.** If
  the user asks for an environment that isn't declared, the script
  exits 2 — surface that. Adding an environment is a deliberate edit to
  the registry, not a side effect of `use` or `version`.
- **The current-env pointer is machine-local and uncommitted** —
  `~/.claude/projects/<key>/current-env`, shared across the project's
  worktrees, never in the repo. `--env` flags on other tools always
  override it.
- **Exit codes are load-bearing.** `0` ok, `1` operational error,
  `2` usage error (unknown environment / bad flag), `3` `validate`
  found drift. Callers branch on them.

## The script

```text
bash .claude/skills/environment/environment.sh <subcommand>

  list                        List environments; marks the current one.
  show <env>                  Print one environment's full config.
  get <env> <field>           Print one field's value (for stage scripts).
  current                     Print the current working environment.
  use <env>                   Switch the current working environment.
  version [<env>] [--semver vX.Y.Z]
                              Print v<semver>-<shortsha>-<env>.
  validate                    Check every environment name used across
                              the project against the registry.
```

Exit codes: `0` success, `1` operational error, `2` usage error,
`3` `validate` found drift.

## Process

### Step 1 — Map intent to a subcommand

- "what environments are there" / "list environments" → `list`
- "what environment am I in" / "current env" → `current`
- "show me staging" / "what's prod configured as" → `show <env>`
- "what's prod's deploy target" / one field for a script → `get <env> <field>`
- "switch to staging" / "use prod" / "set env to local" → `use <env>`
- "what's the version string" / "version for prod" → `version [<env>]`
- "check environments line up" / "validate the registry" → `validate`

### Step 2 — Run it

```bash
bash .claude/skills/environment/environment.sh <subcommand> [args]
```

### Step 3 — Surface the result

Pass the script's stdout through. On a non-zero exit, surface stderr
verbatim — the script already said what was wrong (e.g. "'prd' is not
a declared environment"). Don't retry, don't guess a correction; if the
name was a typo, ask which environment they meant.

## Output

`list`, `show`, `current`, and `version` each render their own plain
output — surface the lines as-is. No catalogue template applies; this
is a utility skill, like `/runtime`. Add at most a one-line follow-up
when there's an obvious next step ("`prd` isn't declared — want to add
it to `.claude/environments.json`?").

## What you must NOT do

- **Don't edit the registry to make a command succeed.** An unknown
  environment is an error to surface, not a registry gap to silently
  fill.
- **Don't paraphrase the script output.** Same rule as `/runtime` and
  `/status`.
- **Don't confirmation-gate `use`.** It's local and reversible; just
  do it and report the change.
- **Don't commit the current-env pointer.** It is machine-local by
  design — it lives outside the repo and stays there.

## When NOT to use this skill

- **Adding, removing, or editing an environment** → a direct edit to
  `.claude/environments.json`. This skill reads and switches; it
  doesn't author the registry.
- **Checking a runtime's env vars are set** → `/runtime`.
- **Cutting a release** → `/release`, which calls `environment.sh
  version --semver` internally.
- **Inspecting env *variables*** (the values a runtime needs) →
  `env/stamps/`, `env-rules.md`. Environments are contexts; env vars
  are values.

## What "done" looks like

The user knows which environments exist, which one is current — or has
switched it — and, when asked, has the canonical
`v<semver>-<sha>-<env>` version string for an environment.
