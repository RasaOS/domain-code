---
name: auto-save
description: Toggle a session-lifecycle auto-save pattern on/off. When ON, installs three Claude Code hooks — SessionStart (injects auto-save context for the AI to perform periodic in-session merges), PreCompact (archives SAVED.md before context compaction), SessionEnd (archives SAVED.md at session termination). When OFF, removes the hooks. Per-user (writes to `.claude/settings.local.json`, gitignored). Subcommands: `on`, `off`, `status`. Triggered when the user wants to enable auto-saving — e.g. "/auto-save on", "/auto-save off", "/auto-save status", "turn on auto-save", "auto checkpoint my work".
---

# /auto-save — Toggle session-lifecycle auto-save

A pattern that combines hooks + `/save` to checkpoint work
periodically and archive at the right moments. **Toggle-driven** —
not designed to be forever on. Flip it on for big sessions; flip it
off when you don't need it.

Builds on top of:
- **`/save`** (does the actual writing to `~/.claude/projects/<key>/saves/`)
- **`/install-hook`** (deterministic JSON manipulation of `settings.local.json`)

This skill orchestrates the hook installation and provides the
hook handlers themselves (`auto-save.sh archive` and `auto-save.sh context`).

## The three hooks

| Hook event | Command | What it does |
|---|---|---|
| `SessionStart` | `bash <skill-dir>/auto-save.sh context` | Emits JSON injecting "auto-save mode is active" instruction into the AI's context. The AI then performs periodic in-session merges per the rules. |
| `PreCompact` | `bash <skill-dir>/auto-save.sh archive` | Archives the current SAVED.md before context compaction. Without this, compaction loses the thread and the next merge writes a stub. |
| `SessionEnd` | `bash <skill-dir>/auto-save.sh archive` | Archives the current SAVED.md at session termination — the standard archive-style save we'd do manually at the end. |

`PreCompact` and `SessionEnd` are pure script — no AI involvement.
`SessionStart` injects context so the AI knows to do periodic in-session merges.

## The cadence (in-session merges)

When auto-save is on, the SessionStart hook injects this guidance into
the AI's context:

> Every 5–8 user prompts, OR at any clear thread shift (whichever
> comes first), invoke `/save` with `--mode replace`. Merge the
> current SAVED.md with this session's activity. Tell the user
> when you auto-saved with a terse single-line note.

Cadence guidance lives in `auto-save.sh` at `AUTO_SAVE_CADENCE_GUIDANCE`
— edit there to evolve as we learn what feels right.

## The merge rules

When the AI invokes `/save --mode replace` during an auto-save,
it should produce a MERGED version of the current SAVED.md, not
write fresh content. Per-section rules:

| Section | Behavior |
|---|---|
| `> **When.**` | Update to current time |
| `> **Thread.**` | Keep unless the thread has materially shifted |
| `> **Branch.**` | Auto-injected by `save.sh` — unchanged |
| `✅ What we did` | **Accumulate** — keep existing bullets, add new ones |
| `🧠 What we worked out` | **Accumulate** |
| `🚧 What's open` | **Replace** with current open state (closed items drop off) |
| `🧪 Threads not yet pulled` | **Accumulate** |
| `📎 References` | **Accumulate, dedupe** |

Two behaviors: **accumulate** (historical) vs **replace** (current state).

## The script

Lives at `kit/skills/auto-save/auto-save.sh` (or
`.claude/skills/auto-save/auto-save.sh` in synced projects).

### Interface

```text
bash <skill-dir>/auto-save.sh on
    Install the three hooks into .claude/settings.local.json.
    Idempotent — safe to re-run.

bash <skill-dir>/auto-save.sh off
    Remove the three hooks.

bash <skill-dir>/auto-save.sh status
    Report ON / OFF / PARTIAL.

bash <skill-dir>/auto-save.sh archive
    What the PreCompact and SessionEnd hooks call. Delegates to
    save.sh archive. Silent — no output even when there's nothing
    to archive (expected no-op for hook firings).

bash <skill-dir>/auto-save.sh context
    What the SessionStart hook calls. Emits JSON to stdout that
    Claude Code passes as additionalContext to the AI.
```

Exit codes: `0` success, `1` operational, `2` usage error.

## Behavior contract

- **Per-user by default.** Writes to `.claude/settings.local.json`
  (gitignored). Auto-save is a personal preference; toggling it
  shouldn't ripple to teammates. To make it team-shared, edit
  the `AUTO_SAVE_TARGET` variable at the top of `auto-save.sh`.
