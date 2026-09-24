---
id: TASK-062
type: change
created: 2026-09-23
created_by: claude
updated: 2026-09-23
phase: P7
---
# TASK-062: Adopt rasa.module.tasks v1.0.0 and migrate consumers' ledgers on update

**User story.** As **the operator of every repo that installs `rasa.domain.code`**, I want **the Element to ship `rasa.module.tasks` v1.0.0 as its task system, and an update to convert my existing ledger** so that **every repo runs one validated lifecycle — `review/` and `closed/`, no `status:` drift, `bin/task` and `bin/check-tasks` — without anyone hand-migrating hundreds of task files**.

**Why.** `rasa.module.tasks` v1.0.0 (2026-09-20) was distilled from this Element and then rebuilt against 558 real task files; this Element still ships the 0.x shape it replaced (`status:` disagreed with its directory in 301 of 536 files). No installer resolves `requires.elements[]`, so the module reaches consumers only if this Element carries it.

## Scope

- Vendor the module's v1.0.0 spine, templates, `/task` `/backlog` `/roadmap`, `bin/task`, `bin/check-tasks`, seeds and `bin/migrate-tasks`, byte-identical and checksum-pinned (`vendored.json`, `bin/check-manifest`).
- The engineering half the module leaves to its parent: `code-task-rules.md` and an engineering `done-gate.md` seed.
- Every skill, mode, rule and script that files, moves or reads tasks uses `bin/task` verbs and the v1.0.0 frontmatter.
- The update path (`bin/init` re-run; `/sync` delegates to it) migrates a pre-1.0 ledger via `bin/migrate-ledger`.
- Migrate this repository's own ledger.

Out of scope: TASK-041's full `/sync` port (three-way diff, `/promote`); retiring `tasks/PHASES.md`.

## Acceptance criteria

- [ ] `bin/check-manifest` passes, and fails when a vendored file is edited in place.
- [ ] This repository's `tasks/` validates with `content/bin/check-tasks`: zero errors.
- [ ] No shipped file writes `status:` / `category:` or moves a task with `git mv`; `bin/lint`, `bin/check-invocations`, `bin/check-bash32` and `bin/test-contract` pass.
- [ ] `bin/init` into an empty directory installs a ledger that validates with zero errors.
- [ ] `bin/init` re-run over a copy of a real 0.x consumer ledger migrates it to zero errors, leaving the change uncommitted.
- [ ] `task-enforce.sh` and `task-guard.sh` file tasks through `.claude/bin/task` and the result validates.
- [ ] Version 0.53.0 with a BREAKING changelog entry naming the upgrade command.

## Expected files

`vendored.json`, `rasa.json`, `bin/{check-manifest,init,migrate-ledger,migrate-tasks}`, `content/{task-rules.md,code-task-rules.md,task-templates/,bin/}`, `content/skills/{task,backlog,roadmap,task-enforce,task-guard,sync,sync-all}/`, every skill / mode / rule that references the task shape, `seed/{done-gate.md.template,tasks/}`, `tasks/`, `CHANGELOG.md`, `README.md`, `VERSION`.

## Notes
