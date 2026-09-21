---
id: TASK-039
category: stub
phase: P6
status: backlog
---

# TASK-039: Truthful approval provenance in the ledger

**User story.** As an **auditor**, I want **the ledger to distinguish how an approval was obtained** so that **a bypass is visible as a bypass**.

**Why.** The ship log records `approval: invocation` and `**Approved.** $(whoami)` regardless of whether a human answered a prompt, a token authorized it, or a flag bypassed it.

**Notes.** The Element already refuses to fabricate an approver elsewhere, on the stated grounds that it "would put a lie in an audit trail" — this applies the same standard here. Depends on TASK-019 and TASK-038.

STATUS: STUB — full spec drafted before implementation.
