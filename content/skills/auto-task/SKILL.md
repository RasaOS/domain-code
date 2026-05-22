---
name: auto-task
description: Autonomous variant of /task — files a Spec-category task and expands it to a full, implementation-ready spec without asking any questions. Decides the phase, runs the reconnaissance, drills the requirements, and resolves every judgment call itself, flagging each as an assumption. For Bug-category tasks use /auto-bug; for urgent prod fixes use /auto-hotfix. Triggered when the user wants a Spec task fully spec'd hands-off — e.g. "/auto-task", "spec this autonomously", "auto-spec a task for X", "file and fully spec this without asking me", "just write the task spec yourself".
---

# /auto-task — autonomous Spec-category task spec

`/task` (Operation 1, Spec category), run with nobody at the
keyboard. The normal `/task` skill asks which phase, stub-or-spec,
and a round of user-context questions before finalizing.
`/auto-task` answers all of them itself, flags each answer as an
assumption, and hands back a complete spec.

**This skill files only Spec-category tasks.** For Bug-category
tasks (fixing broken behavior with reproduction steps), use
`/auto-bug`. For Hotfix-category tasks (urgent prod fixes), use
`/auto-hotfix`. Per `task-rules.md` "Categories", the three are
distinct work types with distinct templates.

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
- **Spec-file fast-path is the default.** Per
  `autonomy-rules.md` "Exception 2", `/auto-task` auto-commits the
  spec and auto-merges a `spec-only` PR to `main` when the
  working tree contains *only* allowlisted spec files
  (`tasks/**/*.md`, `tasks/PHASES.md`, `tasks/ROADMAP.md`). If
  any non-spec file is dirty, fall back to "leave uncommitted" —
  the file lands in `tasks/backlog/` (or `tasks/triage/`), the
  user commits manually, and the autonomy report notes why the
  fast-path was skipped.

## Process

1. **Read `autonomy-rules.md` and `task/SKILL.md`.** The contract
   and the operation.
2. **Run `/task` Operation 1 autonomously, Spec category.** Set
   `category: spec` in frontmatter. Determine the phase from
   `tasks/PHASES.md` — pick the best-fitting phase; if none fits,
   file to `tasks/triage/`. Assign the next `TASK-NNN`. (For Bug
   or Hotfix category, the user should invoke `/auto-bug` or
   `/auto-hotfix` instead.)
3. **Run `/task` Operation 3 autonomously.** Full reconnaissance
   (internal + external). Where Step 3.5 (requirements drilling)
   and Step 3.8 (user-context check) would put questions to the
   user, decide each — grounded in the recon — and log it as an
   assumption.
4. **Write the full spec** to `tasks/backlog/TASK-NNN-slug.md`
   using `task-template.md`'s shape. Update `tasks/ROADMAP.md`.
5. **Spec-file fast-path** (per `autonomy-rules.md` Exception 2).
   Check the working tree:
   - If every dirty file matches the spec-file allowlist
     (`tasks/**/*.md`, `tasks/PHASES.md`, `tasks/ROADMAP.md`) and
     nothing else is dirty: create a `spec/TASK-NNN-slug` branch
     from a fresh `main`, commit the spec there
     (`TASK-NNN spec — <title>`), push, open a PR labeled
     `spec-only` with the autonomy report's assumptions in the
     body, and merge via `gh pr merge --squash --delete-branch`.
     If branch protection refuses the merge, leave the PR open
     and report it.
   - If any non-spec file is dirty: skip the fast-path, leave the
     spec uncommitted, and note in the autonomy report that the
     fast-path was skipped because of `<files>`.
6. **Render the autonomy report** (template in `autonomy-rules.md`)
   — the spec path, every assumption, any hard gate hit, and the
   fast-path result: the merged PR URL, or "fast-path skipped —
   non-spec files in working tree", or "PR open, merge blocked
   by branch protection".

## When NOT to use this skill

- **You want to be consulted** on phase, scope, or the judgment
  calls → use `/task`. That's the whole difference.
- **A whole phase of stubs** needs spec'ing autonomously → use
  `/auto-phase`.
- **Implementing the task** once it's spec'd → use `/auto-develop`.

## What "done" looks like

A complete, implementation-ready spec in `tasks/backlog/` (or
`tasks/triage/`), `ROADMAP.md` updated, plus one autonomy report
listing every decision made on the user's behalf.

If the spec-file fast-path engaged: the spec is on `main` via a
merged `spec-only` PR, the team has visibility, the autonomy
report carries the PR URL. The user reviews the report and the
PR after the fact; corrections happen by re-running or by
amending the spec.

If the fast-path was skipped (non-spec dirty files): the spec is
in the working tree, uncommitted — same as the pre-v0.32.0
behavior. The user commits manually.
