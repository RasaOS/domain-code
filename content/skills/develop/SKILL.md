---
name: develop
description: Build a task with the person, held to the flow — read the sources of truth, gate the task (audit and plan links, no unfilled template, UI and Data blocks, no locked contract), start it, build to the plan, open the PR, and reconcile after the merge so the task reaches completed. Triggered by "/develop", "develop TASK-NNN", "start building this task", "work this task".
---

# /develop — build a task, held to the flow

The conversational counterpart of `/auto-develop`. The flow is
audit → plan → task → develop; this skill is the last step and
refuses to start a task the earlier steps left unfinished.

It moves the task `backlog → active` (`start`). It does **not** run
`submit` or `pass`: `/open-pr` submits, and `/reconcile` passes once
the PR has merged. That is the one sanctioned path to `completed`.

## Steps

1. **Sources of truth.** `bash .claude/skills/develop/develop.sh sources`.
   Output: a first line `tenant: none` or `tenant: <absolute path>`,
   then one line per source that exists (the tenant's `contracts/`,
   `conventions/`, `decisions/`, `design/`, `CLAUDE.md`, then the
   repo's `CLAUDE.md` and `contracts/`). Read them. The tenant is
   named by `RASA_TENANT` or a `tenant:` line in
   `.claude/rasa-deployment.md`; there is no search. A tenant
   contract wins over the repo.
2. **Gate.** `bash .claude/skills/develop/develop.sh gate <id>`.
   Exit 3 lists every reason; fix each, then re-run. It checks:
   - no unfilled `<...>` in the task body (code fences, inline code,
     `## Blocker` and `## Notes` are ignored), and not stub depth (a task with no checkbox under
     `## Acceptance criteria` is expanded first);
   - a task carrying `x-plan`: `x-audit` and `x-plan` exist and
     validate (`audit.sh validate`, `plan.sh validate`), and it has a
     `## Data` section. `priority: now` is exempt. A task with no
     `x-plan` (hotfix, bug, mission) has no audit/plan link to check;
     the gate says so on a `note:` line;
   - `x-ui: true`: a filled `## UI/UX and screens` section;
   - a locked contract named on the Data block's *Contract stamp*
     line stops the task.

   The UI and Data blocks are the files `plan/ui-section.md` and
   `plan/data-section.md`; paste them into the task body before
   `## Blocker` and fill them (`Not touched: <why>` when they do not
   apply). They are enforced here, in `/develop`, until the task
   templates ship them.
   A non-exempt task with no `x-plan` is linked before it starts:
   `bash .claude/skills/develop/develop.sh link <id> --audit docs/audits/<file>.md --plan docs/plans/<file>.md [--ui true|false]`
   writes `x-audit`, `x-plan` and `x-ui` through the frontmatter
   library, and refuses a path that does not exist or does not
   validate. `/task` does not write these keys. An edit to a task body
   or frontmatter by hand drifts the ledger's `updated` check the same
   day; `.claude/bin/check-tasks --fix` accepts it.
3. **Start.** `bash .claude/skills/develop/develop.sh start <id>`
   (gate, then `bin/task start` as the actor from `task-enforce.sh who`).
4. **Build to the plan.** On the task's branch from the latest trunk
   (`open-pr.sh branch`). For UI work, `ui-rules.md` and `flow-rules.md`:
   each size class, back stack, five states, feedback, accessibility,
   the Design source's tokens, visuals. Platform numbers are in the
   conventions file. Tests with the change; the build and the
   verification command from `CLAUDE.md`, results shown.
5. **Open the PR.** `/open-pr <id>`; it submits the task to review.
6. **After the merge.** Run `/reconcile`: it runs the done-gate on
   the trunk and lands the pass, so the task reaches `completed`
   with no hand step.

## Never

- Move a task file by hand, or run `pass` here.
- Edit around a gate failure: fix the task, the plan or the audit.
- Treat a missing tenant as an error: `tenant: none` is a normal answer.
