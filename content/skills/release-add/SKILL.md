---
name: release-add
description: Bundle a COMPLETED task into a release — the official act that puts work into it. Invocation is approval. Only work in `tasks/completed/` can be bundled; targeting a release before the work is done is `/release-plan`. Triggered automatically by `/peer-review` and `/release` after a merge to `main`, or invoked by the user after a manual merge. Idempotent — re-running for the same task is a no-op. Supports a `--since-last-tag` bulk mode to catch up after manual merges. Triggered when a task lands on main and needs to be recorded for the next release — e.g. "/release-add TASK-042", "/release-add --since-last-tag", "track this for the next release".
---

# /release-add — append a task to the next-release entry

Single-purpose skill: take a TASK-NNN that just
landed on `main`, find the top "🚧 Next" entry in
`tasks/RELEASES.md`, and add the task to it. **Idempotent** —
running twice for the same task is a no-op.

Per CLAUDE.md ethos: small skills do one thing well. This skill
manages one append operation on one file. It does not commit, it
does not bump versions, it does not ship.

## Behavior contract

- **Route mechanics through the engine.** `.claude/skills/release/release.sh`
  owns parsing and rewriting:

  ```bash
  bash .claude/skills/release/release.sh bundle TASK-042 v1.3.0
  ```

  Do not hand-edit `tasks/RELEASES.md` — the engine keeps the two layers
  consistent and `check` validates the result.

- **Operate on `tasks/RELEASES.md`.** If the file doesn't exist,
  create it from the template format described in
  `release-rules.md` "Format" (one "🚧 Next" entry, no shipped
  entries below).
- **Resolve the destination release**, in this order:
  1. an explicit `--release vX.Y.Z`;
  2. **the release whose `### Targeted` holds this id** — this is the
     join that makes planning pay off: work aimed at v1.3.0 lands in
     v1.3.0, not in whatever happens to be open;
  3. the single open (📋 or 🚧) release, if there is exactly one;
  4. none open → create one at last-tag + minor (+ patch for a
     hotfix — a `priority: now` defect) and **say that you assumed
     it**.

  Multiple open releases with no other signal → ask. The old "exactly
  one 🚧 Next entry, otherwise stop" rule is **gone**: it hard-stopped
  on the first run in every fresh install, because the seed produced
  zero 🚧 entries.

- **Gate: only completed work is bundled.** `tasks/completed/<ID>-*.md`
  must exist. The engine enforces it and prints the remedy.

  **If git proves the merge and the task is still in `tasks/review/`
  (or `tasks/active/`), pass it through its done-gate**: the id named in
  a commit subject since the last tag is conclusive for the gate's
  **Merged** item. The other items in `.claude/done-gate.md` ran before
  the PR merged, and their evidence is on the PR (the hand-off table,
  `code-task-rules.md` §10). Make sure it is in the task's
  `## Completion report` before `pass` (then
  `.claude/bin/check-tasks --fix`), and name it in the note; if the
  evidence is missing, say so and do not pass. Move it with the
  verbs — never `git mv`, never a hand-edit of frontmatter:

  ```bash
  .claude/bin/task submit TASK-NNN      # only if it is still in active/
  .claude/bin/task pass TASK-NNN --by <who> --note "merged in <sha>, <evidence>"   # logged as "gate: …"
  .claude/skills/task-enforce/task-enforce.sh stamp TASK-NNN x-outcome shipped
  ```

  Say what you did, then bundle.

  `x-outcome` is a **separate fact** from the directory and is never
  inferred from it: `shipped` when the work went out, `reverted` when it
  was backed out afterwards. A task that reaches `completed/` with no
  `x-outcome` at all is exactly what this field exists to surface —
  `task-enforce.sh status` counts those.

  Nothing else in the mainline flow owns that transition —
  `/peer-review` merges without passing the task — so a task in
  `review/` (or `active/`, if nobody ran `submit` when the PR opened)
  plus merged-in-git is the *normal* post-merge state, and it is exactly
  what the gate refuses. `/release-add` is the only skill that runs at
  the moment the transition becomes true. Do **not** pass a task on
  anything weaker than a commit naming the id.

- **Invocation is approval.** Running this skill IS the approval act.
  The engine records `**Approved.** <user> via invocation` once per
  release. Do not ask for a separate confirmation.

- **Bundling clears the id from every `### Targeted` list.** The engine
  does this in the same edit, so an id is never in both layers.
- **Idempotency by ID.** Parse the task IDs already listed under
  the "🚧 Next" entry. If the task to add is already there,
  exit cleanly without modifying the file. Report "already
  tracked" in the closing line.
- **Validate the task ID.** TASK-NNN format (a legacy HOTFIX-NNN
  from an older ledger is still accepted). If the
  ID doesn't exist as a spec file under `tasks/`, **flag a
  warning** but proceed — the task may have been filed under a
  different name, or this may be a placeholder add.
- **Pull the title from the spec file.** If the task's spec file
  exists (in `tasks/completed/` after merge, or wherever it
  lives), read its `# <id>: <title>` H1 and use the title as the
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
3. Extract every TASK-NNN mentioned in commit messages or in
   modified file paths under `tasks/completed/`,
   `tasks/review/` or `tasks/active/`.
4. For each unique ID, run the single-add operation (idempotent
   — already-tracked IDs are skipped).
5. Report the count of newly-tracked tasks at the end.

## Process

1. **Read `release-rules.md`** to confirm the RELEASES.md format
   the kit expects.
2. **Resolve the input.**
   - Single ID arg (`TASK-NNN`) → that one task.
   - `--since-last-tag` → bulk mode, per above.
   - No arg → look at the most recent merge commit on `main`,
     extract the TASK-NNN from the commit message
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
   merge). If not found there, try `tasks/review/<id>-*.md`,
   `tasks/active/<id>-*.md`, then `tasks/backlog/<id>-*.md`.
   Extract the title from its `# <id>: <title>` H1.
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
  TASK-042, TASK-043, TASK-044
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
