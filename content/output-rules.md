# Output rules

The kit ships a catalogue of structured-output templates at
`output-styles.md` (synced into every project as
`.claude/output-styles.md`). This file is the **wiring**: when to
consult the catalogue, which template to pick for what, and how to
apply it.

> **Two files, one system.** `output-styles.md` is the design
> language — what each template *is* and what it *says* about the
> data inside it. `output-rules.md` is the selection and composition
> layer — when each template *applies* and how to combine them.

> **Project copy lives at `.claude/`.** Skills running inside a
> project read `.claude/output-styles.md` and `.claude/output-rules.md`
> (the kit copies). All path references in this file use the project
> path. The kit-internal originals at `kit/output-styles.md` /
> `kit/output-rules.md` are the canonical source.

---

## What this file governs

Outputs whose **type** matches a catalogue entry — whether
they're skill-produced deliverables OR inline answers in chat.

The carve: **structured ask → structured response. Open-ended
dialogue → prose.** The skill-vs-chat boundary isn't the line;
the type-of-output is.

### Output types that get a catalogue template

- Project status / briefing / dashboard
- Deployment or release report
- Test, build, or benchmark result
- Audit, review, or quality finding
- Backlog, roadmap, sprint board, kanban
- PR diff stats, change summary, branch overview
- Decision (with branching criteria) / option comparison
- Architectural topology / dependency graph
- Activity timeline / progress over time
- Single-fact alert (info / warning / error / success)
- Empty state ("nothing to show, here's why")
- Stats summary, leaderboard, ranking
- Search results with code context
- Help text or command reference
- Selection prompt (pick from a list)

### Conversational (in-chat) use is included

The catalogue isn't only for skill deliverables. **Any
structured ask gets a structured response**, whether it comes
through `/status` or just through a chat message. If the user's
question maps to a row in the selection table below, render the
catalogue template inline — you don't need to invoke a skill
first.

| User asks (in chat) | Render |
|---|---|
| *"What's the status?"* | §2 Live dashboard inline |
| *"What's deployed?"* / *"What's in prod?"* | §5 Deployment report inline |
| *"Any issues?"* / *"Anything failing?"* | §6 Severity audit (or §26 Empty state if none) |
| *"How does X compare to Y?"* | §24 Comparison matrix inline |
| *"Walk me through what happened."* | §23 Activity timeline inline |
| *"Show me the open PRs"* | markdown table (or §17 Branch overview if many branches) |
| *"Recent commits?"* | §16 Git log inline |
| *"What's the backlog look like?"* | §4 Sprint task board (or §3 Roadmap timeline for phase view) |
| *"Pick from these options"* | §34 Selection prompt |
| *"Headline numbers?"* | §28 Stats card grid (≤4 KPIs) |

The presence of a `/skill` invocation isn't required. Direct
chat asks of these types get the same treatment as the skill
would produce — denser, more designed, faster to scan than
plain prose.

## What this file does NOT govern

These stay as plain prose or normal markdown:

