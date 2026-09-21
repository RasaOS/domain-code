---
id: TASK-025
category: stub
phase: P3
status: completed
---

# TASK-025: Brownfield carve-out for characterization tests, plus /pin-behavior

**User story.** As an **agent working a legacy repo**, I want **a sanctioned way to pin existing behavior before changing it** so that **untested code has a path to becoming testable instead of being permanently ungated**.

**Why.** `/auto-test` bans characterization testing by name — "A test written to pass whatever the code currently does is worthless" — with no brownfield exception, and `/self-improve` defines behavior-preserving as an unchanged green/red profile, which is trivially true when the profile is empty.

**Notes.** The ban is right for greenfield and wrong for brownfield. Add the carve-out to `content/test-rules.md` and a `/pin-behavior` skill that writes characterization/golden-master tests. Blocks TASK-024 in practice.

## Outcome — shipped in v0.51.0

Closes a contradiction P1 created: the prod gate refuses an empty suite while
`/auto-test` banned the only test a legacy repo can honestly write — "a test
written to pass whatever the code currently does is worthless". A repo with no
spec has nothing to test against except what it does today.

- `test-rules.md` → "Brownfield: pinning behavior you did not specify". Narrow:
  only where no spec exists, never over a spec's test plan, and **never over
  behavior that is plainly wrong** — that is a finding, not a baseline. Pinning
  a bug makes it permanent and makes the fix look like a regression.
- `test_kind: characterization`, **required**, so intent tests and history
  tests stay distinguishable. Without the label nobody can tell whether a red
  test means "this broke" or "this changed, which may be fine".
- `/pin-behavior` writes them — checks for non-determinism by running twice
  *before* writing, and reports what it could **not** pin, which is the useful
  half: those surfaces are what a later change breaks silently.
- `/self-improve` corrected: it defined behavior-preserving as "the green/red
  profile is unchanged", trivially true on an empty profile — it was reporting
  an unchecked claim as verified.

Not touched: `stamps.md`'s `Stamp: test` is a different model from the one
`30-test.sh` runs, so there was no enum row to update there. That is the known
two-incompatible-stamp-models gap.

**Bookkeeping:** this record was written late. The work shipped in
`a6bc272` while the stub stayed in `tasks/backlog/`, so the task existed in two
states at once — the exact thing the graduate-don't-duplicate rule exists to
prevent, applied in an earlier commit this session and then not applied here.
