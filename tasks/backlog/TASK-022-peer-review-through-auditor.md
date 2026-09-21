---
id: TASK-022
category: stub
phase: P3
status: backlog
---

# TASK-022: Route /peer-review judgment through the auditor subagent

**User story.** As a **reviewer**, I want **the reviewing agent to be a different, context-isolated agent from the author** so that **reviewer independence is structural rather than conventional**.

**Why.** `content/agents/auditor.md` is a context-isolated, read-only, severity-tiered reviewer that explicitly advertises itself for "pre-merge review with --lens code" — and `/peer-review` (152 lines, zero agent references) never calls it while holding squash-merge authority per Rule 2.

**Notes.** Record author-vs-reviewer on the PR so the independence is auditable. Wants TASK-019's actor field to record it truthfully.

STATUS: STUB — full spec drafted before implementation.
