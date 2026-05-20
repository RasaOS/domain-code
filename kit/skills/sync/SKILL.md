---
name: sync
description: Reconcile this project's `.claude/` against the upstream claude-kit foundation repo. Fetches the kit at HEAD, diffs every kit-managed file (skills, task-rules, task-template), classifies drift (kit-only updates / both changed / local override / new file / removed file), and proposes per-file pulls. Never auto-commits, never overwrites local overrides without approval, never touches project-content files (CLAUDE.md, PHASES.md, ROADMAP.md, AUDIT.md). Triggered when the user wants to pull foundation updates — e.g. "/sync", "pull latest from claude-kit", "are my skills up to date", "sync the foundation".
---

# /sync — claude-kit foundation sync

Reconcile this project's `.claude/` directory against the upstream
claude-kit repo. Pull updates the user wants; preserve local overrides
the user has intentionally diverged on.

This is a **one-way** sync: kit → project. Pushing changes back to
the kit is a manual git operation by design — improvements get
reviewed before they propagate.

Per CLAUDE.md ethos: honest about conflicts. Surface drift; don't
silently merge.

## Behavior contract

- **Read `.claude/foundation.json` first.** It tells you the kit
  repo URL, the branch to track, the last-synced commit SHA, and the
  list of files this project has intentionally overridden. If
  `foundation.json` is missing, this project wasn't bootstrapped
  from claude-kit — stop and explain.
- **Fetch the kit fresh.** Clone (or shallow-clone) the kit repo at
  the tracked branch's HEAD into a temp directory. Never assume a
  cached copy is current.
