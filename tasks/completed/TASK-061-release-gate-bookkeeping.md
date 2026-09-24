---
id: TASK-061
type: change
created: 2026-09-23
created_by: chazzcoin
updated: 2026-09-23
phase: P1
completed_by: chazzcoin
x-origin: manual
x-outcome: unrecorded
x-owner: unassigned
---
# TASK-061: make the release record and the release gate tell the truth

**User story.** As an **operator**, I want **every shipped version tagged,
every shipped change in the CHANGELOG, and the schema actually checked in
CI** so that **a consumer can pin what they run and the gate's green means
what it says**.

## What was wrong

- **Two releases were never tagged.** `VERSION` reached 0.51.0 at `7a25e57`
  and 0.52.0 at `f6ece75`, first on `main` at `a7d4f98` (the PR #8 merge, and
  the tag target); the remote has tags only through `v0.50.0`, so no consumer
  can pin either.
- **Eight shipped changes are missing from the CHANGELOG** — TASK-019
  (`a4747c9`) and TASK-020 (`d3a055a`) under v0.50.0; TASK-056 (`65ce6d7`),
  TASK-025 (`a6bc272`), TASK-057 (`a6252fd`), TASK-023 (`5744521`),
  `773d89b` and `aea240e` under v0.52.0. `/sync` renders a consumer's upgrade
  delta from these headings, so the omissions were invisible downstream.
- **The CI job named "manifest + schema" never ran the schema validator.**
  `bin/check-manifest` checks the inventory only; `rasa.json` was never
  validated against `RasaOS/schema` in CI.
- **`TASK-023` existed twice** — the original backlog stub survived next to
  the completed, re-scoped record.

## What changed

- `CHANGELOG.md` — the missing lines added under v0.50.0 and v0.52.0, and a
  known-issue line under v0.51.0 (it predates `773d89b`).
- `.github/workflows/checks.yml` — a hard step that clones `RasaOS/schema`
  at tag `v0.2.0`, installs `jsonschema` and validates `rasa.json`;
  `bin/test-contract` runs on ubuntu (mawk) and on stock macOS bash 3.2.
- `tasks/backlog/TASK-023-goal-evaluator-ground-truth.md` removed. The
  completed record already states the re-scope and why the original ask —
  tools and file access for the evaluator — is not available in the
  harness; re-filing it would re-file an impossible ask.
- ROADMAP rows added for TASK-056, -057 and -058 (completed, never listed)
  and for TASK-060 and TASK-061.

**Tags are the user's to push.** Annotated, after this release merges:

```
git tag -a v0.51.0 7a25e57 -m "v0.51.0 — tag backfilled 2026-09-23"
git tag -a v0.52.0 a7d4f98 -m "v0.52.0 — tag backfilled 2026-09-23"
git tag -a v0.52.1 <merge commit> -m "v0.52.1"
git push origin v0.51.0 v0.52.0 v0.52.1
```

Verify with `git ls-remote --tags origin`: `v0.52.0^{}` must be `a7d4f98`.
No domain-code pin in any known consumer points at a 0.51 or 0.52 commit, so
neither tag strands anyone.

## Acceptance criteria

- [x] The two backfill tag targets verified from history: `7a25e57` carries
      `VERSION` 0.51.0 with parent `d3a055a` (v0.50.0) and is an ancestor of
      `main`; `a7d4f98` carries 0.52.0 and is the PR #8 merge
- [x] All eight backfilled commits exist with matching subjects
- [x] No duplicate task ids remain
- [x] The schema step validates `rasa.json` locally with the canonical
      validator
- [x] All four gates exit 0
