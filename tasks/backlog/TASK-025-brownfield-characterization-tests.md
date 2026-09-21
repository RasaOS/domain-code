---
id: TASK-025
category: stub
phase: P3
status: backlog
---

# TASK-025: Brownfield carve-out for characterization tests, plus /pin-behavior

**User story.** As an **agent working a legacy repo**, I want **a sanctioned way to pin existing behavior before changing it** so that **untested code has a path to becoming testable instead of being permanently ungated**.

**Why.** `/auto-test` bans characterization testing by name — "A test written to pass whatever the code currently does is worthless" — with no brownfield exception, and `/self-improve` defines behavior-preserving as an unchanged green/red profile, which is trivially true when the profile is empty.

**Notes.** The ban is right for greenfield and wrong for brownfield. Add the carve-out to `content/test-rules.md` and a `/pin-behavior` skill that writes characterization/golden-master tests. Blocks TASK-024 in practice.

STATUS: STUB — full spec drafted before implementation.
