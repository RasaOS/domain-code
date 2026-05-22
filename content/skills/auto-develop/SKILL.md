---
name: auto-develop
description: Autonomously implement a task spec — read the spec, write the code, follow the repo's patterns, and run the build, making every implementation decision without asking. Each judgment call is flagged as an assumption. Stops at hard gates (locked contracts, gated files) and never commits. Triggered when the user wants a spec built hands-off — e.g. "/auto-develop", "implement this task autonomously", "build TASK-NNN yourself", "develop the active task without asking me".
---

# /auto-develop — autonomous implementation

Takes a task spec and builds it. The kit has no non-autonomous
`/develop` skill — implementation normally happens in open
conversation with the user. `/auto-develop` is the hands-off path:
given a spec, it implements the code to completion and hands back a
working tree plus a report of every call it made.

This is a real expansion of what the kit's skills do. It earns its
keep only when the spec is genuinely complete — `/auto-develop` is
as good as the spec it's handed.

Per CLAUDE.md ethos: build it right the first time. Autonomy is no
excuse for sloppy work — `craft-rules.md` applies in full.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — the
  contract, the hard-gate list, the report template. This
  SKILL.md states only what's specific to `auto-develop`.
- **The spec is the contract.** `/auto-develop` implements a task
  spec — a file in `tasks/active/` or `tasks/backlog/`, or the
  task named by the user. If no spec exists, stop: this skill
  implements specs, it doesn't invent them. Point the user at
  `/auto-task`.
- **Stay inside the spec's file list.** The spec's "Files expected
  to change" is the boundary. If implementation genuinely needs a
  file outside it, that's a flagged assumption — note it, proceed
  only if it's non-gated and safe.
- **Bound by `craft-rules.md` and `task-rules.md`.** Follow the
  repo's existing patterns, naming, type discipline, error
  handling. Autonomy decides *what* to write; the craft rules
  still decide *how well*.
- **Run the verification.** After implementing, run the project's
  build / verification (per `CLAUDE.md` or `/build`). A run that
  ends with a failing build is not done — fix it, or if it can't
  be fixed, that's a hard blocker: stop and report.
- **Hard gates stop the run.** A locked `/contract`, a gated file,
  anything destructive — stop and surface per `autonomy-rules.md`.
  Never auto-commit, never merge, never deploy.

## Process

1. **Read `autonomy-rules.md`, `craft-rules.md`, and the task
   spec.** Plus `CLAUDE.md` for project facts and the verification
   command.
2. **Reconnoitre.** Read the files in the spec's file list and the
   patterns they sit in. Implementation decisions are grounded in
   the real code, not invented.
3. **Implement.** Work through the spec's acceptance criteria and
   file list. Each implementation choice the spec left open — a
   decision, flagged as an assumption.
4. **Verify.** Run the build / verification. Fix what breaks. If a
   genuine blocker remains, stop per the hard-gate rule.
5. **Render the autonomy report** — files changed, the
   verification result, every assumption, any hard gate hit.

## When NOT to use this skill

- **You want to drive or review the implementation as it goes** →
  just implement normally, in conversation.
- **No spec exists yet** → use `/auto-task` (or `/task`) first.
- **Writing or running the tests** → use `/auto-test`.
- **Shipping it** → release is always user-confirmed; see
  `git-flow-rules.md`. `/auto-develop` never merges or deploys.

## What "done" looks like

The task spec is implemented in the working tree — code written to
the repo's standard, the verification green — uncommitted. One
autonomy report lists the files changed, the build result, and
every implementation decision made. The user reviews, runs
`/auto-test` or their own checks, and commits.
