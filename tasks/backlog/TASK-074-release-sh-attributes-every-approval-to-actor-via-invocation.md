---
id: TASK-074
type: defect
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P2
---
# TASK-074: release.sh attributes every approval to "<actor> via invocation"

**Why.** `release.sh bundle` writes `**Approved.** <actor> via invocation` whoever approved and however, and the actor defaults to whatever identity the machine has. Filed during 0.54.0; the truthful-approval work (TASK-039) and the deploy and release record work fix it.

_Filed only — not worked in 0.54.0._

## Notes

- Stabilization plan Step 1 (the plan's TASK-71), renumbered.
