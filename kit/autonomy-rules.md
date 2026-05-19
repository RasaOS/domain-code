# Autonomy Rules

The shared contract for the kit's **`auto-*` skill family** —
`/auto-task`, `/auto-phase`, `/auto-develop`, `/auto-test`. Each is
an autonomous variant of a kit operation: it makes every decision
itself and runs to completion without returning to the user for
clarification. **Read this file before authoring or running any
`auto-*` skill.** Every `auto-*` SKILL.md defers its autonomy
behavior here rather than re-stating it.

The autonomous variant differs from its base skill in exactly one
way: **who decides.** The base skill asks the user; the autonomous
variant decides itself. It does not differ in diligence, quality,
or what counts as done.

## The autonomy contract

- **Decide, don't ask.** Wherever the base skill would ask the user
  a clarification or preference question, the autonomous variant
  makes the most reasonable decision and continues. It does not
  return to the user mid-operation for a preference call.
- **Flag every assumption.** Every call the user would normally
  have made is recorded as a flagged assumption — ⚠️, with the
  reasoning. Same discipline as `/instruct`. A decision is never
  buried silently inside the work; it surfaces in the autonomy
  report so the user can review and override. The user's review
  happens *after*, in one pass, instead of as N interruptions.
- **Ground decisions in reality.** Autonomy is not guessing. Read
  the repo, read the current docs, follow the patterns already in
  the codebase. A decision grounded in code or docs is just a
  decision. A decision that needs knowledge the repo doesn't
  contain — a business call, a product preference, an external
  constraint — is a flagged assumption, surfaced *prominently*,
  because it's the most likely thing to be wrong.
- **Run to completion.** The skill runs until its deliverable is
  done, or until it hits a hard gate (below). It does not stop
  early to "check in." A half-finished autonomous run with no hard
  gate hit is a bug.

## Hard gates — where autonomy STOPS

Autonomy removes the "what do you prefer?" gate. It does **not**
remove the safety gates. When an `auto-*` skill hits any of the
following, it **stops, does not proceed, and surfaces the
situation** in its report:

- **A locked `/contract`.** Per `contract-rules.md`, a locked
  contract blocks a change to it. The skill stops and reports — it
  never unlocks a contract itself. Unlocking is always the user's
  call.
- **Gated files.** Files that require explicit permission to touch,
  per `task-rules.md` and the CLAUDE.md "Gated files" section. The
  skill does not modify them; it surfaces exactly what it needs.
- **Merging or pushing to `main`, release tagging, deploys.** Per
  `git-flow-rules.md` Rules 2, 4, and 5 these are always
  user-confirmed. An `auto-*` skill never merges to `main`, never
  pushes `main`, never tags a release, never deploys. It works on
  a branch and leaves it for the user.
- **Destructive or irreversible operations.** History rewrites,
  force-pushes, data deletion, schema-destroying migrations,
  removing real content. Never auto-decided — the skill stops.
- **A genuine hard blocker.** Something the skill cannot resolve
  after real effort — a build that won't pass, a missing
  credential, an external service down, a spec that contradicts
  itself. The skill stops, records the blocker, and surfaces it.

A hard gate is not a failure — it is the system working as
designed. The skill names the gate plainly and hands the decision
back to the user.

## The quality bars still apply

Autonomy changes *who decides*, never *how good the work is*. Every
`auto-*` skill remains fully bound by `task-rules.md`,
`craft-rules.md`, `test-rules.md`, and `git-flow-rules.md`.
Autonomy never lowers a verification bar, never skips a test, never
ships unreviewed work. **"Never auto-commit" still holds** — an
`auto-*` skill leaves its work in the working tree, uncommitted,
for the user to review with `git diff` and commit.

## The autonomy report

Every `auto-*` skill ends with exactly one report — the user's
single review surface, standing in for the questions they were not
asked. Render it in chat at the end of the run:

```markdown
# 🤖 Autonomous run — <operation> · <target>

> **Outcome.** <completed | stopped at a hard gate>
> **Deliverable.** <what was produced — file paths, or "—">

## Decisions made

Calls the skill made on your behalf. Re-run with a correction to
override any of them.

- ⚠️ <decision> — <the reasoning that grounds it>
- ⚠️ <decision> — <reasoning>

*(If none: "No assumptions — every decision was grounded in the
spec, the code, or the docs.")*

## Hard gates hit

<Each gate that stopped the run, and what it needs from the user.
Omit this whole section if the run completed cleanly.>

- 🔒 <gate> — <what the user must do to unblock it>

## What's next

<One or two lines — the immediate next step. e.g. "Review the spec
and commit", or "Unlock contract `user-schema` and re-run".>
```

## Looping to a verified end state with `/goal`

An `auto-*` skill runs its operation to completion within one
invocation. For work that genuinely spans many turns — implement a
spec until every acceptance criterion holds, work a phase until
every stub is spec'd — pair the skill with Claude Code's built-in
**`/goal`** command (Claude Code v2.1.139+).

`/goal <condition>` sets a completion condition and loops turns
until a separate fast-model evaluator confirms it holds. `/goal`
is the loop engine; the `auto-*` skill is the methodology.

**A skill cannot invoke `/goal`.** Slash commands are the
user-input layer — a SKILL.md is instructions *to* Claude, and
Claude does not type slash commands at itself. `/goal` is therefore
never *embedded* in an `auto-*` skill. The **user** runs the skill
under a goal: set a `/goal` whose condition names the operation's
measurable end state. Claude reads the `auto-*` skill when relevant
and works toward the condition.

```bash
claude -p "/goal /auto-develop has implemented TASK-042 — every
acceptance criterion in the spec holds and the build exits 0"
```

**Writing the condition:**

- **The evaluator only reads the transcript.** It runs no tools
  and reads no files — it judges what Claude has surfaced in the
  conversation. Write conditions Claude's own output demonstrates:
  a build exit code, a test summary, a file count that actually
  appears in the transcript.
- **Encode the hard gates as an escape clause.** `/goal` loops
  relentlessly; the hard gates above require an `auto-*` skill to
  *stop*. A loop with no escape clause will spin against a gate it
  is contractually bound not to cross. Always include one — e.g.
  *"…or stop and report if a locked contract, a gated file, or a
  required merge to main blocks progress."* The hard gates still
  govern each individual turn; the escape clause is what lets the
  *loop itself* terminate at a gate.
- **Bound the run.** Add *"…or stop after N turns"* so a goal that
  cannot converge ends instead of burning turns.

**Requirements.** `/goal` needs Claude Code v2.1.139+, an accepted
trust dialog, and hooks enabled. It is a harness feature — the kit
references it but cannot ship or version it. An `auto-*` workflow
that relies on `/goal` carries that version dependency; without
`/goal` the `auto-*` skills still run, just as a single invocation
rather than a verified multi-turn loop.

> Not to be confused with the **Goal** *section* in `CLAUDE.md`
> (the project's current objective, a static planning artifact).
> `/goal` is a harness command — a loop. Different things that
> happen to share a name.

## Authoring an `auto-*` skill

An `auto-*` skill is **thin**. It does two things and no more:

1. **Names its operation.** Either by deferring to a base skill
   ("this is `/task` run autonomously — follow `task/SKILL.md`")
   or, when there is no base skill, by defining the operation
   itself (`auto-develop`, `auto-test`).
2. **Defers all autonomy behavior to this file.** Do not re-paste
   the contract, the hard-gate list, or the report template into
   the SKILL.md. Reference `autonomy-rules.md`. One contract, one
   place to evolve it.
