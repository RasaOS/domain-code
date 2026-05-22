---
name: retro
description: Agile-style retrospective over a date window — 1 week, 2 weeks, 3 weeks, 1 month, or custom. Synthesizes across `docs/notes/` (lessons), `tasks/completed/`, `tasks/AUDIT.md`, `docs/decisions/`, `docs/postmortems/`, `docs/regrets/`, and the git log to find what went well, what didn't, recurring themes, and action candidates. Distinct from `/lessons` (per-task introspection) and `/postmortem` (single-incident) — `/retro` is the longitudinal cross-source view that surfaces patterns no single artifact catches. Output saved to `docs/retros/<YYYY-MM-DD>-<window>.md`. Schedule it weekly with `/loop 1w /retro 1w` for a recurring rhythm. Triggered when the user wants the look-back — e.g. "/retro", "weekly retro", "retro 2w", "retrospective for this month", "look back at the last few weeks".
---

# /retro — Look back, find patterns, decide what to try

A retrospective answers three questions over a window:

1. **What went well.** What patterns earned their keep?
2. **What didn't go well.** Where did we lose time, ship bugs,
   or get stuck — and is the pain repeating?
3. **What we want to try.** Concrete experiments for the next
   window.

Distinct from `/lessons` (per-task) and `/postmortem` (per-incident).
`/retro` is *longitudinal*: it reads everything captured during a
window and finds the systemic stuff that no single artifact catches.

Per CLAUDE.md ethos: a retro that reads "things were generally
good" wastes the time of whoever runs the next one. Specific or
nothing.

## Behavior contract

- **Writes durable docs only.** Output at
  `docs/retros/<YYYY-MM-DD>-<window>.md`. No source-code edits,
  no commits.
- **Date window is required.** Default to **2 weeks** if not
  given (typical sprint-ish cadence). User can override with
  `1w`, `2w`, `3w`, `1m`, or `<N>d`.
- **Read multiple sources, synthesize across them.** A retro
  that only reads `docs/notes/` is half a retro. The pattern
  detection happens at the intersection of notes, tasks done,
  decisions, postmortems, regrets, and commits.
- **Cluster recurring items.** If "schema sync drift" shows up
  in three notes and one postmortem in the window, that's a
  theme — surface it once with a frequency count, not five
  times verbatim.
- **Action candidates, not commitments.** The retro proposes
  experiments for the next window; the user routes the
  promising ones to `/task` or `/codify`. The retro itself
  never files tasks.
- **Honest about the size of the window.** If the user asks
  for a 1-month retro on a 3-day-old project, say so and
  shorten to actual coverage.
- **Pairs with `/loop`.** Recurring retros are the use case;
  the user can schedule with `/loop 1w /retro 1w` or
  `/loop 2w /retro 2w`. Document this in the closing summary.
- **Never auto-commit.** Standard kit rule.

## Process

### Step 1 — Resolve the window

Parse the user's input:

- `/retro` → default 2 weeks.
- `/retro 1w` / `/retro 7d` → last 7 days.
- `/retro 1m` / `/retro 30d` → last 30 days.
- `/retro <N>d` → custom day count.

Compute:
- **Start date** — `today - <window>`.
- **End date** — today.
- **Window slug** — `1w` / `2w` / `1m` / `<N>d` for the
  filename.

### Step 2 — Gather inputs in the window

In parallel, collect:

1. **Notes** — `docs/notes/<date>-*.md` files where
   `<date>` ≥ start. Read each.
2. **Tasks done** — `tasks/completed/*.md` modified in the window.
   Read each (just title + outcome line).
3. **AUDIT.md entries** — recent shipped items at the top of
   `tasks/AUDIT.md` whose date falls in the window.
4. **Decisions** — `docs/decisions/<date>-*.md` in the window.
5. **Postmortems** — `docs/postmortems/<date>-*.md` in the
   window.
6. **Regrets** — `docs/regrets/<date>-*.md` in the window.
7. **Audits** — `docs/audits/<date>-*.md` in the window
   *(if present from `/audit` skill)*.
8. **Git log** — `git log --since=<start> --until=<end>
   --oneline` for shipped commit signal.

Note any source that's empty — surface honestly in the report.

### Step 3 — Spawn the synthesis sub-agent

```
Agent({
  description: "Retro synthesis across <window>",
  subagent_type: "general-purpose",
  prompt: "<see synthesis prompt below>"
})
```

