---
id: TASK-064
type: defect
created: 2026-09-23
created_by: claude
updated: 2026-09-23
phase: P7
---
# TASK-064: Shipped docs prefix bin/task notes that bin/task already prefixes

**Why.** `.claude/bin/task pass` records its note as `gate: <note>` and `reject` as `gate not passed: <note>`. Five places this Element ships told agents to pass `--note "gate: …"`, so every history line read `gate: gate: …` — TASK-062's own first attempt shows it.

## Acceptance criteria

- [x] `/auto-hotfix`, `/mission`, `/release-add` and the seeded done-gate (two places) pass the evidence bare and say the tool adds the prefix.
- [x] `git grep -- '--note "gate'` over content/ and seed/, excluding vendored files, finds nothing.

## Notes

- Verified on the 0.53.1 branch: check-manifest, lint, check-invocations, check-bash32, test-contract pass; every script parses with its own interpreter; this ledger 0 errors; `bin/init` into an empty repo gives a 0-error ledger; no added line names a private repository.
