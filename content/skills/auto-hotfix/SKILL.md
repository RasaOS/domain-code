---
name: auto-hotfix
description: Autonomous variant of /task for Hotfix-category tasks — files a HOTFIX-NNN spec for an urgent production fix without asking. Captures what's broken in prod, why it's a hotfix and not a bug, the smallest fix that solves it, rollback plan, and post-fix verification. Files directly to tasks/active/ (no backlog stop), uses HOTFIX-NNN id space (not TASK-NNN), and skips ROADMAP per the hotfix contract. Triggered when prod is broken or imminently failing — e.g. "/auto-hotfix", "prod is down — file a hotfix spec yourself", "auto-spec the data-corruption hotfix".
---

# /auto-hotfix — autonomous Hotfix-category task spec

`/task` Operation 8 (file a hotfix), run with nobody at the
keyboard. Production is broken or imminently failing and the
user wants the hotfix spec drafted **now**, not after a round of
questions. `/auto-hotfix` decides every judgment call itself,
flags each, and hands back a complete Hotfix spec using
`task-template-hotfix.md`.

Per CLAUDE.md ethos: a hotfix is a *procedural* commitment — it
ships ASAP. The skill enforces the discipline that comes with
that commitment: the smallest fix, a rollback plan, no scope
creep. Adjacent improvements get filed as follow-on Bug tasks
*after* the hotfix ships, not during it.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — the
  contract, the hard-gate list, the report template.
- **The operation is `/task` Operation 8 (file a hotfix).**
  Read `task/SKILL.md` Operation 8 and `task-rules.md`
  "Categories" section on `hotfix`. `/auto-hotfix` follows that
  operation; it does not redefine the work.
- **Urgency is the discriminator.** The skill verifies the
  user's framing indicates real urgency — "prod is down",
  "data corruption", "regulatory deadline", "customer release
  blocked", "security vulnerability". If the urgency framing is
  absent, **stop at a hard gate**: this is a Bug, not a Hotfix.
  Route the user to `/auto-bug`.
- **`HOTFIX-NNN` id space.** Per `task-rules.md` and
  `git-flow-rules.md` Rule 1: hotfixes use a separate ID space
  from regular tasks. Next available `HOTFIX-NNN`.
- **Skips phase and ROADMAP.** Hotfixes are emergency work, not
  planned work. Frontmatter `phase: null`; no `ROADMAP.md` edit.
- **Files directly to `tasks/active/`.** No backlog stop.
  Hotfixes are being worked, by definition.
- **The smallest fix.** Operation 3.5 (requirements drilling)
  for a hotfix specifically means: identify the smallest change
  that solves the user-visible symptom. Adjacent improvements
  get captured under "Post-fix follow-ups" as stub Bug tasks,
  *not* expanded into the hotfix's scope.
- **Rollback plan is mandatory, not optional.** The hotfix spec
  must name the revert command and what state the project will
  be in if rollback runs. A hotfix without a rollback plan is a
  hotfix that can't be safely shipped.
- **Spec-file fast-path is the default.** Per `autonomy-rules.md`
  Exception 2 — the hotfix spec file matches the allowlist, so
  if the working tree is spec-files-only, it auto-merges to
  `main` via a `spec/HOTFIX-NNN` PR. (The branch name carries
  the HOTFIX prefix; the carve-out doesn't care.)
- **Never auto-commit code.** The hotfix FIX is `/auto-develop`'s
  job, on a `hotfix/HOTFIX-NNN-slug` branch per git-flow Rule 1.
  `/auto-hotfix` writes the contract.

## Process

1. **Read `autonomy-rules.md`, `task/SKILL.md`, `task-rules.md`,
   `task-template-hotfix.md`, `git-flow-rules.md` (Rule 1 for
   the hotfix branch convention), and `release-rules.md` (the
   hotfix path).** Plus the project's `CLAUDE.md`.
2. **Verify urgency.** Parse the user's description for the
   urgency framing. If it's clear ("prod is down", "data
   corruption", etc.), proceed. If the framing is soft ("would
   be nice to fix", "annoying bug"), **stop at a hard gate** and
   route to `/auto-bug`. Urgency is not a guess.
3. **Capture what's broken in prod.** The user-visible symptom
   AND the technical root cause where determinable. Be precise.
4. **Identify the smallest fix.** Read the broken code; figure
   out the minimal change that solves the symptom. Anything
   beyond that minimum becomes a follow-up Bug task, captured
   under "Post-fix follow-ups" in the spec.
5. **Write the rollback plan.** What reverts the hotfix if it
   itself breaks something? Capture: the revert command, the
   resulting state, who can authorize escalation if needed.
6. **Assign ID.** Next available `HOTFIX-NNN`.
7. **Write the full Hotfix spec** to
   `tasks/active/HOTFIX-NNN-slug.md` using
   `task-template-hotfix.md`. Do **not** touch `ROADMAP.md`.
8. **Surface the branch convention** in the report:
   `hotfix/HOTFIX-NNN-slug` per `git-flow-rules.md` Rule 1.
   Implementation starts on that branch.
9. **Spec-file fast-path** per `autonomy-rules.md` Exception 2.
10. **Render the autonomy report** — the hotfix spec path, the
    branch name to use, the urgency justification, every
    assumption, any hard gate hit, and the fast-path result.

## When NOT to use this skill

- **The bug is not actually urgent** → `/auto-bug`. The
  procedural distinction matters; if it can wait a day, it's a
  Bug, not a Hotfix.
- **The work is a new feature** → `/auto-task` (Spec).
- **You want to drive the spec yourself** → `/task` (interactive
  variant, Operation 8 for hotfix).
- **Implementing the fix** → `/auto-develop` on the
  `hotfix/HOTFIX-NNN-slug` branch.
- **Shipping the fix** → `/release` (after the fix lands on
  `main` via the hotfix branch). `/release`'s hotfix path
  defaults to a patch bump.

## What "done" looks like

A complete, implementation-ready Hotfix spec at
`tasks/active/HOTFIX-NNN-slug.md` with urgency, smallest fix,
rollback plan, and post-fix follow-ups captured. `ROADMAP.md`
unchanged. The autonomy report names the branch to use
(`hotfix/HOTFIX-NNN-slug`) and the next skill in the chain
(`/auto-develop` on that branch). If the spec-file fast-path
engaged: the spec is already on `main` via a merged PR. The fix
is the user's next action, urgently.
