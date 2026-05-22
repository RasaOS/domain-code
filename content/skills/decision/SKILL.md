---
name: decision
description: Draft an Architecture Decision Record (ADR) for a real architectural call — context, decision, alternatives considered, consequences. Stored in `docs/decisions/NNNN-title.md`. Companion to AUDIT.md (which logs one-liners) when a call needs the full reasoning preserved. Triggered when the user wants to document a real decision — e.g. "/decision", "ADR for X", "let's record why we chose Y", "document the RTDB-vs-Firestore call".
---

# /decision — Architecture Decision Record

Draft an ADR for a real architectural call. AUDIT.md captures
one-liners ("we chose X"). ADRs capture the *why* — the context,
the alternatives, the tradeoff, the consequences — so future-you
can re-evaluate the decision instead of re-discovering the
reasoning.

Per CLAUDE.md: honest tradeoffs. No rubber-stamps, no marketing.
The point is the reasoning, not the verdict.

## When an ADR is the right shape

ADR scale, not commit-message scale. Use this for:

- A choice between platforms / databases / frameworks (RTDB vs
  Firestore, Vite vs Next, REST vs GraphQL).
- A non-obvious convention that future-you will want to
  re-evaluate (county-scoped paths, schema-owned-by-iOS,
  no-TypeScript-yet).
- A "we considered this and decided not to" that would otherwise
  be lost (skipped emulators, deferred TypeScript migration).
- A breaking change to data shape, API contract, or build flow.

**Not for:**

- Day-to-day code style choices.
- Anything that fits in a one-line AUDIT entry.
- Bug fixes (those go in commits + AUDIT).
- Speculative future work (write the ADR when the decision is
  actually being made, not "in case we ever want to").

## Behavior contract

- **Read first.** Read `tasks/AUDIT.md` for related prior
  decisions, `CLAUDE.md` for stated conventions, and any existing
  ADRs in `docs/decisions/` to maintain numbering and tone.
- **Conversational drafting.** This isn't a fill-in-the-blank
  template — it's a reasoning artifact. Ask the user the
  questions that surface the *real* tradeoff. If the user can't
  articulate the alternative they rejected, the ADR isn't ready.
- **Don't write a marketing pitch.** "We chose X because it's
  amazing" — no. "We chose X because Y mattered more than Z, even
  though we lose W" — yes. Tradeoffs in both directions.
- **Capture what you'd revisit.** Future-you's question is "is
  this still the right call?" — frame the ADR so that question
  is answerable later. What was true then? What conditions would
  change the answer?
- **Don't auto-commit.** ADR file gets drafted; user reviews
  and commits.

## Process

### Step 1 — Find the next ADR number

Glob `docs/decisions/*.md` (or whatever the project's ADR
directory is — check `CLAUDE.md`). If none exist yet, this is
ADR `0001`. Otherwise, next zero-padded integer after the highest
existing.

If `docs/decisions/` doesn't exist, ask: "Create it? This will be
ADR 0001 — first ADR in the project."

### Step 2 — Surface the decision

Ask the user one or two focused questions in sequence:

1. **What's the decision?** One sentence. ("We're using Firebase
   Realtime Database, not Firestore.")
2. **What's the alternative you rejected?** This is the most
   important question. If they can't name a real alternative,
   the decision isn't an architectural call — it's just a choice.
3. **Why this one over that one?** What constraint or property
   tipped it? Cost, fit, familiarity, ops surface, vendor
   lock-in, latency, schema match with another platform?
4. **What does this cost?** Honest tradeoff. What does the
   chosen path *not* give you that the alternative would have?
5. **What would change your mind later?** What conditions, if
   they came true, would make you re-evaluate?

Don't ask all five at once. Ask 1–2, get answers, then ask the
next.

### Step 3 — Draft the file

Filename: `docs/decisions/NNNN-short-slug.md` (e.g.
`docs/decisions/0003-rtdb-over-firestore.md`).

Use this shape:

