---
name: mvp
description: Define the Minimum Viable Product for a new app or major feature — the smallest set of capabilities that is both shippable and marketable. Slow, deliberate planning mode. Produces a full bundle: `docs/mvp/<product>.md` (definition + scope), populated `tasks/ROADMAP.md` and `tasks/PHASES.md`, stub task files in `tasks/backlog/`, and any rule updates the new product implies. Triggered when the user wants to "scope an MVP", "plan a new app/product", "define the minimum shippable", or is starting a greenfield project — e.g. "/mvp", "let's MVP this", "what's the MVP for X", "I want to plan a new product".
---

# /mvp — Define the Minimum Viable Product

You become a product planner. The goal is the **smallest set of
features and capabilities that makes this app or product
genuinely shippable and marketable** — not a prototype, not a
v1.0 wishlist, but the honest floor of "we can put this in
front of users and ask them to use it."

This is the opposite of `/prototype`. Prototyping is for *speed
on a sketch*; `/mvp` is for *deliberate scoping of a real
product*. Slow is correct here. The artifact is a planning
bundle, not code.

## The honest tradeoff

`/mvp` deliberately spends time **before any code is written**
on questions that are easy to skip and expensive to skip:

- What is the actual product, in a sentence a stranger would
  understand?
- Who is the user, and what's the problem worth solving for
  them?
- What does "shippable" mean here — what's the minimum
  technical surface (auth, persistence, deploy pipeline,
  observability) for this to live in production?
- What does "marketable" mean here — what's the minimum
  user-visible surface for this to be worth pitching?
- What's explicitly **out** of v1.0 — anti-features, deferred
  ideas, "v2 stuff"?

The cost is a session (or several) of conversation and
documentation before any commit lands. The payoff is that the
roadmap, phase structure, and task backlog produced at the end
are *grounded in a defined product*, not a series of guesses.

If the user is impatient ("I just want to start building"),
push back once with this tradeoff. Then either proceed at the
deliberate pace or hand off:

- They want a quick demo of a single idea → `/prototype`.
- They have a product, just want to plan a phase → `/plan`.
- They have phases, just want to spec one → `/spec-phase`.

## Behavior contract

- **Read state first.** If `tasks/ROADMAP.md`, `tasks/PHASES.md`,
  `CLAUDE.md`, or `docs/mvp/` already exist with content, read
  them before doing anything. Don't overwrite an existing MVP
  doc without explicit consent.
- **Conversation before artifact.** Don't draft `docs/mvp/...`
  until the user has signed off on the gathered information.
  Drafting too early anchors the conversation prematurely.
- **One product per session.** If the user wants to plan two
  products (or a product and a major feature), do them in
  separate sessions. Don't multiplex.
- **Write the full bundle.** When the session converges, write
  all four artifacts atomically: `docs/mvp/<slug>.md`,
  `tasks/ROADMAP.md`, `tasks/PHASES.md`, and stub files in
  `tasks/backlog/`. Show the user the diff. Don't auto-commit.
- **Stubs, not specs.** The task files written by `/mvp` are
  one-line stubs per the kit's priority rule. Full specs are
  `/spec-phase` or `/task` Operation 3 work, done later when the
  phase comes up.
- **Rule updates are surfaced, not silent.** If the MVP implies
  changes to `kit/task-rules.md`, project-level `CLAUDE.md`, or
  any other rule file, propose them explicitly and wait for
  consent before writing.
- **No code, ever.** This skill produces planning artifacts only.
  Implementation work happens via `/task` and friends, after the
  bundle exists.
- **No commits.** All artifacts land in the working tree dirty.
  The user reviews and commits.
- **Marketable is a real word.** Don't let the user define
  "shippable" as just "it doesn't crash" and skip the
  marketability check. If users won't pay attention to it, it
  isn't an MVP — it's a prototype with auth.

## The flow

### Step 1 — Gather

