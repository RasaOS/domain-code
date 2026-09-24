---
name: roadmap
description: Read-only phase-organized view of the whole task ledger, finished work included — one section per phase from tasks/ROADMAP.md, in ROADMAP order, with per-phase progress, the provenance columns (created, updated, filed by, finished by), and a mark on any task waiting on an unfinished needs: dependency. Covers all seven directories, and flags ledger anomalies. Use for "how is a phase going", "what have we finished", "show me the roadmap", "/roadmap", "/roadmap <phase>", "/roadmap full". Not for the flat unfinished-only view (use /backlog) and not for changing anything (use /task).
---

# /roadmap — the phase view, history included

One section per phase declared in `tasks/ROADMAP.md`, in the order
those headings appear, plus a triage section. Every one of the seven
directories is covered: `triage/`, `backlog/`, `active/`, `review/`,
`blocked/`, `completed/`, `closed/`.

This skill is **read-only**. It runs the validator, reads files, and
renders. It never writes a task file, never writes `tasks/ROADMAP.md`,
and never runs a `.claude/bin/task` verb. Creating or reshaping a phase
is `/task phase`; moving a task is a `/task` verb.

## Invocation

| form | behaviour |
|---|---|
| `/roadmap` | every phase; terminal rows collapsed to a count in any phase holding more than 20 terminal tasks |
| `/roadmap <phase-id>` | that phase only, every row expanded |
| `/roadmap full` | every phase, every row expanded |

The collapse rule is the only thing that keeps this view renderable on
a ledger with hundreds of finished tasks. It is a stated, deterministic
threshold, not a judgement call: count the tasks in that phase whose
directory is `completed/` or `closed/`; at 21 or more, replace those
rows with the single line described under **Output** and say so. Never
silently drop, sample, or summarize rows — a truncated table presented
as complete is worse than a count.

## Preflight — bail out loudly, never silently

1. **`tasks/` missing** → one line, stop: *"No `tasks/` directory here.
   This project has no task ledger."*
2. **`tasks/ROADMAP.md` missing** → one line, stop: *"No
   `tasks/ROADMAP.md`. This view is organized by phase and there are no
   phases declared. Use `/backlog` for a flat view, or `/task phase` to
   declare the first phase."*
3. **`ROADMAP.md` present but declaring zero phase headings** → say so
   in one line, then render the triage section and the unplaced section
   if either is non-empty.
4. **`/roadmap <phase-id>` naming a phase that is not declared** → list
   the declared phase ids and stop. Do not guess at a near match.

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

1. **Phase headings.** A phase heading is any line in
   `tasks/ROADMAP.md` matching

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

   Headings that do not match are ordinary prose headings — skip them.
   Section order is heading order in the file; **never re-sort phases.**

2. **A task's phase is the `phase:` value in its own frontmatter.**
   `ROADMAP.md` supplies the display name and the ordering, and nothing
   else. This is why a task cannot vanish from this view by losing its
   ROADMAP line: it still declares its own phase, and the missing line
   is a validator error the anomalies block has already reported.

3. **Ordering within a phase** is the order the task's line appears
   under that heading in `ROADMAP.md`. A task line is any line matching

   ```
   ^[-*][ \t]+(TASK-\S+)[ \t]+(?:—|–|-)[ \t]+.+$
   ```

   That order is the project's own suggested working order. **Never
   re-sort it.** A task in the phase with no ROADMAP line sorts last, by
   id, naturally (series, then number as a number, then letter suffix).

4. **A file is a task iff** it is a `*.md` file directly inside one of
   the seven directories. Anything at `tasks/*.md` and anything in any
   other subdirectory of `tasks/` is not a task. Do not maintain a
   hand-written skip list; the location rule is the whole rule. If you
   notice subdirectories of `tasks/` that are not among the seven,
   mention them once, at the end, as a one-line note.

5. **Targets.** Read `tasks/tasks.config.yml` if present. If its
   `targets:` list is non-empty, include the `Target` column in every
   phase table. If it is empty, absent, or there is no config file,
   omit the column entirely.

## Per-row values

| column | source |
|---|---|
| **ID** | the `id:` frontmatter value |
| **Title** | the H1 body line `# <id>: <title>`, everything after `<id>: ` |
| **State** | the directory the file is in — nothing else |
| **Type** | the `type:` frontmatter value |
| **Target** | the `target:` list, comma-joined (conditional column) |
| **Created** | the `created:` frontmatter value |
| **Filed by** | the `created_by:` frontmatter value |
| **Updated** | the `updated:` frontmatter value |
| **Finished by** | `completed_by:` in `completed/` and `closed/`; `—` everywhere else |
| **Outcome** | `resolution:` in `closed/` only, with `resolution_ref` appended when present; `—` everywhere else |

