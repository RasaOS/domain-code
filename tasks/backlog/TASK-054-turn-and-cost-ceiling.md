---
id: TASK-054
category: stub
phase: P9
status: backlog
---

# TASK-054: Turn and cost ceiling at the Stop hook seam

**User story.** As an **operator**, I want **a per-run ceiling enforced inside the Element** so that **runaway cost is bounded even where the kernel is not the runtime**.

**Why.** Most agents run directly under Claude Code today, not under the kernel, so a kernel-side breaker does not cover them.

**Notes.** This repo's half of TASK-053. `git-guard` and `task-enforce` already install at the `Stop` hook seam, so the mechanism exists.

STATUS: STUB — full spec drafted before implementation.
