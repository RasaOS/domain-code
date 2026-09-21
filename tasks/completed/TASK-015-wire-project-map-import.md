---
id: TASK-015
category: bug
phase: P1
status: completed
---

# TASK-015: Wire project-map.md into the seeded CLAUDE.md imports

**User story.** As a **session starting in an onboarded repo**, I want **the
generated project map to load with the rest of my context** so that **the
comprehension work `/wrangle` already did is not orphaned**.

## What was broken

`/wrangle` Phase 1 writes `.claude/context/project-map.md` and its own
description says it exists "so future sessions land cold with project context
already loaded". It was the only generated-context artifact missing from the
`@`-imports in `seed/CLAUDE.md.template` — so nothing loaded it, and the most
expensive output of the audit was orphaned.

## Verified before changing

Two of the six existing imports — `.claude/mode.md` and `docs/notes/INDEX.md` —
are **already absent on a fresh `bin/init` install** (confirmed by running one).
So conditionally-present imports are the shipped norm, not a hazard introduced
here, and adding a seventh is consistent. `mode.md`'s own entry already
documents itself as "only present when a mode is active".

## What changed

- `seed/CLAUDE.md.template` — `@.claude/context/project-map.md` added to the
  import block, ordered with the other `.claude/` primitives.
- Its entry in the "Why each one" list notes that it appears only after
  `/wrangle` has run, matching how `mode.md` documents its own conditionality.

## Acceptance criteria

- [x] `@.claude/context/project-map.md` present in the seeded template
- [x] Documented in the "Why each one" list, with its conditional nature stated
- [x] `check-manifest` 182, `check-invocations` exit 0
- [x] `bin/lint` 14 findings — baseline, no regression (TASK-055)