- **Mid-task progress narration** ("reading X next, then Y").
- **Free-form Q&A about HOW something works** ("explain how the
  catalogue is composed"; "why do we use SwiftData here?").
  Explanations are dialogue.
- **Brainstorm sessions, open exploration, planning
  conversations** — generative, exploratory, no clear deliverable.
- **Multi-turn dialogue, clarifying questions, back-and-forth**
  — the meta-shape of conversation itself.
- **Git commit messages, PR titles/bodies** — those have their
  own conventions (covered by `task-rules.md`).
- **One-line affirmations or confirmations** ("yes, done",
  "got it", "stopping here") — short prose is the right tool.

The line: **does the user's ask have an output TYPE in the
table above?** If yes → catalogue. If no (it's open-ended,
exploratory, conversational, narrative) → prose.

When uncertain, default to prose. A wrong catalogue use is
heavier than a missed one.

---

## The selection table

When producing a structured output, look up the kit-scenario in the
left column and use the catalogue § in the right.

| Kit scenario | Catalogue § |
|---|---|
| Project status snapshot, daily briefing | §2 Live status dashboard + §17 Branch overview + §28 Stats card grid |
| Single major task complete (release shipped, milestone hit) | §1 Hero completion card |
| Phased plan or roadmap | §3 Roadmap timeline |
| Hierarchical backlog (groups + items + progress) | §4 Sprint task board |
| Parallel work across stages | §13 Kanban board |
| Decision with branching criteria | §14 Decision tree |
| Production deploy / release report | §5 Deployment report |
| Service or system architecture | §27 Service topology |
| Multi-severity finding (audit, security, lint) | §6 Severity audit |
| Test results | §7 Test results |
| Latency / throughput benchmark | §8 Performance benchmark |
| PR-level review summary | §9 PR / code review |
| Distribution shape (latencies, sizes) | §19 Distribution histogram |
| Module / package dependency graph | §11 Dependency graph |
| Side-by-side before/after code | §12 Side-by-side diff |
| Stack trace with code context | §15 Stack trace |
| Recent commit history | §16 Git log graph |
| Branches snapshot | §17 Branch overview |
| Activity density across time | §18 Contribution heatmap |
| Parts-of-a-whole comparison | §20 Horizontal bar chart |
| Funnel / drop-off across stages | §21 Funnel flow |
| Diff stats with file-by-file bars | §22 Diff stats with bars |
| Chronological event log (incident, deploy, audit) | §23 Activity timeline |
| Comparing 3+ options across criteria | §24 Comparison matrix |
| Single-fact alert (info / warn / error / success) | §25 Alert variants |
| Nothing to show (clean audit, empty backlog) | §26 Empty state |
| Multi-step process status | §30 Multi-step wizard |
| Headline KPI numbers (≤4 cards) | §28 Stats card grid |
| Structured data response (JSON-shaped) | §31 JSON tree viewer |
| Section break in long output | §10 Section banner |
| Search hits with code context | §29 Search results |
| Ranked leaderboard | §32 Leaderboard |
| Help / command listing | §33 Command reference |
| Pick from a list of items | §34 Selection prompt |

If multiple rows fit, prefer the **most specific** match. If two are
equally specific, compose them — see "Composition" below.

If the row you want isn't here, the catalogue likely has the entry
anyway — scan the "Patterns by use case" header at the top of
`output-styles.md`.

---

## Composition rules

Structured outputs often need more than one template. The rules:

- **Lead with one primary template.** Don't open a report with two
  heavy boxes. Pick the dominant pattern; let secondary templates
  support it.
- **Use §10 Section banner only at major breaks.** A long report
  with phases or distinct sections gets a banner per section. A
  short report doesn't need any.
- **Don't stack two heavy ornaments back-to-back.** Hero card (§1)
  immediately followed by a banner (§10) is overkill — they
  compete.
- **Markdown headings (`##`, `###`) still wrap the output.** The
  catalogue templates render *inside* a markdown document. Use
  markdown for outer document structure (so chat / web / IDE
  rendering stays readable); use catalogue templates for the data
  inside each section.
- **Empty sections render as nothing.** If a `/status` has no open
  PRs, drop the section — don't render the catalogue's table with
  a placeholder row.
- **Tables are still tables.** When the data is genuinely tabular
  and the catalogue offers no specific entry, a markdown table is
  fine. The catalogue replaces ornamental visuals, not honest
  tabular data.

---

## Glyph and color discipline

The glyph vocabulary at the bottom of `output-styles.md` is the
kit's canonical set. Don't invent new glyph meanings inline.

Load-bearing glyphs (memorize these — every skill uses them):

- `●` always means **done / healthy / passing**
- `◐` always means **active / in progress**
- `○` always means **pending / queued**
- `✓` / `✗` / `⊘` always mean **check / cross / no-entry**
- `▲` / `▼` always mean **up / down** (improving / regressing, or
  pure direction)
- `═` always means **unchanged / no-op**
- `▌` left-edge bar always marks **the start of a finding's row**
- `★` ★ always marks **a recommendation or top item**
- `▶` always means **focus pointer / "you are here"**

Color is a **second** channel, not the primary one. The catalogue's
"two encodings beat one" principle applies: every status that's
encoded by color must also be encoded by a glyph or position. This
keeps output readable when color is stripped — logs, screenshots,
color-blind users, alternate renderers, plain-text exports.

The kit's color palette (semantic, not hex):

- **success green** — done, healthy, passing, expected
- **warning yellow** — active, in progress, medium severity
- **danger red** — failed, critical, blocked, received-but-wrong
- **accent orange** — high severity, version bumps, suggestions
- **info blue** — links, low severity, neutral information
- **dim gray** — pending, queued, separators, supporting text
- **bright white** — titles and headlines

---

## Rendering constraints

Catalogue templates use Unicode box-drawing characters and sparkline
blocks (`█ ▓ ▒ ░ ▁▂▃▄▅▆▇█`). These render correctly **only** in
monospace font with a code fence:

````markdown
```
╭─────────────────────────╮
│   ✦  TASK COMPLETE      │
╰─────────────────────────╯
```
````

Don't put catalogue art outside a code fence — proportional fonts
will misalign columns. Two exceptions:

- **Single-glyph inline use.** A `✓` next to a sentence is fine
  inline. The catalogue's vocabulary is allowed at the sentence
  level when it's a sigil, not a structural element.
- **Markdown table cells** can use single glyphs (`✓`, `✗`, `◐`)
  because tables enforce alignment by themselves.

Long box-drawing structures, sparkline rows, severity bars, dependency
graphs — always inside a code fence.

---

## When the catalogue doesn't fit

If a structured-output situation isn't well-matched by any §:

1. **Pick the closest entry.** Use it and add a one-line footnote
   in the output if the fit is rough — e.g. *"approximation —
   §6 Severity audit, with rows expanded for non-severity-typed
   findings."*
2. **Compose two adjacent entries** rather than inventing a new
   shape inline. (E.g. §6 Severity + §11 Dependency graph for a
   blast-radius report.)
3. **Stay conversational.** If the situation isn't really a
   structured output (it's a discussion, an explanation, a
   thought) skip the catalogue entirely and use prose. Not every
   reply needs an ornament.

Don't invent a 35th template inline. If a recurring situation has
no good catalogue entry, that's a kit-level fix — propose an
addition via `/contribute` against `kit/output-styles.md`. The
catalogue is meant to grow; it should grow deliberately.

---

## Precedence with skill output structures

Skills declare which catalogue entries they use in their `## Output
structure` section (e.g. `/release` says "render per §5 Deployment
report"). When a skill pins an entry, **follow it.** These universal
rules apply when:

- No skill is invoked (the user asked a question conversationally
  and you decided a structured output is the right answer).
- A skill's output structure section explicitly defers to "the
  standard catalogue selection rules."
- A skill is producing an output beyond the one its `## Output
  structure` describes (e.g. an alert mid-flow, a one-off side
  result).

Skills are also free to **compose** beyond their pinned entries —
e.g. `/status` pins §2 + §17 + §28 but may add a §25 alert if
something is genuinely off. The pinned entries are the *primary*
structure; composition with other entries is allowed when warranted
and follows the composition rules above.

---

## When to consult this file

- **Before producing a structured output.** Scan the selection
  table, pick an entry, render.
- **When composing multiple entries** — re-read the composition
  rules so the result doesn't get visually noisy.
- **When tempted to invent a new visual** — stop. Either find the
  catalogue entry that fits, or note the gap and propose a kit-level
  addition.
- **At skill-authoring time** — `/new-skill` references this file
  so new skills inherit the design language from birth.

This file is short on purpose. The substance lives in
`output-styles.md` — this is the lookup and discipline layer.
