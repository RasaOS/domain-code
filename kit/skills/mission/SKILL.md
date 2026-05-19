---
name: mission
description: Autonomous end-to-end goal execution — the orchestrator above the auto-* family. Takes a goal (a statement, a rough decomposition, a definition of done), decomposes it into TASK specs, runs each through auto-task → auto-develop → auto-test, re-walks the goal to verify it actually holds, then opens a draft PR for the user to validate. Every judgment call is decided and flagged as an assumption. Stops at hard gates; never merges or deploys. Triggered when the user hands over a whole goal to run hands-off — e.g. "/mission", "run this goal autonomously", "take this goal end to end", "audit X, fix what's broken, put up a PR", a goal statement followed by numbered steps and a definition of done.
---

# /mission — autonomous goal execution

The capstone of the kit's autonomous skills. Each `auto-*` skill
runs one operation hands-off — spec a task, spec a phase, build a
task, test a task. `/mission` runs a whole **goal**: it clarifies
the goal into a verified instruction recipe, decomposes that into
tasks, takes each through the full spec → build → test lifecycle,
re-walks the goal to verify it actually holds, and opens a pull
request for the user to validate.

A vague goal is not a blocker. The first thing `/mission` does is
run the `/instruct` methodology on whatever it was handed — prose,
a brain-dump, a half-formed list — to expand it into a concrete,
gap-checked **recipe**. The mission then executes against that
recipe, not against the user's loose phrasing.

`/mission` does not reinvent the lifecycle — it *composes* it. The
per-task work follows `instruct`, `auto-task`, `auto-phase`,
`auto-develop`, and `auto-test`. What `/mission` adds is what the
family has no home for: **goal clarification**, **decomposition**,
a **verification re-walk**, **delivery**, and a **completion
condition** to loop against.

Distinct from two things it is easy to confuse it with — the
harness `/goal` command (a turn loop) and the `Goal` section of
`CLAUDE.md` (a static planning artifact). `/mission` is the
methodology; `/goal` is the loop you run it under for the long
haul — see "Running a mission under `/goal`" below.

Per CLAUDE.md ethos: run, don't speculate, and report the end
state honestly. A mission is done when the goal's conditions are
*verified true* — not when the tasks merely finished, not when the
turns ran out. Step 6 is where that honesty is enforced.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — it is
  the contract: decide don't ask, flag every assumption, ground
  decisions in reality, run to completion, stop only at hard
  gates, end with the autonomy report. This SKILL.md states only
  what is specific to `/mission`.
- **The operation is end-to-end goal execution.** There is no base
  `/mission` skill — `/mission` defines its operation: decompose →
  per-task lifecycle → verify → deliver.
- **Compose the family; don't reinvent it.** Per-task work
  *follows* `auto-task/SKILL.md` (file + spec), `auto-phase/SKILL.md`
  (spec a phase's stubs), `auto-develop/SKILL.md` (implement), and
  `auto-test/SKILL.md` (write + run tests). `/mission` does not
  re-specify reconnaissance, spec-writing, or the test-stamp
  model — it runs those skills' processes.
- **Clarify before decomposing.** A vague or half-formed goal is
  not a reason to stop. `/mission` follows `instruct/SKILL.md` to
  convert the goal — prose, a brain-dump, a rough list — into a
  verified *instruction recipe*: atomic steps, dependencies wired,
  gaps caught by a mock run-through, every judgment call flagged.
  `/instruct`'s no-round-trips rule keeps this fully autonomous —
  the recipe is what gets decomposed into tasks.
- **Always real tasks.** Every goal decomposes into `TASK-NNN`
  specs in `tasks/`. The specs on disk are the mission's durable
  state — what lets a long run, looped under `/goal`, resume after
  a context compaction. No in-memory-only plans.
- **Branch per the goal's directive.** Honor "start a new branch"
  / "stay on this branch". If unstated, cut a new branch —
  `git-flow-rules.md` Rule 1. A mission spans tasks, so a new
  branch is `feat/<goal-slug>`. "Stay" onto `main` is a hard stop.
- **Commit per task; PR at the end.** `/mission` is the one
  autonomous skill that commits and opens a PR — the documented
  exception in `autonomy-rules.md`. Each task is committed to the
  branch as it completes. The branch is pushed and a **draft PR**
  opened only as the final step, only once the verification
  re-walk confirms the goal holds. Never merges to `main`, never
  deploys.
- **Verify before delivering.** The tasks finishing is not the
  goal being met. Before delivery, re-walk the *original goal* and
  *every step the user named*, and confirm each is true. Gaps the
  re-walk finds become new tasks — the mission is not done while
  any remain.
- **Hard gates still stop the run.** A locked `/contract`, a gated
  file, a destructive operation, a required merge to `main`, a
  genuine blocker — `/mission` stops and surfaces it per
  `autonomy-rules.md`. A gate hit mid-mission stops the mission; it
  does not skip the task and continue.

## Process

1. **Read the contracts.** `autonomy-rules.md`, `craft-rules.md`,
   `git-flow-rules.md`, `task-rules.md`, `test-rules.md`, and
   `CLAUDE.md` (project facts, the verification command, gated
   files). And the skills the mission will follow — `instruct`,
   `auto-task`, `auto-phase`, `auto-develop`, `auto-test`.

2. **Parse the goal and set up the branch.** From the user's
   prompt, extract the **mission envelope**: the **goal
   statement**, the **branch directive**, any **decomposition**
   the user sketched (numbered steps, a named phase), the
   **definition of done** and its **terminal deliverables** (PR,
   tests, handoff doc), and the **completion condition**. Decide
   anything unstated and flag it as an assumption. Render this as
   the **mission brief**. Then set up the branch per the
   directive: new → `feat/<goal-slug>`; stay → confirm the current
   branch is not `main`, and stop if it is.

3. **Instruct the goal into a recipe.** Before decomposing into
   tasks, run the `/instruct` methodology — follow
   `instruct/SKILL.md` — on the goal statement and whatever
   decomposition the user sketched: extract the atomic intents,
   decompose them to smallest verifiable deliverables, wire the
   dependencies, look up and verify each against the real
   codebase, then do a mock run-through to catch missing or
   out-of-order steps. The output is the **goal recipe** — the
   verified, ordered, gap-checked statement of what the mission
   must accomplish. This is where a vague or half-formed goal
   becomes concrete; `/instruct`'s no-round-trips rule (gaps
   become flagged assumptions, never questions) keeps it
   autonomous. A crisp goal gets a light pass; a vague one the
   full lift. The one genuine blocker: an open-ended question with
   no objective to decompose toward — stop and point the user to
   `/brainstorm`.

