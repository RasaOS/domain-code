---
name: status
description: Global project snapshot — current production version, latest deploys, recent commits and authors, open PRs, in-flight work, top of the roadmap, doc/audit recency. One pleasant scannable read of "where do things stand right now". Triggered when the user wants a quick situational read — e.g. "/status", "where do things stand", "what's the current state of the project", "give me a snapshot".
---

# /status — Project snapshot

A single readable dashboard of where the project is *right now*.
Production state, in-flight work, recent activity, and what's next.
No editing, no opining — pure situational awareness.

Per CLAUDE.md: honest, calibrated. If a piece of data is stale or
unavailable, say so — don't fabricate.

## Behavior contract

- **Read-only.** Don't edit files, don't commit, don't push. This
  skill answers "where are we?" — it doesn't change anything.
- **The script's stdout IS the user-facing output. Pass it verbatim.**
  This is the load-bearing rule of this skill. See "Output policy"
  below.
- **Script-driven render.** All data gathering AND rendering runs
  through `status.sh dashboard`. This is Cat 1F per
  `script-craft.md`: defined output every single invocation. Same
  project → same output.
- **No recommendations.** This skill reports state. If the user
  wants advice on what to do next, they'll ask `/plan` or `/stuck`.

## Output policy (the load-bearing rule)

`status.sh dashboard` produces a complete, rendered, user-facing
report. The AI's job is to **show that output to the user
exactly as the script produced it**. Nothing else.

**MUST:**
- Run `bash <skill-dir>/status.sh dashboard`.
- Output the script's stdout in your reply, *unchanged and
  unsummarized*.
- If the script exits non-zero, surface stderr verbatim and stop.

**MUST NOT:**
- Summarize the report ("Here's the gist: …"). The user wanted
  the full snapshot — that's why they invoked `/status`.
- Paraphrase any section. The script's wording is the wording.
- Drop sections that look empty. Empty-state lines are
  intentional information ("No active tasks." tells the user
  the state).
- Rewrap the box-drawing art. Monospace alignment depends on
  byte-exact output.
- Add a preamble ("Sure, here's your status:") or closing
  remarks ("Let me know if you have questions!"). End on the
  last line the script emitted.
- Reorder, regroup, or merge sections.

**MAY:**
- Add a follow-up question *below* the script's output if the
  user's intent suggests they want next-step help (e.g. "Want me
  to look into PR #42?"). The script's output is sacrosanct —
  what comes after it is the conversation continuing.

## The script

Lives in this skill's folder at `kit/skills/status/status.sh` (or
`.claude/skills/status/status.sh` in synced projects). Always
invoke with `bash` explicitly per `script-craft.md`.

### Interface

```text
bash <skill-dir>/status.sh dashboard   (default)
    Emit the full status report to stdout. Sections rendered:
      - Title line + date
      - Current goal (one line from CLAUDE.md's Goal section;
        omitted if there's no CLAUDE.md or no goal)
      - §2 dashboard box (production, branch, worktrees, in-flight, pending)
      - Recent commits (markdown table, last 10)
      - Open pull requests (markdown table via `gh` if available)
      - In flight (bullet list of tasks/active/*.md titles)
      - Top of roadmap (first ~5 list items from tasks/ROADMAP.md)
      - Inbox (unread count + list, for your `@handle`)

bash <skill-dir>/status.sh data
    Emit raw key=value lines (repo, current_goal, branch,
    production_tag, inbox_handle, inbox_unread, etc.) for
    composition / debugging. Not the user-facing report.
```

Exit codes: `0` success, `1` operational error (not in a git
repo), `2` usage error.

### What the script handles deterministically

- Latest production tag via `git tag --list 'v*' --sort=-v:refname`
- Branch + clean/dirty state via `git diff` and `git ls-files --others`
- Ahead/behind via `git rev-list --left-right --count`
- Worktree count via `git worktree list`
- Active task count via `find tasks/active -name '*.md'`
- Pending release (commits past latest tag) via `git rev-list --count`
- Recent commits via `git log` with truncated subjects
- PRs via `gh pr list --json ...` (skipped gracefully if `gh`
  missing, unauthed, or no network)
- Roadmap items via grep of `tasks/ROADMAP.md`
- Inbox unread count and listing — handle from `git config
  user.name` (lowercased first word) or cached
  `.claude/inbox/_me.md`. Counts `[unread]` markers in
  `.claude/inbox/<handle>.md`. Section silently skipped if the
  project has no `.claude/inbox/` directory.
- All graceful skip / fallback messages

### What's NOT in this script (yet)

- §23 Activity timeline (was sourced from `tasks/AUDIT.md`)
- §25 Alert variants ("anything off" section)

Both are conditional sections in the original SKILL spec. They
can be added in a later version once the core render is stable.
The current core covers ~90% of the snapshot value.

## Process

### Step 1 — Invoke the script

```bash
bash .claude/skills/status/status.sh dashboard
```

