---
name: load
description: Rehydrate context from the most recent `/save` snapshot. Reads `~/.claude/projects/<key>/saves/SAVED.md` (current state), scans recent `~/.claude/projects/<key>/saves/TIMELINE.md` entries (trajectory), and surfaces `git log` activity since the save was written so the AI can flag mismatches ("you said X was open, but commit Y closed it"). Read-only — does not modify SAVED.md, TIMELINE.md, or archived saves. Distinct from `/onboard` (cold project intro), `/status` (live project state), and `/handoff` (project-leave snapshot). Triggered when the user wants to resume a thread — e.g. "/load", "where was I", "load the save", "pick up where we left off", "what was I doing last time", "rehydrate context".
---

# /load — Rehydrate context from the most recent save

Read-side companion to `/save`. Reads what was saved, scans the
recent trajectory, and surfaces any git activity since the save so
you can pick up the thread without re-deriving where you left off.

Per CLAUDE.md ethos: **calibrated**. The save was true at a point
in time. If git log shows commits since then, those might have
changed the picture. Flag mismatches — don't pretend the save is
current if reality has moved.

## Behavior contract

- **Read-only.** Does not modify SAVED.md, TIMELINE.md, or any
  archived save file. Pure synthesis from existing data.
- **Script-driven data gather.** The deterministic gather (read
  SAVED.md, scan TIMELINE.md, compute git-since-save) runs through
  `load.sh orient`. The AI synthesizes from the script's output;
  doesn't re-implement the data collection. Always invoke as
  `bash <skill-dir>/load.sh ...` per `script-craft.md`.
- **Calibrate against git.** If commits happened since SAVED.md
  was written, surface them. The save's "what's open" may already
  be done — verify before assuming.
- **One thread, not the whole project.** /load orients within the
  most recent /save's thread. For project-wide live state, run
  `/status`. For cold-start orientation, run `/onboard`.
- **Don't expand scope.** /load orients; it doesn't plan, execute,
  or modify. The next action is the user's call.

## The script

Lives in this skill's folder at `kit/skills/load/load.sh` (or
`.claude/skills/load/load.sh` in synced projects). Always invoke
with `bash` per `script-craft.md`.

### Interface

```text
bash <skill-dir>/load.sh status
    Report whether SAVED.md exists and when it was last written.

bash <skill-dir>/load.sh orient
    Emit the full orient data:
      - SAVED.md content
      - Last 5 TIMELINE.md entries
      - Branch comparison (saved vs. current)
      - Git log since SAVED.md was written

bash <skill-dir>/load.sh branch
    Echo the branch recorded in SAVED.md (or "(not recorded)" /
    "None").

bash <skill-dir>/load.sh checkout
    Check out the branch recorded in SAVED.md. Refuses if working
    tree is dirty, saved branch is "None", or branch doesn't exist
    locally. Already-on-branch is a no-op.
```

Exit codes: `0` success, `1` no SAVED.md, `2` usage error,
`3` refused (e.g. dirty tree, missing branch, "None").

## Process

### Step 1 — Check for a save

Run `bash .claude/skills/load/load.sh status`. If exit code is
non-zero (no SAVED.md), render:

```markdown
# 🔁 Nothing to load

No `~/.claude/projects/<key>/saves/SAVED.md` found. Either no /save has been run yet
in this project, or this project doesn't use /save.

**Options:**
- Run `/save` first to create a snapshot you can load later.
- Run `/onboard` for cold-start orientation if you're picking up
  a project without prior save history.
- Run `/status` for current live project state.
```

Then stop.

### Step 2 — Gather orient data

Run `bash .claude/skills/load/load.sh orient`. The script emits
three sections (SAVED.md content, last 5 TIMELINE entries, git log
since save). Read the output verbatim — don't re-derive any of it.

### Step 3 — Handle branch mismatch (if present)

The `orient` output includes a "Branch comparison" section. Three
cases:

1. **Saved branch matches current branch.** No action; render in
   output as confirmation ("on the saved branch ✓").
2. **Saved branch is "None"** (recorded as branch-agnostic) **OR
   "(not recorded)"** (old save pre-branch-tracking). No checkout
   makes sense. Render in output as informational only.
3. **Saved branch differs from current branch.** Ask the user:

   > Saved on `<saved-branch>`, currently on `<current-branch>`.
   > Switch to the saved branch?
   >
   > **(a) yes — checkout** (run `load.sh checkout`; refuses if
   > working tree is dirty)
   > **(b) no — stay on current** (proceed with orientation as-is)

   If (a): invoke `bash <skill-dir>/load.sh checkout`. Surface the
   script's stdout/stderr verbatim. If checkout refuses (exit 3),
   surface the reason and offer (b) as fallback.

### Step 4 — Synthesize and render

Use the **Output structure** below. Lean on the script's output
for facts. Lean on synthesis for:
- Paraphrasing SAVED.md's "What we did" / "What we worked out" tersely
- Cross-referencing "What's open" against the git log to flag stale items
- Surfacing the branch mismatch clearly if not resolved in Step 3
- Picking the single most useful next action

### Step 5 — Closing pointer

Tell the user where to pick up first. Drawn from SAVED.md's
"What's open" section, modified by anything git activity shows is
now done. Cite specifically — file path + first concrete action.

## Output structure

