---
name: regret
description: Capture an architectural regret with hindsight — a decision that didn't pan out, a pattern that didn't age well, a vendor choice that bit back. Distinct from `/postmortem` (incident-focused, "what broke and why") — `/regret` is hindsight on a *choice* ("what we picked, what we know now, what we'd do differently"). Output saved to `docs/regrets/<YYYY-MM-DD>-<slug>.md`. Stops teams from relitigating the same bad call across projects. Triggered when the user wants to record a hindsight lesson on an architectural decision — e.g. "/regret", "I regret X", "this decision didn't pan out", "capture this lesson", "we shouldn't have done Y".
---

# /regret — Capture an architectural regret with hindsight

A regret is a decision you'd make differently knowing what
you know now. Not an incident (that's `/postmortem`), not a
new decision (that's `/decision`) — a record of a *prior*
decision and what hindsight has revealed about it.

The point: stop relitigating the same bad call. When the next
project considers the same path, the regret doc says "we
tried this; here's what happened; here's what we'd do
differently."

Per CLAUDE.md ethos: regrets aren't blame. The original
decision was made with the information available; the regret
captures what the information looks like now. Honest, not
punitive.

## Behavior contract

- **Writes durable docs only.** Output lands at
  `docs/regrets/<YYYY-MM-DD>-<slug>.md`. No source-code edits.
- **Distinct from postmortem.** Postmortems are about
  incidents — something broke, here's why. Regrets are about
  choices — we picked X over Y, hindsight says Y. If the user
  asks for a regret about an incident, route to `/postmortem`
  instead.
- **Distinct from decision.** A decision is forward-looking
  ("we're going with X"). A regret is backward-looking on a
  prior decision. Often a regret references the original
  `/decision` doc.
- **No blame voice.** The artifact is about the decision and
  the lesson, not the people. Names appear only when essential
  (and only with the user's explicit consent).
- **Two distinct things per regret:** (1) what we'd do
  differently next time, (2) how to stop relitigating. Both
  matter.
- **Cite the original decision if it exists.** Link to the
  `/decision` doc, the PR that landed the change, or the
  commit. Anchors the regret to actual history.
- **Don't auto-commit.** Standard kit rule.

## Process

### Step 1 — Capture the regret topic

If the user invokes without context, ask:

```markdown
A regret captures hindsight on a prior decision. Five things,
in one block:

1. **What we picked** — the decision (technology, pattern,
   vendor, structure).
2. **When** — roughly. Year + project phase is enough.
3. **What we hoped for** — the original justification.
4. **What actually happened** — the part hindsight reveals.
5. **Why we're capturing this now** — what made you bring
   it up.

Skip any item where you don't have a clear answer; the doc
will mark it "couldn't reconstruct."
```

### Step 2 — Generate a slug

From the regret topic: e.g. `chose-rtdb-over-firestore`,
`shared-state-context-pattern`, `vendor-X-for-payments`.
Filename: `docs/regrets/<YYYY-MM-DD>-<slug>.md`.

### Step 3 — Find the original decision (if recorded)

Look for an existing record of the original decision:
- `docs/decisions/` — search for the topic.
- `docs/postmortems/` — sometimes a regret crystallizes from
  a postmortem.
- `tasks/AUDIT.md` — when the change was shipped.
- Commit history — `git log --grep=<topic>`.
- Recent CHANGELOG entries.

Surface what you found:

```markdown
**Original record:**
- [`docs/decisions/<file>`](<link>) — *<title>*
- *(or)* "No prior `/decision` doc found. The earliest commit
  referencing this is `<sha>` from `<date>`."
```

If nothing is on disk, that's fine — note "Original decision
not formally recorded; this regret is the first written
artifact."

### Step 4 — Walk the regret structure

Render this in chat (don't write yet) and let the user fill
gaps:

```markdown
Drafting the regret. Confirm or correct:

**What we picked.** <user's answer>
**When.** <user's answer>
**Original justification.** <user's answer + anything from
docs/decisions/>
**What actually happened.** <user's answer>
**What we'd do differently.** <ask if not given>
**How to stop relitigating.** <ask — this is the load-bearing
part>
```

The "stop relitigating" prompt is the most valuable. Common
shapes:
- "If we ever consider <pattern> again, the question to ask
  first is <X>."
- "The trade-off looks attractive when <Y>; in reality, <Z>
  is what dominates."
- "Don't reconsider unless <specific condition that didn't
  hold last time>."

### Step 5 — Write the regret doc

Output to `docs/regrets/<YYYY-MM-DD>-<slug>.md` per the
**Output structure** below.

### Step 6 — Optional: link from the original decision

If a `/decision` doc exists for the original choice, ask:

```markdown
The original decision is at [`<path>`](<link>). Want me to
add a one-line "Update: see `<regret path>`" footer to it?
That way anyone reading the original lands at the regret too.
```

On approval: append a footer to the decision file. Don't
commit.

### Step 7 — Closing summary

```markdown
# 🪨 Regret captured

`docs/regrets/<date>-<slug>.md` — <line count> lines.

**The lesson, in one sentence:** <quote the regret's "stop
relitigating" line>

*(If decision linked:)* Updated [`<original-decision-path>`](<link>)
with a pointer to this regret.

Review with `git diff`, edit anything that misrepresents the
history, commit when ready.
```

## Output structure

The regret doc at `docs/regrets/<YYYY-MM-DD>-<slug>.md`:

```markdown
# 🪨 Regret — <topic, terse>

> **The decision in one sentence.** <e.g. "Chose RTDB over
> Firestore for the inspections data layer.">
>
> **The hindsight in one sentence.** <e.g. "Saved on real-time
> cost; lost everything in query power and pattern flexibility,
> which has cost more in dev time than it saved in infra.">

**Date captured.** <YYYY-MM-DD>
**Decision date.** <when, roughly>
**Original record.** <link if found, else "Not formally
recorded.">

---

## What we picked

<2-4 sentences describing the actual choice — technology,
pattern, vendor, structure. Specific. Cite paths if relevant.>

## What we hoped for

<2-4 sentences on the original justification. The reasons
that made it look right at the time.>

> *(If a `/decision` doc exists, quote the relevant line:)*
> > <quote>

## What actually happened

<3-6 sentences on the lived experience. What did the choice
actually cost? Be specific. Avoid "it was hard" — say what
specifically was hard, with `path:line` examples if it shows
up in the code.>

## What we'd do differently

<2-4 sentences. Concrete. Not "we'd think more carefully" —
"we'd <specific alternative>" or "we'd <specific guardrail>".>

## How to stop relitigating

This is the most important section.

<2-4 sentences. The exact question or condition that should
trigger reconsideration in the future. Phrased so a different
person, in a different project, can apply it.>

> **Rule of thumb:** <one-line pull-quote — the thing future
> people should remember, even if they don't read the rest.>

---

## What's still uncertain

Things hindsight hasn't resolved. Optional but valuable.

- <bullet — e.g. "Whether the original choice would have been
  fine if <condition>; we never tested that branch.">
- …

## Adjacent regrets *(optional)*

If this regret connects to others, link them. One-liners.

- [<other regret>](<link>) — <one-line connection>

---

*Captured by `/regret` on <YYYY-MM-DD>. Not a postmortem (no
incident); not a decision (no forward action). A durable
hindsight record.*
```

## Style rules

- **Past tense for the decision and what happened.** Present
  tense for what we'd do differently and how to stop
  relitigating.
- **Specific over general.** "RTDB joins are unsupported, so
  every query is a manual fan-out at the client" beats "the
  data layer was hard to work with".
- **Pull-quote the rule of thumb.** Block-quote it in the
  "How to stop relitigating" section. That's the line future
  readers will remember.
- **Cite paths when the regret shows up in code.** A regret
  about a pattern is more credible when it points at the
  pattern in the code.
- **Emoji is load-bearing.** 🪨 (regret — heavy, durable).
  One emoji.
- **No blame language.** "We picked", "the team chose",
  "this approach". Not "X decided", "Y forced this".

## What you must NOT do

- **Don't write a postmortem.** If the trigger is an incident,
  route to `/postmortem`. Regrets are about choices, not
  outages.
- **Don't write a new decision.** If the regret implies a new
  choice the user is about to make, route to `/decision` for
  that. The regret is hindsight; the decision is forward.
- **Don't include names without consent.** Even when a single
  person made the call, the doc lives in version history. Ask
  before naming.
- **Don't editorialize emotional language.** "We hated it",
  "this was a disaster" — strip these. Specific facts beat
  emotional adjectives.
- **Don't auto-commit.** Standard kit rule.
- **Don't skip "stop relitigating".** That section is the
  whole point of the artifact. If the user genuinely doesn't
  know what would prevent relitigation, surface that as
  uncertainty rather than skip.
- **Don't propagate to the kit.** Regrets are project-level
  artifacts. If a regret produces a generalizable rule, the
  user runs `/codify` (or `/rule-promote` after it appears
  in 2+ projects).

## Edge cases

- **Original decision was correct given what was known.**
  The regret doc still has value — captures what changed in
  the meantime. Be explicit: "Decision was sound given
  available information; what changed: <X>."
- **Multiple connected regrets.** Don't merge into one doc.
  Each gets its own file; cross-link in the "Adjacent regrets"
  section.
- **Regret about a vendor / commercial relationship.** Same
  shape; surface "What's still uncertain" generously since
  vendor regrets often involve confidential context.
- **The decision is about to be undone in current work.**
  That's good — the regret doc anchors the *why* behind
  the undo. Link the active task or PR.
- **No "what we hoped for" — the team can't remember.** Note
  it: "Original justification not reconstructible; commit
  message reads `<sha>: <message>` only."
- **Regret about claude-kit itself** (e.g. a rule that didn't
  age well). Same shape, but the user runs `/contribute` to
  push the regret + a corrective edit to the kit.

## When NOT to use this skill

- **Capturing an incident** → `/postmortem`.
- **Capturing a forward-looking choice** → `/decision`.
- **Capturing a one-line rule** → `/codify`.
- **Capturing a status update or progress note** → `/handoff`
  or `/status`.
- **The decision was made yesterday and the lesson isn't
  baked yet.** Wait. Regrets are hindsight; premature regrets
  are venting.

## What "done" looks like for a /regret session

A dated markdown file at `docs/regrets/<date>-<slug>.md`
capturing the original choice, what hindsight reveals, what
we'd do differently, and — most importantly — the rule of
thumb that prevents the same call being made unconsidered
next time. Optionally linked from the original decision doc.
Uncommitted. The user knows the lesson is now durable.
