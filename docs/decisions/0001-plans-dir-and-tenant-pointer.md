# ADR 0001 — Request plans live in `docs/plans/`; a tenant is found by an explicit pointer

**Status:** Accepted
**Date:** 2026-11-17
**Decider(s):** Chazz Romeo (via the crew lead)

## Context

v0.63.0 adds a required flow: a request audit (`docs/audits/`), a request plan, tasks that link both through `x-audit`
/ `x-plan`, and `/develop`. The plan needs a home in every install, and `/land` decides by path whether a file self-lands
(docs) or goes by an unmerged PR (code): `land.py:62-65` `DOCS_DIRS` has no plans dir today. A design flow (R2) will
produce design plans too. The flow also reads the tenant's sources of truth "when there is a tenant", but no field or
path in an install names a tenant, and the shipped Element must not hard-code the author's machine.

## Decision

All plans (request now, design in R2) save to `docs/plans/<date>-<slug>.md` with a fixed `**Kind.**` header line, and
`docs/plans/` joins `/land`'s docs class (`land.py DOCS_DIRS`, `land/SKILL.md:34`, `autonomy-rules.md:151`,
`bin/test-land`). A tenant is found by an explicit pointer (a `tenant:` line in `.claude/rasa-deployment.md`, or
`RASA_TENANT`); with no pointer the flow reports `tenant: none` and carries on.

## Alternatives considered

### Option A — plans under `docs/audits/`
No `/land` change. Rejected: mixes two document kinds in one dir and audit tooling that globs the dir would pick plans up.

### Option B — the plan is the task body
No new file. Rejected: one plan often files several tasks, and the plan loses its own validate step and history.

### Option C — one dir per plan kind (`docs/plans/`, later `docs/designs/`)
Clear separation. Rejected: every new kind needs another `/land` edit and ADR; the `**Kind.**` line separates them.

### Option D — discover the tenant by walking up for a parent `rasa.json` listing this repo
Zero config. Rejected as the primary path: depends on a `tenant.members[]` field not confirmed in canon, reads
arbitrary parent folders, and can pick the wrong tenant silently. May be added later once canon defines the field.

## Consequences

**Positive**
- Plans land by themselves like audits and decisions; nothing is lost in a working tree.
- R2's design plans need no further `/land` change.
- The tenant read is deterministic and visible in a project-owned file; no-tenant installs are unaffected.

**Negative / costs**
- Four surgical edits to `/land` and its rule text; `bin/test-land` grows a case.
- Existing installs must add one `tenant:` line by hand (the seed change reaches new installs only).

**Neutral / notable**
- `x-audit` / `x-plan` (and `x-design`, reserved for R2) are project-namespace keys; `check-tasks` does not validate
  them, `/develop gate` does.
- A follow-up to `RasaOS/module-tasks` may promote them to known keys.

## Revisit triggers

- Canon defines a tenant manifest field that lists member repos.
- The kernel mounts the tenant at a fixed path in installs (Pattern 3 `/rasa/app/`) for non-kernel projects too.
- module-tasks adopts audit/plan links as first-class task fields.

## References

- The crew architecture read of the request flow (F1, F4)
- `content/skills/land/land.py:61-67`, `content/skills/land/SKILL.md:34-35`
- `content/task-rules.md:183,200`
- `seed/rasa-deployment.md.template:14`
