---
id: TASK-029
category: stub
phase: P4
status: backlog
---

# TASK-029: deploys.sh gains outcome/health and an annotate subcommand

**User story.** As an **auditor**, I want **a sealed deploy record to learn what happened after the deploy** so that **a release that shipped cleanly and then took production down is distinguishable from one that worked**.

**Why.** The deploy record is written at deploy time and can never be amended, so post-deploy reality never reaches the ledger.

**Notes.** `deploys/records/<id>.md` is already the right pattern — per-execution, machine-written, with status, duration and error_stage, regenerated into a view and drift-checked. This extends it rather than replacing it. Depends on TASK-027 for a health signal to record.

STATUS: STUB — full spec drafted before implementation.
