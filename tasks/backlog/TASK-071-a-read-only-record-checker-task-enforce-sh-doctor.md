---
id: TASK-071
type: change
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P2
---
# TASK-071: A read-only record checker: task-enforce.sh doctor

**Why.** Before an installed project takes this release, and after, there is no way to ask whether its records are sound.

## Acceptance criteria

- [ ] `task-enforce.sh doctor [<root>]` is read-only, has no `--fix`, and writes nothing.
- [ ] It fails on a BOM, CR, bad fences, duplicate keys, escaped values and forged run actors; it warns on duplicate ids, a second frontmatter block, and records the other rules disagree with.
- [ ] It covers every record kind the Element writes (tasks, runs, deploy records, contract stamps, release tracker).

## Notes

- Stabilization plan Step 1 (the plan's TASK-68), renumbered.