- **Idempotent.** Running `auto-save on` twice is a no-op. Running
  `auto-save off` when off is a no-op.
- **Three-hook all-or-nothing.** All three hooks install together;
  all three remove together. `status` reports `PARTIAL` if the
  state is mid-toggle and asks the user to re-run.
- **Silent during normal operation.** PreCompact and SessionEnd
  hooks emit nothing on success or expected no-ops. Users see
  the effect (archived files in `saves/`) but not the activity.
- **AI-visible at session start.** SessionStart hook injects the
  instruction so the AI knows to do merges and tells the user when
  it auto-saves.
- **Never auto-commits.** Standard kit rule. Hooks are installed in
  `settings.local.json` (gitignored anyway); SAVED.md and archives
  live in user-global space outside the repo.

## Process

### Step 1 — Determine the request

User's intent maps to a subcommand:
- "turn on auto-save" / "/auto-save on" → `on`
- "turn off auto-save" / "/auto-save off" → `off`
- "is auto-save on?" / "/auto-save status" → `status`

### Step 2 — Run the subcommand

```bash
bash .claude/skills/auto-save/auto-save.sh <on|off|status>
```

Surface the script's stdout.

### Step 3 — Note the lifecycle

If turning on: tell the user the hooks take effect on the NEXT
session start (the current session won't have the SessionStart
context injected — that already fired).

If turning off: tell the user the in-session AI behavior continues
for the current session (the AI was told auto-save was active by
this session's SessionStart hook); next session won't have it.

## What "auto-save active" means for the AI's behavior

When the AI sees the SessionStart hook's injected context, it
should:

1. **Self-trigger periodic merges.** Every 5–8 user prompts, or
   at any clear thread shift. Invoke `/save --mode replace` with
   merged content per the merge rules.
2. **Tell the user.** Add a terse line at the bottom of the
   response: *— auto-saved at HH:MM —*.
3. **Don't worry about PreCompact / SessionEnd.** Those are hook-
   driven, deterministic. The AI's only auto-save responsibility
   is the in-session merges.
4. **Keep working normally otherwise.** Auto-save is background —
   it shouldn't disrupt the conversation.

## Style rules

- **Toggle output is brief.** One block per `on`/`off`, clear
  status message, no preamble.
- **Status output is one line.** `ON (3/3)`, `OFF (0/3)`, or
  `PARTIAL (N/3)`.
- **Don't render the hook handlers in chat.** The handler
  subcommands (`archive`, `context`) are for the hook system, not
  the user.

## What you must NOT do

- **Don't manually edit `settings.local.json` for these hooks.**
  Use `auto-save on/off`. Direct edits skip the idempotency check
  and the matching `off` won't remove things cleanly.
- **Don't enable auto-save in a session and assume it's already
  active for the same session.** SessionStart fires at session
  start. The current session continues with whatever state was
  active at its start.
- **Don't bundle other hooks under auto-save's umbrella.** This
  skill installs exactly three hooks. Other skills wanting their
  own hooks should call `/install-hook` directly.
- **Don't ship project-wide auto-save by default.** Per-user is
  the right default; opt-in to team-wide if the project explicitly
  decides.

## Edge cases

- **`settings.local.json` is malformed.** `install-hook.sh` refuses
  to write and surfaces the parse error. User fixes manually.
- **`python3` missing.** `install-hook.sh` exits 1. Auto-save can't
  install/remove until python3 is available.
- **Not in a git repo.** Both `install-hook.sh` and `save.sh`
  refuse (they resolve paths via `git rev-parse`). `auto-save on`
  fails the same way.
- **In-session merge produces an unexpected change.** The next
  PreCompact or SessionEnd will archive the current state — if
  it's wrong, the archive timestamp captures it; the user can
  re-load an earlier archived save manually.
- **Two concurrent sessions on the same project.** Both have
  auto-save active. Their merges race on the same SAVED.md (last
  write wins). Avoid: turn auto-save off in one session if you're
  running parallel sessions on the same project.

## When NOT to use this skill

- **Quick single-thread work.** A manual `/save` at the end is
  fine; auto-save's overhead isn't earned.
- **Read-only sessions.** Nothing's changing; nothing to save.
- **Sessions where you're going to /handoff anyway.** /handoff
  is project-shared; /save and auto-save are personal continuity.
- **Pair sessions with another developer.** Auto-save assumes
  one-author-per-session.

## What "done" looks like for an /auto-save session

The user invokes `on` / `off` / `status`. The script does its work.
The user sees the brief result. Next session start (for `on`)
reflects the new state. Nothing else changed in chat or on disk.
