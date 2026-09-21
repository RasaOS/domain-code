---
id: TASK-015
category: stub
phase: P1
status: backlog
---

# TASK-015: Wire project-map.md into the seeded CLAUDE.md imports

**User story.** As a **session starting in an onboarded repo**, I want **the generated project map to load with the rest of my context** so that **the comprehension work `/wrangle` already did is not orphaned**.

**Why.** `/wrangle` writes `.claude/context/project-map.md` specifically "so future sessions read it alongside CLAUDE.md", and it is the only generated-context artifact missing from the `@`-imports in `seed/CLAUDE.md.template` — `welcome.md`, `mode.md` and `docs/notes/INDEX.md` are all wired.

**Notes.** One line. Verify against a fresh `bin/init` that the import list is otherwise complete.

STATUS: STUB — full spec drafted before implementation.