**Synthesis prompt** (literal — substitute window + inputs):

> You are running an agile retrospective over the last
> **<window>** (from <start> to <end>) for the project
> **<repo name>**.
>
> The inputs available — read each and pull material:
>
> - **Notes**: <list of notes filenames>
> - **Tasks done**: <count + titles>
> - **AUDIT.md** entries in window: <count>
> - **Decisions**: <list of filenames>
> - **Postmortems**: <list>
> - **Regrets**: <list>
> - **Audits**: <list>
> - **Commits**: <count>
>
> Produce a structured retrospective with these sections.
> Each section's items must be **specific and cite a source
> file or commit**:
>
> 1. **🌟 What went well** — patterns or wins that earned
>    their keep. Cite the note/task/commit.
> 2. **🪨 What didn't go well** — pain points, time sinks,
>    bugs that surprised us. Cite source.
> 3. **🔁 Recurring themes** — items that appeared in **2+
>    sources** during the window. List with frequency count.
>    These are the systemic signals.
> 4. **🌱 Things to try next window** — concrete experiments
>    to address what didn't go well. Each one as a single
>    actionable line.
> 5. **🎯 Action candidates** — items that should be filed
>    as tasks, codified as rules, or routed to other skills.
>    Tag each with the suggested route (`/task`, `/codify`,
>    `/decision`, `/regret`, `/postmortem`).
>
> Output as structured markdown using the headers above.
> Skip sections with no real material — don't stub.
>
> Hard rules:
> - Don't conflate sources. A theme that's only in one
>   `docs/notes/` file is not a theme — it's an instance.
>   Themes require ≥2 sources.
> - Don't editorialize. "We didn't ship the thing" is fine;
>   "the team struggled with motivation" is not.
> - No marketing voice. Specific or nothing.
> - If a category has nothing real, omit it.

### Step 4 — Show the draft + ask for edits

Render in chat:

```markdown
# 🔁 Retro draft — <window> *(<start> → <end>)*

**Inputs.**
- <count> notes, <count> tasks done, <count> decisions,
  <count> postmortems, <count> regrets, <count> commits

*(Skip categories below that came back empty.)*

## 🌟 What went well
- ...

## 🪨 What didn't go well
- ...

## 🔁 Recurring themes
- **<theme>** — appeared in <N> sources: <list with cites>

## 🌱 Things to try next window
- ...

## 🎯 Action candidates
- **<action>** → suggest `/<skill>`

---

**To proceed:** "write it" / "edit item N: ..." / "drop item N"
/ "regenerate" / "cancel"
```

Loop edits until the user says "write it".

### Step 5 — Write the retro doc

Write to `docs/retros/<YYYY-MM-DD>-<window>.md`. The header
adds a frontmatter block:

```markdown
# 🔁 Retro — <window> ending <YYYY-MM-DD>

> **Window.** <start> → <end>
> **Slug.** `<window>`
> **Inputs.** <counts as above>
> **Bottom line.** <one sentence — the most worth-knowing
> read. e.g. "Schema sync is the recurring drag — three
> postmortems point at it; worth promoting a /codify rule.">

---

## 🌟 What went well
- ...

## 🪨 What didn't go well
- ...

## 🔁 Recurring themes
- ...

## 🌱 Things to try next window
- ...

## 🎯 Action candidates

Routing the highest-leverage candidates to other skills:

- **<action>** → `/task` to file as backlog item
- **<action>** → `/codify` to land as a CLAUDE.md rule
- **<action>** → `/decision` for the architectural choice
  worth recording

---

## Comparison with previous retro *(if one exists)*

If `docs/retros/` has prior retros, briefly compare:

- Carryover themes: <list>
- Resolved since last retro: <list>
- New themes this window: <list>

*(Skip section if this is the first retro.)*

---

*Generated by `/retro` on <YYYY-MM-DD>. To run on a regular
cadence, schedule with `/loop <window> /retro <window>`.*
```

### Step 6 — Closing summary

```markdown
# 🔁 Retro captured

`docs/retros/<YYYY-MM-DD>-<window>.md` — <count> items across
<sections> sections.

**Bottom line.** <one sentence.>

**The single highest-leverage move:** <one — typically the
top recurring theme's action candidate>

*(If there are pending action candidates worth routing now:)*

**Want me to route any of these now?**
- "<action>" → `/<skill>`
- ...

*(If no prior retros:)*

**Schedule it.** Run `/loop 2w /retro 2w` to make this a
recurring rhythm. The first one is always the longest; the
recurring ones lean on prior retros for comparison.
```

