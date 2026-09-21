---
id: TASK-055
category: bug
phase: P1
status: backlog
---

# TASK-055: The bin/lint release gate is red on main

**User story.** As a **maintainer**, I want **`bin/lint` to pass on `main`** so that **the release gate the Element documents is a gate rather than a formality**.

**Why.** `CLAUDE.md` names `bin/lint` as a release gate — "Run before tagging" — and it exits 1 on pristine `main` (`0db5016`) with 14 findings. A gate that is permanently red is either being skipped or ignored at every release, which means it gates nothing and its output is noise.

**Notes.** Found 2026-09-20 while verifying TASK-013: confirmed 14 findings at `0db5016` and 14 after that change, none in the files TASK-013 touched — so the red is pre-existing, not a regression. The visible findings are platform-scope violations (e.g. `xcrun` in `seed/runtime-mobile-app.md.template`, flagged as needing an `ios-*` file), plus 184 suppressed LOW findings. Decide per finding whether the code moves or the rule changes; a gate nobody can pass is worse than no gate. Related: TASK-044 (no gate on shipped prose at all).

STATUS: STUB — full spec drafted before implementation.
