---
id: TASK-045
category: stub
phase: P7
status: backlog
---

# TASK-045: Pin and record the model and harness a run used

**User story.** As an **operator**, I want **to know what my workforce was made of when it produced a result** so that **a vendor-side model update is not an untested simultaneous change to all 50 agents**.

**Why.** `model: opus` is a family name, not a version. Nothing pins a model version, records which model produced a given result, or declares a supported range. The one acknowledged version dependency is the harness: `/goal` requires a minimum Claude Code version, and without it the flagship long-horizon loop silently degrades to a single invocation.

**Notes.** The largest correlated-failure source in the design. Needs a canary cohort, which needs TASK-032's repo inventory. Depends on TASK-044 for an eval delta to compare against.

STATUS: STUB — full spec drafted before implementation.
