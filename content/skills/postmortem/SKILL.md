---
name: postmortem
description: Draft a postmortem for an incident — production outage, broken deploy, data loss, regression caught late. Captures timeline, root cause, contributing factors, what we changed (or will change) to prevent recurrence. Stored in `docs/postmortems/YYYY-MM-DD-slug.md` and logged in AUDIT.md. Triggered when something broke — e.g. "/postmortem", "write up what happened", "we need to capture this incident", "draft a postmortem for the deploy that broke".
---

# /postmortem — Incident postmortem

When something broke, capture what happened so the lesson
survives. AUDIT.md logs wins; postmortems log losses — both are
project history.

Per CLAUDE.md: blunt resonant honesty. No narratives, no
finger-pointing, no false closure. The point is the lesson, not
the absolution.

## When to write a postmortem

Real signals:
- Production outage, broken deploy, or rollback.
- Data loss, data corruption, or migration that misfired.
- Regression caught late (in prod, in stage by a customer, days
  after merge).
- Security incident or near-miss.
- Significant time lost to a confusing failure mode (the system
  surprised you in a way that took >half a day to unwind).

**Not for:**
- A bug caught in code review.
- A test failure during normal development.
- Something annoying but expected (flaky test that we knew
  about).

If you're unsure whether it warrants a postmortem, write the AUDIT
entry instead and move on. Postmortems are for incidents that
*changed how we operate* (or should change it).

## Behavior contract

- **Blameless on people, blunt on the system.** Don't write "X
  forgot to do Y." Write "the workflow allowed Y to be skipped
  silently." The bug is in the system, not the person.
- **Timeline first, theory second.** What happened, in order, with
  timestamps if known. Then the analysis. Inverting this order
  causes the analysis to be retrofitted to the conclusion.
- **Root cause is plural.** Most incidents have a chain — a single
  "root cause" is usually shorthand for the deepest contributing
  factor. List the chain.
- **Action items are concrete and owned.** "We should improve
  testing" is not an action item. "Add E2E coverage for the
  payment-confirmation flow (TASK-NNN, owner: <name>)" is.
- **Don't auto-commit.** Draft the file; user reviews and commits.

## Process

### Step 1 — Get the facts

Ask the user, in this order:

1. **What broke?** One sentence — the user-visible symptom.
2. **When was it noticed? When did it start?** Best estimates are
   fine; mark them as estimates.
3. **How was it detected?** Alert? Customer report? You noticed
   while testing something else?
4. **What did you do to stop the bleeding?** Rollback, hotfix,
   manually fix data, etc.
5. **Is it resolved now?** If still in progress, this is an
   *incident report* — the postmortem comes after the resolution.

If the answer to #5 is "still in progress", offer to draft an
incident *update* instead and revisit for the full postmortem
once resolved.

### Step 2 — Surface the chain

Walk back from the symptom:

- "The user saw X — what does X come from?" → component
- "What did that component depend on?" → upstream system
- "Why did the upstream system give bad output?" → state /
  config / input
- "Why didn't anything catch this earlier?" → testing / monitoring
  / review gap

The chain often has 3–5 links. Stop when "why" stops adding
information.

### Step 3 — Draft the file

Filename: `docs/postmortems/YYYY-MM-DD-short-slug.md` (e.g.
`docs/postmortems/2026-04-28-stale-vehicle-cache.md`).

If `docs/postmortems/` doesn't exist, ask: "Create it? This will
be the first postmortem in the project."

Use this shape:

