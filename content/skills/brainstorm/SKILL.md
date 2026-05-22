---
name: brainstorm
description: Open or resume a brainstorming session on a recurring design tension — "real-time vs query power", "monolith vs services", "strict types vs ergonomics". Each session is a living markdown file at `.claude/tradeoffs/<topic>.md` that accumulates ideas, options, pros/cons, open questions, and dated session logs. Re-running `/brainstorm <topic>` picks up where you left off — never starts fresh on an existing topic. When the brainstorm converges, route to `/decision` for the durable record. Distinct from `/decision` (forward-looking record of what was picked) and `/regret` (hindsight on what was picked). Triggered when the user wants to explore a tradeoff before committing — e.g. "/brainstorm real-time vs queries", "let's brainstorm the auth model", "open a tradeoff on X", "I need to think through Y".
---

# /brainstorm — Open or resume a tradeoff session

A brainstorm is a *thinking session* — explore, weigh, sit with
a tension. Different from a decision (which closes one) and
different from a regret (which reviews one).

Each topic gets its own file at `.claude/tradeoffs/<topic>.md`.
The file is a **living record** — every brainstorming pass
appends to it. When the thinking converges, the session ends
with a route to `/decision`.

Per CLAUDE.md ethos: a brainstorm without specifics is venting.
Tag claims with `?` when uncertain; cite files and prior
decisions when grounding.

## Behavior contract

- **One file per topic, lives at `.claude/tradeoffs/<topic>.md`.**
  Topic is kebab-cased from the user's input — "real-time vs
  query power" → `real-time-vs-query-power.md`.
- **Resume, don't reset.** If the file exists, read it, show
  current state, continue from where you left off. Never
  silently start from scratch on an existing topic.
- **Append-only session log.** Every brainstorming pass adds
  a dated entry to a "Session log" section. Earlier passes
  stay readable as-is.
- **Status field is load-bearing.** `active` / `paused` /
  `promoted-to-decision` / `closed-without-deciding`. Surface
  on every interaction.
- **Don't pick.** This skill explores; the user picks. When
  the user signals convergence, route to `/decision` rather
  than writing the decision here.
- **Cite real things.** Prior decisions, regrets, postmortems,
  code locations. A brainstorm grounded in real artifacts is
  more honest than abstract pro/con theatre.
- **No auto-commit.** Standard kit rule.

## Process

### Step 1 — Resolve the topic

Slug the topic: lowercase, hyphenate, drop articles.
- "real-time vs query power" → `real-time-vs-query-power`
- "should we use Redux or Zustand" → `redux-vs-zustand`
- "the auth model" → `auth-model`

If the user's topic is vague ("the auth thing"), ask for the
tension specifically: "What's the tradeoff? X vs Y, or
something else?"

### Step 2 — Detect mode (new vs resume)

Check `.claude/tradeoffs/<slug>.md`:
- **Missing** → **new mode**. Scaffold the file structure.
- **Exists** → **resume mode**. Read the file, surface
  current state.

### Step 3 (resume) — Show current state

```markdown
# 🧠 Resuming — <topic>

**Status.** <active / paused / promoted-to-decision>
**First opened.** <date>
**Last touched.** <date>
**Sessions so far.** <count>

## Where you left off

> <quote the last session-log entry verbatim>

**Open questions still on the table:**
- <list from Open questions section>

**Continue with:** "add an option", "explore <X>",
"answer <question>", "weigh A vs B", "I'm ready to decide",
"close without deciding".
```

Then wait for direction.

### Step 4 (new) — Scaffold the file

Write a fresh `.claude/tradeoffs/<slug>.md` with the structure
shown in **Output structure** below. Then enter the
brainstorming loop.

Ask the user for the **opening prompt**:

```markdown
**Opening the brainstorm on `<topic>`.** Two quick things to
ground it:

1. **What triggered this?** What's the situation right now
   that makes this tension real?
2. **What are the obvious options on the table?** 2-3 you've
   already considered, even rough ones.
```

### Step 5 — Brainstorm loop

The skill operates in a loop until the user signals exit. Each
pass:

1. **Capture material.** New options, pros/cons, open questions,
   constraints. Append to the file in the right section.
2. **Surface tensions.** If a new pro of A directly opposes a
   con of B, name it.
3. **Probe.** Ask one focused question at a time — "what
   happens if we X?", "have you ruled out Y?". Don't dump
   five at once.
4. **Cite when possible.** Pull from `docs/decisions/`,
   `docs/regrets/`, `docs/postmortems/`, code paths. Brainstorms
   that ignore prior history relitigate solved problems.
5. **Save.** Update the file after each substantive pass.

### Step 6 — Convergence

When the user signals readiness ("I'm leaning toward X",
"let's go with B", "ready to decide"), don't write the
decision here. Instead:

```markdown
Sounds like the brainstorm is converging on **<option>**.

Next step: route to `/decision` to record the choice formally.
The decision doc captures *what was picked* and *why*; this
brainstorm stays as the record of *how you got there*.

I'll mark this brainstorm as `promoted-to-decision` and link
the decision doc once it's filed.

Ready to run `/decision`?
```

If yes: update status to `promoted-to-decision`, leave a
placeholder for the link, save.

### Step 7 — Closing without deciding

Some brainstorms don't converge — and that's fine. Options:

