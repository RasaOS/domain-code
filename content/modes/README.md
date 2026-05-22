# Modes

A mode is a **drive** — a voice in Claude's ear that primes
appetite. Not a permission filter, not a skill router. When a
mode is active, Claude *wants* to do the thing that mode is for,
and feels off-track when not doing it.

The kit's other layers (skills, rules, primitives) tell Claude
*what's available* and *what's required*. Modes tell Claude
*what to want*.

---

## How modes work

| File | Where | Purpose |
|---|---|---|
| `kit/modes/<name>.md` | upstream kit | The drive prose for a mode. Synced down via `/sync`. |
| `.claude/modes/<name>.md` | every project | Local copy of the mode definition. Editable per project. |
| `.claude/mode.md` | active project | The *currently active* mode. `@`-imports the chosen mode definition + adds activation metadata. Doesn't exist when no mode is active (= normal). |
| `.claude/mode-stats.md` | active project | Cross-activation accumulator. Time in mode, activation count, mode-specific units. |

`CLAUDE.md` (the project's working contract) `@`-imports
`.claude/mode.md`. So when a mode is active, the drive prose
is in context on every session start — Claude reads it before
doing anything else.

When no mode is active, `.claude/mode.md` doesn't exist, the
`@`-import is a no-op, and Claude behaves as default Claude
Code. That's the **normal** state.

---

## Modes shipped

- **`task`** — clear the backlog. Pull work in batches, close
  the loop, drive the user to keep going. Counts tasks closed.
- **`cleanup`** — make the codebase nicer to live in. Improve
  in place, narrow scope, no new features. Counts time and
  activations (cleanup work resists per-unit scoring).
- **`project-manager`** — refine the backlog into a roadmap
  that's ready to ship. Walk phase by phase, stub by stub;
  push every stub through `/task` Op 3's full recon flow;
  surface phase-level shape questions; log to
  `docs/refinement/<date>.md`. Counts stubs refined.
- **`normal`** — the absence of a mode. Just Claude Code.

---

## Switching

```
/mode                   # report current mode + stats
/mode task              # activate task mode
/mode cleanup           # activate cleanup mode
/mode project-manager   # activate project-manager (refinement) mode
/mode normal            # end the active mode (back to default Claude)
```

Switching from one mode to another finalizes the previous mode
(writes deltas to `mode-stats.md`) before activating the new
one. `/mode normal` is the off-switch.

---

## Add a mode

1. Drop a new file at `kit/modes/<name>.md`. Use `task.md` or
   `cleanup.md` as a template.
2. Write it in **second person, present tense, drive-priming
   voice.** Not bullet rules — instructions to Claude's
   appetite.
3. Decide what (if anything) the mode counts as a unit, and
   how `/mode` finalizes it. Add detection logic to the
   `/mode` skill if the unit isn't a file count under
   `tasks/completed/`.
4. Add the mode to the **Modes shipped** table above.
5. PR upstream via `/contribute` so every project benefits.

---

## Voice rules for mode prose

The drive primes appetite. That means:

- **Second person, present tense.** "You're in task mode."
  Not "The user is in task mode."
- **Imperative, not declarative.** "Open with the count."
  Not "The count should be opened."
- **Name what feels wrong when off-mode.** The drive lives
  in the contrast — what makes Claude uneasy when the mode
  is being violated.
- **Short.** Aim for 30-50 lines. Long mode docs become
  wallpaper; Claude skims them.
- **Don't lecture about quality.** Mode is about *focus*,
  not *speed*. Quality is universal — the kit's
  `task-rules.md` owns that. Modes never override it.
- **Don't list every skill.** A few key ones, named in
  context. The full catalog lives in `/skills`.

---

## What a mode is NOT

- **A permission filter.** Modes don't gate skills or
  refuse edits. A mode says "here's what to want;" the
  user can always override.
- **A speed dial.** Quality stays slow inside any mode.
  Modes shorten the *gap between* tasks, not the work
  itself.
- **A persona.** Claude's voice and ethos don't change.
  Honesty, citing sources, asking when unsure — all
  universal. Modes shape *which questions Claude pre-empts*
  and *what default behavior feels right*, not how Claude
  speaks.
- **Sticky across repos.** Each project has its own
  `.claude/mode.md`. Switching projects doesn't carry
  mode state.