- **Diff every kit-managed file** (per the kit's `MANIFEST.json`)
  against the local copy. Classify:
  - **Kit changed, local unchanged** → safe pull, propose.
  - **Kit unchanged, local changed** → local override; respect it.
    Surface for awareness only.
  - **Kit changed AND local changed** → conflict; show both diffs,
    let user choose.
  - **New file in kit** → propose adding.
  - **File removed from kit** → propose removing (deletes are
    destructive — confirm explicitly).
- **Bootstrap files are off-limits.** Files listed in the kit's
  `bootstrap/` section (CLAUDE.md, PHASES.md, ROADMAP.md, AUDIT.md,
  foundation.json) are project-content; this skill never touches
  them. They're listed here for clarity:
  - `CLAUDE.md` — project-specific by definition.
  - `tasks/PHASES.md`, `tasks/ROADMAP.md`, `tasks/AUDIT.md` — the
    project's own history.
  - `.claude/foundation.json` — only updated to bump the
    `pinned_sha` and `last_synced` after a successful sync.
- **Propose, don't apply by default.** First pass produces a report.
  User approves which changes to apply. Only then does the skill
  copy files.
- **Never auto-commit.** Apply edits to the working tree; let the
  user review with `git diff` and commit when ready.
- **Bump the pin on success.** After applying any updates, write the
  fresh kit SHA into `.claude/foundation.json` and update
  `last_synced` to today's date.
- **Honest about overrides.** When applying an update to a file the
  project had marked as override, ask explicitly — "this was on
  your overrides list; pulling would discard your local edits.
  Confirm?"
- **Surface the CHANGELOG delta on version moves.** Whenever the
  project's pinned SHA differs from kit HEAD, parse the kit's
  `CHANGELOG.md` and render a §23 Activity timeline of every release
  between the pin and HEAD (Capability A). If the delta crosses a
  release with structural / breaking signals, emit a §25 WARNING
  alert above the timeline. Detail in Step 4.5.
- **Detect and reconcile kit-vs-project file overlap.** Before
  installing kit files, compare each kit file against existing
  project `.claude/*.md` files via two heuristics (filename topic
  match, bold-claim phrase overlap). For every flagged pair, prompt
  the user with four explicit options — keep project (record
  override + install kit as shadow), replace with kit (backup
  first), merge (defer), delete project (backup first). Backup
  discipline is non-negotiable: any deletion or replacement first
  writes the original to `.claude/_archive/<filename>.<YYYY-MM-DD>`.
  Detail in Step 4.6 and Step 6 case 5.

## Process

### Step 1 — Verify configuration

Read `.claude/foundation.json`. Required fields:

```json
{
  "kit": { "repo": "<url>", "branch": "<branch>" },
  "pinned_sha": "<sha or 'unpinned'>",
  "last_synced": "<YYYY-MM-DD>",
  "overrides": ["<relative path>", ...]
}
```

If the file is missing, malformed, or doesn't have a `kit.repo`
URL, **stop**. Explain the project doesn't appear to be bootstrapped
from claude-kit and offer two paths:
1. Bootstrap from kit: clone the kit, run its `bin/init`.
2. Manual pin: write a foundation.json by hand if the user knows
   what they're doing.

### Step 2 — Fetch the kit

```sh
TMP=$(mktemp -d)
git clone --depth 1 --branch <branch> <kit.repo> "$TMP/claude-kit"
KIT_SHA=$(git -C "$TMP/claude-kit" rev-parse HEAD)
KIT_SHA_SHORT="${KIT_SHA:0:12}"
```

If the clone fails (network, auth, repo gone), surface the error
and stop. Don't fall back to anything.

### Step 3 — Read the kit's manifest

Read `$TMP/claude-kit/MANIFEST.json`. The `kit.files` array tells
this skill what files are kit-managed. Any policy other than
`directory-mirror` or `file-replace` is treated as "skip — not in
sync scope" (bootstrap files have other policies).

### Step 4 — Diff each kit file against local

For each kit-managed file:

1. Compute the kit version's hash and the local version's hash.
2. Determine the previous-kit version: if `pinned_sha` is set, fetch
   that commit's version of the same file via `git show
   <sha>:<path>`. If `pinned_sha` is `"unpinned"` or unreachable,
   treat as "unknown previous" — fall back to two-way diff (kit
   vs local) instead of three-way.
3. Classify:
   - **kit_only_changed**: kit ≠ pinned, local == pinned.
   - **local_only_changed**: kit == pinned, local ≠ pinned.
   - **both_changed**: kit ≠ pinned, local ≠ pinned, kit ≠ local.
   - **converged**: kit ≠ pinned, local ≠ pinned, kit == local.
   - **unchanged**: kit == pinned == local.
   - **new_in_kit**: kit has it, local doesn't, pinned didn't.
   - **removed_in_kit**: pinned had it, kit doesn't.
4. If the file is in `overrides`, mark it `local_only_changed` even
   if the hashes match — the user has declared this file
   project-specific.

### Step 4.5 — Build the CHANGELOG delta (Capability A)

Before rendering, parse the kit's `CHANGELOG.md` (at the **kit repo
root**, not under `kit/`) and compute the delta between the project's
pinned position and HEAD. This produces two artifacts: a §23 timeline
and (if applicable) a §25 alert.

**Determining the pinned starting version:**

1. If `pinned_sha` is `"unpinned"`, skip this step entirely — there's
   no "from" point. Render only the unfiltered `## Unreleased` /
   `## vX.Y.Z` headers as informational context.
2. Otherwise, walk the pinned SHA forward through git tags:
   - `git -C "$TMP/claude-kit" tag --points-at <pinned_sha>` —
     if the pinned SHA is itself tagged, that tag is the starting
     version.
   - Otherwise: `git -C "$TMP/claude-kit" describe --tags --abbrev=0
     <pinned_sha>` — the closest preceding tag is the starting
     version. Note this in the timeline as "your last sync was
     between v? and v?+1; rendering deltas from v?+1 inclusive."
3. If `git describe` fails (no tags reachable from pinned SHA, or
   pinned SHA is unreachable in the freshly cloned kit), fall back
   to "unknown previous" and render the full CHANGELOG history with
   a §25 INFO alert explaining the fallback.

**Determining the ending version:** the nearest preceding tag from
HEAD, plus a "(kit HEAD)" marker on the topmost row showing the
in-development version (parsed from `## Unreleased` if it has
content, or from `MANIFEST.json`'s `version` field if `Unreleased`
is empty).

**Parsing CHANGELOG.md:**

- Extract every `## v*.*.* — YYYY-MM-DD` header. Order newest-first.
- For each version, extract the **headline**: the first non-blank,
  non-`---` line after the header. Strip leading markdown emphasis.
  Truncate to ~60 chars for the timeline display.
- Detect **reserved-version gaps**: scan the version sequence; if
  vX.Y.Z is missing between two adjacent entries (e.g. CHANGELOG
  jumps from v0.7.0 to v0.5.0 with no v0.6.0), look for a matching
  git tag. If a tag exists with no CHANGELOG entry, mark the version
  as `─  reserved`. If neither tag nor entry exists, omit the gap
  entry (it was never released).
- Detect **structural / breaking warnings**: scan each version's
  body for any of these phrases (case-insensitive):
  - `"Structural change worth flagging"`
  - `"breaking change"` / `"BREAKING:"` / `"BREAKING CHANGE"`
  - `"replaced"` (when adjacent to a feature/file name)
  - `"rewrite"` / `"rewritten"`
  - A `### Notes` section whose body contains "compat" or
    "migration"
  Tag the version. These drive the §25 alert in Step 5.

**Render the timeline (§23 Activity timeline shape):**

Use the kit-canonical glyph vocabulary from `output-styles.md`:

- `◆` for a normal release row (accent color)
- `─` for a reserved / parked version (dim gray)
- `▶` ("you are here") inline-marking the pinned-from row
- `(kit HEAD)` annotation on the topmost row

Example output (this is the literal shape /sync renders):

```
  DELTA SINCE YOUR LAST SYNC


   v0.8.0  ◆  <one-line headline from changelog body>
              (kit HEAD)
   v0.7.0  ◆  structured outputs + dashboard + git-flow rules
   v0.6.0  ─  reserved (no CHANGELOG entry; tag parked on origin)
   v0.5.0  ◆  primitive layer + 15 new skills
              (your last sync was here — pinned to v0.5.0)
```

If the project pinned mid-version (between two tagged commits),
render the pinned line with the closest preceding tag plus a
"+N commits past v?" annotation.

**Render the §25 ALERT (warning variant) when structural signals
fire:**

```
  ┌─ ⚠  STRUCTURAL CHANGE IN A RELEASE YOU'RE PULLING ───────┐
  │  v0.7.0 — /audit: 3-bucket findings collapsed to 2       │
  │  See `CHANGELOG.md#v070` § "Wired skills" for migration. │
  └──────────────────────────────────────────────────────────┘
```

One alert per structural signal. Place above the timeline. If the
user is jumping multiple versions and several alerts fire, list
them in version order (oldest first, since those are the changes
that compounded into the current state).

This delta render replaces the prior "Kit moved from <sha> → <sha>"
one-liner in the report header. The old `**Pinned at**` /
`**Kit HEAD**` rows still appear below the timeline for raw-SHA
reference.

### Step 4.6 — Detect kit-vs-project overlap (Capability B)

For every kit file the skill is about to install or compare, run
both heuristics against the project's existing `.claude/` files.
Flag matches; the user adjudicates per-file in Step 5.

**Heuristic 1 — Filename topical match:**

For each kit file `kit/<name>.md`, extract its "topic" by stripping
common suffixes: `-rules`, `-conventions`, `-template`, `-styles`.
For each existing project file `.claude/<name>.md` (excluding files
this skill manages by exact-path mapping), do the same.

A pair is flagged if both topic strings share a contiguous substring
of **5 or more characters**, AND the substring is not in the
stop-word list:

```
about, after, again, before, below, every, files, first, group,
items, never, often, other, other, place, rules, since, table,
their, there, these, things, those, today, total, under, using,
where, which, write
```

Examples that fire:

- `kit/git-flow-rules.md` (topic: `git-flow`) ↔ project's
  `.claude/git-flow.md` (topic: `git-flow`) → 8-char match `git-flow`
- `kit/release-rules.md` (topic: `release`) ↔ project's
  `.claude/release.md` (topic: `release`) → 7-char match `release`
- `kit/output-rules.md` (topic: `output`) ↔ project's
  `.claude/output-conventions.md` (topic: `output`) → 6-char match
  `output`

Examples that don't fire:

- `kit/task-rules.md` (topic: `task`) ↔ project's
  `.claude/task-board.md` (topic: `task-board`) → only 4-char match
  `task` → below threshold
- `kit/ios-conventions.md` ↔ project's `.claude/conventions.md` →
  `convention` is in the stop-word list

This is intentionally conservative on the false-positive axis. A
bad miss (we fail to flag overlap) is recoverable — the user notices
later and re-runs `/sync`. A bad fire (we wrongly flag overlap) is
mildly annoying but not destructive — the user picks option 1
("keep project version") and we record an override.

**Heuristic 2 — Bold-claim phrase overlap:**

For each kit file being installed, extract the set of **bold-claim
phrases**: text wrapped in `**...**` markdown emphasis. Strip
trailing punctuation. Lowercase. Skip phrases shorter than 4
characters or longer than 80.

For each existing project `.claude/*.md` (every markdown file under
`.claude/`, recursive), extract its bold phrases the same way.

For each (kit-file, project-file) pair, compute:

```
overlap_ratio = |kit_phrases ∩ project_phrases| / |project_phrases|
```

If `overlap_ratio > 0.30` AND `|kit_phrases ∩ project_phrases| >= 3`
(at least 3 phrases in common, to avoid noise on tiny files), flag
the pair. The dual gate prevents two-bold-phrase project files from
firing trivially.

A pair flagged by Heuristic 1 OR Heuristic 2 enters the reconcile
prompt in Step 5. If both fire on the same pair, render the
evidence from both heuristics in the prompt (gives the user more
to judge against).

**What this skill does NOT do:**

- Doesn't try to semantically diff content. The heuristics are
  intentionally shallow — the user is the only adjudicator.
- Doesn't cross compare project files against each other (only
  kit-file vs project-file pairs).
- Doesn't flag overlap for files the kit is **not** installing
  (e.g. project's `.claude/welcome.md` vs kit's
  `bootstrap/welcome.md.template` — the bootstrap is already
  `skip-if-exists`, so no overlap to resolve at sync time).

### Step 5 — Render the report

```markdown
# 🔁 claude-kit sync — <project name>

> **Headline.** <one sentence — e.g. "Kit moved from <pinned-sha> →
> <head-sha>; 3 skills updated, 1 conflict in task-rules.md, 0
> files removed.">

**Source.** <repo url> @ <branch>
**Pinned at.** `<pinned-sha>` (last synced <date>)
**Kit HEAD.** `<head-sha>` (<N commits ahead>)

---

## Delta since your last sync

*(rendered per Step 4.5 — §23 Activity timeline preceded by any
§25 structural-change alerts. Skipped if pinned_sha is HEAD or
unpinned.)*

---

## ⬇️ Updates available *(safe pulls)*

Files where the kit has new content and your local copy hasn't
been touched. These are the easy wins.

- **`.claude/skills/<name>/SKILL.md`**
  ```diff
  <truncated diff — first 10 lines, "…" for the rest>
  ```
  → Full diff: <link or "ask to expand">

*(group by file, list all)*

---

## ⚠️ Conflicts *(both changed)*

Files where the kit AND your local copy diverged from the pin. You
have to choose.

### `<path>`

**Your local change** *(diff from pin):*
```diff
<your local diff>
```

**Kit's change** *(diff from pin):*
```diff
<kit's diff>
```

**Options:**
1. Take kit's version (discard local)
2. Keep local (mark as override; never overwrite)
3. Manually merge (open both files; sync skips this one)

---

## 🛡 Local overrides *(no action needed)*

Files this project has intentionally diverged on. The kit's version
is shown for awareness only — it won't be applied unless you remove
the override.

- `<path>` — overridden since `<sha>` *(or "since bootstrap" if
  no record)*

---

## ➕ New in kit

Files the kit added since your pin. Propose adding.

- `<path>` — <one-line description from frontmatter or first
  heading>

---

## ➖ Removed from kit

Files the kit removed since your pin. Propose deleting locally.
**Destructive — confirm before applying.**

- `<path>` *(was: <sha-where-removed>)*

---

## ⓘ Potential overlap with project files

*(rendered per Step 4.6 — one §25 INFO alert per flagged pair,
followed by the 4-option reconcile prompt. Skipped if no overlaps
detected. The user must answer each prompt before sync proceeds —
no defaults.)*

For each flagged (kit-file, project-file) pair:

```
┌─ ⓘ  POTENTIAL OVERLAP ───────────────────────────────────┐
│  Kit's `git-flow-rules.md` overlaps with your project's  │
│  `.claude/git-flow.md`.                                  │
│                                                          │
│  Detected: <heuristic that fired + evidence>             │
│  e.g. "Filename match: 8-char shared substring           │
│  'git-flow' between kit topic and project topic."        │
│  e.g. "Bold-phrase overlap: 5 of 12 project bold         │
│  phrases (42%) also appear in the kit file."             │
└──────────────────────────────────────────────────────────┘

How should /sync handle this?

  1. Keep project version — record as local override in
     foundation.json. Kit version installed as
     `.claude/.kit-shadow/git-flow-rules.md` for future
     comparison.

  2. Replace project version with kit version — back up
     project file to `.claude/_archive/git-flow.md.<YYYY-MM-DD>`.

  3. Merge — render `git diff` of project-file vs kit-file
     side-by-side; user manually reconciles in their editor.
     /sync waits; on next invocation, treats the project file
     as the authoritative version.

  4. Delete project version — kit covers it now. Project file
     backed up to `.claude/_archive/<filename>.<YYYY-MM-DD>` first.

Pick 1, 2, 3, or 4. (No default — user must choose.)
```

---

## Bottom line

<2–3 sentences. What's the recommended action? "Apply all 3 safe
pulls; defer the conflict in task-rules.md until you've reviewed
both diffs" or "All current; no action".>

**To apply changes**: tell me which to take — e.g. "all safe
pulls", "skip the conflict", "take kit on task-rules.md", "add the
new skill", "remove the deleted one". I'll apply, bump the pin,
and stop. Commit when you're ready.
```

### Step 6 — Apply approved changes

Only after the user picks what to apply.

**Preserve exec bit on script files.** For every copy operation
below — safe pulls, conflict "take kit", new files, overlap
Options 2 and 4 — if the destination matches any of these patterns,
run `chmod +x <dest>` after the copy:

- Any file under `kit/skills/**/` (project path `.claude/skills/**/`)
  matching `*.sh`, `*.py`, `*.ts`, `*.js`, or `*.mjs`
- Any file under `bin/` (these are always executables)

The executable bit is not guaranteed to survive `Read`/`Write` or
plain `cp` (depends on tooling). Script-driven skills depend on
their `<name>.sh` being executable (or invoked as `bash <script>`,
which is the SKILL.md convention — but chmod'ing belt-and-suspenders
the contract). See `script-craft.md` for the broader convention.

1. **Safe pulls**: copy kit version → local.
2. **Conflict resolutions**: per the user's choice.
   - "take kit" → copy kit version, remove from `overrides` if
     present.
   - "keep local" → no file change; **add to `overrides` list**.
   - "manual merge" → no file change; flag for the user; don't
     touch overrides.
3. **New files**: copy from kit.
4. **Removed files**: `git rm` (or just `rm` if not yet tracked).
5. **Overlap reconcile resolutions** (Capability B): per the user's
   per-pair choice from Step 5.
   - **Option 1 — Keep project, install kit as shadow:**
     - Copy kit file → `.claude/.kit-shadow/<kit-file-name>`.
       Create the `.kit-shadow/` dir if missing.
     - Append the project file's path to `overrides` in
       foundation.json.
     - Append a record to a new `shadows` list in foundation.json
       linking the project file to the shadow path (see schema
       additions below).
   - **Option 2 — Replace project with kit:**
     - **Backup first.** Copy project file to
       `.claude/_archive/<project-filename>.<YYYY-MM-DD>`. Create
       the `_archive/` dir if missing. If a backup with that exact
       date already exists, append `.1`, `.2`, etc.
     - Copy kit file → project's normal kit-managed path
       (`.claude/<kit-file-name>`).
     - Remove the project file (the now-replaced one).
     - Do NOT add to `overrides` (project chose kit's version).
   - **Option 3 — Merge:**
     - Render `git diff --no-index <project-file> <kit-file>`
       inline in the report so the user has the diff in front of
       them. Don't touch any files.
     - Mark the pair as "deferred — user merging" in the closing
       summary. Don't bump the pin until the merge is resolved
       and the user re-runs `/sync`.
     - On the next `/sync` run, this skill will detect that the
       project file has changed (Heuristic 2 will recompute) and
       re-prompt only if overlap is still flagged.
   - **Option 4 — Delete project version:**
     - **Backup first.** Same backup discipline as Option 2 —
       copy project file to
       `.claude/_archive/<project-filename>.<YYYY-MM-DD>` before
       deleting.
     - `git rm` (or `rm` if not yet tracked) the project file.
     - Copy kit file → `.claude/<kit-file-name>` if not already
       present (this is also a "new in kit" path, in effect).
     - Do NOT add to `overrides`.

After all approved changes are applied:

- Write the new `pinned_sha` and `last_synced` into
  `.claude/foundation.json`.
- Update the `overrides` list per any conflict choices and per
  Option 1 overlap resolutions.
- Update the `shadows` list per any Option 1 overlap resolutions.

### Step 7 — Closing summary

Render a tight summary of what was applied, what was skipped, and
where the pin is now:

```markdown
## ✅ Sync applied

- 3 files updated: `<paths>`
- 1 file added: `<path>`
- 1 conflict deferred: `<path>` (you chose: keep local; added to overrides)
- 2 overlap pairs reconciled:
  - `.claude/git-flow.md` ↔ `git-flow-rules.md`: kept project,
    kit installed as shadow at `.claude/.kit-shadow/git-flow-rules.md`
  - `.claude/release.md` ↔ `release-rules.md`: replaced with kit
    version (project backed up to
    `.claude/_archive/release.md.2026-04-30`)
- Pin bumped: `<old>` → `<new>` (was at v0.5.0, now at v0.7.0)

`.claude/foundation.json` updated. Run `git diff` to review,
commit when ready.
```

## Foundation.json — schema additions for Capability B

The existing template at `bootstrap/foundation.json` declares
`overrides`. Capability B's Option 1 (keep project, install kit as
shadow) needs one additional field — `shadows` — that links each
overridden project file to its shadow copy, so future `/sync` runs
can three-way-diff against the kit's most recent version of the
shadow.

Proposed shape (this skill writes; it does not require the bootstrap
template to ship the field — the skill creates it on first use):

```json
{
  "kit": { "repo": "<url>", "branch": "<branch>" },
  "pinned_sha": "<sha>",
  "last_synced": "<YYYY-MM-DD>",
  "overrides": [".claude/git-flow.md", ".claude/release.md"],
  "shadows": [
    {
      "project_file": ".claude/git-flow.md",
      "shadow_file": ".claude/.kit-shadow/git-flow-rules.md",
      "kit_topic": "git-flow",
      "recorded_sha": "<sha at time of override>",
      "recorded_at": "<YYYY-MM-DD>"
    }
  ]
}
```

`shadows` is optional. Projects that have never used Capability B's
Option 1 don't need the field.

Two reasons for the shadow:

- **Future drift detection.** On the next `/sync`, the skill compares
  the kit's current version of the shadow against the recorded
  shadow file. If the kit's version moved, /sync surfaces "the kit's
  version of <topic> changed since you overrode it — review?" The
  user keeps the override or graduates kit's new version into the
  project file.
- **Auditability.** A shadow lets future-you (or future-Claude) see
  what the kit thought best at the time the project diverged. Saves
  archeology.

Whether the `shadows` field belongs in `bootstrap/foundation.json`
itself is a separate decision (touching bootstrap is out of scope
for this skill). The skill writes the field in the project's own
`.claude/foundation.json` when needed; the bootstrap template can
remain minimal.

## What you must NOT do

- **Don't auto-commit.** Same rule as every other skill that
  modifies files.
- **Don't touch project-content files.** CLAUDE.md, PHASES.md,
  ROADMAP.md, AUDIT.md, the project's own task specs in
  `tasks/{backlog,active,blocked,completed}/` — never. Overwriting any of these
  is a bug in the skill.
- **Don't merge in the conflict case.** Three-way merge tooling
  (git merge-file, etc.) is tempting but produces wrong answers
  often enough that the safer policy is "show both, let the user
  decide." If the user wants automated merging, they can use
  `git merge-file` themselves.
- **Don't push.** This is a one-way sync. If the user wants to push
  improvements back to the kit, they do it manually with normal
  git.
- **Don't bypass the override list.** A file marked as overridden
  stays put unless the user explicitly removes the override.

## Edge cases

- **No network / repo unreachable.** Fail loudly. Don't fall back
  to a stale cache.
- **Kit branch doesn't exist.** Fail. Tell the user to fix the
  branch reference in `foundation.json`.
- **Local working tree dirty.** Warn the user before applying —
  they might lose track of which changes came from where if
  unrelated edits are mixed in. Offer to abort.
- **First sync after migrating to claude-kit** (no `pinned_sha`):
  treat every file as "new pin" — show what kit currently has,
  ask the user to confirm wholesale adoption, then stamp the pin.
  Skip Step 4.5 (no "from" point); the overlap detection in
  Step 4.6 is especially valuable here — most files in the project
  predate the kit migration and will fire heuristics.
- **Kit changed file moved or renamed.** Treat as remove + add.
  This is rare and the kit should avoid renames.
- **CHANGELOG.md missing or malformed** (Capability A):
  - File missing: render the "Updates available / Conflicts /
    New / Removed" sections normally; skip the §23 timeline; emit
    a §25 INFO alert: "Kit has no CHANGELOG.md at HEAD — delta
    surfacing skipped. Pin still bumps on apply."
  - File present but no `## v*.*.* — YYYY-MM-DD` headers parse:
    same fallback. Don't crash on a malformed CHANGELOG.
- **CHANGELOG entry exists but has no headline** (rare — author
  forgot the subtitle line): render the row with `<no headline>` in
  dim gray. Don't infer one.
- **Reserved version detected** (a tag with no CHANGELOG entry):
  render the row with `─  reserved` glyph and a parenthetical
  explaining ("no CHANGELOG entry; tag parked on <branch>" or
  similar). Treat the tag's commit metadata as the source of truth
  for the date; omit the date column if the tag is annotated and
  has no useful body.
- **Backup-collision in `.claude/_archive/`** (Capability B Options
  2 and 4): if a file already exists at the target backup path
  (same date, same filename), append `.1`, `.2`, etc. Never
  overwrite an existing archive entry — the archive is append-only
  by design.
- **Shadow-collision in `.claude/.kit-shadow/`** (Capability B
  Option 1): if the directory already has a file with the same
  name (e.g. user previously overrode the same kit topic), the new
  shadow overwrites — there's only one "current kit version" per
  topic and that's what the shadow tracks. Update the `shadows`
  entry's `recorded_sha` and `recorded_at` accordingly.
- **Project has multiple `.claude/*.md` files matching one kit
  topic** (Capability B Heuristic 1): unusual but possible — e.g.
  `.claude/git-flow.md` AND `.claude/git-flow-extras.md` both
  match `git-flow-rules.md`. Render one reconcile prompt per
  match. Don't merge the prompts.
- **User picks Option 3 (manual merge) on every overlap** and
  the sync would otherwise have nothing to apply: still bump the
  pin if the user confirms. Document in the closing summary that
  N pairs are pending merge.

## When NOT to use this skill

- **You want auto-apply on every safe case** → `/sync-all`.
  Same operation, no per-file prompts; stops only at destructive
  ambiguities (conflicts, override-overwrites, project-content
  overlap, dirty-file removals).
- **Bootstrapping a new project** → use the kit's `bin/init` script.
- **Pushing improvements upstream** → manual git operation in the
  kit repo.
- **Reviewing what changed in the kit historically** → `git log`
  in the kit repo.
- **Doc reconciliation within the project** → `/update-docs`.
- **Schema reconciliation** → `/schema-check`.

## What "done" looks like for a /sync session

- A clear report of kit drift, classified.
- A §23 timeline of CHANGELOG deltas between the project's pin and
  kit HEAD (Capability A), with §25 alerts for any structural /
  breaking changes in the range.
- A §25 INFO alert + 4-option reconcile prompt for each detected
  kit-vs-project overlap (Capability B), answered explicitly by
  the user — no defaults.
- The user picks what to take.
- Approved files are applied to the working tree, uncommitted.
- Backups (for any Capability B Option 2 / Option 4 deletions or
  replacements) live at `.claude/_archive/<filename>.<date>` —
  append-only, never overwrites.
- Shadows (for any Capability B Option 1 keep-project resolutions)
  live at `.claude/.kit-shadow/<kit-name>` and are tracked in
  foundation.json's `shadows` field.
- The pin in `.claude/foundation.json` is bumped to the kit's
  current HEAD.
- A closing summary tells the user what was applied and what to do
  next (typically: `git diff` + commit).