```markdown
# Postmortem — <short title>

**Date of incident:** <YYYY-MM-DD>
**Date written:** <YYYY-MM-DD>
**Severity:** SEV1 (full outage) | SEV2 (significant degradation) | SEV3 (minor) | near-miss
**Status:** Resolved | Mitigated | Investigating
**Authors:** <names / handles>

## Summary

<2–4 sentences. What broke, who was affected, how long, how it
ended. The reader should be able to stop here and know what
happened.>

## Impact

- **Users affected:** <count or scope>
- **Duration:** <how long the bad state was visible>
- **Data:** <any data lost / corrupted / mis-stamped>
- **Revenue / external:** <if applicable>

## Timeline

All times in <UTC | local TZ>. Times marked `~` are estimates.

| Time | Event |
|---|---|
| `~HH:MM` | <triggering change or condition> |
| `HH:MM` | <symptom first observable> |
| `HH:MM` | <detection — how we found out> |
| `HH:MM` | <first response action> |
| `HH:MM` | <…> |
| `HH:MM` | <full resolution> |

## What broke (the chain)

Walking from symptom back to source.

1. **Symptom:** <what users saw>
2. **Proximate cause:** <the immediate technical cause —
   e.g. "API returned 500 because the DB query timed out">
3. **Underlying cause:** <one layer deeper — e.g. "the index
   on `created_at` was dropped during the migration in PR #N">
4. **Contributing factors:** <gaps that let this chain
   propagate — e.g. "no E2E coverage for this code path",
   "deploy ran without smoke test", "rollback was manual and
   slow">

## Why we didn't catch it earlier

- **In code review?** <what review would have had to notice>
- **In tests?** <coverage gap, or test that should have failed
  but didn't>
- **In monitoring?** <missing alert / slow alert / noisy alert>
- **In deploy?** <missing smoke check / canary / staging
  parity>

## What we did to fix it

- <the actual response, in order — rollback, hotfix, data
  repair, comms>

## What we're changing

Concrete action items. Owned. Linked to tasks.

| # | Action | Owner | Linked task | Status |
|---|---|---|---|---|
| 1 | <specific change> | <name> | TASK-NNN | open |
| 2 | <specific change> | <name> | — | open |

If no actions yet, **write "none — pending discussion"** rather
than padding with vague intentions.

## What we're not changing (and why)

Sometimes the right answer is "this is an acceptable risk; we
won't invest here." Document those calls so they aren't
re-litigated.

- <thing we considered changing but decided against, with the why>

## Lessons

2–4 sentences of plain-language takeaway. Not "we learned to be
more careful" — something specific. "This class of bug needs
contract tests at the boundary, not just unit tests on either
side."

## References

- Triggering PR / commit: <link>
- Incident channel / thread: <link if applicable>
- Related AUDIT entry: `tasks/AUDIT.md` <date>
- Related ADRs: <if any>
```

### Step 4 — Append AUDIT.md entry

Per the audit log rule:

```markdown
- ⚠️ **Incident — <short title>.** <one-line summary, including
  severity and resolution>. Postmortem at
  [`docs/postmortems/YYYY-MM-DD-….md`](docs/postmortems/YYYY-MM-DD-….md).
```

Use ⚠️ for incidents. (The audit-log rule already lists ⚠️ for
honest tradeoffs — incidents are a kind of tradeoff record, since
they explain why the operating model changed.)

### Step 5 — File action items as tasks

Action items in the postmortem that translate to work should be
filed as tasks via `/task`. Do not draft them inline in this
skill — hand off:

> "I've drafted the postmortem and audit entry. The action items
> in the table need to become tasks — want me to file them via
> `/task`?"

### Step 6 — Show the user

Render the drafted postmortem in the response. Ask for edits
before committing.

## Severity rubric

- **SEV1** — full outage, data loss, security breach. Drop
  everything.
- **SEV2** — significant degradation, broken feature, regression
  visible to users. Postmortem required.
- **SEV3** — minor, contained, short-duration. Postmortem
  optional but useful if the cause was non-obvious.
- **Near-miss** — almost broke prod but didn't (rollback caught
  it, staging caught it, on-call caught it before customer
  impact). Worth a postmortem when the near-miss reveals a real
  gap.

## Style rules

- **Past tense for the timeline.** Present tense for current
  state. ("The deploy *failed* at HH:MM. The bug *is now fixed*.")
- **Specific times, not "later".** "12 minutes after detection",
  not "shortly afterwards."
- **Names of systems, not "it".** "The RTDB write" not "the
  thing that wrote."
- **No "luckily" / "fortunately".** If something didn't break,
  say *why* — luck is not a control.
- **No exoneration language** ("this was an unusual
  circumstance"). Either it'll recur and we should defend
  against it, or it won't and we say why.

## What you must NOT do

- **Don't write blame into the timeline.** "X forgot to do Y" —
  rewrite as "the workflow let Y be skipped".
- **Don't auto-commit.** Same as `/decision`.
- **Don't soften.** If the action items are uncomfortable, that's
  the postmortem doing its job. Don't soften them to make the
  doc easier to read.
- **Don't pad action items.** Three real actions beat ten vague
  ones.

## When NOT to use this skill

- **Bug report** during normal development → just file a task.
- **In-flight incident** that hasn't resolved → write an incident
  *update* (timeline so far, what we know, what we're trying)
  and revisit when resolved.
- **Wrap-up doc for a project** that didn't have an incident →
  use a retrospective doc (different shape; not this skill).

## What "done" looks like for a /postmortem session

- Postmortem file drafted at
  `docs/postmortems/YYYY-MM-DD-….md`.
- AUDIT.md entry appended (⚠️).
- Action items either filed as tasks (via `/task`) or marked
  "pending discussion" with the why.
- File rendered in the response, uncommitted.
- The lesson is captured in language that won't make sense only
  to people who were there.
