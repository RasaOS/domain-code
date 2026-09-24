---
id: TASK-062
type: change
created: 2026-09-23
created_by: claude
updated: 2026-09-23
phase: P7
completed_by: claude
x-outcome: shipped
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
- `sync.sh plan` + `apply --hold` against copies of five installed ledgers (up to 350 tasks): all converted; every remaining error is I-24 — a ROADMAP line naming a task file that does not exist — which the module never auto-fixes; each is listed in that ledger's MIGRATION-REVIEW.md. One copy's plan correctly flagged a real local edit, which `--hold` left untouched.
- Hooks exercised in a scratch install: the PreToolUse deny-once flow, `stamp` (same-day re-stamp stays valid; a raw edit trips I-34 as a control), and two real commits through the pre-commit hook.
- Follow-ups filed outside this task: upstream the ledger preparation into module-tasks; stop bin/init cloning a `kit/` stash; the two writers of `tasks/CHANGES.md`.

Gate satisfied 2026-09-23 by claude — all eight gates recorded in the completion report; Public remedied in 0.53.1

## Completion report

| | |
|---|---|
| **Outcome** | done |
| **Type** | change |
| **Branch** | `task/TASK-062-adopt-module-tasks-v1` |
| **PR** | [#11](https://github.com/RasaOS/domain-code/pull/11), merged as `d2844e5`; tagged `v0.53.0` |
| **Tests** | CI 8/8 green (manifest + schema, bash 3.2 floor, stock macOS bash, lint); local gates as in Notes |
| **Build** | n/a — no build step in this repository |

**Done-gate** (per `.claude/done-gate.md`)
- Manifest: pass · `bin/check-manifest` OK, 27 vendored files byte-identical to module-tasks v1.0.0.
- Lint: pass · `bin/lint` clean.
- Scripts: pass · every script parses with its own interpreter (CI "Scripts parse"); `bin/check-bash32` clean.
- Behaviour: pass · `bin/test-contract` green; `bin/init` smoke-tested into an empty repo and over copies of installed ledgers; hooks exercised in a scratch install.
- Ledger: pass · `content/bin/check-tasks .` — 0 errors.
- CI: pass · PR #11, 8/8 checks green.
- Merged: pass · PR #11 merged to `main` as `d2844e5` with the owner's explicit go-ahead.
- Public: not yet a gate at merge — added by this close-out because the change failed it: the v0.53.0 notes and this task's notes named private repositories. Remedied by TASK-063 (0.53.1) in every file going forward; history and the v0.53.0 tag keep them.

**What changed** — rasa.module.tasks v1.0.0 vendored and pinned; code-task-rules.md + done-gate seed; bin/init migrates a pre-1.0 ledger; hooks file through bin/task; /sync rebuilt on sync.sh; ~60 shipped files swept; this ledger migrated; 0.53.0.

**What to do next**
1. Keep existing installations off 0.53.x until a later release opens the upgrade (TASK-063, v0.53.1).
2. The follow-ups filed outside this task: upstreaming the ledger preparation into module-tasks; `bin/init`'s `kit/` stash; the two writers of `tasks/CHANGES.md`.

**Things I noticed** — tasks/PHASES.md is still seeded beside ROADMAP's phase registry; /contribute still rests on the pre-canon lockfile (TASK-041).
