---
id: TASK-077
type: defect
created: 2026-09-27
created_by: claude
updated: 2026-09-27
phase: P1
---

# TASK-077: git-guard autosave switches off trunk even when there is nothing to save

> **Type `defect`.** Something is wrong and should be put right. Use this
> when the work already exists and does not do what it is supposed to do.
>
> Before starting, read `.claude/task-rules.md` and `.claude/done-gate.md`.
> The done-gate, not this file, defines what *verified* means here.

## Intent

As **anyone whose project has `git-guard on`**, I want a `PreCompact` or
`Stop` checkpoint on trunk with nothing pending to leave my checkout
exactly where it was, so that autosave never becomes the reason a
checkout drifts off trunk.

`PreCompact` fires on every context compaction, whether or not anything
changed since the last save. Today, every one of those on trunk (or in
detached HEAD) switches the checkout to a brand-new, empty `wip/` branch
— nothing is wrong with the state that produces, but nothing ever
reclaims it either, and the checkout is left one step away from `main`
for however long the session runs after that. On a host that dispatches
agent work into whatever branch a checkout happens to be on, that step is
enough: work meant for trunk lands on a stale branch instead, quietly.

## Steps to reproduce

1. In a project with `git-guard` installed and its hooks on, check out
   trunk with a clean working tree.
2. Run `git-guard.sh autosave` directly (the same call `PreCompact` and a
   tripped `Stop` checkpoint make) — no edit needed first.
3. Check which branch the checkout is on.

**Conditions:** any repository the library can resolve a root for (a
`.claude/rasa.lock.json` between the cwd and the top of the repository).
No edit, no untracked file, no prior autosave state is needed — this
reproduces on a bare `git init` + one commit.

## Expected result

The checkout is still on trunk, at the same commit, and nothing was
printed. Autosave is documented as "Returns 0 on no-op."

## Observed result

The checkout is on a new branch, `wip/<host>-<YYYYMMDD-HHMM>`, at the same
commit (nothing was staged, so nothing was committed there either) —
an empty branch switch masquerading as a no-op. `git-guard: rescued work
onto isolated branch wip/…` is printed even though no work was rescued.
Confirmed with `bin/test-git-guard` (added by this task) against the
unfixed script: 5 of 24 assertions fail, all under the two cases that
have nothing to stage — a clean trunk, and an untracked file that is
skipped (secret-shaped) with nothing else pending.

## Cause

`cmd_autosave`'s "Rescue off trunk / detached HEAD onto an isolated wip
branch" step ran unconditionally, before staging anything and before the
existing `git diff --cached --quiet ... return 0 # nothing staged —
silent no-op` check. So the branch switch happened first, and the
no-op check only ever suppressed the *commit*, never the switch that had
already happened.

## Scope

**In scope**

- `content/skills/git-guard/git-guard.sh` — `cmd_autosave`: stage first
  (tracked changes, then untracked files past the existing
  secret/oversize filter, unchanged), check `git diff --cached --quiet`
  for a true no-op *before* the trunk rescue, and only then rescue.
  `checkout -b` leaves the index as it was, so reordering costs nothing
  when there genuinely is something to save. If the rescue checkout
  itself fails (both the `-b` attempt and the plain fallback), `git
  reset` undoes the staging first, so a failure still leaves the tree
  exactly as it was found — matching the old behaviour on that path,
  which never staged anything before attempting the switch.
- `bin/test-git-guard` (new): the reproduction, kept, plus the five
  scenarios that already worked and must go on working (a real change on
  trunk still gets rescued and committed; a real change already off
  trunk commits in place, no rescue). Wired into both CI jobs.
- `CHANGELOG.md`.

**Out of scope, deliberately**

- The `checkout -b` failure path itself is not exercised by the test —
  forcing a git checkout to fail portably (across the CI runners and
  stock macOS bash this repository tests against) is impractical to do
  reliably; the `git reset` added for it was read, not driven.
- Any other git-guard subcommand. `checkpoint`, `session-end`,
  `guard-commit`, `guard-push` do not touch this code path.