```markdown
# 🔁 Rehydrated from save

> **Saved:** <YYYY-MM-DD HH:MM> *(<N hours/days> ago)*
> **Thread:** <one line — from SAVED.md's Thread/title line>
> **Branch:** <saved-branch> *(✓ matches current | switched from <current-branch> | None | mismatch)*

---

## 📌 Where you left off

<2-4 sentences paraphrasing SAVED.md's "What we did" + "What we
worked out" sections. Terse. Specific. Cite SAVED.md.>

## 🌿 Branch state

Render one of:

- **On the saved branch** (`<branch>`) — no action needed.
- **Switched to saved branch** (`<branch>` ← `<previous>`) — done
  via `load.sh checkout`.
- **Mismatch unresolved** — saved on `<saved-branch>`, currently on
  `<current-branch>`. User chose to stay on current. Be aware
  context below refers to the saved branch.
- **No branch tracking** — saved as `None` (or pre-tracking save).
  Branch context is informational only.

## 🚧 What was open

Drawn from SAVED.md's "What's open" section. **Cross-referenced
with git activity** — if a commit since the save addresses an item,
flag it.

- <still-open bullet — render as-is>
- ~~<bullet>~~ — possibly closed in `<short-SHA>` (<subject>) — verify
- …

*(If nothing was open: "Thread closed cleanly — nothing was open.")*

## 📜 Recent trajectory

Last 3-5 TIMELINE entries, one line each. Pattern context.

- <date> — <title>
- …

*(Skip section if TIMELINE.md is absent — first save in this project.)*

## 🌳 Git activity since save

<N> commits between <save timestamp> and now (excluding save-only
commits in `~/.claude/projects/<key>/saves/`).

- `<short-SHA>` — <subject>
- …

*(If zero: "No commits since save — picking up cleanly.")*

## 🎯 Pick this up first

<One specific concrete action, drawn from "What's open" cross-
referenced with git activity. Cite file path or command. Imperative,
not narrative.>
```

## Style rules

- **Emoji are load-bearing.** 🔁 (rehydrate), 📌 (where), 🌿 (branch),
  🚧 (open), 📜 (trajectory), 🌳 (git activity), 🎯 (next). Don't
  add others.
- **Calibrate against git — don't just parrot SAVED.md.** If
  "what's open" mentions test failures and git shows a "fix tests"
  commit since, flag it. That's the value-add of /load over just
  reading SAVED.md.
- **Honest empty sections.** "No commits since save." beats an empty
  bullet. "Thread closed cleanly — nothing open." beats fabricated
  next steps.
- **Cite via `path:line` for file references**, `<short-SHA>` for
  commits.
- **The 🎯 section is the load-bearing one.** Vague nexts here defeat
  the point of /load. If you can't pick a single concrete action,
  say so explicitly: "Nothing single-action stands out — surface
  ambiguity to user."

## What you must NOT do

- **Don't modify SAVED.md, TIMELINE.md, or any archived save.**
  /load is read-only. Use /save to update state; use /load to
  read it.
- **Don't synthesize what isn't there.** If SAVED.md doesn't mention
  something, don't invent it. If git log is empty since the save,
  say so.
- **Don't run /load when SAVED.md is empty/missing.** Surface the
  gap, suggest /save or /onboard, stop. Don't fabricate context
  from nothing.
- **Don't fall back to reading files directly.** All data gather
  goes through `load.sh orient` per script-craft.md. Hand-reading
  bypasses the deterministic gather and risks divergence from
  /save's pattern.
- **Don't conflate /load with /status.** /load is "resume my last
  thread"; /status is "what's the current project state right now."

## Edge cases

- **No SAVED.md.** Step 1 catches this. Render the "Nothing to
  load" block and stop.
- **SAVED.md is very old (>2 weeks).** Surface the age explicitly
  in the header (`*(14 days ago)*`). Optionally suggest running
  `/handoff` if the project has had stepping-away cycles since.
- **Many commits since save (>20).** The script truncates at 20
  with a "... and N more" line. Render that; suggest `git log`
  for the full picture if the user wants to dig.
- **TIMELINE.md missing.** First save in the project — no archive
  yet. Skip the "Recent trajectory" section; don't fail.
- **SAVED.md content is stale or contradicts current code.**
  Surface the contradiction explicitly: "SAVED.md says X is in
  progress, but `<file>` shows Y. Verify before resuming."
- **Multiple worktrees with diverged git history.** Use `git log`
  from the worktree you're invoked in. Don't try to consolidate
  across worktrees — surface that complexity to the user.
- **Pre-branch-tracking save (no Branch line in SAVED.md).** The
  script extracts an empty string; orient output renders "saved
  branch: (not recorded — pre-branch-tracking save)". No checkout
  possible. Treat as branch-agnostic.
- **Saved branch is "None".** Branch-agnostic save. No checkout
  action. Render informationally.
- **Saved branch doesn't exist locally.** `load.sh checkout` exits
  3 with the reason. Surface verbatim. User decides whether to
  create the branch (out of /load's scope) or stay on current.
- **Saved branch is checked out in another worktree.** Git refuses
  to check out the same branch in multiple worktrees. `load.sh
  checkout` detects this proactively (via `git worktree list
  --porcelain`) and exits 3 with the conflicting worktree path.
  User decides: cd to that worktree, remove the other worktree,
  or stay put.
- **Working tree is dirty when user asks for checkout.** `load.sh
  checkout` exits 3 with the reason. Surface verbatim. User
  commits or stashes, then retries.

## When NOT to use this skill

- **Cold project orientation** (no prior save context) → `/onboard`.
- **Live project state right now** → `/status`.
- **Project-leave snapshot** (heavyweight handover) → `/handoff`.
- **No saves yet in this project** → run `/save` first.
- **Resuming someone else's work** → `/handoff` writes the doc
  designed for that; `/load` is for your own resume.

## What "done" looks like for a /load session

The user reads the rendered orient and knows three things:

1. **What they were working on** (the thread, paraphrased)
2. **What's still open** (after git cross-reference)
3. **The single most useful next action** (specific, citable)

No files modified. The user's next message says either "yes, picking
up there" (and they're off) or "actually, I want to switch to X"
(and the load served its purpose anyway — clean re-orientation).
