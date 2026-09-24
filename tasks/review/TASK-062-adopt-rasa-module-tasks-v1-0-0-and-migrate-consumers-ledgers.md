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

- [x] `bin/check-manifest` passes, and fails when a vendored file is edited in place.
- [x] This repository's `tasks/` validates with `content/bin/check-tasks`: zero errors.
- [x] No shipped file writes `status:` / `category:` or moves a task with `git mv`; `bin/lint`, `bin/check-invocations`, `bin/check-bash32` and `bin/test-contract` pass.
- [x] `bin/init` into an empty directory installs a ledger that validates with zero errors.
- [x] `bin/init` re-run over a copy of a real 0.x consumer ledger migrates it to zero errors, leaving the change uncommitted.
- [x] `task-enforce.sh` and `task-guard.sh` file tasks through `.claude/bin/task` and the result validates.
- [x] Version 0.53.0 with a BREAKING changelog entry naming the upgrade command.

## Expected files

`vendored.json`, `rasa.json`, `bin/{check-manifest,init,migrate-ledger,migrate-tasks}`, `content/{task-rules.md,code-task-rules.md,task-templates/,bin/}`, `content/skills/{task,backlog,roadmap,task-enforce,task-guard,sync,sync-all}/`, every skill / mode / rule that references the task shape, `seed/{done-gate.md.template,tasks/}`, `tasks/`, `CHANGELOG.md`, `README.md`, `VERSION`.

## Notes

- Verified 2026-09-23 on `5eb47fa`: check-manifest (27 vendored files byte-identical to module-tasks v1.0.0), lint, check-invocations, check-bash32 (bash 3.2 gate), test-contract, and this ledger (62 tasks, 0 errors) all pass; `bin/init` into an empty git repo gives a ledger with 0 errors.
- `sync.sh plan` + `apply --hold` against fresh clones of five consumers: vsi-web 123 tasks / 1 error, vsi-ios 140 / 1, kernel 256 / 0, rasa-console 350 / 5, rasa-website 0 / 0. Every remaining error is I-24 — a ROADMAP line naming a task file that does not exist — which the module never auto-fixes; each is listed in that project's MIGRATION-REVIEW.md. kernel's plan correctly flagged one real local edit (`.claude/skills/deploy/SKILL.md`), which `--hold` left untouched.
- Hooks exercised in a scratch install: the PreToolUse deny-once flow, `stamp` (same-day re-stamp stays valid; a raw edit trips I-34 as a control), and two real commits through the pre-commit hook.
- Follow-ups filed outside this task: upstream the ledger preparation into module-tasks; stop bin/init cloning a `kit/` stash; the two writers of `tasks/CHANGES.md`.
