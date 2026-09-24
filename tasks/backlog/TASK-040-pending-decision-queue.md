---
id: TASK-040
type: change
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P6
---
# TASK-040: Pending-decision queue for headless runs

**User story.** As an **agent hitting a hard gate**, I want **to file a pending decision and park, rather than render a question into a void** so that **a blocked run is recoverable instead of lost**.

**Why.** A gate hit in a headless run renders a question in a transcript nobody reads, and no human can answer "what am I blocking right now, across the company?"

**Notes.** The kernel has `/v1/permission-requests` unfinished and without a durable store. This task is the domain.code client for it; the kernel half is cross-repo. Depends on TASK-037.

STATUS: STUB — full spec drafted before implementation.
