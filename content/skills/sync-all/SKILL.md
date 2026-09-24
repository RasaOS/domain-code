---
name: sync-all
description: Autonomous variant of /sync — fetches the Element fresh, plans the update, and applies it through the Element's bin/init without asking, holding every local edit untouched rather than overwriting it. Archives and removes files the Element retired, migrates a pre-1.0 task ledger when tasks/ is clean, and reports every hard gate (local edits, retired-but-edited files, a refused ledger migration) for a person. Triggered when the user wants the latest Element applied hands-off — e.g. "/sync-all", "pull everything from domain code", "just bring me up to date".
---

# /sync-all — autonomous Element update

`/sync`, run with nobody at the keyboard. Same script, same update path
(`bin/init`); the difference is that every decision `/sync` would ask about
is either unambiguous and applied, or data-bearing and **held** for a person.

Read `autonomy-rules.md` for the contract, the hard-gate list and the report
template, and `sync/SKILL.md` for the operation. This file states only what
differs.

## Behavior contract

- **Safe cases apply.** Updated and new Element files, retired files the
  project never touched (archived to `.claude/_archive/` first), missing
  seeds, and the pin restamp — all through `bin/init`.
- **Local edits are held, never overwritten.** `apply --hold` leaves every
  file that differs from both the pin and upstream exactly as it is for this
  run, and records no override — no standing decision is made on the user's
  behalf. Each one is a hard gate in the report.
- **The task ledger migrates only over a clean `tasks/`.** `bin/init`
  refuses otherwise and holds back every `tasks/` seed; that refusal is a
  hard gate, never worked around.
- **Never auto-commit, never push.**

## Process

1. `SRC="$(bash .claude/skills/sync/sync.sh fetch)"` — stop if it fails.
2. `bash .claude/skills/sync/sync.sh plan "$SRC"` — keep the output for the
   report.
3. `bash .claude/skills/sync/sync.sh apply "$SRC" --hold`.
4. If the ledger migrated, run `.claude/bin/check-tasks` and list its errors;
   do not resolve a dangling ROADMAP line (I-24) yourself — only a person
   knows whether the task was lost or the line is stale.
5. Render the autonomy report, extended with:
   - **Applied** — releases pulled (flag each `⚠ BREAKING` with one line on
     what it changes), counts of updated / new / retired files.
   - **Hard gates hit** — every held local edit (run `/sync` to decide
     them), every retired-but-edited file, a refused or erroring ledger
     migration with the command to finish it.
   - **Pin** — old → new. `bin/init` moves the pin even when local edits
     are held; the report says which files are still on their old content.

## When NOT to use this skill

- **You want to decide each local edit** → `/sync`.
- **Sending an improvement back to the Element** → `/contribute`.

## What "done" looks like

The project is on the Element's latest release, every held edit and every
gate is named in one report, nothing was overwritten or deleted without an
archive, and the working tree is uncommitted for the user to review.
