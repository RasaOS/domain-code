---
name: save
description: Mid-session state-save for an active thread of work. Snapshots what we did, what we worked out, and what's open right now — distinct from `/handoff` (project-leave) and `/status` (live read-only dashboard). Writes to `~/.claude/projects/<key>/saves/SAVED.md` (always current), archives previous saves to `~/.claude/projects/<key>/saves/<YYYY-MM-DD-HHMM>.md`, and maintains a newest-first index in `~/.claude/projects/<key>/saves/TIMELINE.md`. File plumbing is handled by the shipped `save.sh` script — the AI synthesizes content; the script handles archive policy, timestamps, and TIMELINE upkeep. Triggered when the user wants to checkpoint mid-thread — e.g. "/save", "save where we are", "snapshot this thread", "checkpoint before I switch contexts", "save our progress", "log this state".
---

# /save — Checkpoint the current thread of work

Mid-session state-save. Lighter and more frequent than `/handoff`:
no project-wide sweep, no tacit-knowledge questionnaire, no broad
multi-source synthesis. Just: what we did *in this thread*, what we
worked out, what's open next. Run as often as needed — multiple
times a day is normal.

Per CLAUDE.md ethos: blunt, calibrated, no narrative-shaping. A save
is a record of what *actually* happened — including the dead-ends
and the half-figured-out bits. If we backtracked or got stuck, say
so. A save with no "what's open" or only happy-path bullets is a
diary entry, not a checkpoint.

## Behavior contract

- **Writes durable docs only.** Output lands at `~/.claude/projects/<key>/saves/SAVED.md`
  (current) plus archived history at `~/.claude/projects/<key>/saves/<timestamp>.md` and
  `~/.claude/projects/<key>/saves/TIMELINE.md` (index). No source-code edits. Never
  auto-commits.
