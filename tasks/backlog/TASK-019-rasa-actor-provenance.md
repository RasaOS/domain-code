---
id: TASK-019
category: stub
phase: P2
status: backlog
---

# TASK-019: Thread RASA_ACTOR through every provenance site

**User story.** As an **auditor**, I want **the ledger to record which actor performed an action** so that **"who approved this production release" does not resolve to a service account**.

**Why.** Five sites stamp `$(whoami)`: `deploys.sh`, `content/build/deploy` (which `export`s over any inherited value), `env-sync.sh`, `gates/approval.sh` and `release.sh`. `grep -rn "DEPLOY_APPROVAL="` returns zero writers, so the ship log always records the literal `invocation`.

**Notes.** One `RASA_ACTOR` value, defaulting to `$(whoami)` when unset, threaded through all five plus the approval gate. Depends on TASK-018 for the field definition.

STATUS: STUB — full spec drafted before implementation.
