---
name: mode
description: Activate, switch, end, or report on the current work mode. Modes are *drives* — voice in Claude's ear that primes appetite (e.g., "task mode" wants to clear the backlog; "cleanup mode" wants to improve in place). Activating a mode writes `.claude/mode.md` (which `CLAUDE.md` `@`-imports), so the drive prose loads on every session start. Switching or ending a mode finalizes activation stats to `.claude/mode-stats.md`. Distinct from `/playlists` (curated skill chains for a moment) — modes persist across sessions until explicitly ended. Triggered when the user wants to switch how Claude approaches the work — e.g., "/mode", "/mode task", "/mode cleanup", "/mode normal", "let's do task mode", "we're in cleanup mode now", "what mode am I in".
---

# /mode — Switch Claude's drive

A mode shapes Claude's *appetite* for the duration of work.
`/mode task` makes Claude want to clear the backlog;
`/mode cleanup` makes Claude want to improve the codebase in
place. The drive prose is in `kit/modes/<name>.md` (synced to
`.claude/modes/<name>.md`); activation writes
`.claude/mode.md` which `CLAUDE.md` reads on every session
start.

`/mode normal` is the off-switch — back to default Claude.

## Behavior contract

- **Operates only on `.claude/mode.md` and `.claude/mode-stats.md`.**
  Never edits source code, never auto-commits, never modifies
  the kit-managed `.claude/modes/<name>.md` definitions.
- **Excludes `README.md` from mode listings.** The `kit/modes/`
  directory ships with a `README.md` (concept doc + voice rules)
  that gets mirrored down to `.claude/modes/` like the mode files
  themselves. When listing available modes, filter it out
  (case-insensitive). Same goes for any `_*.md` file (reserved
  for future doc files).
- **Activation is via `@`-import, not body copy.**
  `.claude/mode.md` contains a small header (mode name, started
  timestamp, activation metadata) plus an `@`-import of
  `.claude/modes/<name>.md`. This way, edits to the local mode
  definition flow into active mode immediately, and `/sync`
  updates to mode definitions take effect on next activation.
- **Finalization is mandatory on switch.** Switching from one
  mode to another, or to normal, always writes the prior
  mode's deltas to `.claude/mode-stats.md` *before* activating
  the new one. Stats never get lost on a clean switch.
- **No mode = file absent.** Normal state is the absence of
  `.claude/mode.md`. Don't write a "Mode: normal" stub — the
  file's absence is the signal.
- **Single mode active at a time.** The kit's design is one
  drive at a time. Composite modes ("task + testing") are not
  supported; if needed, write a new dedicated mode.
- **Stats are append-only.** The activation log in
  `mode-stats.md` is never rewritten or pruned. The totals
  table is recomputed from the log on each finalize.

## Operations

The skill's behavior depends on the user's args:

| Invocation | Operation |
|---|---|
| `/mode` (no args) | **Report** current mode + stats |
| `/mode <name>` where `.claude/modes/<name>.md` exists | **Activate** or **switch** to that mode |
| `/mode normal` | **End** the active mode (return to default Claude) |
| `/mode <unknown>` | List available modes; suggest the closest match |

### Operation A — Report (`/mode` with no args)

Read `.claude/mode.md` if present and `.claude/mode-stats.md`
if present. Render:

