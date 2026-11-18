# Flow rules (universal)

The path from a request to merged code, the artifact each stage
leaves, and the gate between stages. Read with `ui-rules.md`.

## The flow

**audit → plan → task → develop**

| Stage | Skill | Leaves |
|---|---|---|
| Audit | `/audit` | `docs/audits/<date>-<slug>.md`, Kind `request` |
| Plan | `/plan` | `docs/plans/<date>-<slug>.md`, Kind `request`, citing the audit |
| Task | `/task` | a task carrying `x-audit`, `x-plan`, and `x-ui` when a screen is touched |
| Develop | `/develop` | a branch and a PR; the task moves to `review/` |

After the PR merges, `/reconcile <id>` runs the trunk done-gate and
lands the move to `completed/` through the one sanctioned path. There
is no other way to a `pass`.

## Gates

- `/develop` checks the task before it starts: the audit and the plan
  named by `x-audit` and `x-plan` exist and validate; the task body
  has no unfilled `<to-fill …>` blanks; the UI block is filled when
  `x-ui: true`; the Data block is filled.
- A task whose Data block names a **locked contract** stops there.
- Every template marks a blank with `<to-fill …>`, and every
  `validate` fails while one remains. A slot that does not apply is
  filled with one line: `Not touched: <why>`.

## Exemptions

- `priority: now` defects and stub-depth tasks skip the audit and plan
  link.
- `/auto-develop` keeps its own entry. It reuses only the unfilled-blank
  check and the sources-of-truth read; the audit and plan link applies
  to `/develop`, and only to tasks that carry `x-plan`.

## Slots every request carries

- **Data.** Either `Not touched: <why>`, or: the entities and fields
  read or changed; who owns the schema (`code-task-rules.md` §8); the
  contract stamp and whether it is locked (`contract-rules.md`); the
  migration file name (`migration-rules.md`); whether `/schema-check`
  runs. There is no second copy of data-model rules here.
- **UI and screens.** Per `ui-rules.md`: size classes, states, back
  stack, accessibility, feedback, visuals, and the **Design source**.
  Or `Not touched: <why>`.

## Sources of truth

Read them before an audit or a plan, and cite what you used.

1. The repo: `CLAUDE.md`, `docs/`, the conventions files.
2. The **tenant**, when there is one. It is named by one explicit
   pointer: a `tenant: <path>` line in `.claude/rasa-deployment.md`, or
   the `RASA_TENANT` environment variable. Nothing is searched for. Read
   its `contracts/`, `conventions/`, `decisions/` and `design/`
   folders and its `CLAUDE.md`. **A tenant contract wins over the
   repo.** No pointer means no tenant: say `tenant: none` and go on.

## Where the blocks are enforced

The UI, Data and Design source blocks are enforced at `/develop`
only, until the task templates themselves carry them.
