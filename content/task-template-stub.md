---
id: TASK-XXX
category: stub
phase: <phase-id-or-null>
status: triage | backlog | active | blocked | completed
owner: unassigned       # accountable human/team/agent — not the per-run actor
blocked_by:             # comma-separated task ids, e.g. TASK-012, TASK-014
outcome: unrecorded     # unrecorded | shipped | reverted | superseded
filed: <YYYY-MM-DD HH:MM UTC>
origin: manual          # manual | auto-fallback | auto-guard
---

# TASK-XXX: <short title>

> Stub-category task. **Light tracking only.** No full spec is
> expected. The category signals: this exists to be visible and
> counted, not to be implemented from a contract.
>
> If this task grows enough that a full implementation contract
> would help, change `category:` to `spec` (or `bug`) and follow
> `task-template.md` (or `task-template-bug.md`) instead.

## What this is

One or two sentences. The smallest description that lets a
reviewer understand what the task represents.

## Notes

Anything worth keeping near the task — context, who flagged it,
adjacent tasks. Free-form. Bullets, prose, links, all fine.

-
