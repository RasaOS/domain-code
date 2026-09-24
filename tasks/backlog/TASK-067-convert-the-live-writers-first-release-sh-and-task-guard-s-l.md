---
id: TASK-067
type: defect
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P2
---
# TASK-067: Convert the live writers first: release.sh and task-guard's ledger

**Why.** `release.sh` is the one record writer already producing records in installed projects, and it passes free text through `awk -v` (theme, target, title, the approver, the shipped stamp), which expands `\n` and forges lines. Its title parser uses exact fences. task-guard's change-ledger row carries raw values.

## Acceptance criteria

- [ ] A newline or a literal `\n` in `--approved-by` or `RASA_ACTOR` yields exactly one approval line and no forged key.
- [ ] No `awk -v NAME="$var"` remains in `release.sh` or `task-guard.sh`.
- [ ] Output on a clean `RELEASES.md` is byte-identical to `main`; the file mode is unchanged.

## Notes

- Stabilization plan Step 1 (the plan's TASK-64), renumbered.
