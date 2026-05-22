---
name: contribute
description: Package a local edit to a kit-managed file (a fix to `task-rules.md`, a tweak to a skill, an improved template) into a clean PR back to the upstream claude-kit repo. Detects drift in kit-managed files since the last sync, classifies each as portable improvement vs project-specific override, drafts a PR title + body, and either opens the PR (if GitHub tooling is available) or prints the exact manual steps. Closes the kit ↔ project loop. Triggered when the user has improved something in `.claude/` and wants it to flow back upstream — e.g. "/contribute", "push this back to the kit", "this fix should be in claude-kit", "contribute this skill upstream".
---

# /contribute — Push improvements back to claude-kit

Take a local edit to a kit-managed file and turn it into a PR
on the upstream claude-kit repo. The kit improves only when
real-world fixes flow back; this skill is the path.

Per CLAUDE.md ethos: blunt about whether an edit is genuinely
portable. Some local changes belong in the project's CLAUDE.md
forever, not in the kit. Don't push project-specific quirks
upstream.

## Behavior contract

- **Read `.claude/foundation.json` first.** It tells you the
  upstream kit URL, branch, and `pinned_sha`. If absent, this
  project wasn't bootstrapped from claude-kit — stop.
- **Detect drift, don't infer it.** Use `git show
  <pinned_sha>:<path>` against the kit repo to compare each
  kit-managed file's current local version with what it was at
  the pin. Drift = real bytes-different.
- **Classify every drifted file** with the user before
  packaging:
  - **Portable improvement** — applies generally; ship to kit.
  - **Project-specific override** — useful here, not generally;
    add to `overrides` in `foundation.json`, leave in place.
  - **Mistaken edit** — meant for a project file, not a
    kit-managed one; revert locally.
- **Group by theme into one or more PRs.** A PR that fixes a
  typo + adds a new skill + tightens a rule is three PRs. Ask
  before splitting.
- **Never push without confirmation.** Show the user the PR
  title, body, and file list. Open only on explicit go.
- **Never auto-commit in the project repo.** Any
  `foundation.json` updates (new override entries) are staged in
  the working tree, uncommitted.
- **Honest about uncertainty.** If the user can't tell whether
  an edit is portable, say so and offer a path: open as a
  draft PR, get feedback in the PR, decide there.

## Process

### Step 1 — Verify configuration

Read `.claude/foundation.json`. Required:
- `kit.repo` — upstream URL.
- `kit.branch` — usually `main`.
- `pinned_sha` — last synced commit.
- `overrides` — files this project intentionally diverges on.

If missing or malformed, stop. Suggest the user run `bin/init`
or repair the file.

### Step 2 — Fetch the kit at the pin

```sh
TMP=$(mktemp -d)
git clone --depth 1 --branch <kit.branch> <kit.repo> "$TMP/claude-kit"
git -C "$TMP/claude-kit" fetch --depth 1 origin <pinned_sha>
```

If the network or auth fails, stop and surface the error. No
fallbacks.

### Step 3 — Detect drift

For each file listed in the kit's `MANIFEST.json` (`kit.files`
section), compare three versions:

1. **Pinned-kit version** — `git -C $TMP/claude-kit show <pinned_sha>:<from-path>`.
2. **HEAD-kit version** — `git -C $TMP/claude-kit show HEAD:<from-path>`.
3. **Local version** — read `<to-path>` from the project.

Classify each file:

- **Local == pinned == HEAD** → no drift. Skip.
- **Local != pinned, kit-pinned == kit-HEAD** → user has local
  edits the kit hasn't seen. **Candidate for /contribute.**
- **Local != pinned, kit-pinned != kit-HEAD** → both diverged.
  Ask user to `/sync` first; this skill doesn't merge.
- **Local == pinned, kit-pinned != kit-HEAD** → kit moved, no
  local change. Suggest `/sync`, not `/contribute`.

Skip files in `overrides` — those are intentionally local.

### Step 4 — Classify each candidate with the user

For every candidate, render a tight summary and ask:

```markdown
### `<path>`

**Diff from pinned-kit version:**
```diff
<truncated diff — first ~20 lines, "…" for the rest>
```