## Style rules

- **Cite the source for every item.** A retro item without
  a cite is editorializing.
- **Frequency counts make themes legible.** "Appeared in 4
  sources" beats "this came up a lot".
- **Action candidates are imperatives, one line each.**
  "Add a CI check that fails the build when the schema
  drifts from the codegen output" — not "address schema
  drift".
- **Emoji are load-bearing.** 🔁 (retro), 🌟 (went well),
  🪨 (didn't go well), 🌱 (try next), 🎯 (actions). Don't
  add others.
- **Comparison with previous retro is one paragraph, max.**
  Don't re-litigate the prior retro inside this one.
- **Window-ending date is in the title.** `2026-04-29` and
  `2w` together tell the reader exactly what's covered.

## What you must NOT do

- **Don't summarize each input source separately.** A retro
  is synthesis, not a digest. If the output reads like
  "from notes: …; from postmortems: …", it's wrong.
- **Don't fabricate themes.** A theme requires ≥2 sources.
  Don't promote a single-source item to a theme to make the
  section feel meatier.
- **Don't file tasks.** Action candidates surface; the user
  routes via `/task`.
- **Don't apologize for empty sections.** "Nothing
  noteworthy in 'what went well' this window" is honest;
  padding with filler is not.
- **Don't paste in raw note content.** The retro is
  one-line items with cites; the deep content lives in the
  source files.
- **Don't reach beyond the window.** A retro for the last
  2 weeks doesn't reference last quarter's work, even if
  tempting. The window is the contract.
- **Don't auto-commit.** Standard kit rule.

## Edge cases

- **Window has no inputs.** Surface honestly: "No notes,
  decisions, or postmortems in the last 2 weeks. Either
  nothing happened or `/lessons` isn't being run. Skipping
  retro." Suggest the user start `/lessons` going forward.
- **Window predates project start.** Shorten to actual
  coverage and note: "Window requested 1m; project history
  starts <date>. Retroing actual coverage."
- **First retro ever.** Skip the comparison section. Note
  in the closing: "First retro — recurring rhythm starts
  here."
- **Massive window (3+ months).** Ask the user to confirm —
  retros at this scale tend to lose specificity. Suggest
  splitting into multiple shorter retros instead.
- **Recurring theme spans multiple windows.** Surface that:
  "This theme appeared in last retro too; not yet
  resolved." Builds momentum on the chronic stuff.
- **Very chatty git log, sparse docs.** Lean on the docs;
  don't try to make commits the primary signal. Commits
  are corroboration, not source material.
- **The retro itself surfaces a regret.** Suggest routing
  to `/regret` rather than including a deep regret entry
  in the retro body.

## Scheduling — pair with `/loop`

The natural rhythm is recurring. Three suggested cadences:

- **Weekly** — fast feedback. `/loop 1w /retro 1w`. Best
  when shipping fast or actively building.
- **Bi-weekly** — sprint-ish. `/loop 2w /retro 2w`. Default
  recommendation.
- **Monthly** — strategic. `/loop 1m /retro 1m`. Best for
  steady-state projects where the week-to-week is quiet.

A project can run both — weekly for tactical, monthly for
strategic. The output files are date-windowed so they don't
collide.

## When NOT to use this skill

- **Capturing one task's lessons** → `/lessons`.
- **Documenting an incident** → `/postmortem`.
- **Recording one decision** → `/decision`.
- **Recording one regret** → `/regret`.
- **Onboarding into a project** → `/onboard` (the retros
  surface as part of project history but aren't onboarding
  themselves).
- **Project hasn't been running long enough** to have
  meaningful artifacts in any source. Wait until there's
  a couple weeks of `/lessons` notes plus some shipped
  tasks. A retro on a 3-day project is just a status
  update.

## What "done" looks like for a /retro session

A dated markdown retro at
`docs/retros/<YYYY-MM-DD>-<window>.md` synthesizing across
all in-window sources, with concrete recurring themes (each
with a frequency count) and action candidates routed to
specific skills. Optionally: the user picks one or two
action candidates to route immediately. Uncommitted.
Future retros build on this one — the comparison section
in the next retro starts to show resolved themes vs
chronic ones.
