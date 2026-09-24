---
id: TASK-017
type: change
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P1
completed_by: chazzcoin
---
# TASK-017: Rename tasks/done/ to tasks/completed/

**User story.** As a **maintainer**, I want **this repo's own task folders to match the rule it ships** so that **the Element is not drifting from its own documented lifecycle**.

**Why.** `content/task-rules.md` states the directory was renamed from `done/` to `completed/` in v0.36.0, and this repo still has `tasks/done/`.

**Notes.** Trivial, but it is the Element dogfooding its own rules — the drift is visible to anyone reading both.

## Outcome

Renamed `tasks/done/` → `tasks/completed/` (`git mv`, history preserved) and
added the missing `tasks/blocked/`, so this repo has every state its own
`task-rules.md` lifecycle defines: triage → backlog → active ⇄ blocked →
completed.

Verified no blast radius: shipped content references `tasks/completed` 38
times and `tasks/done` zero times, and neither `rasa.json` nor `bin/`
references either path — `tasks/` is this repo's own workspace, not shipped
content.