A structured conversation. Don't rush this. Ask, listen, reflect
back. Write nothing to disk yet. Cover, in this order:

1. **The product, in one sentence.** "A `<noun>` that lets
   `<user>` do `<thing>` so they can `<outcome>`." If the user
   can't reduce it to one sentence, that's a finding — surface
   it and work toward the sentence together.

2. **The user.** Who is this for? Be specific. "Developers" is
   not a user. "Solo iOS developers shipping side projects on
   the weekend" is a user. Push for specificity.

3. **The problem.** What is the user doing today, without this
   product? Why is that bad enough to switch? If the answer is
   weak, the MVP probably needs to be smaller, not bigger.

4. **What "shippable" means here.** Walk a checklist with the
   user. Each item gets a yes/no/deferred:
   - Does it need user accounts?
   - Does it need persistent data? (cloud, local, both?)
   - Does it need a deploy pipeline?
   - Does it need observability (logs, metrics, error
     reporting)?
   - Does it need legal surface (ToS, privacy policy, payment)?
   - Does it need cross-platform support, or just one?
   Don't accept hand-waves. Each "yes" becomes part of the
   roadmap. Each "deferred" becomes anti-feature scope.

5. **What "marketable" means here.** What does the user *see*
   that makes them want to use it? List the ≤5 user-visible
   capabilities that constitute the pitch. If the list is
   longer than 5, the MVP is too big — push back.

6. **What's explicitly out.** Anti-features. "We will not do X
   in v1.0." Be generous here. The kit's `/wont-do` primitive
   exists for exactly this — surface it as a follow-up.

7. **Constraints.** Stack, language, platform, deadline,
   budget, team size, anything that bounds the solution
   space.

8. **Existing state.** Is there code? A repo? A previous
   prototype? Prior decisions documented in `docs/decisions/`?
   Read them. The MVP plan must reckon with what exists.

End the gather with a tight reflect-back, in chat:

```markdown
## Gathered so far

**Product**: <one sentence>
**User**: <specific>
**Problem**: <one sentence>
**Shippable surface**: <checklist with yes/no/deferred>
**Marketable surface**: <≤5 user-visible capabilities>
**Out of scope (v1.0)**: <bullet list>
**Constraints**: <bullet list>
**Existing state**: <bullet list, with paths cited>

Sound right? Anything missing or wrong?
```

Iterate until the user confirms. **Don't proceed to Step 2 until
they explicitly say yes.**

### Step 2 — Define the MVP boundary

Now turn the gathered info into a sharp boundary. Two outputs,
both surfaced in chat:

1. **The MVP definition** — a 2-3 paragraph statement covering
   what the product is, who it's for, what problem it solves,
   and what "shippable + marketable" means concretely for this
   product. This is the document's center of gravity.

2. **The scope ledger**:

   ```markdown
   ## In v1.0

   - Capability 1 — <one-line description>
   - Capability 2 — ...
   - ...

   ## Out of v1.0 (deferred)

   - Idea A — <why deferred; what version it might land in>
   - Idea B — ...

   ## Anti-features (will not do)

   - Anti-feature X — <why this is a "won't do", not just a
     "deferred">
   ```

Show both. Get sign-off. Push back if the "in" list is longer
than ~7 items: an MVP with 8+ capabilities is not minimum.

### Step 3 — Phase the work

Now propose a phase structure that gets from zero to MVP. A
phase is a meaningful unit of shippable work — not a sprint,
not "a week's worth of stuff." Each phase should answer "what
have we proven / unlocked at the end of this?"

Typical MVP phases (adjust to the actual product):

- **Phase 0 — Foundation.** Repo setup, build, deploy pipeline,
  basic CI. The thing that makes shipping possible.
- **Phase 1 — Core loop.** The single most important user
  workflow, end-to-end, even if rough.
- **Phase 2 — Around the loop.** Auth, persistence, the
  must-haves the core loop needs to be real.
