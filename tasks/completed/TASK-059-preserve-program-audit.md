---
id: TASK-059
type: change
created: 2026-09-23
created_by: chazzcoin
updated: 2026-09-23
phase: P1
completed_by: chazzcoin
x-origin: manual
x-outcome: unrecorded
x-owner: unassigned
---
# TASK-059: Keep the program audit's gap-to-task coverage in the repository

**User story.** As a **maintainer**, I want **the audit that defines P1–P9
kept next to the ROADMAP** so that **coverage of its 38 surviving gaps can be
re-checked as tasks land, instead of reconstructed from session transcripts
that are deleted automatically**.

## Why

The only copies of the 2026-09-20 audit were a temporary workflow output and
session transcripts subject to automatic cleanup after about 30 days. The
ROADMAP restates the audit's conclusions but not its gap list, so "which gaps
does no task cover yet" could not be answered from the repository. A
2026-09-23 re-verification found six such gaps; nothing in the repo showed it.

## What

- `docs/audits/2026-09-20-v0.48.1/gap-coverage.md` — one row per surviving
  gap: id, severity, covering task ids, coverage state.
- `docs/audits/2026-09-20-v0.48.1/README.md` — what the audit was, what the
  columns mean, where the full audit lives, and when to update the table.
- `tasks/ROADMAP.md` — the program section points at the table; this task is
  row 8 of P1.

**Redacted by design.** This repository is public. The table carries ids,
severities and task numbers only; gap statements, evidence and anything
naming a specific installation stay in the private workspace repository.
Nothing under `content/` or `seed/` changes, so no install target receives
anything and no version bump is needed.

## Acceptance criteria

- [x] 38 rows, one per surviving gap, with severities matching the audit
      result in order (checked programmatically against the result file: 0
      mismatches)
- [x] Every cited task id exists in `tasks/` (42 ids, 0 missing)
- [x] `git grep` finds no installation-specific name under `docs/audits/`
- [x] No new duplicate task ids (the known `TASK-023` pair is unchanged)
- [x] All four gates exit 0
