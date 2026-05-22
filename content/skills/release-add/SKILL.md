---
name: release-add
description: Append a task to the top "🚧 Next" entry of `tasks/RELEASES.md`. Triggered automatically by `/peer-review` and `/release` after a merge to `main`, or invoked by the user after a manual merge. Idempotent — re-running for the same task is a no-op. Supports a `--since-last-tag` bulk mode to catch up after manual merges. Triggered when a task lands on main and needs to be recorded for the next release — e.g. "/release-add TASK-042", "/release-add HOTFIX-007", "/release-add --since-last-tag", "track this for the next release".
---

# /release-add — append a task to the next-release entry

Single-purpose skill: take a TASK-NNN or HOTFIX-NNN that just
landed on `main`, find the top "🚧 Next" entry in
`tasks/RELEASES.md`, and add the task to it. **Idempotent** —
running twice for the same task is a no-op.

Per CLAUDE.md ethos: small skills do one thing well. This skill
manages one append operation on one file. It does not commit, it
does not bump versions, it does not ship.

## Behavior contract

- **Operate on `tasks/RELEASES.md`.** If the file doesn't exist,
  create it from the template format described in
  `release-rules.md` "Format" (one "🚧 Next" entry, no shipped
  entries below).
- **Find the active "🚧 Next" entry.** Exactly one should exist
  at the top of the file. If zero or multiple are found,
  **stop**: the file is in an unexpected shape, surface the
  finding.
- **Idempotency by ID.** Parse the task IDs already listed under
  the "🚧 Next" entry. If the task to add is already there,
  exit cleanly without modifying the file. Report "already
  tracked" in the closing line.
- **Validate the task ID.** TASK-NNN or HOTFIX-NNN format. If the
  ID doesn't exist as a spec file under `tasks/`, **flag a
  warning** but proceed — the task may have been filed under a
  different name, or this may be a placeholder add.
- **Pull the title from the spec file.** If the task's spec file
  exists (in `tasks/completed/` after merge, or wherever it
  lives), read the first `# <title>` line and use it as the
  bullet's title. If the spec isn't findable, use a placeholder
  `<title from spec — fill in later>` and flag it.
- **Append, don't reorder.** The task list under "🚧 Next" is in
  merge order. Append the new task at the bottom of the list.
- **Never auto-commit.** Same as the rest of the kit's
  non-`/release` skills. The user reviews `git diff` and commits
  the RELEASES.md change in their next commit.

## The `--since-last-tag` mode

For catching up after manual merges that bypassed `/peer-review`
and `/release`:

```bash
/release-add --since-last-tag
```

Behavior:

1. Find the last release tag (`git describe --tags --abbrev=0`).
2. List every commit on `main` since that tag (`git log
   <tag>..main --pretty=%s`).
3. Extract every TASK-NNN and HOTFIX-NNN mentioned in commit
   messages or in modified file paths under
   `tasks/completed/` or `tasks/active/`.
4. For each unique ID, run the single-add operation (idempotent
   — already-tracked IDs are skipped).
5. Report the count of newly-tracked tasks at the end.

## Process

1. **Read `release-rules.md`** to confirm the RELEASES.md format
   the kit expects.
2. **Resolve the input.**
   - Single ID arg (`TASK-NNN` / `HOTFIX-NNN`) → that one task.
   - `--since-last-tag` → bulk mode, per above.
   - No arg → look at the most recent merge commit on `main`,
     extract the TASK-NNN / HOTFIX-NNN from the commit message
     (most kit-friendly merges name the task in their subject).
     If none found, **stop** and ask the user for an explicit
     ID — guessing is worse than asking here.
3. **Open `tasks/RELEASES.md`.** If it doesn't exist, create it
   with one "🚧 Next" entry at the top, version computed as
   `<last-tag-version> + default-bump-minor`. Otherwise locate
   the "🚧 Next" entry (must be exactly one).
4. **Check idempotency.** Scan the entry's bullet list for the
   task ID. If present, exit cleanly with "already tracked."
5. **Resolve the task title.** Read the task's spec file from
   `tasks/completed/<id>-*.md` (the most likely location post-
   merge). If not found there, try `tasks/active/<id>-*.md`,
   then `tasks/backlog/<id>-*.md`. Extract the first H1 line.
   If no spec file is found anywhere, use the merge-commit
   subject as the title (stripped of the `TASK-NNN —` prefix)
   and flag as an assumption.
6. **Append the bullet** to the entry's task list:
   `- TASK-NNN — <title>`. Preserve the entry's other content.
7. **Render a one-line confirmation** in chat:
   `→ Tracked TASK-NNN for v0.38.0 (next release).` or
   `→ Already tracked TASK-NNN for v0.38.0.`
8. **Don't commit.** The file change sits in the working tree.

For `--since-last-tag` bulk mode, replace Steps 2 and the
single-add steps with a loop, and at the end render:

```
→ Tracked N new task(s) for v0.38.0 (next release):
  TASK-042, TASK-043, HOTFIX-007
→ Skipped M already-tracked task(s):
  TASK-040, TASK-041
```

## When NOT to use this skill

- **Shipping a release** → `/release`. That skill stamps the
  "🚧 Next" entry as ✅ Shipped and creates a new "🚧 Next"
  entry — `/release-add` only appends to the existing one.
- **Tracking a task in a phase / `ROADMAP.md`** → `/task` (or
  `/auto-task` etc.). `/release-add` is about *what's about to
  ship*, not *what's planned*.
- **Recording a deploy in `AUDIT.md`** → `/release` Step 7
  handles the 🚀 AUDIT entry.

## What "done" looks like

A modified `tasks/RELEASES.md` with the task ID appended to the
"🚧 Next" entry's bullet list, uncommitted. One short
confirmation line in chat. Re-running the skill for the same ID
exits cleanly with "already tracked" and changes nothing.
