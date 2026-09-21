---
id: TASK-035
category: stub
phase: P5
status: backlog
---

# TASK-035: Cross-repo change set with landing order and joint revert

**User story.** As a **tech lead**, I want **a change spanning N repos expressed as one unit** so that **a breaking API change with five consumers is not five uncoordinated, locally-green PRs**.

**Why.** Nothing expresses ordering, gating repo B's merge on repo A's deploy, or a joint rollback. Every cross-cutting initiative therefore retains a human coordinator — the exact role the program exists to eliminate.

**Notes.** Also unblocks the inert contract ownership fields: `content/stamps.md` says `owner` and `consumers` are "populated but unused in the single-repo model". Depends on TASK-032.

STATUS: STUB — full spec drafted before implementation.
