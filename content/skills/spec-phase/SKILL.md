---
name: spec-phase
description: Expand every stub in a given phase into a full spec, then propose a working order for the batch. Use when the user wants to commit to a phase as a batch (per the "batch == a phase of tasks" definition) and prep all its tasks for execution. Triggered by "/spec-phase", "spec out Phase N", "prepare Phase N for work", "let's batch up Phase N".
---

# /spec-phase — Prep a phase as a batch

You take a phase from `tasks/ROADMAP.md`, walk through every
stub it contains, and turn each one into a full spec ready for
execution. By the end of the session, the user has a coherent
batch — every task in the phase is either already-shipped, full-
specced, or explicitly deferred — plus a proposed working order.

This is the "commit to a whole phase" flow. Companion to
`/task` (single-task scope) and `/plan` (phase-shaping scope).

## The honest tradeoff

The default doctrine, encoded in most project ROADMAPs and in
`/task` Operation 3, is **just-in-time spec expansion**: stubs
become full specs *as you approach implementation*, not before,
because speccing too far ahead means rewriting work when earlier
phases teach us things.

`/spec-phase` deliberately spec's a whole phase up front. That
trades JIT-flexibility for batch coherence. **Surface this
tradeoff to the user at session start** so they're entering
with eyes open. Acceptable reasons to invoke anyway:

- The phase is small (≤4 tasks) and tightly coupled.
- The phase is being treated as one release.
- The phase is well-understood (e.g., late-phase cleanup, where
  the surface area is known).
- The user explicitly says "I know, do it anyway."

If the user is invoking it on a large phase whose dependencies
they don't yet understand (especially one with tightly-sequenced
subdivisions like `TASK-XXXa/b/c`), **push back once with the
tradeoff before proceeding**. Don't refuse. Just make the cost
legible. Then do what they say.

## Behavior contract

- **Read state first.** `tasks/ROADMAP.md` for the phase
  registry; `tasks/backlog/`, `tasks/active/`, `tasks/completed/` for
  current state. Never spec from memory.
- **One phase per session.** If the user wants more than one
  phase prep'd, do them sequentially. Don't multiplex.
- **Stubs only.** Tasks already in `tasks/active/` or
  `tasks/completed/`, or backlog tasks already in full-spec form,
  are skipped. Show them in the rollup but don't re-spec them.
- **Don't commit during the session.** Drafts are written to
  `tasks/backlog/<file>.md` (overwriting the stub in place).
  Show the user the result; they decide when to commit.
- **Don't open branches or PRs.** That's per-task work, done
  outside this skill. The deliverable here is filesystem state
  + a proposed working order.
- **Respect dependency hints.** If a task has been deliberately
  split into siblings (e.g. `TASK-XXXa/b/c`), the split exists
  because shipping the original as one lift was the wrong move.
  Honor the subdivision and call out the hard sequencing it
  implies.

## The flow

### Step 1 — Identify the phase

User passes the phase as arg (e.g., `/spec-phase 3` or
`/spec-phase Phase 3`). If ambiguous or missing:

1. List the phases from `ROADMAP.md` (just names + a one-line
   scope each).
2. Ask which one.
3. Wait for an answer. Don't pick.

### Step 2 — Snapshot the phase

Produce a one-screen rollup:

```markdown
# Phase N — <phase name>

**Scope.** <copy the phase's scope paragraph from ROADMAP.md>

| ID | Title | State | Type |
|---|---|---|---|
| TASK-... | ... | ✅ Done | — |
| TASK-... | ... | 🚧 Active | 📄 Spec |
| TASK-... | ... | 📋 Backlog | 📄 Spec |
| TASK-... | ... | 📋 Backlog | 📝 Stub |
```

Then state plainly: **"X stubs to expand. Working through them
one at a time."** Surface the tradeoff (see "Honest tradeoff"
above) if the phase is large or complex. Wait for the user to
confirm before starting.

### Step 3 — Expand each stub, one at a time

For each stub, in the order the phase lists them in ROADMAP.md,
**run the full `/task` Operation 3 flow** — not just the
questions. That includes:

- **Internal reconnaissance** — read CLAUDE.md, the stub,
  referenced files, existing patterns, likely-touched files.
- **External reconnaissance** — fetch current official
  documentation (`developer.apple.com`, `developer.android.com`,
  `react.dev`, framework docs, etc.) for the APIs this task
  will touch. Don't draft framework code from memory.
- **Synthesize a recon report** — show the user what you
  found before drafting.
- **Requirements drilling** — sharpen acceptance bar, edge
  cases, constraints, test scenarios.
