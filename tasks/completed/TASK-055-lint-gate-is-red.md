---
id: TASK-055
type: defect
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P1
completed_by: chazzcoin
---
# TASK-055: The bin/lint release gate was red on main

**User story.** As a **maintainer**, I want **`bin/lint` to pass on `main`** so
that **the release gate the Element documents is a gate rather than a formality**.

## What was wrong

`CLAUDE.md` names `bin/lint` a release gate — "run before tagging" — and it
exited 1 on pristine `main` with 5 HIGH findings. A permanently-red gate is
skipped or ignored at every release, so it gated nothing, and every task this
session had to carve out "lint is red at baseline, not a regression."

## The finding: all 5 HIGH were false positives

The linter flags platform-specific content in universal files. Read in context,
none of the five was drift:

| File | Why it is correct |
|---|---|
| `craft-rules.md:112` | A **paired** Web/iOS list, each half cross-referencing its own `*-conventions.md`. The ±5 window cannot see the pairing because the Web half is prose (hooks, components, pages) with no lintable token, so `ctx_platforms_count` never reaches 2. |
| `migration-rules.md:113` | "`npm run migrate` **/ equivalent**" — the "/ equivalent" *is* the generality marker. |
| `runtime/SKILL.md:66,241` | `pip install pyyaml` is the **skill's own dependency**, under its "### Dependencies" heading. Moving it to a `python-*` file would strip the skill of its own install instruction. |
| `test-rules.md:52` | Inside a fenced YAML block demonstrating stamp frontmatter, `language: swift` two lines above. |

So the answer to the stub's question — *"per finding, does the code move or does
the rule change?"* — is **the rule changes, 5 times out of 5**.

## Why not the existing mechanism

`CROSS_CUTTING_BASENAMES` already demotes HIGH→MEDIUM, and adding these four
files to it would have been a one-line fix. Rejected: it demotes an **entire
file**, which would permanently hide real future drift in `craft-rules.md` and
`test-rules.md` — two core universal files where HIGH is exactly what we want.

## What changed

`bin/lint` gains `REVIEWED_OK`: narrow `<relpath>|<token>` exemptions, each with
its reason written next to it. Demoted to **LOW, never silenced** — `VERBOSE=1
bin/lint` still lists all four. Adding an entry means writing down why.

## Verified by running

- `bin/lint` exit **0**; 0 HIGH
- Severity accounting: before 5 HIGH + 9 MEDIUM + 184 LOW = 198;
  after 0 HIGH + 9 MEDIUM + **189** LOW = 198. Nothing lost — the 5 moved.
- All four tokens confirmed present in `VERBOSE=1` output at LOW
- **Regression test:** injected `xcodebuild archive` into `craft-rules.md` →
  caught at HIGH, exit 1. The exemption is token-scoped, not file-scoped.

## Acceptance criteria

- [x] `bin/lint` exits 0 on a clean tree
- [x] Every exemption carries a written reason
- [x] Exemptions are demoted, not silenced — visible at `VERBOSE=1`
- [x] Real drift in an exempted file is still caught HIGH
- [x] No finding disappears from the totals
