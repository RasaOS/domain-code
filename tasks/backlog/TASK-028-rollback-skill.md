---
id: TASK-028
category: stub
phase: P4
status: backlog
---

# TASK-028: /rollback skill

**User story.** As an **operator**, I want **a first-class rollback verb** so that **an agent facing a bad release has a sanctioned action available**.

**Why.** The rollback command is declared (`seed/cloud.md.template` seeds a Rollback row) and its effect on release history is specified (`release-rules.md`, "Rollback semantics"), but no skill invokes it, no pipeline stage calls it, and nothing detects the condition that should trigger it.

**Notes.** Declared but never invoked. This is one skill mirroring `/deploy`, not a subsystem — do not let it grow.

STATUS: STUB — full spec drafted before implementation.
