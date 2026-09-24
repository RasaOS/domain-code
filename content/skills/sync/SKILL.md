---
name: sync
description: Bring this project up to the latest release of the Element it was installed from (rasa.domain.code). Fetches the Element fresh, shows what changed since the project's pin — releases, breaking changes, which installed files update, which the project edited locally, which the Element retired, and whether the task ledger needs migrating — then applies through the Element's own bin/init after the user decides on every local edit. Never auto-commits. Triggered by "/sync", "update domain code", "pull the latest Element", "are my skills up to date", "sync with domain.code".
---

# /sync — update to the latest Element release

One direction: **Element → this project**. Pushing an improvement back is
`/contribute`.

The Element's own `bin/init` is the update path. It is manifest-driven
(`rasa.json`), honours `overrides[]` in `.claude/rasa.lock.json`, never
overwrites a seeded project file that already exists, restamps the pin — and,
from 0.53.0, migrates a pre-1.0 task ledger. `/sync` never copies an Element
file by hand. What it adds is the part that needs a person: a plan before
anything is written, a decision on every local edit, and cleanup of files the
Element retired.

The mechanics are one script, `.claude/skills/sync/sync.sh`. This file says
when to run each verb and what to ask.

## Behavior contract

- **Fresh, never cached.** `sync.sh fetch` clones the Element at the
  lockfile's branch every time. If the clone fails, stop and say why — never
  fall back to an old copy.
- **Plan before writing.** Show the plan and wait. Nothing is applied until
  the user says so.
- **Every local edit is the user's call.** A file that differs from both the
  pinned release and the new one was edited here; `bin/init` would overwrite
  it. Ask, per file: keep it for good, take upstream (the local copy is
  archived first), or hold it for this run only.
- **Nothing is lost.** Anything overwritten or removed is copied to
  `.claude/_archive/<path>.<date>` first. The archive is append-only.
- **Project-owned files are off-limits.** `CLAUDE.md`, `tasks/` content,
  `.claude/done-gate.md` and every other seeded file are the project's.
  `bin/init` creates a seed only when it is missing.
- **Never auto-commit.** Everything lands in the working tree; the user
  reviews with `git diff`.

## Process

### 1. Check the starting point

`.claude/rasa.lock.json` must exist. A project that only has the pre-canon
`.claude/foundation.json` still works — `sync.sh` reads it, and `bin/init`
writes the canonical lockfile on apply. Neither present → this project was
not installed from an Element; stop and point at the Element's `bin/init`.

Warn if the working tree is dirty: mixed changes make the update's diff hard
to review. Offer to stop so the user can commit first.

### 2. Fetch

```sh
SRC="$(bash .claude/skills/sync/sync.sh fetch)"
```

It reads `element.repo` and `element.branch` from the lockfile. Lockfiles
written before the GitHub org rename point at `github.com/rasa-os/…`, which
no longer resolves; the script corrects it, and `bin/init` restamps the right
URL.

### 3. Plan

```sh
bash .claude/skills/sync/sync.sh plan "$SRC"
```

Read-only. It prints:

| section | meaning | what you do |
|---|---|---|
| RELEASES SINCE YOUR PIN | every release between the pin and now; `⚠ BREAKING` marks the ones that change behaviour | summarize; read each BREAKING entry in `$SRC/CHANGELOG.md` and tell the user what it means for them |
| update | upstream changed, local copy untouched | safe |
| new | the Element added it | safe |
| **LOCAL EDIT** | differs from the pin *and* from upstream | ask — step 4 |
| kept | in `overrides[]`, upstream differs | mention; the override holds |
| retired | the Element removed it; local copy unmodified | archived and removed on apply |
| **RETIRED BUT EDITED** | the Element removed it; the project changed it | leave it; tell the user it is now theirs alone |
| TASK LEDGER | whether `tasks/` will be migrated to `rasa.module.tasks` v1.0.0 | see step 6 |

Exit 3 means the plan contains something that needs a person.

### 4. Decide every local edit

For each **LOCAL EDIT**, show the diff against upstream
(`diff <local> "$SRC/<from>"` — the `from` path is in `$SRC/rasa.json`) and
ask:

1. **Keep mine for good** → `bash .claude/skills/sync/sync.sh keep <path>`
   records it in `overrides[]`; this and every later sync leave it alone.
2. **Take upstream** → do nothing; apply archives the local copy first.
3. **Hold for now** → apply with `--hold`: every local edit is left untouched
   this run, and no override is recorded.

No defaults — each file gets an answer.

### 5. Apply

```sh
bash .claude/skills/sync/sync.sh apply "$SRC"          # or: … apply "$SRC" --hold
```

In order: archives the local edits it is about to overwrite, archives and
removes retired files, then runs `$SRC/bin/init` on this project — which
installs every Element file, creates missing seeds, migrates the task ledger
if it is pre-1.0, and restamps the pin.

### 6. The task ledger

If the plan said the ledger is pre-1.0, `bin/init` migrated it (only when
`tasks/` had no uncommitted changes — otherwise it held back every `tasks/`
seed and printed the command to finish). Then:

- Read `tasks/MIGRATION-REVIEW.md` with the user: every judgement the
  migration could not make — renumbered ids with a ready `grep` for
  references outside `tasks/`, dangling ROADMAP lines, dropped ROADMAP notes.
- Run `.claude/bin/check-tasks`. A dangling ROADMAP line (I-24) is never
  auto-fixed: the task was either lost or the line is a stale promise, and
  only the user knows which. Delete the line or file the task, then re-run
  until it reports zero errors.
- From now on tasks move only through `.claude/bin/task` —
  `.claude/task-rules.md` and `.claude/code-task-rules.md` say how.

### 7. Report

```markdown
## ✅ Synced to <name> v<version> (`<sha>`)

- Releases pulled: v<a> → v<b> (<n>); BREAKING: <list, or "none">
- Updated <n> · added <n> · kept (override) <n> · retired <n>
- Local edits: <path> — kept / taken (archived at …) / held
- Task ledger: migrated — <n> tasks, <e> errors left (see MIGRATION-REVIEW.md) / already v1.0.0 / none
- Pin: `<old>` → `<new>`

Next: review `git diff`. Commit the ledger migration on its own
(`git add tasks && git commit`), then the rest.
```

## What you must NOT do

- **Don't copy Element files by hand** or edit the fetched clone — `bin/init`
  is the one writer, and it honours overrides.
- **Don't migrate the ledger by hand**, and never write `status:` into a task
  file. If the migration was refused, fix what it names and re-run the
  command it printed.
- **Don't overwrite a local edit without the user's answer**, and don't
  delete anything that is not archived first.
- **Don't auto-commit, don't push.**

## When NOT to use this skill

- **Hands-off, with every safe case decided for you** → `/sync-all`.
- **Sending an improvement back to the Element** → `/contribute`.
- **A first install** → the Element's `bin/init`.
- **Reviewing the Element's history** → `git log` in the Element repo.
