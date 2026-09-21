---
id: TASK-021
category: stub
phase: P2
status: backlog
---

# TASK-021: rasa.module.telemetry — roll per-repo run lines into a fleet view

**User story.** As an **engineering leader**, I want **one view of throughput, success rate and cost across every repo** so that **I can answer whether the development arm is healthy today**.

**Why.** Per-repo records answer nothing at fleet scale. The kernel already writes `cost_usd`/`duration_ms`/`outcome` per turn to a JSONL audit ledger and grep finds no reader of that file anywhere.

**Notes.** New Element, `module` kind. Also widen the kernel's audit `skill` field, which has three legal values today, so `/auto-develop`, `/auto-test` and `/mission` are distinguishable. Depends on TASK-018 and TASK-020.

STATUS: STUB — full spec drafted before implementation.
