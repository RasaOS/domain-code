---
name: roadmap
description: Display a phase-organized table of every task across `tasks/{backlog,active,blocked,completed}/` — including completed tasks. Triggered when the user wants a per-phase progress view — e.g. "show me the roadmap", "/roadmap", "how is Phase N going", "everything we've built and queued".
---

# /roadmap — Task list by phase (full history)

When invoked, produce a markdown summary grouped by **Phase**.
Each phase gets its own table containing every task in that
phase regardless of state (done / active / backlog). The output
should be the only thing in the response (no preamble, no
closing commentary). It needs to render cleanly in Claude
Code's UI and let the reviewer see "how is Phase N going" at a
glance.

## What to do

1. **Parse `tasks/ROADMAP.md`** to build a `task ID → phase`
   mapping. The ROADMAP has `## Phase N — <name>` sections
   followed by bulleted lists of `TASK-NNN — <title>`. Extract
   each phase's task IDs (preserving letter suffixes like
   `018a`).

2. **Read every task file** in `tasks/active/`,
   `tasks/backlog/`, `tasks/completed/`. For each:
   - **ID** — from the filename (`TASK-014` from
     `TASK-014-vehicle-crud.md`). Preserve letter suffixes.
   - **Title** — first H1, with the `TASK-XXX:` prefix stripped.
   - **State** — derived from directory:
     - `🚧 Active` — `tasks/active/`
     - `📋 Backlog` — `tasks/backlog/`
     - `✅ Done` — `tasks/completed/`
   - **Type** — only meaningful for non-Done states:
     - `📝 Stub` if the file contains `STATUS: STUB`
     - `📄 Spec` otherwise
   - **Shipped in** — for Done items only, look up the version in
     `tasks/RELEASES.md`: a ✅ Shipped release names the phases and
     tasks it landed, so a Done task's version is the shipped release
     naming its phase (or naming the task directly). If no shipped
     release names it, mark `(pre-versioning)`.

3. **Skip non-task files:** `.gitkeep`, `README.md`,
   `ROADMAP.md`, anything not matching `TASK-` prefix.

4. **Output the document** with this exact structure:

```markdown
# 📋 Task overview by Phase

<one-line summary>: total tasks · ✅ N completed · 🚧 N active · 🚫 N blocked · 📋 N backlog (M specs / K stubs)

---

## Phase 1 — <name from ROADMAP>

<one-line phase status>: ✅ shipped / 🚧 in flight / 📋 not started

| ID | Title | State | Type | Shipped in |
|---|---|---|---|---|
| TASK-XXX | … | ✅ Done | — | v1.0.0 |
| TASK-YYY | … | 🚧 Active | 📄 Spec | — |
| TASK-ZZZ | … | 📋 Backlog | 📝 Stub | — |

## Phase 2 — <name>
...

## Phase N — <name>
...

## Cross-cutting / unphased

(Tasks that aren't in any Phase section of the ROADMAP — e.g.
TASK-000 emulators; bug-fix follow-ups like TASK-033.)

| ID | Title | State | Type | Notes |
|---|---|---|---|---|
| TASK-XXX | … | … | … | … |
```

5. **Sort within each phase** by task ID ascending, with
   letter suffixes following their parent (014, 015, …, 018,
   018a, 018b, …).

6. **Phase status line** rules:
   - `✅ shipped` if every task in the phase is Done
   - `🚧 in flight` if any task is Active or any has Done items
     mixed with Backlog
   - `📋 not started` if every task is Backlog

## Style rules

- The `Type` column is empty (`—`) for Done rows.
- The `Shipped in` column is empty (`—`) for non-Done rows.
- Use the exact emoji set: 🚧 📋 ✅ 📝 📄. Don't substitute.
- Keep titles ≤ 60 chars; tables stay readable.
- No commentary outside the tables and headers — the data is
  the answer.
- If a phase has zero tasks (rare — empty phase in ROADMAP),
  skip its table but mention it in the summary line.

## When NOT to use this skill

- The user wants to *modify* a task — that's an edit, not a view.
- The user wants the roadmap *prose* (phase rationale, tradeoffs)
  — point them at `tasks/ROADMAP.md` directly.
- A specific task's content — read the file with `Read`.
