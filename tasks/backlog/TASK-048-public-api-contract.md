---
id: TASK-048
type: change
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P8
---
# TASK-048: Public-API deprecation policy and breaking-change gate

**User story.** As an **API consumer**, I want **to be warned before an interface I depend on changes** so that **a silently-broken public API is not discovered by the counterparty**.

**Why.** `deprecated`/`retired` exist only as stamp lifecycle states for env vars and tests — internal bookkeeping, never a shipped interface with users on the other end. `contract-rules.md` and the `/contract` skill mention no deprecation or backward-compatibility policy at all.

**Notes.** Depends on TASK-035's cross-repo change set for the consumer side of the graph.

STATUS: STUB — full spec drafted before implementation.