```markdown
## 🎯 Current mode

**<MODE>** — started <relative time, e.g. "2h 14m ago">.
<one line from the active mode's "What you want" section,
quoted. No quotes if the mode definition is missing.>

## 📊 This activation

- Started: <ISO timestamp>
- Time in mode so far: <duration>
- <Mode-specific live counter, e.g. "Tasks closed so far: 3
  (backlog: 37 → 34)" for task mode; "Time-in-mode" only
  for cleanup mode.>

## 📈 Totals across activations

<render the totals table from mode-stats.md verbatim, or
"No prior activations.">

## What's available

- `/mode <name>` — switch
- `/mode normal` — end this mode

Available modes: <list every `.claude/modes/*.md` file by name>.
```

If no mode is active (file absent), render:

```markdown
## 🎯 No mode active

You're in normal Claude. To activate a drive:

- `/mode task` — clear the backlog
- `/mode cleanup` — improve the codebase in place
- `/mode project-manager` — refine the backlog phase by phase
<list every `.claude/modes/*.md` file by name>

## 📈 Totals across activations

<render mode-stats.md totals if present, else "No prior
activations.">
```

### Operation B — Activate or switch (`/mode <name>`)

1. **Validate `<name>`.** Verify `.claude/modes/<name>.md`
   exists *and* is a valid mode name (not `README` and not
   prefixed `_`). If invalid, list available modes (every file
   in `.claude/modes/` excluding `README.md` and `_*.md`) and
   suggest the closest match (Levenshtein or simple prefix).
   Stop.

2. **If a mode is currently active**, finalize it before
   activating the new one:
   - Read the active mode's metadata from `.claude/mode.md`
     (started timestamp, units_at_start).
   - Compute deltas:
     - **Time:** now − started.
     - **Units:** depends on the prior mode's `count_unit` field
       in `.claude/mode.md`. For `tasks_done_count`:
       `(current count of files in tasks/completed/) − units_at_start`.
       For `stubs_remaining_count`: `units_at_start − (current
       count of *.md files under tasks/backlog/ containing the
       string "STATUS: STUB")`. (Direction is inverted because
       refining a stub *removes* the STATUS: STUB header, so the
       remaining-stubs count drops; the delta = stubs refined.)
       For `none`: skip.
   - Append a row to `.claude/mode-stats.md`'s **Activation
     log**.
   - Recompute the **Totals** table from the full log.

3. **Capture activation metadata** for the new mode:
   - `mode`: `<name>`
   - `started`: ISO 8601 UTC timestamp now
   - `count_unit`: per the mode (see **Mode units** below)
   - `units_at_start`: the baseline value of that unit *now*

4. **Write `.claude/mode.md`** with the activation header
   plus an `@`-import of the mode definition. See **Output:
   `.claude/mode.md`** below for the exact shape.

5. **Initialize or update `.claude/mode-stats.md`** to show
   the new mode in **Active**.

6. **Render the activation announcement.** Speak in the
   mode's voice — set the tone immediately:

```markdown
## 🎯 Mode activated: <NAME>

<2-3 lines summarizing the drive, paraphrased from the mode's
"What you want" section. End with the count or starting state
the mode cares about.>

For task mode, that opener might be:
> "37 in backlog. 3 active. Let's go."

For cleanup mode:
> "Probing for smells. /audit on src/auth and src/payments
> next — say 'go' or pick a different slice."

To exit: `/mode normal`. To switch: `/mode <other>`.
```

### Operation C — End (`/mode normal`)

1. If no mode active: report "Already in normal Claude" and
   stop.

2. Finalize the current mode (same as step 2 in Operation B):
   compute deltas, append to log, recompute totals.

3. **Delete `.claude/mode.md`** (or move it to
   `.claude/mode.md.last` if you want to keep a record;
   default: delete).

4. Render the close-out:

```markdown
## 🎯 Mode ended: <NAME>

- Time in mode: <duration>
- <Units-specific summary, e.g. "Tasks closed: 4. Backlog:
  37 → 33." for task; "Time-in-mode logged. Activations:
  N total." for cleanup; "Stubs refined: 5 (8 → 3
  remaining). Session log: docs/refinement/<date>.md." for
  project-manager.>

You're back in normal Claude. Stats are in
`.claude/mode-stats.md`. Run `/mode` anytime to see totals.
```

## Mode units

Each mode defines what (if anything) it counts. The skill
hardcodes the detection logic per mode:

| Mode | `count_unit` | How units are detected |
|---|---|---|
| `task` | `tasks_done_count` | Number of `*.md` files in `tasks/completed/` (excluding `.gitkeep`). Activation records the baseline; finalization computes the delta. |
| `cleanup` | `none` | Time-in-mode only; no per-unit counting. |
| `project-manager` | `stubs_remaining_count` | Number of `*.md` files under `tasks/backlog/` containing the string `STATUS: STUB`. Activation records the baseline; finalization computes the inverse delta (`baseline - current` = stubs refined this session). Refining a stub removes the `STATUS: STUB` header, so the remaining count drops. |
| `normal` | n/a | Not a mode — represented by `.claude/mode.md` absence. |
| New modes | varies | Author chooses. If the unit isn't in this table, the skill must be extended to detect it. |

Adding a new unit type requires editing this skill's
detection logic. Filesystem-based units (file counts, mtimes)
are easiest. Git-log-based units (commit counts matching a
pattern) are richer but require committed work to count.

## Output: `.claude/mode.md`

The active-mode file uses YAML frontmatter for metadata + an
`@`-import for the drive prose:

```markdown
---
mode: task
started: 2026-05-01T09:14:32Z
count_unit: tasks_done_count
units_at_start: 47
---

# 🎯 Active mode: TASK

> *Started <relative time>. To switch: `/mode <name>`. To
> end: `/mode normal`. Stats:
> [`.claude/mode-stats.md`](mode-stats.md).*

@.claude/modes/task.md
```

The body after the frontmatter is human-readable status; the
`@`-import pulls the drive prose. `CLAUDE.md` `@`-imports
this file, so the prose loads transitively.

## Output: `.claude/mode-stats.md`

```markdown
# Mode stats

> Tracks activations across the project's lifetime. Updated by
> `/mode` on switch or end. Append-only log; totals are
> recomputed.

## Active

**TASK** — started 2026-05-01T09:14:32Z. Tasks closed so far:
0 (baseline: 47 in `tasks/completed/`).

*(If no mode active: "No mode active.")*

## Totals

| Mode | Activations | Total time | Units |
|---|---|---|---|
| task | 5 | 12h 30m | 12 closed |
| cleanup | 2 | 4h | — |

*(Empty when no activations have completed yet.)*

## Activation log

Append-only. Most recent first.

- 2026-05-01T09:14 → (active) | task
- 2026-04-29T14:00 → 18:00 (4h) | cleanup
- 2026-04-29T08:00 → 09:30 (1h 30m) | task | +2 closed
- 2026-04-28T10:00 → 12:00 (2h) | task | +3 closed
- ...
```

The "Active" section reflects the current `.claude/mode.md`.
When that file is absent, render "No mode active."

## Style rules

- **Match the active mode's voice on activation.** When
  activating task mode, the announcement should *feel*
  task-mode: count up front, "Let's go." For cleanup, it
  should feel investigative: probing language, suggesting
  audit slices. The mode's own prose dictates the tone of the
  meta-announcement.
- **Time deltas in human form.** "2h 14m" not
  "8040 seconds." "yesterday" or "3d ago" for activation
  references in the stats render.
- **Absolute timestamps in storage.** ISO 8601 UTC in
  frontmatter and log lines. Renderable everywhere.
- **Backlog count is the dopamine.** When in task mode, every
  status render that mentions tasks should include the
  backlog count and how it's moved. "37 → 34" beats "3 closed."

## What you must NOT do

- **Don't edit `kit/modes/<name>.md`** — those are upstream
  definitions, owned by the kit. Local edits go in
  `.claude/modes/<name>.md`. The skill operates on
  `.claude/mode.md` (the activation record) and
  `.claude/mode-stats.md` (the accumulator).
- **Don't auto-commit.** Same rule as every kit-write skill.
  Activation writes a file; the user commits when they're
  ready.
- **Don't fabricate stats.** If the activation log is empty
  or the mode definition is missing, render the empty state
  honestly. Never guess deltas from memory.
- **Don't switch modes silently.** If the user types
  something that *implies* a mode switch ("let's clean up
  this code") but doesn't invoke `/mode`, surface the
  question rather than acting: "Sounds like cleanup mode —
  switch with `/mode cleanup`?"
- **Don't enforce the mode.** Modes are drives, not
  guardrails. If the user asks for a feature mid-cleanup-mode,
  do it — but mention the mode mismatch ("we're in cleanup
  mode; this is more of a `/task` — fine to do, want to
  switch?") and continue. The mode keeps presence by surfacing
  the friction, not by refusing.
- **Don't combine modes.** One drive at a time. If a user
  asks for a combo mode, suggest writing a new dedicated mode
  via `/new-skill`-style scaffolding (or just a new file in
  `kit/modes/`).
- **Don't lose stats on errors.** If finalization fails
  partway (e.g., can't read `tasks/completed/`), abort the switch
  and report the error — don't activate the new mode while
  losing the previous one's tally.

## Edge cases

- **`.claude/modes/` doesn't exist.** Project pre-dates
  modes. Suggest re-running `bin/init` to scaffold the
  modes dir, or running `/sync` to pull mode definitions.
  Don't activate.
- **Active mode references a definition that's been
  deleted.** Render a warning ("active mode `task` has no
  definition file — was `.claude/modes/task.md` removed?"),
  let the user finalize it cleanly with `/mode normal` even
  without the definition body.
- **`tasks/completed/` doesn't exist.** Task mode's unit detection
  fails gracefully — report units as `unknown` rather than
  zero. Don't create the dir.
- **Switching to the currently-active mode.** No-op with a
  friendly message: "Already in `task` mode. Run `/mode` to
  see stats."
- **Stats file is corrupted or hand-edited inconsistently.**
  Don't try to repair. Report the issue and ask the user to
  fix or reset the file.
- **Time-in-mode crosses days.** No special handling — the
  duration is just `now − started`. The log row renders the
  full span.
- **User invokes `/mode` in a non-kit project.** If
  `.claude/modes/` doesn't exist, point at the kit's docs
  rather than failing silently.

## When NOT to use this skill

- **One-off ritual** (morning standup, end-of-day wrap) → use
  `/playlists`, which curates skill chains for a moment.
  Modes are for sustained drive across sessions.
- **Filing a single piece of work** → `/task`.
- **Capturing a single decision** → `/decision`.
- **Switching how Claude *talks* to you** (more concise, less
  verbose, etc.) → edit `.claude/pact.md`. The pact is your
  working-relationship contract; mode is your drive.

## What "done" looks like for a /mode session

After `/mode <name>`:
- `.claude/mode.md` exists with the activation header + the
  drive prose import.
- `.claude/mode-stats.md`'s **Active** section reflects the
  new mode.
- Claude renders the activation announcement in the mode's
  voice, with the relevant starting count or probe.
- The previous mode (if any) has been finalized — its
  deltas appear in the log and totals.

After `/mode normal`:
- `.claude/mode.md` is gone.
- `.claude/mode-stats.md` shows "No mode active" and includes
  the just-ended activation in the log + totals.
- The user is told the duration and units of the run that
  just ended.

After `/mode` with no args:
- A status block in chat. No file changes.