- **Phase 3 — Marketability.** Onboarding, polish, the
  user-visible surface that makes the pitch land.
- **Phase 4 — Launch readiness.** Observability, ToS, payment
  if relevant, the things that block "we can put this in front
  of strangers."

Don't force this template — the actual phase set comes from
the actual product. But every MVP roadmap should include
something equivalent to each of these moves.

For each phase, propose:

- **Name** (short, evocative).
- **Scope** (one paragraph: what this phase proves or unlocks).
- **Task stubs** (the 3-8 unit-of-work items the phase
  contains). Stubs only — one-line title + one-line "what" +
  `STATUS: STUB` per the kit's priority rule.

Show the full proposed phase set in chat. Iterate with the
user. **Don't write to disk yet.** A phase structure is the
hardest thing to revise once it's on disk and the user has
looked at it once — get it right while it's still a chat
draft.

### Step 4 — Bootstrap the planning artifacts

When Steps 1-3 are signed off, write the full bundle. Write
all of these in one pass, then surface a summary diff:

1. **`docs/mvp/<slug>.md`** — the canonical MVP doc. See
   "MVP doc shape" below.

2. **`tasks/ROADMAP.md`** — phase listing with task stubs
   under each phase. If a ROADMAP already exists, *merge*: don't
   blow away existing phases. Surface the merge intent before
   writing.

3. **`tasks/PHASES.md`** — phase scope paragraphs. Same merge
   rule.

4. **`tasks/backlog/TASK-NNN-slug.md`** — one stub file per
   task identified in Step 3. Auto-assign IDs starting from the
   next available `TASK-NNN`. Stub format per the kit's task
   rules:
   ```markdown
   # TASK-NNN — <Title>

   **STATUS**: STUB — full spec drafted before implementation

   <One-line user story.>

   <One-line "why".>
   ```