Glyphs — the exact set, identical to `/backlog` for the five states
they share:

- State: `🗂 Triage` · `📋 Backlog` · `🚧 Active` · `👁 Review` ·
  `🚫 Blocked` · `✅ Completed` · `🗄 Closed`
- Type: `🔄 Change` · `🐞 Defect` · `🧹 Upkeep` · `🔍 Inquiry` ·
  `📄 Record`
- Depth: prefix the **Title** cell with `📝 ` when the task is
  stub-depth
- Dependency: prefix the **Title** cell with `⛓ ` when the task is
  waiting on a dependency. Both prefixes can apply; order them
  `⛓ 📝 `, always the same way, so the column stays scannable.

**Depth is derived, never stored.** A task is stub-depth iff it has no
`## Acceptance criteria` heading, or that heading holds no `- [ ]` /
`- [x]` item with non-empty text after the checkbox.

**Waiting is derived too, and it is not a state.** A task is *waiting
on a dependency* iff its `needs:` list holds at least one id whose task
is in neither `completed/` nor `closed/`. Read the other task's
directory to decide; `needs:` itself never records whether it is met.

Four things this rule is deliberately strict about:

- **The terminal pair, not just `completed/`.** A need that reached
  `closed/` counts as met here, because that is exactly the rule the
  validator's I-28 uses. The two must agree — a view that called a task
  waiting while the anomalies block stayed silent would be the same
  disagreement the lockstep note above exists to prevent.
- **`⛓` is not `🚫 Blocked`.** `blocked/` is a directory a verb put the
  task in. `⛓` is a fact computed from frontmatter, and it can sit on a
  row in any of the seven states. Never render one as the other.
- **A need naming a task that is not in the ledger counts as
  waiting.** It is a validator error (I-26) that the anomalies block
  has already reported verbatim, and an id nobody can resolve is not an
  id that finished. Marking the row `⛓` and leaving the diagnosis to
  `/task check` is the honest reading; quietly treating it as met is
  not.
- **`⛓` on a `✅ Completed` row is the interesting one.** That is
  exactly the condition I-28 warns about — finished while something it
  declared it needed has not — so the warning and the mark appear
  together, one in the anomalies block and one in the table. Do not
  suppress either because the other is present.

**If a value is missing or unrecognized, render it as `⚠️` — never
substitute a default.** A blank where a required value belongs is a
validator error that has already fired.

## Cell escaping — mandatory

Before a value goes into a table cell:

1. Replace every `|` with `\|`. A title containing a pipe otherwise
   splits the row and corrupts every column after it.
2. Collapse any run of whitespace to a single space, and trim.
3. Truncate to 50 characters, appending `…` when truncated. Truncate
   **after** escaping, so an escape is never cut in half.

## Phase progress line

Under each phase heading, one line:

```
<glyph> <verdict> — 🚧 N · 👁 N · 🚫 N · 📋 N · ✅ N · 🗄 N  (T tasks)
```

The verdict, decided in this order — first match wins:

1. `✅ complete` — every task in the phase is in `completed/` or
   `closed/`, and there is at least one task.
2. `🚧 in flight` — at least one task is in `active/`, `review/` or
   `blocked/`.
3. `📋 partly done` — at least one in `completed/`/`closed/` and at
   least one in `backlog/`, with nothing in flight.
4. `📋 not started` — every task is in `backlog/`.
5. `— empty` — the phase has no tasks. Render the heading and this
   line, then no table.

Omit the zero counters from the line; keep the order above for those
you show.

## Sections

In this order:

1. **One section per declared phase**, in `ROADMAP.md` heading order.
2. **`## 🗂 Triage — unphased by design`** — every task in
   `tasks/triage/`, by id. These carry no `phase:`, are deliberately
   absent from `ROADMAP.md`, and are shown here so triage cannot rot
   invisibly. Omit the section when `triage/` is empty. The `Created`
   and `Filed by` columns still apply; `Finished by` and `Outcome` are
   `—`.