- **Pause** — status = `paused`. The file stays; resume later.
- **Close without deciding** — status = `closed-without-deciding`.
  Add a final session-log note explaining why (e.g. "no longer
  relevant — the underlying problem went away").

Don't pretend a brainstorm converged when it didn't.

### Step 8 — Closing chat summary

```markdown
# 🧠 Brainstorm — <topic>

**Status.** <new status>
**File.** `.claude/tradeoffs/<slug>.md`

<one-line summary of the session — what was added, what's
open, what's next>

*(If promoted-to-decision:)* Run `/decision` next to record the
choice formally. I'll link it back here.
```

## Output structure

The brainstorm file at `.claude/tradeoffs/<slug>.md`:

```markdown
# 🧠 Tradeoff — <topic>

> **Status.** active *(or paused / promoted-to-decision /
> closed-without-deciding)*
> **First opened.** <YYYY-MM-DD>
> **Last touched.** <YYYY-MM-DD>

## Background

<2-4 sentences — what triggered this brainstorm. The situation
that made the tension real. Cite files or prior decisions if
relevant.>

## Options on the table

### Option A — <short name>

<one-paragraph description>

**Pros.**
- <specific>
- <specific>

**Cons.**
- <specific>
- <specific>

**Cost to switch later.** <one line — easy / hard, why>

### Option B — <short name>

*(same shape)*

### Option C — <short name>

*(same shape; add more as needed)*

## Open questions

Things we don't know yet that would change the call.

- <question>
- <question>

## Constraints

Hard constraints that bound the answer regardless of preference.

- <constraint — e.g. "must work offline">
- <constraint — e.g. "team has 1 backend engineer">

## Prior history

References to earlier related thinking — decisions, regrets,
postmortems. Helps stop relitigating.

- [<title>](<link>) — <one-line connection>

## Session log

Append-only. Newest at the bottom.

### <YYYY-MM-DD> — Session 1

<one-paragraph summary of where the thinking went today. What
was added, what was challenged, what's still open.>

### <YYYY-MM-DD> — Session 2

<…>

---

## Outcome *(filled when promoted-to-decision)*

- **Decision.** <one-line — what was picked>
- **Decision doc.** [<link to /decision file>](…)
- **Promoted on.** <date>

*(Or, if closed without deciding:)*

## Closed without deciding *(filled when closed)*

- **Why.** <one paragraph>
- **Closed on.** <date>
```

## Style rules

- **One option per heading.** Don't merge "Option A or A-prime"
  into one section — they're two options if pros/cons differ.
- **Cite specifics in pros/cons.** "Saves 200ms p99 latency
  per request" beats "faster".
- **Cost-to-switch-later is mandatory.** Without it, "we'll
  decide later if we need to" is doing all the lifting.
- **Append, don't rewrite, the session log.** Each pass is a
  diary entry. Earlier passes stay even when superseded.
- **Open questions are first-class.** A brainstorm with
  unanswered questions is honest. One that lists none is
  hiding something.
- **Emoji is load-bearing.** 🧠 marks brainstorms. Don't add
  others.

## What you must NOT do

- **Don't decide.** This skill explores. Route to `/decision`
  when convergence is real.
- **Don't reset on resume.** Re-running `/brainstorm <topic>`
  loads the existing file. Never start a fresh session on an
  existing topic without explicit user say-so.
- **Don't conflate options.** "Option A or B" with shared
  pros/cons is bad — split them. Different options have
  different consequences.
- **Don't extrapolate past the user.** If the user says
  "ready to decide", don't pre-write the decision doc. Hand
  off to `/decision`.
- **Don't auto-commit.** Standard kit rule.
- **Don't bury real history.** If a prior decision or regret
  is relevant, link it explicitly in "Prior history".

## Edge cases

- **Same topic, different framings.** User runs
  `/brainstorm storage layer` after previously opening
  `/brainstorm rtdb-vs-firestore`. Surface the related file:
  "There's an active brainstorm at
  `.claude/tradeoffs/rtdb-vs-firestore.md` — same topic, or
  different angle?" Let the user decide whether to merge or
  open a new file.
- **User wants to revisit a closed brainstorm.** Status
  changes to `active` again; new session log entry explains
  why. Past content stays.
- **Promoted brainstorm — but the decision falls through.**
  Move status back to `active` if the decision didn't land,
  or `closed-without-deciding` if it actively died.
- **Brainstorm has been stale for months.** When resumed,
  prompt: "Last session was <N> months ago. Anything change
  in the meantime?"
- **The "tradeoff" is actually a one-sided question.** If
  there isn't a real tension (Option A clearly dominates),
  surface that and route to `/decision` directly, skipping
  the brainstorm shape.
- **A brainstorm references stale decisions.** Surface in
  "Prior history" honestly: "Decision <X> from <date> may no
  longer apply — assumptions changed."

## When NOT to use this skill

- **Recording a final choice** → `/decision`.
- **Recording hindsight on a past choice** → `/regret`.
- **Capturing one rule** → `/codify`.
- **An incident happened** → `/postmortem`.
- **The user already knows what they want** — don't run a
  brainstorm out of formality. Route to `/decision` directly.
- **The "topic" is just a question without a tension.** Ask
  it directly; don't manufacture a brainstorm shape.

## What "done" looks like for a /brainstorm session

A live `.claude/tradeoffs/<slug>.md` file with the current
brainstorming state — options, pros/cons, open questions,
session log. Status field reflects reality (active / paused /
promoted-to-decision / closed). Uncommitted. The user knows
the next move (continue thinking, run `/decision`, or pause).
Future sessions can resume mid-thought without re-explaining
context.
