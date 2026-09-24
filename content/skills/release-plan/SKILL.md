---
name: release-plan
description: Create a release before anything is in it, and target phases and tasks at it. Targeting is fluid — any task stage, freely moved between releases, changed at will. It does NOT put work into a release; only `/release-add` does that, and only for completed work. Use for "/release-plan", "create v1.3.0", "plan the next release", "what's slated for v1.3.0", "move this to the next release", "target this at 1.4".
---

# /release-plan — declare a release, then aim work at it

Two layers, and the distinction is the whole point:

| | |
|---|---|
| **Targeted** | Fluid. Any task stage — backlog, active, review, blocked. Moved freely. This skill. |
| **Bundled** | Committed. Requires completed work. `/release-add`. |

A release exists as an empty container the moment you name it. You aim
work at it while the work is still being done. Nothing ships from the
targeted layer — `/release` reads `### Bundled` and nothing else, so a
plan can be wrong all week without risk.

Engine: `.claude/skills/release/release.sh`.
Contract: `.claude/release-rules.md`.

## Operations

```bash
R=.claude/skills/release/release.sh

bash $R create v1.3.0 --theme "offline mode" --target 2026-11-30
bash $R target TASK-061 v1.3.0
bash $R target "Phase 5" v1.3.0
bash $R untarget TASK-061
bash $R list
bash $R check
```

**No argument** → render the plan (`list`) and then `check`. That is the
whole read path.

**Targeting is idempotent and exclusive.** Targeting an id that is
already targeted elsewhere *moves* it, in one edit. An id is never in two
releases.

## Rules you enforce

- **Never gate targeting on a task's stage.** A backlog task, an active
  task, a task in review, a blocked task can all be targeted. That is
  the fluidity the feature exists for. If you find yourself wanting to
  check whether something is done before targeting it, you are
  thinking of `/release-add`.
- **Refuse to target into a shipped release.** The engine refuses; say
  why rather than restating the error — a shipped release is frozen, and
  its manifest is also in the annotated tag where it cannot be edited at
  all.
- **Bundled work moves with `/release-add`, not here.** The engine
  refuses and names the release it is bundled into.
- **Do not put a `release:` field in a task's frontmatter.** The mapping
  lives in `tasks/RELEASES.md`, one place, deliberately — see
  `release-rules.md` "No `release:` field on tasks". A field in 12 task
  files is 12 files to edit when a release slips, and `release` is not a
  key the task validator knows, so it is an error anyway (I-11).

## Versions

`v<semver>`, matching the heading grammar. The engine refuses a duplicate
and refuses a version that has already shipped. It does **not** refuse a
version below the highest shipped one — maintenance lines are legitimate
and `v1.2.4` after `v1.3.0` is a normal thing to plan.

If the user does not give a version, propose one from the last tag plus a
minor bump and say that is what you did.

## Committing

**This skill never commits.** Planning edits are ordinary doc edits and
the user commits them with their next change.

This is deliberate rather than lazy: `git-clean.sh` counts `tasks/` as
dirty for production, so a release that "helpfully" auto-committed or
exempted the file would pass its own preflight and then fail the prod
pipeline on the file it just exempted. End with the command, suggested
not executed:

```bash
git add tasks/RELEASES.md && git commit -m "releases: target TASK-058 at v1.3.0"
```

## Related

- `/release-add` — bundle completed work into a release.
- `/release` — ship one.
- `/roadmap` — phases and their tasks; the source for a `Phase N` name.
- `.claude/release-rules.md` — the format and the lifecycle.
