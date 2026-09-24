---
name: auto-hotfix
description: Autonomous variant of /task for hotfixes — files an urgent production fix as a `defect` with `priority: now` and writes its full spec without asking. Captures what's broken in prod, why it's a hotfix and not a bug, the smallest fix that solves it, rollback plan, and post-fix verification. `priority: now` lands it directly in tasks/active/ (no backlog stop) under the broken functionality's phase, with a regular TASK-NNN id — the HOTFIX-NNN id space is retired. Triggered when prod is broken or imminently failing — e.g. "/auto-hotfix", "prod is down — file a hotfix spec yourself", "auto-spec the data-corruption hotfix".
---

# /auto-hotfix — autonomous hotfix task spec

`/task`'s **File a task** as a hotfix (`code-task-rules.md` §4),
run with nobody at the keyboard. Production is broken or
imminently failing and the user wants the hotfix spec drafted
**now**, not after a round of questions. `/auto-hotfix` decides
every judgment call itself, flags each, and hands back a
complete hotfix spec in the shape of
`.claude/task-templates/defect.md`.

Per CLAUDE.md ethos: a hotfix is a *procedural* commitment — it
ships ASAP. The skill enforces the discipline that comes with
that commitment: the smallest fix, a rollback plan, no scope
creep. Adjacent improvements get filed as follow-on `defect`
tasks *after* the hotfix ships, not during it.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — the
  contract, the hard-gate list, the report template.
- **The operation is `/task`'s File a task, as a hotfix.** Read
  `task/SKILL.md` **File a task** and `code-task-rules.md` §4
  (Hotfixes). `/auto-hotfix` follows that operation; it does not
  redefine the work.
- **Urgency is the discriminator.** The skill verifies the
  user's framing indicates real urgency — "prod is down",
  "data corruption", "regulatory deadline", "customer release
  blocked", "security vulnerability". If the urgency framing is
  absent, **stop at a hard gate**: this is an ordinary `defect`,
  not a hotfix. Route the user to `/auto-bug`.
- **A regular `TASK-NNN` id.** Per `code-task-rules.md` §4 the
  `HOTFIX-NNN` id space is retired — it forced a
  reference-breaking rename every time the urgency passed. A
  hotfix is a `defect` with `priority: now`, and
  `.claude/bin/task new` allocates its id. If the urgency passes
  before it ships, `task-enforce.sh stamp <id> priority high`;
  the id never changes.
- **Filed under the broken functionality's phase.**
  `priority: now` needs a phase (I-14, I-19): the one whose
  functionality is broken, decided the way `/auto-bug` decides
  it. `bin/task new` writes the `tasks/ROADMAP.md` line itself.
  If `ROADMAP.md` declares no phase at all, **stop at a hard
  gate** — a phase's scope paragraph is the user's to write.
- **Lands directly in `tasks/active/`.** `--priority now` routes
  it there; no backlog stop. Hotfixes are being worked, by
  definition.
- **The smallest fix.** Requirements drilling (step 9 of
  `task/expanding-a-task.md`) for a hotfix specifically means:
  identify the smallest change that solves the user-visible
  symptom. Adjacent improvements get listed under the template's
  **Out of scope, deliberately** as follow-up `defect` stubs,
  *not* expanded into the hotfix's scope.
- **Rollback plan is mandatory, not optional.** The hotfix spec
  must name the revert command and what state the project will
  be in if rollback runs, under **Blast radius and reversal**. A
  hotfix without a rollback plan is a hotfix that can't be
  safely shipped.
- **Spec-file fast-path is the default.** Per `autonomy-rules.md`
  Exception 2 — the hotfix spec file and the `tasks/history.tsv`
  and `tasks/ROADMAP.md` lines filing it wrote all match the
  allowlist, so if the working tree is spec-files-only, it
  auto-merges to `main` via a `spec/TASK-NNN-slug` PR.