- **Per-file rationale** — what changes WHERE and WHY.
- **Draft the full spec** via `task-template.md`.
- **Show, sign-off, write** to `tasks/backlog/<file>.md`.

See `/task` Operation 3 for the detailed sub-steps and concrete
doc-source examples per platform.

This is **heavier than the original `/spec-phase` flow**.
That's intentional — Chazz's task-builder→task-developer
discipline means the up-front recon is where the value lands.
Surface the cost when the phase is large: *"This phase has 7
stubs. Full recon per stub means ~10–20 min per task; this
session will likely take an hour or two. Want to spec all 7
or pick a subset?"*

After each spec is written, move to the next stub.

If the user pauses or breaks the session, leave the partially-
specced files in place. They're already saved. The session
resumes by re-reading current state.

### Step 4 — Propose the working order

After all stubs are either expanded or explicitly deferred:

1. **Re-read every spec in the phase** (full-specs, both newly-
   expanded and pre-existing).
2. **Identify dependencies** between tasks. Look for:
   - Hard sequencing (X must ship before Y because Y references
     a primitive only X creates).
   - Soft ordering (X teaches us something useful for Y; doing
     X first reduces rework risk).
   - Independence (X and Y don't touch each other; can be
     parallelized if multiple agents are available).
3. **Propose an ordered list** with reasoning:

```markdown
## Suggested working order

1. **TASK-XXX — <title>** — <one-line reason this is first>
2. **TASK-YYY — <title>** — <reason; e.g. "depends on XXX's
   primitive", "independent — can run in parallel with YYY">
3. ...

**Hard sequencing constraints**:
- TASK-A blocks TASK-B because <reason>
- TASK-C blocks TASK-D because <reason>

**Parallelizable subsets** (if any):
- {TASK-X, TASK-Y} can run concurrently — they don't share files
  or models.
```

4. **Propose a release strategy**:
   - One ship at the end? `vX.Y+1.0` with all phase tasks?
   - Split into two ships? Where to draw the line?
   - Phase shipped piecemeal as each task lands? When and why.
5. **Wait for confirmation** on the working order. The user may
   override.

### Step 5 — Closing report

```markdown
# /spec-phase — Phase N prepped

**Phase**: <name>
**Tasks in phase**: <count> · already done: <n> · already spec'd: <n>
**Stubs expanded this session**: <n>
**Stubs left as stubs** (deferred): <n>

**Working order** (suggested):
1. TASK-XXX
2. TASK-YYY
...

**Release strategy** (suggested): <one-shot vX.Y.0 / split into
vX.Y / vX.Y+1 / piecemeal>

**Files written**:
- tasks/backlog/TASK-XXX-slug.md (stub → full spec)
- tasks/backlog/TASK-YYY-slug.md (stub → full spec)

**Uncommitted.** Run `git status` to see the draft state. Commit
when you're ready to lock in the batch.

**Next step**: start TASK-<first-in-order> via `/task` or just
begin the implementation.
```

## What you must NOT do

- **Don't write code.** This skill produces specs, not
  implementations.
- **Don't commit.** The user owns the commit gate. Drafts are
  uncommitted by design.
- **Don't open branches or PRs.** Per-task plumbing happens
  outside this skill.
- **Don't promote tasks across phases** mid-session. If a stub
  turns out to belong elsewhere, surface that as an observation
  and hand off to `/task` (which owns phase moves).
- **Don't subdivide an existing task into siblings** without
  explicit ask. If a stub looks too big, *say so* — don't
  silently spawn TASK-XXXa/b/c.
- **Don't auto-spec phases the user didn't ask for.** One phase
  per invocation.
- **Don't skip the tradeoff surface** at session start. The
  user invoking this is consciously trading JIT-spec-flexibility
  for batch coherence. Naming the trade keeps it honest.

## When NOT to use this skill

- **Single task** → `/task` (Operation 3: expand one stub).
- **Strategic phase shaping** (renaming, re-scoping, splitting
  into multiple phases) → `/plan`.
- **Just viewing a phase's tasks** → `/roadmap` or `/backlog`.
- **Implementing a task** → just start; this skill doesn't
  implement.
- **Speccing a single task in advance because it's coming up
  next** → `/task` is the right tool. `/spec-phase` is for
  *committing to a phase as a unit*, not "spec this one task
  early."

## What "done" looks like for a /spec-phase session

- Every stub in the chosen phase is either:
  - Expanded into a full spec, written to disk, **or**
  - Explicitly deferred with the user's sign-off.
- A proposed working order is on the table.
- A proposed release strategy is on the table.
- The worktree is dirty with draft spec files; the user holds
  the commit gate.
- The user knows the next concrete action ("start TASK-X").
