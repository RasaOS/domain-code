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

- [x] `task-enforce.sh doctor [<root>]` is read-only, has no `--fix`, and writes nothing.
- [x] It fails on a BOM, CR, bad fences, duplicate keys, escaped values and forged run actors; it warns on duplicate ids, a second frontmatter block, and records the other rules disagree with.
- [x] It covers every record kind the Element writes (tasks, runs, deploy records, contract stamps, release tracker).

## Notes

- Stabilization plan Step 1 (the plan's TASK-68), renumbered.
- `task-enforce.sh doctor [<root>]` runs `content/skills/task-enforce/doctor.py` with `python3 -B`. It uses only the standard library, reads bytes strictly, and does not use the tolerant library, which would hide exactly what it looks for. It has no `--fix`, opens files read-only, and writes no cache or state. An explicit root checks any project, including a clone at the release-candidate step. The research prototype `scan.py` was the model.
- Coverage: tasks (the seven stages), run records, deploy and env-transfer records, `DEPLOYS.md`, contract, env-var and test stamps (a test stamp's name is its file's slug after `<YYYYMMDD>_<NNN>_`), and `tasks/RELEASES.md`.
- FAIL codes: bom, cr, fence, body-kv, dup-key, escaped, actor (an `auto-*` run recorded as human), blank-row, and approval (a second **Approved.**, **Shipped.**, **Theme.** or **Target.** line). WARN codes: dup-id, name, enum, status, outcome, second-fm, no-fm, heading and unreadable. Exit 1 on any FAIL.
- Values are never printed: keys, ids, files and line numbers only.
- `bin/test-readers` doctor section (17 cases):
  - A project written by the Element's own scripts is clean, with every kind read.
  - Every FAIL code and both drift warnings are named on a damaged set.
  - A checksum of the whole tree is unchanged after the run.
  - No value appears in the report.
- Real ledgers: 0 failures on this repo (75 tasks) and on six other RasaOS ledgers in the workspace. That agrees with R2's finding of no damage.
  - The warnings are real drift: 159 legacy `status:` fields in ledgers not yet on module-tasks v1.0.0, one duplicate task id, one placeholder id, and one pre-0.48 tracker heading.
  - Three `name` false positives on dated test stamps were found this way and fixed.
- The per-repo fleet baseline (plan 1.16, "doctor reports 0 W-class findings") runs with this at the release-candidate step.