3. **`## ⚠️ Unplaced`** — tasks outside `triage/` whose `phase:` names
   no declared phase, or which carry no `phase:` at all. **This section
   exists only when it is non-empty, and every row in it is a validator
   error.** The only legitimately unphased stages are `triage/` (not yet
   graduated) and `closed/` (a task declined straight out of triage), so
   this is not a bucket for orthogonal work — it is a defect report. Say
   so in one line above the table and point at `/task check`.

## Output

Nothing but this. No preamble, no closing commentary.

```markdown
# 📋 Roadmap — every phase, history included

**T tasks** · ✅ N completed · 🗄 N closed · 🚧 N active · 👁 N review · 🚫 N blocked · 📋 N backlog · 🗂 N triage
📝 N stub-depth · ⛓ N waiting on a dependency

---

## Phase 2 — Intake

🚧 in flight — 🚧 1 · 👁 1 · 📋 1 · ✅ 4  (7 tasks)

| ID | Title | State | Type | Created | Filed by | Updated | Finished by | Outcome |
|---|---|---|---|---|---|---|---|---|
| TASK-042 | Amend the retention schedule | 🚧 Active | 🔄 Change | 2026-09-02 | jmr | 2026-09-19 | — | — |
| TASK-051 | 📝 Second-reader pass on the summary | 👁 Review | 📄 Record | 2026-09-04 | para1 | 2026-09-18 | — | — |
| TASK-044 | Standing instruction for the file room | ✅ Completed | 🧹 Upkeep | 2026-08-28 | jmr | 2026-09-10 | jmr | — |
| TASK-047 | Duplicate of the retention amendment | 🗄 Closed | 🔄 Change | 2026-09-03 | para1 | 2026-09-05 | jmr | duplicate → TASK-042 |

## Phase 3 — Filing

📋 partly done — 📋 2 · ✅ 24  (26 tasks)

| ID | Title | State | Type | Created | Filed by | Updated | Finished by | Outcome |
|---|---|---|---|---|---|---|---|---|
| TASK-060 | ⛓ Draft the standing instruction | 📋 Backlog | 🔄 Change | 2026-09-20 | jmr | 2026-09-20 | — | — |
| TASK-062 | 📝 Index the historical folders | 📋 Backlog | 🧹 Upkeep | 2026-09-20 | jmr | 2026-09-20 | — | — |

✅ 24 terminal tasks collapsed (24 completed · 0 closed · ⛓ 1 waiting). `/roadmap 3` to expand.

## 🗂 Triage — unphased by design

| ID | Title | State | Type | Created | Filed by | Updated |
|---|---|---|---|---|---|---|
| TASK-061 | 📝 Someone should look at the index | 🗂 Triage | 🔍 Inquiry | 2026-09-20 | para1 | 2026-09-20 |
```

The header counters **must sum to the total**, and the total must equal
the number of tasks found on disk — including rows collapsed by the
threshold and rows in the unplaced section. `📝 stub-depth` and
`⛓ waiting` sit on the second line because they cross-cut the seven and
would break the sum. Omit the `⛓` counter when it is zero.
Every task appears in exactly one section: its phase, triage, or
unplaced.

**A collapsed row keeps its `⛓`.** Append `· ⛓ N waiting` to the
collapse line whenever any collapsed row is waiting, and omit that
clause when none is. Collapsing is a rendering economy for finished
work; it is not permission to hide the one condition — a task finished
while something it needed did not — that I-28 exists to catch.

## Style

- One table per section. Phases are the grouping; do not invent
  sub-groups inside a phase.
- Use the glyph sets above exactly. `/backlog` shares them so the same
  state never renders two ways across two views.
- Show a phase's heading and progress line even when it has no tasks —
  an empty declared phase is information.
- The data is the answer. No interpretation, no advice.
- There is no "delivered in" column. Which version shipped a task is
  owned by a different module and lives outside `tasks/`; guessing at
  it from a file this module does not write is how the old view
  reported `(unversioned)` forever.

## When NOT to use this skill

- The flat, unfinished-only working view → `/backlog`.
- Filing, moving, closing, repairing, or declaring a phase → `/task`.
- A phase's scope paragraph and reasoning → read `tasks/ROADMAP.md`
  directly; this view deliberately renders none of that prose.
- One task's full content → read the file.
- *Which* tasks a row is waiting on → read that task file's `needs:`
  line, or hand off to `/task`. This view marks **that** a row is
  waiting, never on what: a list of ids does not survive a truncated
  cell, and this skill runs no `.claude/bin/task` verb, not even a
  read-only one.
- Declaring or removing a dependency → `/task`. This view never writes.
