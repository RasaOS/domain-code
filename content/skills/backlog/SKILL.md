---
name: backlog
description: Show what's actively being worked on, what's queued up next, and what's parked in triage. Forward-looking only — completed work is not included. Triggered when the user wants to know "what are we doing now and what's next" — e.g. "show me the backlog", "/backlog", "what's queued", "what's next".
---

# /backlog — Active + queued + triage tasks

When invoked, produce a single markdown table of every task that
is **not yet done** — i.e. everything in `tasks/active/`,
`tasks/backlog/`, and `tasks/triage/`. Completed tasks are
deliberately excluded. The user wants to see what's in flight,
what's coming up, and what's parked — not what's already shipped.

The output is the only thing in the response (no preamble, no
closing commentary). Render in under 5 seconds.

## What to do

1. **Read** every task file in `tasks/active/`, `tasks/backlog/`,
   and `tasks/triage/`. Skip `tasks/completed/` entirely. Skip
   `.gitkeep`, `README.md`, `ROADMAP.md`, anything not matching
   `TASK-` prefix.

2. **Parse `tasks/ROADMAP.md`** to map task IDs → phase names
   (`## Phase N — <name>` sections, then bulleted task IDs).
   Tasks not in any phase get phase = `Cross-cutting` — except
   triage tasks, which are unphased by design (phase = `—`).

3. **For each task, extract:**
   - **ID** — from the filename, with letter suffix preserved
     (e.g. `TASK-018a`).
   - **Title** — the first H1, with the `TASK-XXX:` prefix
     stripped.
   - **State** — by directory:
     - `🚧 Active` — `tasks/active/`
     - `📋 Backlog` — `tasks/backlog/`
     - `🗂 Triage` — `tasks/triage/` (tracked, not yet triaged
       into a phase)
   - **Type**:
     - `📄 Spec` — full spec; ready to implement.
     - `📝 Stub` — still needs detail before starting.
       Detected by the literal string `STATUS: STUB` anywhere
       in the file.
   - **Phase** — from step 2. Triage tasks show `—`.

4. **Sort the rows** by readiness, so the things shipping
   soonest are at the top:

   1. All `🚧 Active` rows first, by ID ascending.
   2. Then `📋 Backlog · 📄 Spec` rows, by ID ascending.
   3. Then `📋 Backlog · 📝 Stub` rows, by ID ascending.
   4. Then `🗂 Triage` rows last, by ID ascending — tracked,
      but not yet planned.

   Within each group, `TASK-018a` comes after `TASK-018` and
   before `TASK-018b`.

5. **Output** with this exact structure:

```markdown
# 📋 Backlog — what's now, next & parked

**Active**: N · **Specs ready**: N · **Stubs to flesh out**: N · **In triage**: N

| ID | Title | State | Type | Phase |
|---|---|---|---|---|
| TASK-XXX | … | 🚧 Active | 📄 Spec | Phase 3 |
| TASK-YYY | … | 📋 Backlog | 📄 Spec | Phase 1 |
| TASK-ZZZ | … | 📋 Backlog | 📝 Stub | Phase 4 |
| TASK-WWW | … | 🗂 Triage | 📝 Stub | — |
```

## Style rules

- One single table — don't subdivide by phase or state. Phase and
  state show as columns for context, not as groupings. (User has
  `/roadmap` for the phase-organized view.)
- Use the exact emoji set: 🚧 📋 🗂 📄 📝. Don't substitute.
- Trim titles to ≤ 60 chars.
- No commentary outside the header line and table — the data
  is the answer.
- If `active/`, `backlog/`, and `triage/` are all empty, output a
  single line: *"No active, queued, or triage tasks. See
  `/roadmap` for the full history."*

## When NOT to use this skill

- The user wants to see completed work or per-phase progress —
  point them at `/roadmap` instead.
- The user wants the roadmap *prose* (rationale, tradeoffs) —
  point them at `tasks/ROADMAP.md`.
- A specific task's content — read the file with `Read`.