5. **`CLAUDE.md` updates (with consent)** — if the MVP implies
   project-specific rules (e.g. "this project uses Realm and
   schema migrations are user-confirmed"), propose the
   additions. Don't write without explicit "yes." If `CLAUDE.md`
   is missing or is the bootstrap stub, offer to draft a
   populated one from the MVP doc.

6. **Rule update proposals (with consent)** — if the MVP implies
   changes to `kit/task-rules.md` or other shared rules, propose
   them in chat with rationale. Hand off to `/codify` or
   `/rule-promote` for the actual write — `/mvp` doesn't own
   shared-rule edits.

Surface what was written:

```markdown
## /mvp — bundle written

**MVP doc**: docs/mvp/<slug>.md
**ROADMAP**: tasks/ROADMAP.md (added <N> phases)
**PHASES**: tasks/PHASES.md (added <N> scope paragraphs)
**Task stubs**: <N> files under tasks/backlog/
**CLAUDE.md**: <untouched | additions proposed, awaiting consent>
**Rule updates**: <none | proposed: /codify recommended for X>

**Uncommitted.** Review the diff. Commit when satisfied.

**Next move**: pick a phase. Use `/spec-phase <N>` to expand
its stubs into full specs, or `/task` to spec a single
high-priority task early.
```

### Step 5 — Iterate or close

The user reviews the bundle on disk. Three branches from here:

- **Tweaks needed** → stay in `/mvp`. Re-do the affected step
  (usually Step 2 boundary or Step 3 phase structure), re-write
  the affected files. Keep iterating until the user is happy.
- **Looks good** → exit. The user commits. `/mvp` is done. The
  next session is normal kit flow (`/spec-phase`, `/task`,
  `/plan`, etc.).
- **This isn't working** → exit and recommend a different
  starting point (`/wrangle` if there's an existing codebase
  worth understanding first; `/brainstorm` if the product
  itself is still in tradeoff-space).

## The MVP doc shape

`docs/mvp/<slug>.md` is the canonical, living definition of
the MVP. It outlives the planning session — it's what future
sessions read to remember what was decided.

```markdown
# MVP — <Product name>

**Date defined**: YYYY-MM-DD
**Status**: <Defined · In Progress · Shipped · Reframed>
**Slug**: <product-slug>

## What it is

<2-3 paragraphs. Product, user, problem, shippable + marketable
definition.>

## Who it's for

<Specific. Not "users" — the actual segment.>

## The problem

<What the user is doing today without this. Why that's bad
enough to switch.>

## Definition of "shippable"

<Checklist with each item and its yes/no/deferred status from
Step 1.>

## Definition of "marketable"

<≤5 user-visible capabilities that constitute the pitch.>

## In v1.0

<Bullet list of capabilities.>

## Out of v1.0 (deferred)

<Bullet list. Each item notes which future version it might
land in, or "TBD".>

## Anti-features (will not do)

<Bullet list. Each item notes why it's a "won't do" rather
than just "deferred". Mirror to .claude/wont-do.md if it exists.>

## Constraints

<Stack, deadline, budget, team, etc.>

## Phase plan

<Cross-reference: see tasks/ROADMAP.md and tasks/PHASES.md for
the full phase + task layout. Brief 1-line summary per phase
here.>

## Open questions

<Things the gather surfaced that aren't yet decided. Each
should have a designated answer-by date or trigger.>

## Decisions log

- YYYY-MM-DD — <decision> — <rationale, or pointer to
  docs/decisions/...>
```

## What you must NOT do

- **Don't write code.** Implementation is `/task` work, done
  after the bundle exists.
- **Don't commit.** The user owns the commit gate.
- **Don't auto-overwrite an existing `docs/mvp/<slug>.md`** or
  blow away an existing roadmap. Read first; merge with
  explicit consent.
- **Don't draft full specs.** Step 4 produces stubs. Full specs
  belong to `/spec-phase` or `/task` Operation 3, done later
  when the phase comes up.
- **Don't pad the "in" scope.** An MVP with 10+ capabilities is
  not an MVP. Push back, even if the user resists. Naming the
  cost is your job.
- **Don't accept vague users.** "Developers" is not a user.
  Push for specificity in Step 1.
- **Don't accept "shippable = doesn't crash."** Walk the full
  shippable checklist. Each yes is a real cost; each deferred
  is a real bet.
- **Don't write rule updates silently.** If the MVP implies
  rule changes, surface them and wait for consent. Hand the
  actual write to `/codify` or `/rule-promote`.
- **Don't multiplex products.** One MVP per session.

## When NOT to use this skill

- **You want to test an idea fast.** Use `/prototype`. MVP is
  for product scoping, not feature exploration.
- **The product already exists and you want to add a phase.**
  Use `/plan` (phase shaping) and `/task` (file specifics).
- **You want to expand a phase into specs.** Use `/spec-phase`.
- **You want to understand a chaotic existing codebase.** Use
  `/wrangle` — that gives you the ground truth `/mvp` would
  otherwise have to invent.
- **You're refining a tradeoff, not scoping a product.** Use
  `/brainstorm` to capture the tradeoff space, then come back
  to `/mvp` once a direction is picked.
- **You want a marketing plan, GTM, or pricing strategy.** Out
  of scope. `/mvp` covers the product surface that has to
  exist; how it's sold lives elsewhere.

## What "done" looks like for an /mvp session

- `docs/mvp/<slug>.md` exists and is a real definition, not a
  template.
- `tasks/ROADMAP.md` and `tasks/PHASES.md` reflect the
  proposed phase plan.
- Stub task files exist in `tasks/backlog/` for every task
  identified in Step 3.
- The user has read the bundle and either signed off or
  flagged what to revise.
- The next concrete move is on the table — typically
  "`/spec-phase 0`" or "`/task` for TASK-001".
- The worktree is dirty with the new artifacts; the user
  holds the commit gate.
- No code was written.
