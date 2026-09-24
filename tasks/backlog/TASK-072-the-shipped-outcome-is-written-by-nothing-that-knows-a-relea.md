---
id: TASK-072
type: defect
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P2
---
# TASK-072: The shipped outcome is written by nothing that knows a release shipped

**Why.** A task's `x-outcome: shipped` is stamped at bundle or merge time, not when a production release happens, and `release.sh` writes no outcome at all, so the stamp and `RELEASES.md` can disagree. Filed during 0.54.0; fixed with the deploy and release record work.

_Filed only — not worked in 0.54.0._

## Notes

- Stabilization plan Step 1 (the plan's TASK-69), renumbered.
