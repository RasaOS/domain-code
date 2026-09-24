---
name: task-enforce
description: Toggle and operate change-time task enforcement — no code change without a linked task, enforced by a PreToolUse hook that denies the edit, files a task into tasks/triage/ through .claude/bin/task, and lets the retry through. Also stamps this domain's x- frontmatter keys and runs the spec-only merge gate. Use for "/task-enforce", "turn on task enforcement", "require a task for every change", "why was my edit blocked", "link this work to a task", "what task am I on", "stamp x-outcome on TASK-N". Ships off; turn it on deliberately.
---

# /task-enforce — No code change without a task

`task-rules.md` §12 and `code-task-rules.md` §6 say every code change is
task-linked. This is what makes that true rather than aspirational — a
`PreToolUse` guard that **denies** an unlinked code edit, files the task,
and lets the retry proceed.

Engine: `.claude/skills/task-enforce/task-enforce.sh`.
Contract: `.claude/task-enforcement-rules.md`.

## Before anything else

**If the user is about to have you change code, file the task first.**

```bash
.claude/skills/task-enforce/task-enforce.sh new "add retry to the webhook client"
```

That is one command, it costs nothing, and it means the trail says
something true. It files a `change` into `tasks/triage/` through
`.claude/bin/task new` (`x-origin: manual`) and makes it the current
task. The guard's auto-filed task is a backstop — it produces
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
task-enforce.sh new "title"      # file a task (triage/) and link it
task-enforce.sh clear            # unlink; next code edit re-gates
task-enforce.sh who              # the handle to pass as .claude/bin/task --by
```

`who` folds `RASA_ACTOR` (else git's `user.name`) into the handle grammar
`.claude/bin/task` accepts — `agent:Mission Runner` → `agent-mission-runner`
— so an autonomous skill passes `--by "$(bash
.claude/skills/task-enforce/task-enforce.sh who)"` rather than a raw value
the command would refuse.

The pointer is machine-local and **per-worktree** — two worktrees are two
pieces of work. (`/environment`'s current-env pointer deliberately does
the opposite and is shared across worktrees.)

### Understand a decision

```bash
task-enforce.sh classify src/app.js
```

### Stamp this domain's keys

```bash
task-enforce.sh stamp TASK-042 x-outcome shipped
task-enforce.sh stamp TASK-042 x-severity high
```

Writes one frontmatter key, and only these: `x-origin`, `x-owner`,
`x-outcome`, `x-severity` (`code-task-rules.md` §7) and `priority`. It
checks the value, bumps `updated` and re-records the task's digest, so
the write never trips I-34. Every other key is refused, and the refusal
says what to use instead — there is no `status` (the directory is the
state; move it with `.claude/bin/task`), `phase` is
`.claude/bin/task graduate`, and the rest belong to the lifecycle.
`priority now` is refused while the task sits in `triage/` or
`backlog/` — start it first (I-14). The old names `origin`, `owner`,
`outcome`, `severity` still land, as their `x-` form.

### The spec-only merge gate

```bash
task-enforce.sh spec-gate            # the working tree (pre-push)
task-enforce.sh spec-gate --pr 88    # the pushed PR (pre-merge)
```

The program behind `autonomy-rules.md` Exception 2. It passes only if
every path in the change set is `tasks/**/*.md` or `tasks/history.tsv` —
the transition log `.claude/bin/task` appends to on every filing and
move. Anything else, `tasks/tasks.config.yml` included, refuses the
fast-path. There is no flag or variable that skips it.

### Check every record — read-only

```bash
task-enforce.sh doctor               # this install's project
task-enforce.sh doctor <root>        # any project: a clone, before it takes a release
```

Reads every record this Element writes — task files, run records, deploy
and env-transfer records and `DEPLOYS.md`, contract, env-var and test
stamps, and `tasks/RELEASES.md` — and **writes nothing**: no `--fix`, no
cache, no state file (`check-tasks` writes `tasks/.state`; this does not).

- **FAIL** (exit 1) on what a reader or writer outside the frontmatter
  contract gets wrong: a BOM, a CR, a blank after a fence, a block that
  never closes, the body line that exposes, a duplicated key, a literal
  `\n` or a control character in a value, an `auto-*` run recorded as
  `actor_kind: human`, a `DEPLOYS.md` row with no id, a release with a
  second **Approved.** line.
- **WARN** on drift: one id on two records, an id or name that disagrees
  with its file, a value outside its set, a task carrying `status:`, an
  outcome on an open task, a second frontmatter block.

It prints keys, ids, files and line numbers — never a value — so its report
can be shared from any project. It repairs nothing: fix a finding by hand,
or with the verb that owns the record.

## When an edit gets denied

The deny reason names the task that was just filed. Do this, in order:

1. **Retry the edit.** It will now succeed, and so will everything after
   it. Do not go around the guard — no `Bash` heredocs to write the file,
   no turning enforcement off.
2. **Fix the task.** It was filed into `tasks/triage/` with
   `x-origin: auto-fallback` and named after a filename. Open it and
   rewrite the H1 title and `## Intent` to say what the work actually
   is, run `.claude/bin/check-tasks --fix` (I-34), then graduate it into
   a phase (`.claude/bin/task graduate <id> --phase P`) — or close it.
3. Carry on.

If the work belongs to an existing task, `set TASK-NNN` and close the
auto-filed one — do not delete it; its id is already in
`tasks/history.tsv`:

```bash
.claude/bin/task close <id> --resolution duplicate --ref TASK-NNN --by <who>
```

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
