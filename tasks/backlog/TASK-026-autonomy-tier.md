---
id: TASK-026
category: stub
phase: P3
status: backlog
---

# TASK-026: autonomy_tier on rasa.lock.json

**User story.** As an **operator**, I want **a repo's autonomy to be scoped to what that repo has earned** so that **repo #47 with no surviving author does not get the authority repo #3 with green CI gets**.

**Why.** `bin/init` performs zero fitness assessment of the target, so every repo grants an agent identical authority regardless of its tests, CI, docs or build health.

**Notes.** Read by `content/autonomy-rules.md`. Extends the pattern `class-guard.sh` already proves for environment classes. Wants TASK-018's record to have evidence to tier on.

STATUS: STUB — full spec drafted before implementation.