```markdown
# ADR NNNN — <short title>

**Status:** Proposed | Accepted | Superseded by [ADR-MMMM](MMMM-…) | Deprecated
**Date:** <YYYY-MM-DD>
**Decider(s):** <names / handles>

## Context

<2–5 sentences. What's the situation that requires a decision?
What constraints exist? What's the question being answered?>

## Decision

<1–3 sentences. The actual call. Specific.>

## Alternatives considered

### Option A — <name>
<1–3 sentences on what this would have looked like, and why it
was rejected. Be specific about the tradeoff, not "didn't fit our
needs".>

### Option B — <name>
<…>

*(Repeat for each genuine alternative. Two minimum — if there
wasn't a real alternative, it isn't an architectural decision.)*

## Consequences

**Positive**
- <what we get from this choice that the alternatives wouldn't
  have given us>
- …

**Negative / costs**
- <what we lose, what gets harder, what we'll have to revisit>
- …

**Neutral / notable**
- <observations about how the decision shapes future work,
  without classifying as good or bad>

## Revisit triggers

Conditions that, if they occur, mean we should re-open this
decision:

- <condition — e.g. "if our read patterns require server-side
  query filters that RTDB can't express">
- <condition — e.g. "if we need offline-write conflict resolution
  beyond last-write-wins">
- …

## References

- [related AUDIT entry, if any](../../tasks/AUDIT.md)
- [other ADRs that informed this one](./<file>.md)
- <external docs, RFCs, vendor pages>
```

### Step 4 — Append AUDIT.md entry

Per task-rules.md "Audit log":

```markdown
- 📜 **ADR NNNN — <short title>** filed. <one-line summary>.
  See [`docs/decisions/NNNN-…md`](docs/decisions/NNNN-….md).
```

Don't auto-commit; leave the AUDIT edit alongside the ADR file
for the user to commit.

### Step 5 — Show the user

Render the drafted ADR in the response so they can review without
opening the file. Ask if they want edits before committing.

## Status field

- **Proposed** — drafted, not yet accepted. Use when filing for
  discussion.
- **Accepted** — the decision is in force. Default for ADRs filed
  about decisions already made.
- **Superseded by [ADR-MMMM]** — a newer ADR replaces this one.
  Don't delete superseded ADRs; they're history.
- **Deprecated** — the decision no longer applies (the technology
  was removed entirely). Rare.

When marking an ADR superseded, the new ADR explicitly references
the old one and says what changed.

## Style rules

- **Names for alternatives, not "Option 1 / Option 2"** —
  "RTDB", "Firestore", "Custom backend on Postgres" reads better
  than numbered options.
- **No marketing language.** "Industry-standard", "best-in-class"
  → cut.
- **Quote stakeholder constraints.** "iOS team owns the schema"
  is a constraint; cite where it's documented.
- **Short.** A good ADR is 1–2 screens. If it's longer, it's
  probably trying to be a design doc — those are different.

## What you must NOT do

- **Don't auto-commit.** ADR + AUDIT entry are reviewed and
  committed by the user.
- **Don't propose ADRs for things that aren't decisions.** A
  refactor isn't an ADR. A bug fix isn't an ADR. A code-style
  choice isn't an ADR.
- **Don't fabricate alternatives.** If only one option was
  seriously considered, the ADR should say so plainly. Don't
  invent a strawman alternative for the "Alternatives" section.

## When NOT to use this skill

- **One-line "we did X" log entry** → `tasks/AUDIT.md` directly.
- **Design doc / spike** → write a separate doc in `docs/` or
  the relevant task spec. ADRs are decision-records, not designs.
- **Reviewing an existing decision** → just read the ADR; don't
  re-run this skill.
- **Filing a task** → `/task`.

## What "done" looks like for a /decision session

- ADR file drafted at `docs/decisions/NNNN-….md`.
- AUDIT.md entry appended.
- Both shown to the user, uncommitted.
- User decides what to commit and when.
