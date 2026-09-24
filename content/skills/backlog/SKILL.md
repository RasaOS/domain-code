---
name: backlog
description: Read-only forward view of the task ledger — everything not yet finished, as one flat table. Renders tasks/{active,review,blocked,backlog,triage}/ with state, type, phase, priority and target, marks tasks waiting on an unfinished needs: dependency, and flags ledger anomalies. Excludes terminal work. Use for "what am I doing now and what is next" — "/backlog", "show me the backlog", "what is queued", "what is in flight", "what is blocked", "what is waiting on a gate", "what is waiting on another task". Not for per-phase or historical views (use /roadmap) and not for changing anything (use /task).
---

# /backlog — the forward view

One flat table of every task that has **not** reached a terminal
directory: `tasks/active/`, `tasks/review/`, `tasks/blocked/`,
`tasks/backlog/`, `tasks/triage/`. `tasks/completed/` and
`tasks/closed/` are deliberately excluded — `/roadmap` is the view that
includes them.

This skill is **read-only**. It runs the validator, reads files, and
renders. It never writes a task file, never writes `tasks/ROADMAP.md`,
and never runs a `.claude/bin/task` verb. If the user wants something
changed, hand off to `/task`.

## Preflight — bail out loudly, never silently

Do these in order, before reading any task file.

1. **`tasks/` missing** → output exactly one line and stop:
   *"No `tasks/` directory here. This project has no task ledger."*
2. **All five forward directories missing or empty** → output one line
   and stop: *"Nothing in flight, queued, or in triage. See `/roadmap`
   for finished work."*
3. **`tasks/ROADMAP.md` missing** → do not stop. Render the table with
   the `Phase` column showing the raw `phase:` value, and add this to
   the anomalies line: *"`tasks/ROADMAP.md` is missing — phase names and
   ordering are unavailable."*

## The anomalies block (keep in lockstep with the sibling view)

> This block is verbatim-identical in `/backlog` and `/roadmap`, apart
> from nothing at all — the two views must never disagree about whether
> the ledger is sound. A view that renders a corrupt ledger as if it
> were clean is how drift goes unnoticed for months. Change both files
> or neither.

Before rendering, run the validator from the project root:

```
.claude/bin/check-tasks
```

Interpret its exit code:

| exit | meaning | what to emit |
|---|---|---|
| `0`, no `WARN` lines | the ledger is sound | nothing |
| `0`, with `WARN` lines | warnings only | `⚠️ **N warnings** — run /task check for the list.` |
| `1` | errors found | the full anomalies line, below |
| `2` | the validator could not run | `⚠️ **Unverified** — check-tasks could not run: <its message>. The view below may be wrong.` |
| absent / not executable | no validator installed | `⚠️ **Unverified** — no .claude/bin/check-tasks in this project, so nothing has checked this ledger. The view below may be wrong.` |

The full anomalies line, emitted directly under the header, above
everything else:

```markdown
⚠️ **ANOMALIES — N errors · M warnings.** This view may be wrong.
- <first validator error message, verbatim>
- <second>
- <third>
- …and K more. Run `/task check` for the full list and a repair offer.
```

Rules for it:

- Quote the validator's own messages **verbatim**. Do not paraphrase,
  re-rank, or decide which errors matter.
- Show at most three, then the `…and K more` line.
- Never suppress the line because the view "looks fine". The view
  looking fine is the failure mode this line exists to catch.
- Never repair anything. Repair is `/task check` → `/task repair`.

## Reading the ledger

1. **Phase names and order** come from `tasks/ROADMAP.md`. A phase
   heading is any line matching

   ```
   ^##[ \t]+Phase[ \t]+(\S+?):?(?:[ \t]+(.*))?$
   ```

   The **phase id** is capture 1 with one trailing `:` stripped. The
   **phase name** is capture 2 with any leading `—`, `–`, `-`, `:` and
   whitespace stripped. This is the same grammar the validator enforces
   and the same grammar the seeded `tasks/ROADMAP.md` ships, so it
   accepts both forms that occur in practice:

   - `## Phase 1: Foundations` → id `1`, name `Foundations`
   - `## Phase P0.5 — Preparatory cleanup` → id `P0.5`, name
     `Preparatory cleanup`

   Headings that do not match are ordinary prose headings — skip them,
   do not guess.

