---
id: TASK-050
category: stub
phase: P9
status: backlog
---

# TASK-050: Queue group and bounded worker pool on commands.dispatch

**User story.** As an **operator**, I want **the kernel to run more than one agent turn at a time, safely** so that **scaling out does not mean every replica executes every command**.

**Why.** The kernel executes exactly one agent turn process-wide, and the dispatch subscription has no queue group — so a second `core` replica receives and executes every command, producing double commits and double pushes. The naive scale-out is worse than the limit.

**Notes.** **Cross-repo (`kernel/`).** Keep the per-session TurnQueue. Filed here for program completeness only.

STATUS: STUB — full spec drafted before implementation.
