---
name: auto-task
description: Autonomous variant of /task — files a `change` task and expands it to a full, implementation-ready spec without asking any questions. Decides the phase, runs the reconnaissance, drills the requirements, and resolves every judgment call itself, flagging each as an assumption. For a `defect` use /auto-bug; for urgent prod fixes use /auto-hotfix. Triggered when the user wants a `change` task fully spec'd hands-off — e.g. "/auto-task", "spec this autonomously", "auto-spec a task for X", "file and fully spec this without asking me", "just write the task spec yourself".
---

# /auto-task — autonomous change task spec

`/task` (**File a task** as a `change`, then **Expand**), run
with nobody at the keyboard. The normal `/task` skill asks which
phase, outline-or-full, and a round of user-context questions
before finalizing. `/auto-task` answers all of them itself,
flags each answer as an assumption, and hands back a complete
spec.

**This skill files only `change` tasks.** For a `defect`
(fixing broken behavior with reproduction steps), use
`/auto-bug`. For a hotfix (an urgent prod fix — a `defect` with
`priority: now`), use `/auto-hotfix`. Per `code-task-rules.md`
§3–§4, the three are distinct work.

Per CLAUDE.md ethos: calibrated confidence. A decision grounded in
the repo is a decision; a decision that needed product knowledge
the repo doesn't hold is a flagged assumption, surfaced loudly.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — it is
  the contract: decide don't ask, flag every assumption, run to
  completion, stop only at hard gates, end with the autonomy
  report. This SKILL.md only states what's specific to `auto-task`.
- **The operation is `/task`.** Read `task/SKILL.md` and follow its
  **File a task** and **Expand an outline into a full task**
  (`task/expanding-a-task.md`). `/auto-task` does not redefine the
  work — it runs `/task`'s work without the questions.
- **Always a full spec.** `/task` defaults to an outline;
  `/auto-task` always produces a complete spec in the shape of
  `.claude/task-templates/change.md`. The point of the autonomous
  variant is a finished, actionable artifact — a stub would just
  defer the questions.
- **Diligence is not skipped.** The expansion's reconnaissance —
  internal (read the repo) and external (fetch current docs) — is
  done in full. Autonomy means *deciding* the open questions, not
  *skipping* the homework. An autonomous spec built on no recon is
  a bug.
- **Questions become decisions + assumptions.** Every point where
  `/task` would ask — phase placement, drilling the acceptance
  criteria in step 9, the questions only the user can answer in
  step 10 — is resolved by picking the best-grounded option and
  recording it as a ⚠️ assumption in the report.
- **Docs landing is the default.** Per `autonomy-rules.md`
  "Exception 2", `/auto-task` lands what it wrote — the spec, its
  `tasks/history.tsv` and `tasks/ROADMAP.md` lines, and the run
  record — with `land.sh docs`: a PR from the latest trunk that
  merges itself after CI. **Never code:** the landing names only
  those files, never `tasks/tasks.config.yml` or anything else;
  `land.sh` classifies each one and refuses a code-class file
  (exit 3), with no bypass. Other changes in the working tree
  neither block it nor ride along — landing is path-scoped.

## Process

1. **Read `autonomy-rules.md` and `task/SKILL.md`.** The contract
   and the operation.
2. **Run `/task`'s File a task autonomously, as a `change`.**
   Determine the phase from the `## Phase` headings and scope
   paragraphs in `tasks/ROADMAP.md` — pick the best-fitting phase;
   if none fits, file to `tasks/triage/` (omit `--phase`). Then
   sync and file — ids come from the local ledger, so it must hold
   the latest trunk (report a non-zero sync exit; never retry it
   blindly):

   ```bash
   bash .claude/skills/land/land.sh sync
   .claude/bin/task new --type change --phase <P> \
     --by "$(bash .claude/skills/task-enforce/task-enforce.sh who)" "<title>"
   ```

   The actor is `$RASA_ACTOR` folded to a lowercase handle. The
   command allocates the next `TASK-NNN` and writes the
   `tasks/history.tsv` line and, with a phase, the
   `tasks/ROADMAP.md` line. (For a `defect` or a hotfix, the user
   should invoke `/auto-bug` or `/auto-hotfix` instead.)
3. **Run `/task`'s Expand autonomously**
   (`task/expanding-a-task.md`). Full reconnaissance (internal +
   external). Where step 9 (drilling the acceptance criteria) and
   step 10 (the questions only the user can answer) would put
   questions to the user, decide each — grounded in the recon —
   and log it as an assumption.
4. **Write the full spec** into the file the command reported
   (`tasks/backlog/TASK-NNN-slug.md`, or `tasks/triage/…`), in
   `.claude/task-templates/change.md`'s shape, then run
   `.claude/bin/check-tasks --fix` (I-34).
5. **Land the spec** (per `autonomy-rules.md` Exception 2). Once
   the spec is written and validated and the run record is closed
   (`.claude/skills/runs/runs.sh close`, per `autonomy-rules.md`),
   land the spec, the ledger and the run record together:

   ```bash
   bash .claude/skills/land/land.sh docs --skill auto-task --title "spec TASK-NNN: <title>" --tasks TASK-NNN -- tasks/backlog/TASK-NNN-slug.md tasks/history.tsv tasks/ROADMAP.md tasks/runs/<RUN-id>.md
   ```

   Name the file `task new` reported (`tasks/triage/…` for a
   triage filing, which also leaves `tasks/ROADMAP.md` out).
   `land.sh` does the rest — the classification (a program, no
   bypass), the sync with the latest trunk, the PR, CI and the
   merge pinned to the verified head. Exit 4 (no `gh`): finish
   with the session's GitHub tooling per `land/SKILL.md` "Without
   `gh`". Exits 5/6/7: report, never retry blindly. As a step of
   `/mission`, `/self-heal` or `/self-improve`, skip this: the
   orchestrator's branch and PR carry the spec.
6. **Render the autonomy report** (template in `autonomy-rules.md`)
   — the spec path, every assumption, any hard gate hit, and one
   landing line: `Landed: PR #N merged` or
   `Not landed: exit N — <message>`.

## When NOT to use this skill

- **You want to be consulted** on phase, scope, or the judgment
  calls → use `/task`. That's the whole difference.
- **A whole phase of stubs** needs spec'ing autonomously → use
  `/auto-phase`.
- **Implementing the task** once it's spec'd → use `/auto-develop`.

## What "done" looks like

A complete, implementation-ready spec in `tasks/backlog/` (or
`tasks/triage/`), `ROADMAP.md` updated when it has a phase, plus
one autonomy report listing every decision made on the user's
behalf.

Landed: the spec, its ledger lines and the run record are on the
trunk via a merged `land.sh docs` PR, the team has visibility, the
autonomy report carries the landing line. The user reviews the
report and the PR after the fact; corrections happen by re-running
or by amending the spec.

Not landed: the report names the exit code and what is still open
(a PR waiting on CI or branch protection, or files still in the
working tree). In a composed run, the orchestrator's PR carries
the spec instead.