- Cleaning up `wip/` branches this bug already left behind in existing
  installs. Out of this repository's reach; `git-guard`'s own `status`
  and `audit` already name a leftover `wip/*` branch as something to
  merge or delete by hand.

## Artifacts expected to change

- `content/skills/git-guard/git-guard.sh`
- `bin/test-git-guard` (new)
- `.github/workflows/checks.yml` (two new steps)
- `CHANGELOG.md`
- `tasks/` (this task, its ROADMAP line, `history.tsv`)

## Acceptance criteria

- [x] Following "Steps to reproduce" now produces the expected result:
      the checkout stays on trunk, at the same commit, silent.
- [x] The reproduction is captured and re-runnable:
      `bin/test-git-guard` (1. clean trunk).
- [x] A real change on trunk is still rescued onto an isolated `wip/`
      branch and committed there (2. dirty trunk) — the fix narrows
      *when* the rescue runs, it does not remove it.
- [x] A real change already off trunk still commits in place, with no
      rescue message (5. already off trunk, a real change).
- [x] `bin/test-git-guard` passes against the fixed script (24/24) and
      fails against the unfixed one (19/24) for the documented reason.
- [x] The done-gate passes (`.claude/done-gate.md`), with the evidence
      recorded in `## Notes`.

## Verification

1. Reproduce the failure against the unfixed script
   (`TEST_GIT_GUARD_SCRIPT=<pre-fix copy> bin/test-git-guard`): fails,
   for the documented reason.
2. Apply the fix.
3. Re-run `bin/test-git-guard` against the fixed script: passes in full.
4. Neighbours: `bin/check-bash32`, `bin/lint`, `bin/test-contract`, and a
   `bin/init` smoke install into a fresh temporary project, confirming
   the installed copy is byte-identical and its `status` subcommand
   still runs.
5. Run the done-gate.

## Recurrence guard

`bin/test-git-guard`, case 1 and case 3, kept. Both fail against the
unfixed script and pass against the fixed one.

1. **Setting up:** a fresh repository, the library and `git-guard.sh`
   installed exactly as `bin/init` lays them out, one commit on trunk.
2. **Doing:** run `git-guard.sh autosave` with the tree clean (case 1),
   and again with only a secret-shaped untracked file present and
   nothing else pending (case 3).
3. **Reading:** the branch, HEAD and whether anything was printed are
   unchanged in both cases; no `wip/*` ref exists afterward.

## Blast radius and reversal

Touches one function in one shipped script, used only by the four hooks
`git-guard on` installs and by direct invocation. Nothing reads
`cmd_autosave`'s internals from outside it. If this turns out to be
wrong, reverting the commit restores the old (buggy but understood)
ordering exactly; nothing else in the Element depends on the new
ordering.

## Blocker

## Notes

- 2026-09-27 — Reproduced against the unfixed script: `bin/test-git-guard`
  gives 19 passed, 5 FAILED, all under cases 1 and 3 (the branch changed,
  a `wip/*` ref was created, and the rescue message printed, in each case
  where nothing was ever staged). Cases 2, 4 and 5 — the paths that were
  already correct — passed unfixed too, which is the control: the fix
  narrows the bug's trigger, it does not change working behaviour.
- 2026-09-27 — Fixed script: `bin/test-git-guard` gives 24 passed, 0
  failed, under both `bash -n`/real execution on this host's bash 5 and
  on stock macOS `/bin/bash` 3.2.57.
- 2026-09-27 — `bin/check-bash32`: clean, 69 files (was 68 — the new test
  script is counted). `bin/lint`: exits 0; its one MEDIUM finding
  (`seed/runtime-mobile-app.md.template:75`) is pre-existing and
  unrelated, confirmed present with this change set aside.
  `bin/test-contract`: 40/40, unaffected. `bin/check-manifest`: OK — a
  `bin/` script needs no `rasa.json` entry.
- 2026-09-27 — `bin/init` into a fresh temporary project: the installed
  `.claude/skills/git-guard/git-guard.sh` is byte-identical to the
  source, and its `status` subcommand runs cleanly there.
