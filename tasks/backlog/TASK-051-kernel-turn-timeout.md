---
id: TASK-051
category: stub
phase: P9
status: backlog
---

# TASK-051: Configurable turn timeout with a default retry

**User story.** As an **operator**, I want **a long autonomous run not to be hard-killed mid-edit** so that **a `/mission` run can exceed five minutes**.

**Why.** Every turn is hard-killed at 5 minutes with zero default retries, and `WorkflowStep.timeout_ms` is not honored. A `/mission` run is hours of wall clock.

**Notes.** **Cross-repo (`kernel/`).** A non-zero default retry against the existing `--resume` path.

STATUS: STUB — full spec drafted before implementation.
