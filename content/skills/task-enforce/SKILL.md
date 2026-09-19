---
name: task-enforce
description: Toggle and operate change-time task enforcement — no code change without a linked task, enforced by a PreToolUse hook that denies the edit, files a stub, and lets the retry through. Use for "/task-enforce", "turn on task enforcement", "require a task for every change", "why was my edit blocked", "link this work to a task", "what task am I on". Ships off; turn it on deliberately.
---

# /task-enforce — No code change without a task

`task-rules.md` has always said every code change is task-linked. This
is what makes that true rather than aspirational — a `PreToolUse` guard
that **denies** an unlinked code edit, files the task, and lets the retry
proceed.

Engine: `.claude/skills/task-enforce/task-enforce.sh`.
Contract: `.claude/task-enforcement-rules.md`.

## Before anything else

**If the user is about to have you change code, file the task first.**

```bash
.claude/skills/task-enforce/task-enforce.sh new "add retry to the webhook client"
```

That is one command, it costs nothing, and it means the trail says
something true. The guard's auto-filed stub is a backstop — it produces
`work on client.js`, which is an audit trail in the same sense that a
receipt for "goods" is.

## Operations

### Turn it on / off

```bash
task-enforce.sh on
task-enforce.sh off
task-enforce.sh status
```

`on` sets `enabled` in `.claude/task-enforcement.json` and installs the
hook into `.claude/settings.json`. That file is **committed**, so the
setting binds every contributor — unlike `/task-guard`, whose state lives
in `.git/hooks/` and dies on a fresh clone.

Ships **off**. Turning it on is a deliberate act.

### Link work

```bash
task-enforce.sh current          # what am I on
task-enforce.sh set TASK-042     # link to an existing task
task-enforce.sh new "title"      # file a stub and link it
task-enforce.sh clear            # unlink; next code edit re-gates
```

The pointer is machine-local and **per-worktree** — two worktrees are two
pieces of work. (`/environment`'s current-env pointer deliberately does
the opposite and is shared across worktrees.)

### Understand a decision

```bash
task-enforce.sh classify src/app.js
```

## When an edit gets denied

The deny reason names the task that was just filed. Do this, in order:

1. **Retry the edit.** It will now succeed, and so will everything after
   it. Do not go around the guard — no `Bash` heredocs to write the file,
   no turning enforcement off.
2. **Fix the stub.** Open it and rewrite the title and "What this is" to
   say what the work actually is. It was named after a filename.
3. Carry on.

If the work belongs to an existing task, `set TASK-NNN` and delete the
auto-filed stub.

## What to tell the user honestly

If they ask whether this guarantees every change is audited — **it does
not**, and say so:

- Raw `Bash` writes (`cat >`, `sed -i`, `git apply`, codemods) are not
  `Edit`/`Write` tool calls, so no `PreToolUse` hook sees them.
  `/task-guard` catches those at commit time.
- `--no-verify` bypasses that reconciler; merge commits never run it.
- The config is class `meta`, so enforcement can be switched off without
  filing a task. That is deliberate: the alternative is not being able to
  turn it off without its own permission.

The claim that holds: **no Claude Code `Edit`/`Write` to a code path
happens without a linked task, and every classified change lands in
`tasks/CHANGES.md`.**

## Do not

- **Do not disable enforcement to get past a deny.** Retry the edit. If
  the classification is genuinely wrong, fix the globs in
  `.claude/task-enforcement.json` and say what you changed.
- **Do not remove entries from `audit_anyway`.** They ship non-empty on
  purpose: `.claude/environments.json` decides which environments count
  as production, and an untracked edit there would let the next
  `/deploy` reach prod through a working gate.
- **Do not hand-edit `tasks/CHANGES.md`.** It is regenerated.

## Related

- `.claude/task-enforcement-rules.md` — the full contract and its limits.
- `/task` `/backlog` — the task lifecycle this feeds.
- `/task-guard` — the commit-time reconciler beneath this.
- `/deploys` — the other ledger, same discipline.
