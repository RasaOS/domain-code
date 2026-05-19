---
name: auto-phase
description: Autonomous variant of /spec-phase — expands every stub in a named phase to a full, implementation-ready spec without asking any questions. Decides each spec's open questions itself and flags them as assumptions, then proposes a working order. Triggered when the user wants a whole phase spec'd hands-off — e.g. "/auto-phase", "spec out the whole phase autonomously", "auto-spec phase N", "expand every stub in this phase without asking me".
---

# /auto-phase — autonomous phase spec

`/spec-phase`, run with nobody at the keyboard. The normal
`/spec-phase` walks every stub in a phase and expands each to a
full spec, consulting the user along the way. `/auto-phase` does
the same walk and resolves every question itself, flagging each
decision, then hands back the full set of specs plus a proposed
working order.

Per CLAUDE.md ethos: no narratives. The report says plainly what
was decided and what's still uncertain — one honest review surface
for the whole phase.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — the
  contract, the hard-gate list, the report template. This
  SKILL.md states only what's specific to `auto-phase`.
- **The operation is `/spec-phase`.** Read `spec-phase/SKILL.md`
  and follow it — the phase walk, per-stub expansion, dependency
  analysis, and working-order proposal. `/auto-phase` runs that
  work without the questions.
- **Every stub becomes a full spec.** For each stub in the named
  phase, run the same expansion `/auto-task` does — full
  reconnaissance, questions resolved as flagged decisions.
- **Diligence per stub is not skipped.** Each spec gets real
  recon. A phase of twelve specs is twelve real reconnaissance
  passes, not twelve guesses.
- **One report for the whole phase.** Don't render a report per
  stub. The autonomy report at the end covers every spec, groups
  the assumptions by task, and lists the proposed working order.
- **Never auto-commit.** All spec files land uncommitted.

## Process

1. **Read `autonomy-rules.md` and `spec-phase/SKILL.md`.**
2. **Identify the phase.** From the user's argument, or — if
   absent — the current active phase in `tasks/PHASES.md`.
3. **Walk every stub in the phase.** For each, run the autonomous
   expansion: full recon, open questions decided and flagged,
   full spec written via `task-template.md`.
4. **Propose a working order** with dependency analysis, as
   `/spec-phase` does.
5. **Render one autonomy report** covering the whole phase — specs
   written, assumptions grouped by task, working order, any hard
   gate hit.

## When NOT to use this skill

- **You want to review each spec as it's drafted** → use
  `/spec-phase`.
- **A single task**, not a whole phase → use `/auto-task`.
- **Implementing the phase's tasks** once spec'd → use
  `/auto-develop` per task.

## What "done" looks like

Every stub in the named phase is now a full, implementation-ready
spec — uncommitted — with a proposed working order and one
autonomy report covering every decision made across the phase. The
user reviews once, corrects any wrong assumption by re-running that
task, and commits.
