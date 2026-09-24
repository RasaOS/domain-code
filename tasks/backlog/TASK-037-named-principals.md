---
id: TASK-037
type: change
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P6
---
# TASK-037: Named principals in the tenant roster

**User story.** As an **operator**, I want **decisions to have an owner who is not "whoever is at the terminal"** so that **business decisions the agents correctly flag have somewhere to go**.

**Why.** Every gate resolves to one principal: the user, on this channel. Decisions an agent flags as "a business call, a product preference, an external constraint" have no owner, no queue and no aging, and `tasks/blocked/` demands "when to check back" while nothing ever checks back.

**Notes.** Extend `tenant.members[]` with owners and approvers; add `requester`/`owner`/`approver` to the task stamp. Depends on TASK-032 for the roster and TASK-018 for the stamp.

STATUS: STUB — full spec drafted before implementation.
