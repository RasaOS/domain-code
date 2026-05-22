---
name: task-guard
description: Toggle enforcement of the change-audit rule — every code or configuration change must be linked to a task. When ON, installs a git pre-commit hook that checks each commit: if it touches code/runtime config with no active task, a minimal stub task is auto-created and rides into the commit, and a row is appended to the change ledger (tasks/CHANGES.md). Never blocks a commit — it auto-creates so the audit trail is never broken. Subcommands: on, off, status. Triggered when the user wants change-to-task enforcement — e.g. "/task-guard on", "/task-guard off", "/task-guard status", "enforce tasks for every change", "make sure every code change has a task", "lock down change auditing".
---

# /task-guard — enforce the change-audit rule

Every code change and every running-configuration change should be
linked to a task — for audit and review, long term. Not just the
planned work: the quick fixes and hotfixes too, the ones that
normally skip the task system entirely. `/task-guard` makes that
enforcement automatic.

`/task-guard on` installs a pre-commit hook that holds the line.
The rule it enforces is documented in `task-rules.md` ("Every
change is task-linked"); this skill is the mechanism.

Built on the kit's git-hook pattern (see `/git-guard`). The script
`task-guard.sh` owns every mechanic; this SKILL.md only routes the
`on` / `off` / `status` choice.

## What it installs

| Hook | Type | What it does |
|---|---|---|
| `pre-commit` → `guard-commit` | git | On every commit: if staged files include a code / runtime-config change, ensure it's task-linked. No active task → auto-create a stub and ride it into the commit. Append a row to the change ledger. **Never rejects the commit.** |

The git hook lives in the repo's shared hooks dir (worktree-aware
via `git rev-parse --git-common-dir`). It is **per-machine** —
`.git/hooks/` is not version-controlled — so run `/task-guard on`
once on each machine, per project.

## The model — auto-create, never block

`/task-guard` does not stop you to ask for a task. When an
auditable change has no active task, the hook **creates one** — a
minimal stub at `tasks/active/TASK-NNN-auto-<slug>.md`, flagged
`STATUS: STUB — not spec'd`, with a "why not spec'd" note (the
change was a direct fix made without filing a task). The stub and
a change-ledger row ride into the *same commit* as the change, so
the audit trail closes itself with zero friction.

That is the whole point: a hotfix made in thirty seconds still
ends up with a task and a ledger row, without the developer having
to stop and think about it.

## What counts as an auditable change

Source code and runtime/user-facing configuration. **Not**
auditable — and so never triggering a stub: anything under
`tasks/`, `docs/`, or `.claude/`, and any `*.md`, `LICENSE`,
`.gitignore`-class file. A docs-only or task-only commit passes
through untouched.

## The change ledger

`tasks/CHANGES.md` — append-only. One row per auditable commit:
the timestamp, the author, the linked task, the files, and — for
auto-created stubs — the note that it wasn't spec'd. Each row
rides in the same commit as its change, so `git blame
tasks/CHANGES.md` recovers the exact commit for any row. This is
the long-term audit-and-review surface.

## Interface

```text
bash <skill-dir>/task-guard.sh on        Install the hook; scaffold
                                         tasks/ + the ledger.
bash <skill-dir>/task-guard.sh off       Remove the hook.
bash <skill-dir>/task-guard.sh status    Report ON / OFF + ledger count.
```

Hook handler — called by the hook, not directly: `guard-commit`.

Exit codes: `0` success, `1` operational, `2` usage.

## Behavior contract

- **Script-driven.** `task-guard.sh` owns the hook install, the
  auditable-file classification, stub creation, and the ledger.
  This SKILL.md routes `on` / `off` / `status`. Always invoke as
  `bash <skill-dir>/task-guard.sh ...`.
- **Per-machine.** Git hooks are not version-controlled. Run `on`
  once per machine, per project. Tell the user this on `on`.
- **Never blocks a commit.** The `guard-commit` handler always
  exits 0. It enforces by auto-creating, not by rejecting — a
  rejected commit is friction the user explicitly didn't want.
- **The hook commits nothing on its own.** It stages the stub and
  the ledger row into the commit the user is *already making*.
  That's the user committing, not the skill auto-committing —
  the kit's "never auto-commit" rule is intact.
- **Idempotent.** `on` twice is a no-op; `off` when off is a
  no-op. The git-hook edit uses a sentinel block, so `off` removes
  cleanly and co-existing hooks (e.g. `/git-guard`'s) are
  preserved.

## Process

### Step 1 — Map intent to a subcommand

- "enforce tasks for changes" / "/task-guard on" → `on`
- "turn it off" / "/task-guard off" → `off`
- "is task-guard on?" / "/task-guard status" → `status`

### Step 2 — Run it

```bash
bash .claude/skills/task-guard/task-guard.sh <on|off|status>
```

Surface the script's stdout verbatim.

### Step 3 — Note the lifecycle

On `on`: the hook takes effect on the **next** commit, on **this
machine only**. Other machines need their own `/task-guard on`.

## Honest limits

- **Per-machine install.** A teammate who hasn't run `/task-guard
  on` commits unguarded. The enforcement is only as complete as
  the installs.
- **`--no-verify` bypasses it.** `task-rules.md` already forbids
  `--no-verify`; `/task-guard` relies on that rule holding, it
  can't out-muscle a deliberate bypass.
- **The stub is crude.** A pre-commit hook is bash — the
  auto-stub's title and details are mechanical. It's a real,
  linked, audit-complete task, but it is *not* a spec. Spec it
  retroactively with `/task` if the change warrants it.

These are real. `/task-guard` closes the common gap — the honest
quick-fix that just forgot a task — not a determined bypass.

## What you must NOT do

- **Don't hand-edit `.git/hooks/pre-commit`** for this — use `on`
  / `off`. Direct edits break idempotent removal.
- **Don't hand-edit `tasks/CHANGES.md`.** It's written by the
  hook; hand-edits corrupt the audit trail.
- **Don't treat the auto-stub as a finished spec.** It's an
  audit-trail placeholder. Expand or close it deliberately.
- **Don't render `guard-commit` output in chat** as if the user
  asked for it — it's for the hook.

## Edge cases

- **Not a git repo** — every subcommand errors cleanly.
- **`/git-guard` also on** — both append sentinel blocks to the
  same `pre-commit` file; they coexist.
- **Commit `--amend` / interactive rebase** — `pre-commit` re-runs
  per replayed commit, which can append a duplicate ledger row.
  Harmless but noisy; trim by hand if it matters.
- **Multiple active tasks** — the hook can't know which one a
  commit belongs to, so the ledger row records all active task
  IDs. Cleaner ledger rows come from one active task at a time.
- **Merge commits** — git skips `pre-commit` for merges; merges
  are not ledgered.

## When NOT to use this skill

- **Filing or spec'ing a task properly** → use `/task`.
  `/task-guard` only guarantees a task *exists*; `/task` makes it
  good.
- **Guarding system contracts specifically** → `/contract` already
  locks and ledgers schema/endpoint/doc changes.
- **Git-hygiene lockdown** (trunk protection, WIP capture) → that's
  `/git-guard`.

## What "done" looks like for a /task-guard session

The user has run `on`, `off`, or `status` and seen the brief
result. With it ON: from the next commit, every code or
configuration change is linked to a task — a real one if work was
filed, an auto-created stub if not — and recorded in
`tasks/CHANGES.md`. The audit trail has no gaps, and the developer
was never stopped to make it so.
