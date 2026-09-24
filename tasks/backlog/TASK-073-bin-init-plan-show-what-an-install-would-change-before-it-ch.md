---
id: TASK-073
type: change
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P2
---
# TASK-073: bin/init --plan: show what an install would change before it changes it

**Why.** `bin/init` writes immediately. An installed project has no dry run that lists which managed files would be replaced, which seeds created, and whether its ledger would migrate. Filed during 0.54.0.

_Filed only — not worked in 0.54.0._

## Notes

- Stabilization plan Step 1 (the plan's TASK-70), renumbered.
