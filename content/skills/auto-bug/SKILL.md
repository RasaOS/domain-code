---
name: auto-bug
description: Autonomous variant of /task for Bug-category tasks — files a bug task and expands it to a full, implementation-ready spec without asking. Reproduces the bug from the user's description where possible, captures steps to reproduce, expected vs. actual behavior, root-cause notes, and acceptance criteria for the fix. Every judgment call is flagged as an assumption. Triggered when the user wants a bug fully spec'd hands-off — e.g. "/auto-bug", "file and fully spec this bug yourself", "auto-spec a bug for the broken login", "the dashboard shows yesterday's date — file and spec it autonomously".
---

# /auto-bug — autonomous Bug-category task spec

`/task` Operation 1, Bug category, run with nobody at the
keyboard. The normal `/task` flow asks the category, the phase,
and a round of context questions; `/auto-bug` decides all of them
itself, flags each as an assumption, and hands back a complete
Bug spec using `task-template-bug.md`.

Per CLAUDE.md ethos: a bug is something *verifiably broken*, not
something subjectively wrong. The spec captures real reproduction
steps and the observable wrong behavior — not what the developer
*thinks* the bug is.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — the
  contract, the hard-gate list, the report template. This
  SKILL.md states only what's specific to `/auto-bug`.
- **The operation is `/task` Operation 1 with Bug category.** Read
  `task/SKILL.md` and `task-rules.md` "Categories". `/auto-bug`
  follows that operation; it does not redefine the work.
- **Always a full spec.** A Bug task always gets the full
  `task-template-bug.md` template filled in. No stub-content for
  bugs that have been triaged — if the work is real enough to be
  filed as a bug, it's real enough to be reproducible.
- **Reproduce where possible.** Operation 3.5 (requirements
  drilling) for a bug specifically means: try to reproduce the
  symptom from the user's description, capture the actual
  observable behavior, then ground the spec in what you saw —
  not what the user assumed.
- **Root cause is a flagged assumption, not a guarantee.** If
  the root cause is determinable without fixing (a clear
  reading of the broken code), state it. If not, leave the
  template's "Root cause" section as `Unknown — to be determined
  during fix.` and flag the gap.
- **Phase is the broken functionality's phase, not a "bugs"
  phase.** A login bug belongs to the auth phase. The skill
  decides phase by reading where the broken code lives.
- **Spec-file fast-path is the default.** Per `autonomy-rules.md`
  Exception 2 — same allowlist as `/auto-task`. If the working
  tree is spec-files-only, the bug spec auto-merges to `main`
  via a `spec/TASK-NNN` PR. Otherwise leave uncommitted.
- **Never auto-commit code.** The bug FIX is `/auto-develop`'s
  job. `/auto-bug` writes the contract, not the implementation.

## Process

1. **Read `autonomy-rules.md`, `task/SKILL.md`, `task-rules.md`,
   and `task-template-bug.md`.** Plus the project's `CLAUDE.md`
   for verification commands.
2. **Parse the bug from the user's description.** Extract: the
   user-visible symptom, the affected functionality, any
   reproduction hints the user gave.
3. **Attempt reproduction.** Where possible without changing
   state — run the project's verification or smoke test, read
   the relevant code, look for the failure signal. Capture what
   you actually saw, not what you expected.
4. **Determine the phase** by reading where the broken code
   lives. If the broken functionality spans multiple phases, file
   to the phase that *owns* the symptomatic surface (auth phase
   for a login bug, even if the actual broken code is in a
   shared utility). Flag the choice as an assumption.
5. **Run full reconnaissance** — internal (the broken code, its
   tests, its callers) and external (current docs for the
   framework, if relevant). The Bug template's "Root cause"
   section is filled from this recon where possible.
6. **Assign ID.** Next available `TASK-NNN` (Bug uses the regular
   TASK-NNN space, not HOTFIX-NNN).
7. **Write the full Bug spec** to `tasks/backlog/TASK-NNN-slug.md`
   using `task-template-bug.md`'s shape. Update `tasks/ROADMAP.md`
   under the bug's phase.
8. **Spec-file fast-path** per `autonomy-rules.md` Exception 2.
   Same allowlist as `/auto-task`.
9. **Render the autonomy report** — the bug spec path, every
   assumption (especially the root-cause guess if any), any hard
   gate hit, and the fast-path result.

## When NOT to use this skill

- **The work is a new feature, not a fix** → `/auto-task` (Spec
  category).
- **The bug is *urgent* — prod is broken right now** →
  `/auto-hotfix`. The procedural distinction matters; route
  through the hotfix flow.
- **You want to drive the spec yourself** → `/task` (interactive
  variant). `/auto-bug` decides everything.
- **Implementing the fix** → `/auto-develop`. `/auto-bug` writes
  the contract; `/auto-develop` builds against it.

## What "done" looks like

A complete, implementation-ready Bug spec in `tasks/backlog/`,
`ROADMAP.md` updated under the broken functionality's phase,
plus one autonomy report. If the spec-file fast-path engaged:
the spec is on `main` via a merged `spec-only` PR. Otherwise:
uncommitted, for the user to review and commit. The fix routes
through `/auto-develop` next.