2. **A task's phase is the `phase:` value in its own frontmatter**, not
   something inferred from `ROADMAP.md`. `ROADMAP.md` supplies only the
   display name and the ordering. The validator proves the two agree; if
   they do not, the anomalies line has already said so.

3. **Ordering within a phase** is the order the task's line appears
   under that phase heading in `ROADMAP.md`. A task line is any line
   matching

   ```
   ^[-*][ \t]+(TASK-\S+)[ \t]+(?:—|–|-)[ \t]+.+$
   ```

   That order is the project's own suggested working order. **Never
   re-sort it.** A task with no line (only legal in `tasks/triage/`)
   sorts last within its group, by id.

4. **A file is a task iff** it is a `*.md` file directly inside one of
   the five forward directories. Anything at `tasks/*.md`
   (`ROADMAP.md`, `intake.md`, `README.md`, …) and anything in any other
   subdirectory is not a task. Do not maintain a hand-written skip list;
   the location rule is the whole rule.

5. **Targets.** Read `tasks/tasks.config.yml` if present. If its
   `targets:` list is non-empty, include the `Target` column. If it is
   empty, absent, or there is no config file, **omit the column
   entirely** — a project that has not declared a target axis does not
   get an empty column.

## Per-row values

| column | source |
|---|---|
| **ID** | the `id:` frontmatter value |
| **Title** | the H1 body line `# <id>: <title>`, everything after `<id>: ` |
| **State** | the directory the file is in — nothing else |
| **Type** | the `type:` frontmatter value |
| **Phase** | `phase:` rendered as `<id> · <name from ROADMAP>`; in `triage/` it is `—` (triage tasks carry no phase, by design) |
| **Target** | the `target:` list, comma-joined |
| **Pri** | the `priority:` value; absent means `normal` |
| **Updated** | the `updated:` frontmatter value |

Glyphs — the exact set, identical to `/roadmap`:

- State: `🗂 Triage` · `📋 Backlog` · `🚧 Active` · `👁 Review` ·
  `🚫 Blocked`
- Type: `🔄 Change` · `🐞 Defect` · `🧹 Upkeep` · `🔍 Inquiry` ·
  `📄 Record`
- Priority: `‼️ now` · `↑ high` · `·` (normal) · `↓ low`
- Depth: prefix the **Title** cell with `📝 ` when the task is
  stub-depth
- Dependency: prefix the **Title** cell with `⛓ ` when the task is
  waiting on a dependency. Both prefixes can apply; order them
  `⛓ 📝 `, always the same way, so the column stays scannable.

**Depth is derived, never stored.** A task is stub-depth iff it has no
`## Acceptance criteria` heading, or that heading holds no `- [ ]` /
`- [x]` item with non-empty text after the checkbox. That is the one
signal telling a reader which rows still need fleshing out.

**Waiting is derived too, and it is not a state.** A task is *waiting
on a dependency* iff its `needs:` list holds at least one id whose task
is in neither `completed/` nor `closed/`. Read the other task's
directory to decide; `needs:` itself never records whether it is met.

Three things this rule is deliberately strict about:

- **The terminal pair, not just `completed/`.** A need that reached
  `closed/` counts as met here, because that is exactly the rule the
  validator's I-28 uses. The two must agree — a view that called a task
  waiting while the anomalies block stayed silent would be the same
  disagreement the lockstep note above exists to prevent.
- **`⛓` is not `🚫 Blocked`.** `blocked/` is a directory a verb put the
  task in. `⛓` is a fact computed from frontmatter, and it can sit on a
  row in any of the five states, including `🚧 Active`. Never render
  one as the other, and never move a task because of a `⛓`.
