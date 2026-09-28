---
name: auto-bug
description: Autonomous variant of /task for bugs — files a `defect` task and expands it to a full, implementation-ready spec without asking. Reproduces the bug from the user's description where possible, captures steps to reproduce, expected vs. actual behavior, root-cause notes, and acceptance criteria for the fix. Every judgment call is flagged as an assumption. Triggered when the user wants a bug fully spec'd hands-off — e.g. "/auto-bug", "file and fully spec this bug yourself", "auto-spec a bug for the broken login", "the dashboard shows yesterday's date — file and spec it autonomously".
---

# /auto-bug — autonomous defect task spec

`/task`'s **File a task** with `--type defect`, run with nobody
at the keyboard. The normal `/task` flow asks the type, the
phase, and a round of context questions; `/auto-bug` decides all
of them itself, flags each as an assumption, and hands back a
complete defect spec in the shape of
`.claude/task-templates/defect.md`.

Per CLAUDE.md ethos: a bug is something *verifiably broken*, not
something subjectively wrong. The spec captures real reproduction
steps and the observable wrong behavior — not what the developer
*thinks* the bug is.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — the
  contract, the hard-gate list, the report template. This
  SKILL.md states only what's specific to `/auto-bug`.
- **The operation is `/task`'s File a task, `--type defect`.**
  Read `task/SKILL.md` and `code-task-rules.md` §3 (types).
  `/auto-bug` follows that operation; it does not redefine the
  work.
- **Always a full spec.** A `defect` task always gets the full
  `.claude/task-templates/defect.md` shape filled in. No stub
  depth for bugs that have been triaged — if the work is real
  enough to be filed as a bug, it's real enough to be
  reproducible.
- **Reproduce where possible.** Requirements drilling (step 9 of
  `task/expanding-a-task.md`) for a bug specifically means: try
  to reproduce the symptom from the user's description, capture
  the actual observable behavior, then ground the spec in what
  you saw — not what the user assumed.
- **Root cause is a flagged assumption, not a guarantee.** If
  the root cause is determinable without fixing (a clear
  reading of the broken code), state it. If not, leave the
  template's "Cause, so far as it is known without fixing it"
  section as `Not yet known.` and flag the gap.
- **Phase is the broken functionality's phase, not a "bugs"
  phase.** A login bug belongs to the auth phase. The skill
  decides phase by reading where the broken code lives.
- **Docs landing is the default.** `autonomy-rules.md`
  Exception 2 (docs landing) covers `/auto-bug` by class, not by
  name: the defect spec, its `tasks/history.tsv` and
  `tasks/ROADMAP.md` lines, and the run record are docs class, so
  they land exactly as `/auto-task`'s do — `land.sh sync` before
  filing, `land.sh docs` at the end: a PR from the latest trunk
  that merges itself after CI. Other changes in the working tree
  neither block it nor ride along — landing is path-scoped.
- **Never auto-commit code.** The bug FIX is `/auto-develop`'s
  job — code, which goes by PR. `/auto-bug` writes the contract, not the implementation.

## Process

1. **Read `autonomy-rules.md`, `task/SKILL.md`, `task-rules.md`,
   and `.claude/task-templates/defect.md`.** Plus the project's
   `CLAUDE.md` for verification commands.
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
   framework, if relevant). The defect template's cause section
   is filled from this recon where possible.
6. **Sync, then file it.** Ids come from the local ledger, so it
   must hold the latest trunk (report a non-zero sync exit; never
   retry it blindly):

   ```bash
   bash .claude/skills/land/land.sh sync
   .claude/bin/task new --type defect --phase <P> \
     --by "$(bash .claude/skills/task-enforce/task-enforce.sh who)" "<what is wrong>"
   ```

   The actor is `$RASA_ACTOR` folded to a lowercase handle. The
   command allocates the next `TASK-NNN` (a bug and a hotfix
   share the one id space), lands the file in `tasks/backlog/`,
   and writes the `tasks/history.tsv` and `tasks/ROADMAP.md`
   lines.
7. **Write the full defect spec** into the file the command
   reported (`tasks/backlog/TASK-NNN-slug.md`), in
   `.claude/task-templates/defect.md`'s shape, then run
   `.claude/bin/check-tasks --fix` (I-34).
8. **Land the spec** per `autonomy-rules.md` Exception 2, as
   `/auto-task` does. Once the spec is validated and the run
   record is closed (`.claude/skills/runs/runs.sh close`):

   ```bash
   bash .claude/skills/land/land.sh docs --skill auto-bug --title "spec TASK-NNN: <what is wrong>" --tasks TASK-NNN -- tasks/backlog/TASK-NNN-slug.md tasks/history.tsv tasks/ROADMAP.md tasks/runs/<RUN-id>.md
   ```

   Exit 4 (no `gh`): finish with the session's GitHub tooling per
   `land/SKILL.md` "Without `gh`". Exits 5/6/7: report, never
   retry blindly. As a step of `/mission`, `/self-heal` or
   `/self-improve`, skip this: the orchestrator's branch and PR
   carry the spec.
9. **Render the autonomy report** — the bug spec path, every
   assumption (especially the root-cause guess if any), any hard
   gate hit, and one landing line: `Landed: PR #N merged` or
   `Not landed: exit N — <message>`.

## When NOT to use this skill

- **The work is a new feature, not a fix** → `/auto-task` (a
  `change`).
- **The bug is *urgent* — prod is broken right now** →
  `/auto-hotfix`. The procedural distinction matters; route
  through the hotfix flow.
- **You want to drive the spec yourself** → `/task` (interactive
  variant). `/auto-bug` decides everything.
- **Implementing the fix** → `/auto-develop`. `/auto-bug` writes
  the contract; `/auto-develop` builds against it.

## What "done" looks like

A complete, implementation-ready defect spec in `tasks/backlog/`,
`ROADMAP.md` updated under the broken functionality's phase,
plus one autonomy report. Landed: the spec, its ledger lines and
the run record are on the trunk via a merged `land.sh docs` PR.
Not landed: the report names the exit code and what is still
open; in a composed run, the orchestrator's PR carries the spec.
The fix routes through `/auto-develop` next, by PR.
