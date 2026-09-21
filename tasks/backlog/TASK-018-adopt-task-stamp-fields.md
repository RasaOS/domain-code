---
id: TASK-018
category: stub
phase: P2
status: backlog
---

# TASK-018: Adopt the proposed task stamp fields and add run identity

**User story.** As an **operator**, I want **every task to carry who acted, what happened, and how many attempts it took** so that **the system produces evidence about itself**.

**Why.** `content/stamps.md` already specifies `priority`, `blocked_by` and `assignee` under the heading "Models — proposed but not yet adopted", while the shipped frontmatter is id/category/phase/status — so tasks terminate at merge with no outcome field of any kind.

**Notes.** Extend the adopted set with `actor`, `actor_kind: human|agent`, `run_id`, `outcome` and `attempts`. This is the foundation the rest of P2 and most of P3/P6 read from. Zero dependencies.

STATUS: STUB — full spec drafted before implementation.
