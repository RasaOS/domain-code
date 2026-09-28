---
name: auto-develop
description: Autonomously implement a task spec — read the spec, write the code, follow the repo's patterns, and run the build, making every implementation decision without asking. Each judgment call is flagged as an assumption. Stops at hard gates (locked contracts, gated files); works on the task's branch from the latest trunk and lands the result as a draft PR it never merges. Triggered when the user wants a spec built hands-off — e.g. "/auto-develop", "implement this task autonomously", "build TASK-NNN yourself", "develop the active task without asking me".
---

# /auto-develop — autonomous implementation

Takes a task spec and builds it. The Element has no non-autonomous
`/develop` skill — implementation normally happens in open
conversation with the user. `/auto-develop` is the hands-off path:
given a spec, it implements the code to completion and hands back a
draft PR on the task's branch plus a report of every call it made.

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
- **Work begins with `start`.** A spec still in `tasks/backlog/`
  moves first, before any code:
  `.claude/bin/task start <id> --by "$(bash .claude/skills/task-enforce/task-enforce.sh who)"` —
  the actor is `$RASA_ACTOR` folded to a lowercase handle, and
  `active/` is a branch being worked (`code-task-rules.md` §2).
  Never move the file by hand. `/auto-develop` never runs
  `submit` or `pass`: those follow the PR and the merge.
- **Stay inside the spec's file list.** The spec's "Artifacts
  expected to change" is the boundary. If implementation
  genuinely needs a file outside it, that's a flagged assumption
  — note it, proceed only if it's non-gated and safe.
- **Bound by `craft-rules.md` and `task-rules.md`.** Follow the
  repo's existing patterns, naming, type discipline, error
  handling. Autonomy decides *what* to write; the craft rules
  still decide *how well*.
- **Run the verification.** After implementing, run the project's
  build / verification (per `CLAUDE.md`, or `/build`'s compile check —
  a pipeline `/build` records a build and refuses an uncommitted
  tree, so it belongs after the commit, not here). A run that
  ends with a failing build is not done — fix it, or if it can't
  be fixed, that's a hard blocker: stop and report.
  **Show the result, do not summarize it.** The verbatim command,
  its exit code and real output go in the report's Evidence
  section. Under `/goal` the evaluator reads only the transcript,
  so "the build is green" is a claim it has no way to check.
- **Hard gates stop the run.** A locked `/contract`, a gated file,
  anything destructive — stop and surface per `autonomy-rules.md`.
  A gated file is a blocker (`task-rules.md` §13): write the
  task's `## Blocker`, then `.claude/bin/task block <id>`.
  Never merge, never deploy. It commits only to the task's
  branch, through a draft PR (`autonomy-rules.md` Exception 5:
  autonomous code skills commit to the task branch and open a
  draft PR; the merge is always a reviewer's).

## Process

1. **Read `autonomy-rules.md`, `craft-rules.md`, and the task
   spec.** Plus `CLAUDE.md` for project facts and the verification
   command.
2. **Get onto the task's branch, from the latest trunk.** On the
   trunk, before any code (report a non-zero exit; never retry it
   blindly):

   ```bash
   bash .claude/skills/land/land.sh sync
   bash .claude/skills/open-pr/open-pr.sh branch <TASK-ID> --slug <slug>
   ```

   The work then sits on `task/TASK-NNN-<slug>` (`hotfix/…` for a
   `priority: now` defect), never on the trunk, where it would
   strand. Derive the slug from the task title. Already on a side
   branch (a `hotfix/` branch, or the orchestrator's in a composed
   run): stay on it.
3. **Reconnoitre.** Read the files in the spec's file list and the
   patterns they sit in. Implementation decisions are grounded in
   the real code, not invented.
4. **Implement.** Work through the spec's acceptance criteria and
   file list. Each implementation choice the spec left open — a
   decision, flagged as an assumption.
5. **Verify.** Run the build / verification. Fix what breaks. If a
   genuine blocker remains, stop per the hard-gate rule.
6. **Land it as a draft PR** (`autonomy-rules.md` Exception 5).
   Once the verification is green and the run record is closed
   (`.claude/skills/runs/runs.sh close`), name every file the run
   changed, plus the run record:

   ```bash
   bash .claude/skills/land/land.sh pr --skill auto-develop --title "<task title>" --tasks TASK-NNN --draft --summary "<what>" -- <every file changed> tasks/runs/<RUN-id>.md
   ```

   It never merges: after `/auto-test`, `/open-pr` marks it ready
   with the `code-task-rules.md` §10 body, and a reviewer merges.
   Exit 4 (no `gh`): finish with the session's GitHub tooling per
   `land/SKILL.md` "Without `gh`". Exits 5/6/7: report, never
   retry blindly. As a step of `/mission`, `/self-heal` or
   `/self-improve`, skip this: the orchestrator's branch and PR
   carry the files.
7. **Render the autonomy report** — files changed, the
   verification result **as real command output in the Evidence
   section**, every assumption, any hard gate hit, and one
   landing line: `PR: #N open (draft), never merged by this skill`
   or `Not landed: exit N — <message>`.

## When NOT to use this skill

- **You want to drive or review the implementation as it goes** →
  just implement normally, in conversation.
- **No spec exists yet** → use `/auto-task` (or `/task`) first.
- **Writing or running the tests** → use `/auto-test`.
- **Shipping it** → release is always user-confirmed; see
  `git-flow-rules.md`. `/auto-develop` never merges or deploys.

## What "done" looks like

The task spec is implemented on the task's branch — code written to
the repo's standard, the verification green — in a draft PR this
skill never merges (in a composed run, the orchestrator's PR
carries it). One autonomy report lists the files changed, the
build result, every implementation decision made, and the PR. The
user reviews, runs `/auto-test` or their own checks, and
`/open-pr` marks the PR ready; the merge is a reviewer's.