(Or `kit/skills/status/status.sh` in the kit repo itself.)

### Step 2 — Surface stdout verbatim

Whatever the script printed is the user-facing report. Don't:
- Rephrase the headline
- Reorder sections
- Synthesize commentary above or below the report
- Re-render the box with different glyphs / spacing

The script owns the output shape. The AI is a pass-through.

If the script exited non-zero, surface stderr and stop. Don't
fall back to hand-gathering the data.

## Output structure

The script renders exactly this shape (placeholders filled with
real data per invocation):

````markdown
# Project status · <repo> · <YYYY-MM-DD>

🎯 **Goal** — <current goal, one line from CLAUDE.md's Goal section>

```
┌─ <repo> · <YYYY-MM-DD HH:MM TZ> ──────────────────────────┐
│                                                            │
│  ● Production    v1.1.0 (742b5f1 / 2026-04-27)             │
│  ● Branch        main | clean | 2 ahead                    │
│  ● Worktrees     3 worktrees active        (omitted if 1)  │
│  ◐ In flight     3 tasks active                            │
│  ◐ Pending       2 commits past v1.1.0, untagged           │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

*(§2 dashboard. Glyph semantics: ● current/healthy, ◐
active/in-progress, ○ empty/pending. The script drops rows that
don't apply — no pending → skip Pending row; only 1 worktree →
skip Worktrees row. Values are ASCII to keep width math
deterministic.)*

## Recent commits

| SHA | Author | When | Subject |
|---|---|---|---|
| `72c3810` | Chazzcoin | 2h ago | Wire Parts Inventory, Work Orders, … |
| … | … | … | … |

*(Up to 10 commits via `git log`. Subjects truncated at 60 chars
with `…`. Pipes in subjects replaced with `/` to keep table clean.)*

## Open pull requests

| # | Title | Author | Branch | Age |
|---|---|---|---|---|
| #35 | /skills meta-skill | Chazzcoin | chore/skills-meta-skill | 2026-04-27 |

*(Via `gh pr list --json ...`. Renders one of: the table, "No open
PRs.", or "`gh` not installed/failed" message — all script-side
deterministic.)*

## In flight

- **TASK-XXX — <title>** — `tasks/active/<file>.md`
- …

*(Bulleted list from `tasks/active/*.md`. Title is the first H1
of each file. If `tasks/active/` doesn't exist or is empty, the
script renders "No active tasks." or "No `tasks/active/` directory
in this project.")*

## Top of roadmap

- TASK-XXX — <title>
- …

*(First 5 list items grepped from `tasks/ROADMAP.md`. If absent,
renders "No `tasks/ROADMAP.md` in this project.")*

## 📬 Inbox

**3 unread messages** for `@chazz`:

- `#0007` `[unread]` from `@michael` · 2026-05-09 14:22
- `#0008` `[unread]` from `@self` · 2026-05-10 09:15
- `#0009` `[unread]` from `@sam` · 2026-05-10 18:30

*(Up to 5 unread headers from `.claude/inbox/<your-handle>.md`,
identity from `git config user.name`. Whole section silently
skipped if the project has no `.claude/inbox/` directory.)*
````

## Style rules

The script enforces the style — the AI's only style rule is
"don't touch what the script produced." If you want to refine the
output, change the script. Don't paraphrase in the chat layer.

- **Render structured deliverables per `output-rules.md`.** §2
  dashboard rows use the canonical glyph set (● ◐ ○ ✗); the
  script uses these exclusively.
- **ASCII values, Unicode borders.** Values use `|`, `/`, `-`
  separators (not `·`, `—`) to keep bash padding math
  deterministic. Box-drawing characters (`┌─┐│└┘`) are
  multi-byte but aren't padded — they're emitted directly.
- **No closing chat.** End on the last section the script
  emitted. The user will follow up if they want detail.

## What you must NOT do

- **Don't recommend actions.** "You should deploy v1.2.0" — not
  this skill's job. Report state; let the user decide.
- **Don't editorialize PRs.** Just list them. Reviewing them is
  `/review` or `/ultrareview`.
- **Don't deep-dive any single section.** If the user wants
  details on a PR, an audit entry, or a task, they'll ask. Keep
  the snapshot a snapshot.
- **Don't run write operations** to "tidy up" before reporting.
  If the working tree is dirty, that's part of the status —
  report it, don't clean it.

## When NOT to use this skill

- **Looking at the full roadmap or backlog** → `/roadmap` or
  `/backlog`.
- **Reviewing what shipped historically** → read `tasks/AUDIT.md`
  directly.
- **Code-level "what's going on in this folder"** → `/audit` or
  `/review`.
- **Strategic "what should we do next"** → `/plan`.
- **Filing or moving tasks** → `/task`.

## What "done" looks like for a /status session

A single rendered snapshot. The user reads it, knows where things
stand, and either asks a follow-up or moves on. No file changes,
no git operations beyond reads, no commits.
