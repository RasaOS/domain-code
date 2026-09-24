---
id: TASK-016
type: defect
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P1
completed_by: chazzcoin
---
# TASK-016: bin/init sets the task-enforcement default per target

**User story.** As an **operator**, I want **task enforcement on by default in a
new install** so that **the default agent runtime has gates rather than none**.

## The tension, and how it resolved

The audit called `enabled: false` "the one brownfield-aware decision in the
Element running backwards". But the Element has a **stated rationale**, in two
places:

> "Default off. This Element installs into existing projects, and a gate that
> switches itself on mid-stream is a gate people delete."

That argument is correct — for existing projects. It is simply not an argument
about **new** ones, where there is no mid-stream, and where defaulting off means
the gate is never turned on at all. So rather than override a documented
decision, `bin/init` now distinguishes the two cases. Both rationales survive.

Two facts settled the design, and neither was in the stub:

- `.claude/task-enforcement.json` is **`skip-if-exists`**, so an existing
  install is never rewritten. Any default only ever applies to a repo receiving
  the file for the first time.
- `bin/init` had **no notion** of whether its target was greenfield or
  brownfield, so it could not have made this distinction before.

## What changed

- `bin/init` classifies the target **before writing anything**, so the install's
  own files cannot make a new project look established. Greenfield = no commits,
  or no tracked files. Anything with history is brownfield — the cautious
  direction.
- Greenfield → `enabled: true`, and the file records why.
- Brownfield → left `false`, and init prints the one-line enable command
  instead of leaving the operator to discover it.
- A pre-existing file is never touched — the run only sets a default on a file
  it created this run.
- `seed/task-enforcement.json.template` and `content/task-enforcement-rules.md`
  both describe the per-target rule now, replacing the flat "ships off".

## Verified by running

| Case | Result |
|---|---|
| `git init`, no commits, then install | `enabled = True`, "ENABLED (new project)" |
| Existing repo with code + history | `enabled = False` + enable command printed |
| Consumer sets `false`, re-runs init | `skip (exists)`, still `False` — not overwritten |

## Acceptance criteria

- [x] New project gets enforcement on
- [x] Existing project keeps it off, and is told how to enable it
- [x] A consumer's existing setting is never overwritten by re-init
- [x] Classification happens before any file is written
- [x] Both docs describe the per-target rule
- [x] `check-manifest` 182, `check-invocations` 0, `check-bash32` green,
      `bin/lint` 14 (baseline, TASK-055)
