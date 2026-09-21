---
id: TASK-033
category: stub
phase: P5
status: backlog
---

# TASK-033: Ship render-active-notice as the active-notice writer

**User story.** As an **org tier**, I want **a supported way to publish a notice that member repos already read** so that **the one cross-repo protocol this Element defines is not dead on the write side**.

**Why.** `content/task-rules.md` defines "Active orchestrator notices" — read at session start and "treat as authoritative" — and `find` for `active-*.md` across the reference tenant returns nothing, because nothing ships that writes them.

**Notes.** Read side exists and is specified. This is the missing writer.

STATUS: STUB — full spec drafted before implementation.
