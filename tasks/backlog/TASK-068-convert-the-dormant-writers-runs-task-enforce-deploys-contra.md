---
id: TASK-068
type: defect
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P2
---
# TASK-068: Convert the dormant writers: runs, task-enforce, deploys, contract

**Why.** `runs.sh`, the task-enforce writers and `deploys.sh` have the same defects as the live writer but have not produced records in installed projects yet. `contract.sh` carries its own hardened copy of the rules (0.52.1) that should become the library.

## Acceptance criteria

- [ ] `runs.sh`, `task-enforce.sh`'s writers and `deploys.sh` write through the library; `contract.sh` uses the library instead of its private copy.
- [ ] Every refusal leaves the file byte-identical; field order and file modes are unchanged; record `id` and timestamp formats are unchanged.
- [ ] Values are validated before a record id is reserved: an actor or tag containing a newline leaves no reserved file behind.
- [ ] 0 differences between the old and new readers across the parity comparisons.

## Notes

- Stabilization plan Step 1 (the plan's TASK-65), renumbered.
