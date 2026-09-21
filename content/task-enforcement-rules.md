# Task Enforcement Rules

No code change without a task. Enforced at **change time**, by denying
the tool call — not at commit time, after the fact.

`task-rules.md` already said every code and running-config change is
task-linked and that a stub is acceptable but nothing is not. This is the
mechanism that makes that true instead of aspirational.

## The one thing to internalize

**File the task yourself, before you edit.** The guard's auto-filed stub
is a backstop, not the happy path. When it fires you get a task titled
`work on app.js`, which is technically an audit trail and practically
useless six weeks later.

When the user asks for a code change, your first action is:

```bash
.claude/skills/task-enforce/task-enforce.sh new "what this work actually is"
```

That files a stub, links it, and every edit afterwards proceeds silently.
One command, no interruption, and the trail says something true.

If the work belongs to a task that already exists:

```bash
.claude/skills/task-enforce/task-enforce.sh set TASK-042
```

## What happens if you don't

The `PreToolUse` guard on `Edit|Write|MultiEdit|NotebookEdit`:

1. Classifies the path — `code`, `docs`, or `meta`.
2. `docs` and `meta` are **recorded and allowed**. Touching a README is
   not a task.
3. `code` with a linked task → recorded and allowed.
4. `code` with nothing linked → **denied once**. A stub is filed, linked,
   and the retry proceeds.

**One deny per task, not per edit.** The cost of the audit trail is a
single interrupted tool call.

When you get that deny: retry the edit, then **open the stub and fix the
title and the "What this is" section**. It was named after a filename.
`task-enforce.sh status` counts stubs still carrying
`origin: auto-fallback` so they do not quietly accumulate.

## Classification

| Class | Default paths | Behavior |
|---|---|---|
| `meta` | `.claude/**`, `tasks/**`, `deploys/**` | recorded, never gated |
| `docs` | `docs/**`, `*.md`, `LICENSE`, dotfiles | recorded, never gated |
| `code` | everything else | gated |

`audit_anyway` in `.claude/task-enforcement.json` **overrides both
exemptions** and ships non-empty:

```
.claude/environments.json
.claude/env-transport.md
build/environments/*/env.sh
build/environments/*/deploy.sh
```

The exemption exists so a README touch is not a task. It does **not**
exist so that the files defining what production *is* can be edited
untracked. `.claude/environments.json` carries each environment's
`class`; flipping one from `prod` to `staging` would let the next
`/deploy` reach production through a gate working exactly as designed —
with no task, no ledger row, and nothing for the commit-time reconciler
to catch. Add paths to that list. Removing these four is a decision to
accept that hole.

## The ledger

Every classified change appends to `tasks/changes/<date>-<TASK>.md`, and
`tasks/CHANGES.md` is regenerated from those files. **Per-day-per-task
files, not one appended table** — a single append-only file conflicts on
every PR the moment two long-lived branches exist, and a ledger that
conflicts on every PR gets deleted. Same discipline as `deploys/`.

`tasks/CHANGES.md` is generated. Do not hand-edit it.

## Honest limits

State these plainly if asked; do not imply a guarantee that does not
hold.

- **Raw `Bash` writes bypass the guard entirely.** `cat > file`,
  `sed -i`, `git apply`, a codemod — none of these are `Edit`/`Write`
  tool calls, so no `PreToolUse` hook sees them. `/contract` concedes the
  identical hole. The commit-time reconciler (`/task-guard`) is what
  catches those.
- **`--no-verify` bypasses the reconciler**, and merge commits never run
  `pre-commit`.
- **The config is `meta`**, so `.claude/task-enforcement.json` can be
  edited — including setting `enabled: false` — without filing a task.
  The off switch is itself unaudited. Making it `code` would mean you
  cannot turn enforcement off without enforcement's permission, which is
  a worse failure mode.

The claim that holds: **no Claude Code `Edit`/`Write` to a code path
happens without a linked task, and every classified change lands in the
ledger.** Not "no change of any kind is ever unaudited."

## Interaction with the deploy gates

`git-clean.sh` excludes `tasks/`, `deploys/` and `build/deploy-log.md`
for non-production classes. These are records the toolkit writes as you
work — and the last two are written **by the deploy pipeline itself**, so
without the exclusion the first staging deploy succeeds, writes its
record, and the second fails the gate on the evidence of the first.

For `ENV_CLASS=prod` the check is unfiltered. `BOOKKEEPING_STRICT=1`
makes it unfiltered everywhere.

## Toggle

```bash
task-enforce.sh on | off | status
```

State lives in `.claude/task-enforcement.json`, which is **committed** —
so the setting binds everyone on the repo. `/task-guard` keeps its state
in `.git/hooks/pre-commit`, which is per-machine and lost on a fresh
clone; that is the difference.

**The default is decided per target, by `bin/init`, at install time.**

- **New project** — no commits and no tracked files when the Element is
  installed → `enabled: true`. There is no mid-stream to disrupt, and
  defaulting off in a greenfield repo means the gate is never turned on.
- **Existing project** → `enabled: false`, and `bin/init` prints the one-line
  command to enable it. A gate that switches itself on mid-stream is a gate
  people delete, and that reasoning still holds wherever it applies.

The file is `skip-if-exists`, so once `.claude/task-enforcement.json` exists
the setting is the consumer's; no later install or re-init rewrites it. Only
a run that creates the file sets a default at all.

## See also

- `task-rules.md` — the task contract this enforces.
- `task-template-stub.md` — the shape of a filed stub.
- `.claude/skills/task-enforce/` — the engine.
- `/task-guard` — the commit-time reconciler underneath this.
