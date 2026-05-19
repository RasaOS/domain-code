---
name: auto-task
description: Autonomous variant of /task — files a task and expands it to a full, implementation-ready spec without asking any questions. Decides the phase, runs the reconnaissance, drills the requirements, and resolves every judgment call itself, flagging each as an assumption. Triggered when the user wants a task fully spec'd hands-off — e.g. "/auto-task", "spec this autonomously", "auto-spec a task for X", "file and fully spec this without asking me", "just write the task spec yourself".
---

# /auto-task — autonomous task spec

`/task`, run with nobody at the keyboard. The normal `/task` skill
asks which phase, stub-or-spec, and a round of user-context
questions before finalizing. `/auto-task` answers all of them
itself, flags each answer as an assumption, and hands back a
complete spec.

Per CLAUDE.md ethos: calibrated confidence. A decision grounded in
the repo is a decision; a decision that needed product knowledge
the repo doesn't hold is a flagged assumption, surfaced loudly.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — it is
  the contract: decide don't ask, flag every assumption, run to
  completion, stop only at hard gates, end with the autonomy
  report. This SKILL.md only states what's specific to `auto-task`.
- **The operation is `/task`.** Read `task/SKILL.md` and follow its
  **Operation 1** (file a new task) and **Operation 3** (expand a
  stub to a full spec). `/auto-task` does not redefine the work —
  it runs `/task`'s work without the questions.
- **Always a full spec.** `/task` defaults to a stub; `/auto-task`
  always produces a complete spec via `task-template.md`. The
  point of the autonomous variant is a finished, actionable
  artifact — a stub would just defer the questions.
- **Diligence is not skipped.** Operation 3's reconnaissance —
  internal (read the repo) and external (fetch current docs) — is
  done in full. Autonomy means *deciding* the open questions, not
  *skipping* the homework. An autonomous spec built on no recon is
  a bug.
- **Questions become decisions + assumptions.** Every point where
  `/task` would ask — phase placement, the requirements drilling
  in Step 3.5, the user-context check in Step 3.8 — is resolved by
  picking the best-grounded option and recording it as a ⚠️
  assumption in the report.
- **Never auto-commit.** The spec file lands in `tasks/backlog/`
  (or `tasks/triage/` if no phase fits), uncommitted.

## Process

1. **Read `autonomy-rules.md` and `task/SKILL.md`.** The contract
   and the operation.
2. **Run `/task` Operation 1 autonomously.** Determine the phase
   from `tasks/PHASES.md` — pick the best-fitting phase; if none
   fits, file to `tasks/triage/`. Assign the next `TASK-NNN`.
3. **Run `/task` Operation 3 autonomously.** Full reconnaissance
   (internal + external). Where Step 3.5 (requirements drilling)
   and Step 3.8 (user-context check) would put questions to the
   user, decide each — grounded in the recon — and log it as an
   assumption.
4. **Write the full spec** to `tasks/backlog/TASK-NNN-slug.md`
   using `task-template.md`'s shape. Update `tasks/ROADMAP.md`.
5. **Render the autonomy report** (template in `autonomy-rules.md`)
   — the spec path, every assumption, any hard gate hit.

## When NOT to use this skill

- **You want to be consulted** on phase, scope, or the judgment
  calls → use `/task`. That's the whole difference.
- **A whole phase of stubs** needs spec'ing autonomously → use
  `/auto-phase`.
- **Implementing the task** once it's spec'd → use `/auto-develop`.

## What "done" looks like

A complete, implementation-ready spec in `tasks/backlog/` (or
`tasks/triage/`), `ROADMAP.md` updated, uncommitted — plus one
autonomy report listing every decision made on the user's behalf.
The user reviews the report, corrects any wrong assumption by
re-running, and commits.
