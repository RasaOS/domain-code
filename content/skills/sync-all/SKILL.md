---
name: sync-all
description: Autonomous variant of /sync — fetches the kit at HEAD, diffs every kit-managed file, and auto-applies every safe update without asking. Pulls kit-only changes, adds new kit files, removes files the kit removed (when the local copy is unmodified). Stops at destructive ambiguities (conflict where both sides changed, override-overwrite, overlap with project file) and surfaces them as hard gates per autonomy-rules.md. Triggered when the user wants the latest kit applied hands-off — e.g. "/sync-all", "pull everything from the kit", "auto-sync the foundation", "just bring me up to date".
---

# /sync-all — autonomous foundation sync

`/sync`, run with nobody at the keyboard. The normal `/sync` skill
proposes per-file pulls and waits for the user to approve each.
`/sync-all` makes every safe call itself, flags each decision as
an assumption, and hands back a report — same autonomy shape as
`/auto-task`, `/auto-bug`, `/mission`, etc.

Per CLAUDE.md ethos: a sync is only worth automating if the
common case is safe. `/sync-all` auto-applies the cases where the
kit is the unambiguous source of truth (kit-only changes, new
files, removed files with clean local copies) and **stops at the
cases where data could be lost** (conflicts, override overwrites,
project-content overlaps). The destructive cases stay the user's
call by design.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — the
  contract, the hard-gate list, the report template. This
  SKILL.md states only what is specific to `/sync-all`.
- **The operation is `/sync`.** Read `sync/SKILL.md` and follow
  its process (Steps 1–7 verbatim). `/sync-all` does not
  redefine the work — it runs `/sync`'s pipeline without the
  per-file prompts in Step 6.
- **Auto-apply the safe cases.** Step 6 cases that have an
  unambiguous answer get applied automatically:
  - **Kit changed, local unchanged** → pull the kit version.
  - **New file in kit** → install it.
  - **File removed from kit, local unchanged** → remove the
    local copy.
  - **Local override (kit unchanged, local changed)** → leave
    alone; record awareness only.
  Every applied change is logged in the autonomy report as an
  ⚠️ flagged assumption ("I pulled `X` because the kit-only
  contract said it was safe — re-check if you didn't expect
  this").
- **Stop at the destructive cases.** Step 6 cases where data
  could be lost are hard gates per `autonomy-rules.md`. The skill
  applies all the safe cases, then **stops and surfaces** the
  destructive cases for the user — it does **not** silently
  pick a side:
  - **Conflict — kit changed AND local changed.** Either side
    is potential data loss. Hard gate.
  - **File removed from kit, local changed.** The local copy
    has edits; removing it would discard them. Hard gate.
  - **Overlap with project file** (Capability B). The four
    options (keep project / replace with kit / merge / delete
    project) require human judgment about which content wins.
    Hard gate.
  - **Override on the override list, kit changed.** Per
    `/sync`'s contract: "this was on your overrides list;
    pulling would discard your local edits." Hard gate.
- **Bootstrap files stay off-limits.** Per `/sync`, `CLAUDE.md`,
  `tasks/PHASES.md`, `tasks/ROADMAP.md`, `tasks/AUDIT.md`, and
  `.claude/foundation.json` are never touched (except
  foundation.json's `pinned_sha` / `last_synced` after a
  successful sync).
- **Backup discipline still holds.** When auto-applying a kit
  removal of a file the local has *unmodified*, the local copy
  is archived to `.claude/_archive/<filename>.<YYYY-MM-DD>`
  before removal — same as `/sync`'s manual flow.
- **Bump the pin on success.** After applying safe updates,
  write the fresh kit SHA into `.claude/foundation.json` and
  update `last_synced` to today's date. If destructive cases
  remain unresolved, **don't bump the pin** — the project isn't
  fully synced until they're handled, and bumping would lie.
- **Never auto-commit.** Same as `/sync`. The user reviews with
  `git diff` and commits.

## Process

1. **Read `autonomy-rules.md` and `sync/SKILL.md`.** The contract
   and the operation.
2. **Run `/sync`'s Steps 1–5 verbatim.** Verify configuration,
   fetch the kit, read its manifest, diff each file, build the
   CHANGELOG delta, detect kit-vs-project overlap, render the
   report. The report is informational at this stage — the user
   sees what the sync would do.
3. **Run `/sync`'s Step 6 with auto-apply on the safe cases.**
   For each entry in the report:
   - **Safe case** (kit-only update, new file, clean removal)
     → apply. Log as a flagged assumption in the autonomy
     report.
   - **Destructive case** (conflict, override-overwrite,
     overlap, dirty-removal) → skip. Add to "Hard gates hit"
     in the autonomy report. Do not pick a side.
4. **Bump the pin only if no destructive cases remain.** If any
   hard gate was hit, the sync is partial — leave the pin where
   it was. Note this in the report. If the safe cases drained the
   delta to zero, bump the pin to the fresh kit SHA.
5. **Render the autonomy report.** Same template as
   `autonomy-rules.md`, extended:
   - **Applied** — every safe case that auto-applied, with the
     kit→local diff summary per file.
   - **Hard gates hit** — every destructive case left
     unresolved, with the recommended next step (run `/sync`
     interactively to handle them).
   - **Pin state** — bumped to `<sha>` (clean sync) or held at
     `<sha>` (destructive cases remain).

## When NOT to use this skill

- **You want to review each pull before it applies** → `/sync`
  (the interactive variant). `/sync-all` decides for you.
- **You're nervous about overwrites** → `/sync` first to see
  the delta. Once you trust the report, re-run as `/sync-all`.
- **There are destructive cases you want resolved this run** →
  `/sync`. `/sync-all` won't pick a side on those; you'll end
  up running `/sync` afterward anyway.
- **You want to write your own kit changes** → `/contribute`.
  Sync is one-way (kit → project); contribute is the reverse.

## What "done" looks like for a /sync-all session

One of two terminal states:

**Clean sync.** Every kit update was a safe case; all applied
automatically; the pin in `foundation.json` is bumped to fresh
kit HEAD; one autonomy report lists every file pulled, every
new file installed, every clean removal, every override
respected. User reviews with `git diff` and commits.

**Partial sync — hard gates remain.** Safe cases applied; one
or more destructive cases left unresolved; the pin is **held**
at its previous value (not bumped). The autonomy report names
every gate and tells the user to run `/sync` interactively to
finish.
