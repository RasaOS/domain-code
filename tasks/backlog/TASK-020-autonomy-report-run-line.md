---
id: TASK-020
category: stub
phase: P2
status: backlog
---

# TASK-020: Autonomy report appends a run line instead of only rendering

**User story.** As an **operator**, I want **each autonomous run to leave a machine-readable record behind** so that **a skill regression is one signal rather than 200 unrelated local incidents in prose**.

**Why.** `content/autonomy-rules.md` specifies the autonomy report as "Render it in chat at the end of the run", and all 20 call sites across the auto-* family and `/mission` say "Render", never write. A gate hit dies in a transcript nobody was watching.

**Notes.** Follow the `deploys/records/<id>.md` precedent — per-file ledger, chosen because a single append-only file conflicts on every PR once two long-lived branches exist. Depends on TASK-018.

STATUS: STUB — full spec drafted before implementation.
