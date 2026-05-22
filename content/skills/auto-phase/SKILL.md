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
- **Spec-file fast-path is the default.** Per
  `autonomy-rules.md` "Exception 2", `/auto-phase` auto-commits
  the phase's new specs and auto-merges a `spec-only` PR to
  `main` when the working tree contains *only* allowlisted spec
  files (`tasks/**/*.md`, `tasks/PHASES.md`, `tasks/ROADMAP.md`).
  A whole-phase fast-path is a *single* PR carrying every new
  spec, not one PR per spec. If any non-spec file is dirty, fall
  back to "leave uncommitted" — and the autonomy report says
  why.
- **Watch for phase-collision.** Other in-flight branches may
  already have task numbers reserved against the same phase.
  `/auto-phase` assigns `TASK-NNN` sequentially from
  `tasks/ROADMAP.md` — if a feature branch has reserved numbers
  the local roadmap doesn't yet know about, collisions surface
  on merge. The fast-path doesn't make this worse than committing
  by hand; just be aware.

## Process

1. **Read `autonomy-rules.md` and `spec-phase/SKILL.md`.**
2. **Identify the phase.** From the user's argument, or — if
   absent — the current active phase in `tasks/PHASES.md`.
3. **Walk every stub in the phase.** For each, run the autonomous
   expansion: full recon, open questions decided and flagged,
   full spec written via `task-template.md`.
4. **Propose a working order** with dependency analysis, as
   `/spec-phase` does.
5. **Spec-file fast-path** (per `autonomy-rules.md` Exception 2).
   Check the working tree:
   - If every dirty file matches the spec-file allowlist: create
     a `spec/PHASE-<id>-<slug>` branch from a fresh `main`,
     commit all of the phase's new specs in a single commit
     (`PHASE-<id> specs — <title>` with each task listed in the
     body), push, open a PR labeled `spec-only` with the autonomy
     report's assumptions and working order in the body, and
     merge via `gh pr merge --squash --delete-branch`. If branch
     protection refuses the merge, leave the PR open and report
     it.
   - If any non-spec file is dirty: skip the fast-path, leave
     every spec uncommitted, and note why in the autonomy report.
6. **Render one autonomy report** covering the whole phase — specs
   written, assumptions grouped by task, working order, any hard
   gate hit, and the fast-path result.

## When NOT to use this skill

- **You want to review each spec as it's drafted** → use
  `/spec-phase`.
- **A single task**, not a whole phase → use `/auto-task`.
- **Implementing the phase's tasks** once spec'd → use
  `/auto-develop` per task.

## What "done" looks like

Every stub in the named phase is now a full, implementation-ready
spec, with a proposed working order and one autonomy report
covering every decision made across the phase.

If the spec-file fast-path engaged: every new spec is on `main`
via a single merged `spec-only` PR. The team has the full phase
visible. The user reviews the report and the PR after the fact.

If the fast-path was skipped (non-spec dirty files): all specs
sit uncommitted — same as the pre-v0.32.0 behavior. The user
reviews and commits manually.