- **Script-driven mechanics — do not hand-write the files.** All
  plumbing runs through `save.sh` (ships in this skill's folder).
  The AI's job is content; the script's job is files. Hand-writing
  SAVED.md, TIMELINE.md, or archive files skips the archive policy
  and corrupts the index.
- **One thread, not the whole project.** A save documents *this
  conversation's thread of work*. For project-wide live state, run
  `/status`. For stepping away from the project entirely, run
  `/handoff`.
- **"What's open" is the load-bearing section.** Be specific: file
  paths, the exact failure mode you stopped on, the half-baked idea
  you didn't try yet. Vague nexts are worse than no nexts.
- **No tacit-knowledge questionnaire.** `/save` captures what just
  happened in this conversation — facts the AI already has. Only
  ask the user a question if synthesis genuinely requires it
  (e.g. they switched topics mid-thread and the boundary is unclear).

## The script

Lives in this skill's folder. Path varies by context:

- In the kit repo: `kit/skills/save/save.sh`
- In a synced project: `.claude/skills/save/save.sh`

Always invoked from inside a git repo — the script resolves the
project's saves directory under `~/.claude/projects/<key>/saves/`,
where `<key>` is the absolute path of the *main* repo root with
slashes replaced by hyphens (e.g. `-Users-chazzromeo-claude-kit`).

The main-repo lookup uses `git rev-parse --git-common-dir`, so all
linked worktrees of the same project share **one** save state —
not one per worktree.

**Always invoke with `bash` explicitly**, not `./save.sh`. The kit's
`/sync` mechanism doesn't guarantee the executable bit survives the
copy; `bash <script>` works regardless of file mode and is the
canonical call form for this skill.

### Interface

```text
bash <skill-dir>/save.sh status
    Reports SAVED.md state and archive count.

bash <skill-dir>/save.sh write <content-file> [--mode auto|archive|replace]
    Writes <content-file> into ~/.claude/projects/<key>/saves/SAVED.md.
    --mode auto      (default) archive existing SAVED.md if non-empty, then write
    --mode archive   force archive of existing SAVED.md before writing
                     (errors if SAVED.md is empty/missing)
    --mode replace   overwrite SAVED.md without archiving

bash <skill-dir>/save.sh archive
    Archives current SAVED.md to ~/.claude/projects/<key>/saves/<YYYY-MM-DD-HHMM>.md and
    prepends an entry to TIMELINE.md. No new content written.

bash <skill-dir>/save.sh current-branch
    Echoes the current git branch ("None" for detached HEAD or no
    commits). Used internally by `write` to auto-inject the Branch
    metadata; exposed for `/load` and other readers.
```

Exit codes: `0` success, `1` operational error, `2` usage error,
`3` refused (e.g. archive requested but SAVED.md is empty).

### Branch metadata auto-injection

After `write` copies the content into SAVED.md, the script checks
for a `> **Branch.** ...` line. If absent, it injects one based on
the current branch (or "None" for detached HEAD / no-commits). The
line is inserted after the last `> **...**` header line in the
content (typically right after `> **Thread.**`).

This makes the branch part of every save without requiring the AI
to remember to capture it. If the user wants to override (e.g.
mark a save as branch-agnostic), they can write `> **Branch.** None`
in the content explicitly — the script won't overwrite an existing
Branch line.

`/load` reads this line to detect mismatch between saved branch
and current branch, and optionally checks out the saved branch.

## Where saves live (and why)

Saves live **outside the project repo** at
`~/.claude/projects/<key>/saves/`. This is the same convention as
the kit's memory directory.

This is a deliberate choice — saves are **personal continuity, not
project documentation:**

- **Survive branch switches.** `git checkout <other-branch>` doesn't
  affect saves. /load can read your save from any branch and offer
  to switch you back to the saved branch.
- **Unified across worktrees.** All worktrees of the same project
  share one save state, instead of fragmenting per-worktree.
- **Per-user, per-project.** Two developers on the same repo don't
  see each other's saves — and shouldn't. The team-shared snapshot
  is `/handoff`, not `/save`.
- **Cross-project trajectory.** `ls ~/.claude/projects/*/saves/` gives
  a one-shot "what have I been working on lately" view across every
  project that uses the kit.

The kit's `/handoff` is the project-shared, team-visible
counterpart. Use `/save` for personal "where I left off" continuity;
use `/handoff` when you're stepping away and want a snapshot the
team (or future-you in 6 months) can pick up cold.

## Process

### Step 1 — Check current state

Run `bash .claude/skills/save/save.sh status` (or
`bash kit/skills/save/save.sh status` in the kit repo). The
output is one line — read it before synthesizing anything.

### Step 2 — Decide the archive mode

- **SAVED.md is empty or missing** → no question needed; use
  `--mode auto` (the script will just write).
- **SAVED.md has content** → ask the user:

  > SAVED.md already has content from `<mtime>`. Three options:
  > **(a) archive + new on top** (default — old content moves to
  > `~/.claude/projects/<key>/saves/<timestamp>.md`, TIMELINE.md gets an entry)
  > **(b) replace** (overwrite SAVED.md, drop old)
  > **(c) cancel**

  Map: (a) → `--mode auto`, (b) → `--mode replace`, (c) → stop.

### Step 3 — Synthesize content into a temp file

Write the snapshot using the **Output structure** below. The first
H1 of the file becomes the TIMELINE.md entry title — make it
descriptive (not "save 2026-05-10" — describe the actual thread).

Suggested temp path: `$(mktemp -t save-XXXX).md` so it lives
outside the repo.

### Step 4 — Call the script

```bash
bash .claude/skills/save/save.sh write <tempfile> --mode <auto|replace>
```

Surface the script's stdout in the closing summary. If exit code is
non-zero, surface stderr and stop — don't fall back to writing
files directly.

### Step 5 — Closing summary

Render:

```markdown
# 💾 Saved

- **Current.** `~/.claude/projects/<key>/saves/SAVED.md` — <line count> lines.
- **Archived previous.** `~/.claude/projects/<key>/saves/<archive>.md` *(only if archive happened)*
- **Timeline.** `~/.claude/projects/<key>/saves/TIMELINE.md` — <total archived> entries.

**Pick this up first when you come back:**
1. <terse — drawn from "What's open">
2. <terse>
3. <terse>

Review with `git diff`; commit when ready.
```

## Output structure

The content written to SAVED.md. The first H1 is mandatory — the
script uses it for TIMELINE.md.

```markdown
# <descriptive thread title — used in TIMELINE>

> **When.** <YYYY-MM-DD HH:MM>
> **Thread.** <one sentence — what we're working on right now>
> **Branch.** <branch-name or "None">

---

## ✅ What we did

Concrete completed steps in this thread. Specific — file paths,
commands run, what changed. No filler.

- <bullet — what + where>
- …

## 🧠 What we worked out

Conclusions, decisions, tradeoffs explored. The reasoning that
survived, not just the outcome. If a tradeoff is still open, say
so here AND list it under "What's open".

- **<short claim>** — <reasoning>
- …

## 🚧 What's open

The next pick-up point. Specific. The failure mode you stopped on,
the exact next experiment, the file:line to read first. This is
the load-bearing section — a save without specifics here is noise.

- <bullet — what + where to resume>
- …

## 🧪 Threads not yet pulled

Half-formed ideas, almost-figured-out bits, dead-ends worth
remembering so we don't re-litigate them. Don't lose these to the
next compaction.

- <bullet>
- …

## 📎 References

Files touched, links, external context.

- [`path/to/file.ext:line`](path/to/file.ext:line) — <why it matters>
- …
```

Empty sections render an honest one-liner ("Nothing in flight."),
not an empty bullet.

## Style rules

- **Imperative, specific, cited.** "Resume by re-running
  `pytest tests/test_auth.py::test_token_refresh` and reading
  `auth/token.py:42`." beats "continue the auth work."
- **Emoji are load-bearing.** 💾 (save), ✅ (did), 🧠 (worked out),
  🚧 (open), 🧪 (threads), 📎 (refs). Don't add others.
- **Bold the claim, dash, reason.** `- **Claim** — reason.`
- **First H1 is the title.** The script reads it for TIMELINE.md.
  Don't bury it under a frontmatter block or quote.
- **Cite via relative paths from `~/.claude/projects/<key>/saves/`** (i.e. `../../foo.md`)
  so links work when the archive file is opened directly.

## What you must NOT do

- **Don't hand-write SAVED.md, TIMELINE.md, or archive files.**
  All plumbing goes through `save.sh`. Hand-writing skips the
  TIMELINE entry, breaks the archive naming, and defeats the
  point of the deterministic split.
- **Don't run /save for project-wide state.** That's `/status`
  (read-only dashboard) or `/handoff` (project-leave). /save is a
  single thread.
- **Don't auto-commit.** Standard kit rule.
- **Don't omit "what's open".** A save without a specific next is
  a diary entry. If genuinely nothing is open (thread closed
  cleanly), say so explicitly: "Thread closed — nothing to resume."
- **Don't fabricate progress.** If a thread stalled, backtracked,
  or hit a wall, record that honestly. "Spent 90 minutes on X;
  concluded it's the wrong direction" is a valid save and saves
  future-you from re-running the same dead-end.
- **Don't capture secrets.** If credentials surface in the thread,
  flag and refuse to write them down. Suggest a secret-manager
  note instead.

## Edge cases

- **First /save in a project.** `~/.claude/projects/<key>/saves/` doesn't exist yet.
  The script creates it; SAVED.md is written directly with no
  archive. TIMELINE.md is created with header + zero entries
  (entries only appear when something gets archived).
- **Same-minute saves.** The script appends `-2`, `-3` suffixes
  to archive filenames to avoid collisions.
- **TIMELINE.md was manually edited.** The script inserts new
  entries above the first existing `- ` bullet, so manual header
  prose is preserved.
- **Empty conversation / nothing to save.** Push back: "There's
  no thread to checkpoint." Don't fabricate filler.
- **Script not executable or missing.** Surface the error
  verbatim. Don't fall back to hand-writing — that defeats the
  point of the split.
- **User wants to undo a save.** Not supported by the script.
  Tell them: `git checkout ~/.claude/projects/<key>/saves/` to revert, or rename the
  most recent archive back to SAVED.md manually.
- **User wants to see history.** Read `~/.claude/projects/<key>/saves/TIMELINE.md` —
  that's its job. Or list `~/.claude/projects/<key>/saves/20*.md`.

## When NOT to use this skill

- **Project-leave snapshot** → `/handoff`.
- **Live read of project state** → `/status`.
- **One-decision capture** → `/decision`.
- **Incident or postmortem** → `/postmortem`.
- **Nothing to save** → skip. A checkpoint with no content is
  noise.

## What "done" looks like for a /save session

`~/.claude/projects/<key>/saves/SAVED.md` updated with the current thread snapshot.
If a previous save existed and `--mode` was `auto` or `archive`,
the old content lives at `~/.claude/projects/<key>/saves/<YYYY-MM-DD-HHMM>.md` and
`~/.claude/projects/<key>/saves/TIMELINE.md` has a fresh entry at the top.
Uncommitted. The user can re-read `SAVED.md` to resume the
thread cold, or scan TIMELINE.md for the long view.
