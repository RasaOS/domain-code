---
id: TASK-012
category: stub
phase: P1
status: backlog
---

# TASK-012: Fail-closed test gate

**User story.** As a **release engineer**, I want **the production test stage to fail when its suite is empty or missing** so that **a deploy can never pass a test gate that ran no tests**.

**Why.** `content/build/stages/30-test.sh` prints "Skipping" and exits 0 on an empty suite — including at `ENV_CLASS=prod` — and `seed` ships `tests: []` with no `prod-gate.md`, so on a fresh install the production test gate passes vacuously.

**Notes.** Confirmed by hand 2026-09-20: `ENV_CLASS=prod bash build/stages/30-test.sh production` exits 0 against the seeded empty suite. Also implement the quarantine `status:` semantics `test-rules.md` documents but the stage never parses, and handle the all-tests-quarantined case so quarantine does not become the new vacuous pass.

STATUS: STUB — full spec drafted before implementation.