- **A need naming a task that is not in the ledger counts as
  waiting.** It is a validator error (I-26) that the anomalies block
  has already reported verbatim, and an id nobody can resolve is not an
  id that finished. Marking the row `⛓` and leaving the diagnosis to
  `/task check` is the honest reading; quietly treating it as met is
  not.

**If a value is missing or unrecognized, render it as `⚠️` — never
substitute a default.** A task with no `type:`, or a `type:` outside the
five, is a validator error that has already fired; silently showing it
as a `Change` is how the anomaly gets buried.

## Cell escaping — mandatory

Before a value goes into a table cell:

1. Replace every `|` with `\|`. A title containing a pipe otherwise
   splits the row and corrupts every column after it.
2. Collapse any run of whitespace to a single space, and trim.
3. Truncate to 60 characters, appending `…` when truncated. Truncate
   **after** escaping, so an escape is never cut in half.

## Sorting

Groups, in this order — this is also the order of the counters:

1. `🚧 Active`
2. `👁 Review`
3. `🚫 Blocked`
4. `📋 Backlog`
5. `🗂 Triage`

Within each group: `priority: now` rows first, then `ROADMAP.md` order
(phases in the order their headings appear, tasks in the order their
lines appear under each heading), then any task with no ROADMAP line by
id. Sort ids naturally: series first, then the number as a number, then
the letter suffix — `TASK-9` before `TASK-10`, `TASK-018` before
`TASK-018a` before `TASK-018b`.

## Output

Nothing but this. No preamble, no closing commentary.

```markdown
# 📋 Backlog — in flight, queued, and untriaged

🚧 **Active** N · 👁 **Review** N · 🚫 **Blocked** N · 📋 **Backlog** N · 🗂 **Triage** N — **T total**
📝 N stub-depth · ‼️ N at `now` · ⛓ N waiting on a dependency

| ID | Title | State | Type | Phase | Pri | Updated |
|---|---|---|---|---|---|---|
| TASK-042 | Amend the retention schedule | 🚧 Active | 🔄 Change | 2 · Intake | ‼️ now | 2026-09-19 |
| TASK-051 | 📝 Second-reader pass on the summary | 👁 Review | 📄 Record | 2 · Intake | · | 2026-09-18 |
| TASK-038 | Awaiting the counterparty reply | 🚫 Blocked | 🔄 Change | 3 · Filing | ↑ high | 2026-09-11 |
| TASK-060 | ⛓ Draft the standing instruction | 📋 Backlog | 🔄 Change | 3 · Filing | · | 2026-09-20 |
| TASK-061 | 📝 Someone should look at the index | 🗂 Triage | 🔍 Inquiry | — | · | 2026-09-20 |
```

The five state counters **must sum to the total**, and the total must
equal the number of rows. Every task lands in exactly one group, so if
they do not sum you have dropped or duplicated a row — fix that before
emitting. `📝 stub-depth`, `‼️ now` and `⛓ waiting` sit on the second
line precisely because they cross-cut the five and would otherwise
break the sum. Omit the `⛓` counter when it is zero; the other two are
always shown.

Add the `Target` column between `Phase` and `Pri` when, and only when,
`tasks.config.yml#targets` is non-empty.

## Style

- One table. Do not subdivide by phase or state — the columns carry
  that. `/roadmap` is the grouped view.
- Use the glyph sets above exactly. They are shared with `/roadmap` so
  the same state never renders two ways across two views.
- The data is the answer. No interpretation, no advice, no "you might
  want to…". If the user wants a judgement, they will ask.

## When NOT to use this skill

- Finished work, per-phase progress, or history → `/roadmap`.
- Filing, moving, closing, or repairing anything → `/task`.
- The reasoning behind a phase (its scope paragraph) → read
  `tasks/ROADMAP.md` directly.
- One task's full content → read the file.
- *Which* tasks a row is waiting on → read that task file's `needs:`
  line, or hand off to `/task`. This view marks **that** a row is
  waiting, never on what: a list of ids does not survive a truncated
  cell, and this skill runs no `.claude/bin/task` verb, not even a
  read-only one.
- Declaring or removing a dependency → `/task`. This view never writes.