4. **Decompose the recipe into tasks.** Group the goal recipe's
   atomic steps into `TASK-NNN` specs — one task per coherent
   unit of work, the recipe's dependency wiring carried into the
   task order. Follow `auto-task/SKILL.md` to file and fully spec
   each. The recipe is the raw material; how that material was
   sourced depends on the goal:
   - **Audit-first** — the goal says "audit X, fix what's wrong":
     the recipe leads with the audit itself (following
     `audit/SKILL.md`) as the first task; the findings it
     surfaces at runtime become the tasks that follow.
   - **Steps-as-plan** — the goal gave numbered steps: the recipe
     has already sharpened them into atomic, ordered deliverables.
   - **Phase-driven** — the goal names a phase: its stubs are the
     tasks; spec them following `auto-phase/SKILL.md`.
   Render the task list and the order they will run.

5. **Execute each task, in order.** For each: move its spec to
   `tasks/active/`, implement it following `auto-develop/SKILL.md`,
   write and run its tests following `auto-test/SKILL.md` (real,
   reusable test stamps per `test-rules.md`). When the acceptance
   criteria hold and the tests pass, commit the task to the branch
   — spec, code, and tests together, `TASK-NNN — <title>` — and
   move the spec to `tasks/done/`. A hard gate hit here stops the
   mission.

6. **Verification re-walk.** With every task done, re-walk the
   *goal*, not the task list. Re-read the changed surface, re-run
   the project's verification/build, re-run the test suite, and
   confirm every deliverable in the goal recipe is met. Any gap →
   file it as a new task and return to Step 5. Repeat until the
   goal holds with no gaps. If successive re-walks surface the
   same gaps without progress, stop and report it as a blocker —
   a goal that will not converge is a hard finding, not a reason
   to loop forever.

7. **Deliver.** Only once Step 6 is clean: push the branch and
   open a **draft PR** (via the project's GitHub tooling) — title
   from the goal, body carrying the mission summary: the goal and
   its recipe, the tasks done with their commits, the
   verification result, how to validate and the command to run
   the tests, and every flagged assumption. If the goal asked for
   a handoff doc, produce it following `handoff/SKILL.md`. Never
   merge, never deploy.

8. **Render the autonomy report.** The `autonomy-rules.md` report,
   extended for a mission: the brief, the goal recipe (with the
   assumptions and gaps `/instruct` surfaced), the task list with
   commits, the re-walk result, and the PR link. One report — the
   single surface where the user reviews every call the mission
   made.

## Running a mission under `/goal`

`/mission` runs as far as it can in one invocation, but a real
goal spans many turns. Pair it with Claude Code's built-in `/goal`
loop — see the `/goal` section of `autonomy-rules.md`:

```bash
claude -p "/goal /mission <the goal> — done when <the completion
condition>; stop and report at a hard gate; stop after N turns"
```

`/mission` is the autonomous skill purpose-built for that loop —
the durable `TASK` specs and per-task commits are exactly what let
a looped run resume after a compaction. As `autonomy-rules.md`
requires, the goal condition must carry the hard-gate escape
clause and a turn bound, or the loop will spin against a gate.

## When NOT to use this skill

- **A single task** → `/auto-task`, then `/auto-develop`, then
  `/auto-test`. For one task, `/mission`'s decomposition and
  re-walk are overhead.
- **You want to drive or review as it goes** → run the steps
  yourself in conversation. `/mission` decides everything and
  reports after.
- **Speccing only, no build** → `/auto-task` (one task) or
  `/auto-phase` (a phase).
- **There is no goal — an open-ended question or a problem space,
  not an objective** → `/brainstorm` or `/plan`. `/mission`
  *clarifies* a vague goal itself (Step 3, via `/instruct`), but
  it still needs a goal to aim at — it cannot explore one into
  existence.
- **Shipping — merge, tag, deploy** → `/release`. `/mission`
  delivers a PR and stops; it never merges or deploys.

## What "done" looks like for a /mission session

A `feat/` branch with one commit per completed task, every task's
spec in `tasks/done/`, the verification re-walk green, and a
**draft PR** open for the user to validate — plus one autonomy
report listing every decision the mission made. The goal's
definition of done is *verified*, not assumed. The user reviews
the PR, validates it against the goal, and merges it (or sends it
back). Merging and deploying remain the user's call.