- **Never auto-commit code.** The hotfix FIX is `/auto-develop`'s
  job, on a `hotfix/TASK-NNN-slug` branch per
  `code-task-rules.md` §10. `/auto-hotfix` writes the contract.

## Process

1. **Read `autonomy-rules.md`, `task/SKILL.md`, `task-rules.md`,
   `code-task-rules.md` (§4 Hotfixes, §10 for the hotfix branch
   convention), `.claude/task-templates/defect.md`, and
   `release-rules.md` (the hotfix path).** Plus the project's
   `CLAUDE.md`.
2. **Verify urgency.** Parse the user's description for the
   urgency framing. If it's clear ("prod is down", "data
   corruption", etc.), proceed. If the framing is soft ("would
   be nice to fix", "annoying bug"), **stop at a hard gate** and
   route to `/auto-bug`. Urgency is not a guess.
3. **Capture what's broken in prod.** The user-visible symptom
   AND the technical root cause where determinable. Be precise.
4. **Identify the smallest fix.** Read the broken code; figure
   out the minimal change that solves the symptom. Anything
   beyond that minimum becomes a follow-up `defect`, listed
   under **Out of scope, deliberately** in the spec.
5. **Write the rollback plan.** What reverts the hotfix if it
   itself breaks something? Capture: the revert command, the
   resulting state, who can authorize escalation if needed.
6. **File it.**

   ```bash
   .claude/bin/task new --type defect --priority now --phase <P> \
     --by "$(bash .claude/skills/task-enforce/task-enforce.sh who)" "<what is broken>"
   ```

   `<P>` is the broken functionality's phase, and the actor is
   `$RASA_ACTOR` folded to a lowercase handle. The command
   allocates the `TASK-NNN` id, lands the file in
   `tasks/active/`, and writes the `tasks/history.tsv` and
   `tasks/ROADMAP.md` lines. Never write any of those by hand.
7. **Write the full hotfix spec** into the file the command
   reported (`tasks/active/TASK-NNN-slug.md`), in the shape of
   `.claude/task-templates/defect.md`, then run
   `.claude/bin/check-tasks --fix` (I-34).
8. **Surface the rest of the path** in the report: branch
   `hotfix/TASK-NNN-slug` per `code-task-rules.md` §10 —
   implementation starts on that branch;
   `.claude/bin/task submit <id>` when the fix's PR opens;
   `.claude/bin/task pass <id> --by <actor> --note "<evidence>"`
   (the tool records it as `gate: <evidence>`) once the
   done-gate passes and the PR merges; then the 🔥
   `tasks/AUDIT.md` entry and the postmortem
   (`code-task-rules.md` §4, §13).
9. **Spec-file fast-path** per `autonomy-rules.md` Exception 2.
10. **Render the autonomy report** — the hotfix spec path, the
    branch name to use, the urgency justification, every
    assumption, any hard gate hit, and the fast-path result.

## When NOT to use this skill

- **The bug is not actually urgent** → `/auto-bug`. The
  procedural distinction matters; if it can wait a day, it's an
  ordinary `defect`, not a hotfix.
- **The work is a new feature** → `/auto-task` (a `change`).
- **You want to drive the spec yourself** → `/task` (interactive
  variant; file it with `--type defect --priority now`).
- **Implementing the fix** → `/auto-develop` on the
  `hotfix/TASK-NNN-slug` branch.
- **Shipping the fix** → `/release` (after the fix lands on
  `main` via the hotfix branch). `/release`'s hotfix path
  defaults to a patch bump.

## What "done" looks like

A complete, implementation-ready hotfix spec at
`tasks/active/TASK-NNN-slug.md` — a `defect` with
`priority: now` — with urgency, smallest fix, rollback plan, and
post-fix follow-ups captured, and listed in `ROADMAP.md` under
the broken functionality's phase. The autonomy report names the branch to
use (`hotfix/TASK-NNN-slug`) and the next skill in the chain
(`/auto-develop` on that branch). If the spec-file fast-path
engaged: the spec is already on `main` via a merged PR. The fix
is the user's next action, urgently.
