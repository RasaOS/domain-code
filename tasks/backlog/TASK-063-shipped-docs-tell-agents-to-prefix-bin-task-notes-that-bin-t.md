---
id: TASK-063
type: defect
created: 2026-09-23
created_by: claude
updated: 2026-09-23
phase: P7
---
# TASK-063: Shipped docs tell agents to prefix bin/task notes that bin/task already prefixes

**Why.** `.claude/bin/task pass` writes its note to `tasks/history.tsv` as `gate: <note>`, and `reject` as `gate not passed: <note>` — the prefix is the tool's. Five places this Element ships tell agents to pass `--note "gate: …"`, so every consumer's history records `gate: gate: …`. Found closing TASK-062, whose own `pass` line reads exactly that (the log is append-only; it stays).

## Acceptance criteria

- [ ] `content/skills/auto-hotfix/SKILL.md`, `content/skills/mission/SKILL.md`, `content/skills/release-add/SKILL.md` and `seed/done-gate.md.template` (two lines) pass the evidence alone, and say the tool adds the prefix.
- [ ] `git grep -- '--note "gate:'` over content/ and seed/ (excluding vendored files) finds nothing.
- [ ] Patch 0.53.1 with a CHANGELOG entry; `bin/check-manifest` and `bin/lint` pass.


## Acceptance criteria

## Notes
