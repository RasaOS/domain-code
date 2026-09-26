---
name: contribute
description: Package a local edit to an Element-managed file (a fix to `code-task-rules.md`, a tweak to a skill, an improved template) into a clean PR back to the upstream Element repo named in `.claude/rasa.lock.json`. Detects drift in Element-managed files since the last sync (through `/sync`'s own `sync.sh`), classifies each as portable improvement vs project-specific override, drafts a PR title + body, and either opens the PR (if GitHub tooling is available) or prints the exact manual steps. Closes the Element ↔ project loop. Triggered when the user has improved something in `.claude/` and wants it to flow back upstream — e.g. "/contribute", "push this back to the Element", "this fix should be upstream", "contribute this skill upstream".
---

# /contribute — Push improvements back to the Element

Take a local edit to an Element-managed file and turn it into a
PR on the upstream Element repo. The Element improves only when
real-world fixes flow back; this skill is the path.

Per CLAUDE.md ethos: blunt about whether an edit is genuinely
portable. Some local changes belong in the project's CLAUDE.md
forever, not in the Element. Don't push project-specific quirks
upstream.

## Behavior contract

- **Read `.claude/rasa.lock.json` first.** It is the lockfile
  `bin/init` writes: `element.repo`, `element.branch`,
  `pinned_sha`, and `overrides[]`. A pre-canon
  `.claude/foundation.json` is still read as a fallback, the way
  `/sync` reads it. If neither exists, this project was not
  installed from an Element — stop.
- **Detect drift through `/sync`'s script, don't infer it.**
  `sync.sh fetch` clones the Element with the pin in its history;
  `sync.sh plan` compares every Element-managed file three ways
  (local, pin, upstream). Drift = real bytes-different. Never
  hand-roll a second comparison — it will disagree with `/sync`.
- **Classify every drifted file** with the user before
  packaging:
  - **Portable improvement** — applies generally; ship to the Element.
  - **Project-specific override** — useful here, not generally;
    record it with `sync.sh keep <path>` so `/sync` and `bin/init`
    leave it alone; leave the file in place.
  - **Mistaken edit** — meant for a project file, not an
    Element-managed one; revert locally.
- **Vendored files go to their own upstream.** `task-rules.md`,
  `task-templates/`, `bin/task`, `bin/check-tasks` and the
  `/task` `/backlog` `/roadmap` skills are vendored byte-for-byte
  from `rasa.module.tasks` (the Element's `vendored.json` lists
  them); a PR that edits one here fails `bin/check-manifest`. A
  portable fix to one belongs in `RasaOS/module-tasks`.
- **Group by theme into one or more PRs.** A PR that fixes a
  typo + adds a new skill + tightens a rule is three PRs. Ask
  before splitting.
- **Never push without confirmation.** Show the user the PR
  title, body, and file list. Open only on explicit go.
- **Never auto-commit in the project repo.** Any
  `rasa.lock.json` updates (new override entries) are left in
  the working tree, uncommitted.
- **Honest about uncertainty.** If the user can't tell whether
  an edit is portable, say so and offer a path: open as a
  draft PR, get feedback in the PR, decide there.

## Process

### Step 1 — Verify configuration

Read `.claude/rasa.lock.json` (fallback: `.claude/foundation.json`).
Required:
- `element.repo` — upstream URL (the PR target).
- `element.branch` — usually `main`.
- `pinned_sha` — last synced commit.
- `overrides[]` — files this project intentionally diverges on.

If missing or malformed, stop. Suggest the user re-run the
Element's `bin/init`, which writes the lockfile.

### Step 2 — Fetch the Element

```sh
SRC="$(.claude/skills/sync/sync.sh fetch)"
```

A fresh full clone of `element.repo` at `element.branch`, so the
pinned commit is in its history. If the network or auth fails,
it stops and says so. No fallbacks.

### Step 3 — Detect drift

```sh
SYNC_PLAN_ALL=1 .claude/skills/sync/sync.sh plan "$SRC"
```

Exit 3 is expected here — it means the plan found local edits.
The **LOCAL EDIT** list is the candidate set: installed files
that differ from both the pinned Element version and the current
one. Overrides are already excluded (they appear under **kept**).

Split each LOCAL EDIT by whether upstream moved since the pin.
Its source path is the matching `element.files[]` entry in
`$SRC/rasa.json` (`.claude/<x>` ← `content/<x>` for the
directory mirrors):

```sh
git -C "$SRC" diff --quiet <pinned_sha> HEAD -- <source-path>
```

- **Exit 0 — upstream unchanged since the pin** → the local edit
  is new to the Element. **Candidate for /contribute.**
- **Exit 1 — upstream changed too** → both diverged. Ask the user
  to `/sync` first; this skill doesn't merge.

Files under **new**, **update** or **retire** have no local edit —
suggest `/sync`, not `/contribute`.

### Step 4 — Classify each candidate with the user

For every candidate, render a tight summary and ask:

```markdown
### `<path>`

**Diff from pinned Element version:**
```diff
<truncated diff — first ~20 lines, "…" for the rest>
```

**Is this a portable improvement, a project-specific override,
or a mistake?**
- (P)ortable — push to the Element
- (O)verride — keep local, mark as override
- (M)istake — revert locally
- (S)kip — decide later, don't include in this PR
```

Wait for an answer per file. Don't bulk-default.

### Step 5 — Group portable edits into PR(s)

Default: one PR per coherent theme. Examples:
- "Fix typo in code-task-rules + clarify the same rule" → one PR.
- "Add /handoff skill + fix /onboard's broken link" → two PRs.

Ask the user how to group if there are 3+ portable files. Show
the proposed grouping; user confirms or regroups.

### Step 6 — Draft the PR(s)

For each PR:

```markdown
## PR draft — `<branch-name>`

**Title:** <one-line; under 70 chars; imperative; no scope tag>

**Body:**
```markdown
## Summary
<1-3 bullets — what changed and why>

## Files changed
- `<path>` — <one-line role>
- …

## How this came up
<one paragraph — what real situation in <project name> revealed
the gap. Stays grounded; no abstract pitch.>

## Test plan
- [ ] Pulled into a fresh project via `/sync`
- [ ] <skill-specific check, if applicable>
```

**Branch name:** `contribute/<short-slug>-<from-project-name>`
(e.g. `contribute/clarify-postmortem-rules-from-acme-app`).
```

Show the user the draft. They can edit before submission.

### Step 7 — Submit (or print manual steps)

Detect available GitHub tooling, in order:
1. `mcp__github__create_pull_request` — preferred, in-session.
2. `gh pr create` — local CLI fallback.
3. **Manual** — if neither, print the exact commands the user
   runs locally:

```sh
# In a clone of the Element repo (element.repo):
git checkout -b <branch-name>
# Apply the diff (the skill prints it as a patch the user pipes in)
git am < contribute.patch
git push -u origin <branch-name>
gh pr create --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

For the in-session paths: ask explicitly before opening. The
default is print-and-confirm, not auto-open.

### Step 8 — Record overrides in the lockfile

For files the user marked as **Override**:

```sh
.claude/skills/sync/sync.sh keep <path>...
```

It appends each path to `.claude/rasa.lock.json`'s `overrides[]`,
which `/sync` and `bin/init` both honor. Leave the change in the
working tree. Don't commit.

For files marked **Mistake**, restore from the pinned Element
version (`git -C "$SRC" show <pinned_sha>:<source-path>`, written
over the local file). Do this only
after confirming with the user — it's a destructive operation.

### Step 9 — Closing summary

```markdown
# 📤 Contribute summary

- **PRs opened:** <count> *(or "drafted; not opened — see above
  for manual steps")*
  - `<title>` → `<url-or-branch-name>`
- **Files marked as override:** <count> *(added to
  `rasa.lock.json` overrides[])*
- **Files reverted locally:** <count>
- **Files deferred:** <count>

`.claude/rasa.lock.json` updated. Run `git diff` to review
overrides additions, commit when ready.

Once the upstream PR is merged and tagged, run `/sync` to pull
the new pinned SHA into the project.
```

## Style rules

- **One file = one classification.** Don't ask the user to
  rate-limit decisions across files; keep them per-file.
- **Diffs ≤ 20 lines in chat.** Truncate with "…" and offer to
  expand.
- **PR title is imperative, no scope tag.** "Clarify postmortem
  ownership rule" not "[code-task-rules] update postmortem section".
- **PR body grounds the change in real use.** "How this came
  up" forces the user to articulate the real-world signal, which
  is the thing the Element maintainer cares about.
- **No "small fix" PRs without context.** Even a typo PR
  should say where it bit and how.

## What you must NOT do

- **Don't push project-specific quirks upstream.** Override
  classification exists for a reason. If a rule only makes sense
  in this project, don't argue with the user — mark it
  override and move on.
- **Don't auto-open PRs.** Always confirm. Even with GitHub
  tooling available, the default is "draft + show + ask".
- **Don't merge a PR you opened.** Merging is the Element
  maintainer's call.
- **Don't bundle unrelated changes.** Three themes = three PRs.
- **Don't include the whole project in a PR body.** The Element
  maintainer wants the change, not the project's lore.
- **Don't auto-commit `rasa.lock.json`.** Same rule as every
  other Element-managed-file edit.
- **Don't fall back to a stale cache.** If the Element clone
  fails, surface the error and stop.
- **Don't write overrides anywhere but `rasa.lock.json`.** An
  override in any other file is read by nothing, and the next
  `/sync` overwrites the file it was meant to protect.

## Edge cases

- **Both local and Element HEAD diverged from pin** (`both_changed`
  in `/sync` terms). This skill doesn't merge. Stop, route the
  user to `/sync` first to reconcile, then come back to
  `/contribute`.
- **User has a brand-new file that doesn't exist in the Element
  yet.** That's a "new contribution" — same flow, just the
  pinned Element version is empty/missing. The PR adds the file.
- **User wants to contribute back a file the Element doesn't manage
  yet** (e.g. a new platform-rules file). Generate the PR + a
  proposed `rasa.json` change in the same PR.
- **User edits triggered an existing override**. Surface it:
  "this file is on your overrides list — pulling these edits to
  the Element means dropping the override. Confirm?"
- **Authenticated push fails** (403 / no scope). Fall back to
  manual-steps mode. Don't retry indefinitely.
- **Kit repo restructured since the pin.** A file's `from-path`
  may have moved. Treat as: open a PR to whatever the file's
  current location is in the Element's HEAD.

## When NOT to use this skill

- **Pulling Element updates into the project** → `/sync`, not
  `/contribute`. This is the opposite direction.
- **Capturing a project-specific rule** → `/codify` (writes to
  CLAUDE.md), not this.
- **Promoting a rule that appears across multiple projects** →
  `/rule-promote`. That skill identifies the candidate; this
  skill packages a single edit.
- **Rewriting the Element substantially** → that's a normal git
  operation in the Element repo, not a contribution from a project.

## What "done" looks like for a /contribute session

One or more PRs drafted (and optionally opened) against the
upstream Element, each grounded in real use, each scoped to a single
theme. Project-side bookkeeping (`rasa.lock.json` overrides
list) updated and staged. The user knows which PRs to track and
that running `/sync` after merge will pull the change back into
the project at the new pinned SHA.
