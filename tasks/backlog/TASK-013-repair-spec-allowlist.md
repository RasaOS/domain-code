---
id: TASK-013
category: stub
phase: P1
status: backlog
---

# TASK-013: Repair the corrupted spec-file allowlist

**User story.** As a **reviewer**, I want **the Rule 2 spec-file allowlist to parse as a list again** so that **the rule governing autonomous merges to `main` says what it means**.

**Why.** A botched doc edit left `content/git-flow-rules.md` Rule 2 and its `content/autonomy-rules.md` mirror reading `tasks/ROADMAP.md`. Any file outside the allowlist disqualifies `tasks/RELEASES.md`. — a duplicated sentence with an orphaned entry.

**Notes.** Practically harmless today because the existing `tasks/**/*.md` glob already covers the orphaned entry, but this is the governance rule for autonomous merges to `main` and it no longer reads as a list.

STATUS: STUB — full spec drafted before implementation.