**Is this a portable improvement, a project-specific override,
or a mistake?**
- (P)ortable — push to kit
- (O)verride — keep local, mark as override
- (M)istake — revert locally
- (S)kip — decide later, don't include in this PR
```

Wait for an answer per file. Don't bulk-default.

### Step 5 — Group portable edits into PR(s)

Default: one PR per coherent theme. Examples:
- "Fix typo in task-rules + clarify the same rule" → one PR.
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
# In a clone of claude-kit:
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

### Step 8 — Update foundation.json for overrides

For files the user marked as **Override**, append the relative
path to `.claude/foundation.json`'s `overrides` array. Stage
the change in the working tree. Don't commit.

For files marked **Mistake**, restore from the pinned-kit
version (overwrite local with the pinned content). Do this only
after confirming with the user — it's a destructive operation.

### Step 9 — Closing summary

```markdown
# 📤 Contribute summary

- **PRs opened:** <count> *(or "drafted; not opened — see above
  for manual steps")*
  - `<title>` → `<url-or-branch-name>`
- **Files marked as override:** <count> *(added to
  `foundation.json`)*
- **Files reverted locally:** <count>
- **Files deferred:** <count>

`.claude/foundation.json` updated. Run `git diff` to review
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
  ownership rule" not "[task-rules] update postmortem section".
- **PR body grounds the change in real use.** "How this came
  up" forces the user to articulate the real-world signal, which
  is the thing the kit maintainer cares about.
- **No "small fix" PRs without context.** Even a typo PR
  should say where it bit and how.

## What you must NOT do

- **Don't push project-specific quirks upstream.** Override
  classification exists for a reason. If a rule only makes sense
  in this project, don't argue with the user — mark it
  override and move on.
- **Don't auto-open PRs.** Always confirm. Even with GitHub
  tooling available, the default is "draft + show + ask".
- **Don't merge a PR you opened.** Merging is the kit
  maintainer's call.
- **Don't bundle unrelated changes.** Three themes = three PRs.
- **Don't include the whole project in a PR body.** The kit
  maintainer wants the change, not the project's lore.
- **Don't auto-commit `foundation.json`.** Same rule as every
  other kit-managed-file edit.
- **Don't fall back to a stale cache.** If the kit clone fails,
  surface the error and stop.

## Edge cases

- **Both local and kit-HEAD diverged from pin** (`both_changed`
  in `/sync` terms). This skill doesn't merge. Stop, route the
  user to `/sync` first to reconcile, then come back to
  `/contribute`.
- **User has a brand-new file that doesn't exist in the kit
  yet.** That's a "new contribution" — same flow, just the
  pinned-kit version is empty/missing. The PR adds the file.
- **User wants to contribute back a file the kit doesn't manage
  yet** (e.g. a new platform-rules file). Generate the PR + a
  proposed `MANIFEST.json` change in the same PR.
- **User edits triggered an existing override**. Surface it:
  "this file is on your overrides list — pulling these edits to
  the kit means dropping the override. Confirm?"
- **Authenticated push fails** (403 / no scope). Fall back to
  manual-steps mode. Don't retry indefinitely.
- **Kit repo restructured since the pin.** A file's `from-path`
  may have moved. Treat as: open a PR to whatever the file's
  current location is in kit-HEAD.

## When NOT to use this skill

- **Pulling kit updates into the project** → `/sync`, not
  `/contribute`. This is the opposite direction.
- **Capturing a project-specific rule** → `/codify` (writes to
  CLAUDE.md), not this.
- **Promoting a rule that appears across multiple projects** →
  `/rule-promote`. That skill identifies the candidate; this
  skill packages a single edit.
- **Rewriting the kit substantially** → that's a normal git
  operation in the kit repo, not a contribution from a project.

## What "done" looks like for a /contribute session

One or more PRs drafted (and optionally opened) against the
upstream kit, each grounded in real use, each scoped to a single
theme. Project-side bookkeeping (`foundation.json` overrides
list) updated and staged. The user knows which PRs to track and
that running `/sync` after merge will pull the change back into
the project at the new pinned SHA.
