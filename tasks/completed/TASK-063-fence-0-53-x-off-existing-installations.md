---
id: TASK-063
type: defect
created: 2026-09-23
created_by: claude
updated: 2026-09-24
phase: P7
completed_by: claude
priority: now
x-outcome: shipped
---
# TASK-063: Fence 0.53.x off existing installations

**Why.** v0.53.0 changed the task-ledger shape and its notes and README gave installed projects an upgrade command. Tools outside this Element that read or write task frontmatter directly have not been updated for the new shape, so an upgraded installation would have them writing `status:` and bare keys the new validator rejects. The same notes also named private repositories, in a public repository.

## Acceptance criteria

- [x] CHANGELOG v0.53.0's upgrade section and the README say existing installations must not upgrade to 0.53.x yet, and new installations are unaffected; no upgrade command for installed projects remains.
- [x] No file on `main` changed by TASK-062 names a private repository or company; TASK-062's own notes are generic.
- [x] v0.53.1 CHANGELOG entry; `bin/check-manifest`, `bin/lint`, `bin/check-invocations`, `bin/check-bash32`, `bin/test-contract` pass; this ledger has zero errors.

## Notes

- Verified on the 0.53.1 branch: check-manifest, lint, check-invocations, check-bash32, test-contract pass; every script parses with its own interpreter; this ledger 0 errors; `bin/init` into an empty repo gives a 0-error ledger; no added line names a private repository.

Gate satisfied 2026-09-24 by claude — PR #13 merged as 86500e2, CI 8/8 green, tagged v0.53.1
