---
name: auto-phase
description: Autonomous variant of /spec-phase — expands every stub in a named phase to a full, implementation-ready spec without asking any questions. Decides each spec's open questions itself and flags them as assumptions, then proposes a working order. Triggered when the user wants a whole phase spec'd hands-off — e.g. "/auto-phase", "spec out the whole phase autonomously", "auto-spec phase N", "expand every stub in this phase without asking me".
---

# /auto-phase — autonomous phase spec

`/spec-phase`, run with nobody at the keyboard. The normal
`/spec-phase` walks every stub in a phase and expands each to a
full spec, consulting the user along the way. `/auto-phase` does
the same walk and resolves every question itself, flagging each
decision, then hands back the full set of specs plus a proposed
working order.

Per CLAUDE.md ethos: no narratives. The report says plainly what
was decided and what's still uncertain — one honest review surface
for the whole phase.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — the
  contract, the hard-gate list, the report template. This
  SKILL.md states only what's specific to `auto-phase`.
- **The operation is `/spec-phase`.** Read `spec-phase/SKILL.md`
  and follow it — the phase walk, per-stub expansion, dependency
  analysis, and working-order proposal. `/auto-phase` runs that
  work without the questions.
- **Every stub becomes a full spec.** For each stub in the named
  phase, run the same expansion `/auto-task` does — full
  reconnaissance, questions resolved as flagged decisions.
- **Diligence per stub is not skipped.** Each spec gets real
  recon. A phase of twelve specs is twelve real reconnaissance
  passes, not twelve guesses.
- **One report for the whole phase.** Don't render a report per
  stub. The autonomy report at the end covers every spec, groups
  the assumptions by task, and lists the proposed working order.
- **The specs land by themselves, once.** Per
  `autonomy-rules.md` "Exception 2" (docs landing): `land.sh
  sync` before filing anything, then one `land.sh docs` call at
  the end (Process step 5) naming every spec file written,
  `tasks/PHASES.md` / `tasks/ROADMAP.md` / `tasks/history.tsv`
  when they changed, and the run record. A whole phase is a
  *single* landing carrying every new spec, not one PR per spec.
  It merges itself after CI, built on the latest trunk (see
  `land/SKILL.md`).
- **Watch for phase-collision.** Other sessions may already have
  task numbers filed against the same phase. Any task
  `/auto-phase` files gets its `TASK-NNN` from
  `.claude/bin/task new`, which allocates from the local
  `tasks/history.tsv` and disk — a stale ledger hands out an id
  the trunk already used. So `land.sh sync` first (Process step
  1), and `land.sh docs` refuses (exit 5) a landing whose task id
  the trunk already used: report it, never retry blindly.

## Process

1. **Read `autonomy-rules.md` and `spec-phase/SKILL.md`, then
   sync.** `bash .claude/skills/land/land.sh sync` before filing
   anything: ids come from the local ledger, so it must hold the
   latest trunk. A non-zero exit: report it, never retry blindly.
2. **Identify the phase.** From the user's argument, or — if
   absent — the current active phase in `tasks/PHASES.md`.
3. **Walk every stub in the phase.** For each, run the autonomous
   expansion: full recon, open questions decided and flagged,
   full spec written over the stub in the shape of
   `.claude/task-templates/<type>.md`, then
   `.claude/bin/check-tasks --fix` (I-34).
4. **Propose a working order** with dependency analysis, as
   `/spec-phase` does.
5. **Land the phase** (per `autonomy-rules.md` Exception 2, docs
   landing). One call, once every spec is written and validated:

   ```bash
   bash .claude/skills/land/land.sh docs --skill auto-phase --title "PHASE-<id> specs — <title>" --summary "<working order; assumptions>" --tasks "<ids>" -- <spec files> tasks/PHASES.md tasks/ROADMAP.md tasks/history.tsv tasks/runs/<RUN-id>.md
   ```

   Name every `tasks/backlog/TASK-*.md` (or `tasks/triage/…`)
   this run wrote; `tasks/PHASES.md`, `tasks/ROADMAP.md` and
   `tasks/history.tsv` only when they changed; and the run record,
   closed first so the copy that lands is final. `land.sh`
   classifies every file and refuses (exit 3) any that is not docs
   class, so pass only what this run wrote. Exit 4 (no `gh`):
   finish with the session's GitHub tooling per `land/SKILL.md`
   "Without `gh`". Exits 5/6/7: report, never retry blindly; on 6
   the PR stays open. As a step of `/mission`, `/self-heal` or
   `/self-improve`, skip this: the orchestrator's branch and PR
   carry the specs.
6. **Render one autonomy report** covering the whole phase — specs
   written, assumptions grouped by task, working order, any hard
   gate hit, and the landing line: `Landed: PR #N merged` or
   `Not landed: exit N — <message>`.

## When NOT to use this skill

- **You want to review each spec as it's drafted** → use
  `/spec-phase`.
- **A single task**, not a whole phase → use `/auto-task`.
- **Implementing the phase's tasks** once spec'd → use
  `/auto-develop` per task.

## What "done" looks like

Every stub in the named phase is now a full, implementation-ready
spec, with a proposed working order and one autonomy report
covering every decision made across the phase.

Every new spec is on the trunk via a single merged `land.sh docs`
PR (in a composed run, the orchestrator's PR carries them). The
team has the full phase visible. The user reviews the report and
the PR after the fact.

If the landing did not merge, the report names the exit code and
what is still open.
