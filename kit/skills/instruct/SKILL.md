---
name: instruct
description: Converts a human explanation of how to do something — prose, a brain-dump, a half-formed list, anything — into an unambiguous AI-formatted instruction recipe. Decomposes the input into the smallest sensible deliverable steps, does a mock run-through to catch missing or out-of-order steps, flags every assumption inline, and returns a formatted recipe an AI (or human) can follow without guessing. A pre-task: it produces the instruction set, it does NOT execute it. Triggered when the user wants their messy instructions turned into a clean step list — e.g. "/instruct", "turn this into a step-by-step list", "break this down into steps for the AI", "make this an instruction recipe", "instruct-ify these notes".
---

# /instruct — Turn human instructions into an AI instruction recipe

A human explains how to do something the way humans do — in
prose, in a brain-dump, in a list that mixes a whole task with
half a sub-step. An AI needs the opposite: an ordered set of
atomic, verifiable instructions with no ambiguity. `/instruct`
is the converter.

It is a **pre-task**. The deliverable is the *recipe* — the
instruction set the AI will follow next. This skill never
executes the steps; it produces the contract that some later
session executes against. Same idea as `task-template.md`: a
fixed shape, always filled, tailored for AI guidance.

Per CLAUDE.md ethos: calibrated confidence. Every judgment call
made while decomposing is surfaced as a flagged assumption — the
recipe never hides a guess inside a step.

## Behavior contract

- **Read-only. Chat output.** This skill renders one recipe in
  chat. It writes no files, edits no code, commits nothing. The
  user copies the recipe into a fresh session as the AI's
  marching orders.
- **No standalone script.** All work is AI synthesis —
  decomposition and dry-run verification are judgment, not
  deterministic plumbing.
- **Accept any input shape.** Prose, a paragraph, a stream-of-
  consciousness brain-dump, a rough list, a list mixing coarse
  and fine steps — all valid. The skill's job is to normalize
  whatever it gets into one canonical shape.
- **Smallest sensible deliverable wins.** The core rule. Split
  every step until each one produces exactly one verifiable
  deliverable and splitting it further would leave a fragment
  that delivers nothing on its own. See Step 3 for the
  atomicity test.
- **No round-trips.** When the mock run-through finds a gap or
  ambiguity, the skill makes a reasonable call, bakes it into
  the recipe, and records it in the **Assumptions** section.
  It does not stop to ask. The user overrides by re-running
  with a correction.
- **Verify before finalizing.** Look the steps up — read the
  codebase, the referenced files, the relevant docs — to ground
  the recipe in reality, then do a full mock run-through
  (Step 6) before rendering. A recipe that was never dry-run is
  not finished.
- **Don't execute.** `/instruct` produces instructions; it never
  follows them. The moment the recipe is rendered, the skill is
  done.
- **Don't auto-commit.** Standard kit rule (nothing to commit
  here anyway — output is chat-only).
- **Stay in scope.** The recipe covers exactly what the input
  asked for. Adjacent ideas the user didn't ask for go in the
  **Out of scope** footer as one-liners, not as new steps.

## Process

### Step 1 — Ingest the input

Take whatever the user gave. If `/instruct` was invoked with no
content to convert, this is the **one** allowed question —
without input there is nothing to decompose:

```markdown
Give me the instructions to convert — paste them however they
exist. Prose, a brain-dump, a rough list, notes — shape doesn't
matter. I'll turn it into an atomic step recipe.
```

Otherwise, proceed. Quote the goal back in one sentence so the
user can see how you read it.

### Step 2 — Extract the atomic intents

Pull every distinct action, sub-goal, and constraint out of the
input regardless of how it was written. A single sentence may
contain three steps; a single bullet may contain half a step;
prose may bury a step inside a subordinate clause. Read for
*intent*, not for the user's formatting.

Produce an internal flat list of raw intents — not yet ordered,
not yet sized. Just "everything the user wants done."

### Step 3 — Decompose to smallest deliverables

The heart of the skill. For each raw intent, apply the
**atomicity test**:

> A step is atomic when it produces **exactly one verifiable
> deliverable** — one artifact, one state change, one decision
> — and splitting it further would leave a fragment that
> delivers nothing checkable on its own.

Split coarse intents down to that line. Examples of the split:

- "Set up the backend" → not atomic. Splits into: create the
  schema, write the migration, add the endpoint, wire the
  route, add the test.
- "Add the migration and run it" → two deliverables (the file,
  the applied state) → two steps.
- "Rename the variable" → already atomic if it's one symbol in
  one place; one step.

But do **not** over-split. If a single edit is the whole
deliverable, it is one step — don't manufacture "open the file"
/ "find the line" / "type the change" as three steps. The unit
is the *deliverable*, not the keystroke. Over-splitting a 6-step
job into 30 trivial steps is as wrong as leaving it at 2 coarse
ones.

### Step 4 — Order and wire dependencies

Sequence the atomic steps so every step's prerequisites are
satisfied by steps before it. For each step, record what prior
steps it **Needs**. If two steps are independent, order them by
natural reading order — but mark them as having no dependency
so a reader knows they can be parallelized.

### Step 5 — Look up and verify the steps

Ground the recipe in reality before trusting it. "Look up the
steps" means: read what the steps actually touch.

- If the input references files, symbols, or modules — read
  them. Confirm they exist and the step makes sense against
  the real code.
- If a step depends on a framework or external API — fetch the
  current docs (`WebFetch`) rather than relying on stale
  memory. A recipe step that names a deprecated API is a
  broken recipe.
- If the scope is broad, spawn an `Explore` agent to confirm
  the lay of the land.

The point: a step that can't survive contact with the actual
codebase should be corrected, split, or flagged now — not
discovered broken mid-execution later.

### Step 6 — Mock run-through (dry run)

Walk the ordered recipe start to finish *as if executing it*,
without executing. At each step ask:

- **Inputs present?** Does this step have everything it needs
  from the steps before it? If not — a step is missing. Add it.
- **Implicit step?** Did the human assume a step "obviously"
  happens (install a dep, create a directory, seed data)? Make
  it explicit.
- **Order right?** Does any step depend on something that comes
  later? Reorder.
- **Goal reached?** After the last step, does the end state
  actually equal the stated goal? If there's a gap between the
  last deliverable and the goal — steps are missing. Add them.
- **Dead steps?** Any step that delivers nothing the goal needs?
  Cut it.

Every change the dry run forces — added step, reorder, resolved
ambiguity — gets recorded for the **Gaps found** section.

### Step 7 — Flag every assumption inline

Anywhere decomposition required a judgment call the input
didn't settle — a naming choice, a tool choice, an ordering
decision, an assumed environment — make the call, bake it into
the recipe, and list it in the **Assumptions** section with the
reason. No round-trips. The user overrides by re-running.

### Step 8 — Render the recipe

Render the recipe in chat using the **Output structure** below.
That is the entire deliverable. Do not offer to execute it; do
not start doing the work. The skill ends when the recipe is on
screen.

## Output structure

A single recipe rendered in chat. No file written.

```markdown
# 🧭 Instruction recipe — <goal, terse>

> **Goal.** <one sentence — the end state this recipe reaches>
> **Done when.** <one verifiable condition true once every step
> is complete>
> **Steps.** <count> atomic instructions

---

## Assumptions

Judgment calls made while decomposing. The input didn't settle
these — re-run with a correction to override any of them.

- ⚠️ <assumption> — <why it was needed>
- ⚠️ <assumption> — <why it was needed>

*(If none: "No assumptions — the input was fully specified.")*

---

## Instructions

Follow in order. Each step produces exactly one verifiable
deliverable. `Needs` lists prior steps that must finish first;
steps with `Needs: —` can run in any order relative to their
peers.

### 1. <imperative action — terse>

- **Do.** <the single concrete action>
- **Produces.** <the one artifact or state change delivered>
- **Verify.** <how to confirm it's done — a concrete check, not
  a feeling>
- **Needs.** <prior step numbers, or "—">

### 2. <imperative action — terse>

- **Do.** <...>
- **Produces.** <...>
- **Verify.** <...>
- **Needs.** <...>

<!-- one block per atomic step -->

---

## Gaps found in the mock run-through

What the dry run surfaced and how the recipe above already
accounts for it.

- <gap — e.g. "input never said to install the dep"> →
  <resolution — e.g. "added as step 2">

*(If none: "Mock run-through clean — no gaps, no reordering.")*

---

## Out of scope

What this recipe deliberately does NOT cover — adjacent things
the input mentioned or implied but didn't ask for.

- <thing>

*(If none: omit this section.)*

---

*Generated by `/instruct`. This is a pre-task instruction set —
hand it to an AI (or yourself) and follow the steps in order.
Re-run with a correction if any assumption is wrong.*
```

## Style rules

- **The recipe is the kit's design language for this skill.**
  Follow the glyph discipline in `output-rules.md` — one emoji
  per role (🧭 recipe, ⚠️ assumption). Don't invent inline
  visual patterns.
- **Steps are imperative and terse.** "Create the migration
  file" — not "You should now create a migration file so that
  the schema is updated."
- **`Verify` is a check, not a vibe.** "`npm test` passes",
  "the file exists at `path`", "the endpoint returns 200" —
  something observable. Never "looks right" or "works."
- **`Produces` is exactly one thing.** If you can't name the
  single deliverable in one phrase, the step isn't atomic —
  go back to Step 3.
- **Cite files as `path:line`.** Click-through links in chat.
- **Bold the claim, then dash, then the reason.** `- **Claim**
  — reason.`
- **No "let me know if you have questions" sign-offs.** End on
  the recipe footer.

## What you must NOT do

- **Don't execute the recipe.** `/instruct` is a pre-task. It
  produces the instruction set and stops. Following the steps
  is a separate session's job.
- **Don't ask round-trip questions.** Per the behavior
  contract — gaps become flagged assumptions, not questions.
  The only allowed question is Step 1's "give me the input."
- **Don't leave steps coarse.** "Set up the backend" is a
  phase, not a step. If a step has more than one deliverable
  inside it, it failed the atomicity test — split it.
- **Don't over-split into keystrokes.** "Open the file" /
  "scroll to the line" / "type" are not three deliverables.
  The unit is the verifiable deliverable, not the action.
- **Don't expand scope.** The recipe covers what the input
  asked. New ideas go in the **Out of scope** footer as
  one-liners — never as bonus steps.
- **Don't skip the mock run-through.** A recipe that was never
  dry-run is unfinished. Step 6 is mandatory.
- **Don't bury a guess in a step.** Every judgment call is a
  visible flagged assumption. A step must read as fact.

## Edge cases

- **Input is already a clean list.** Still decompose (Step 3),
  still verify (Step 5), still dry-run (Step 6). A tidy-looking
  list is often still coarse or out of order. Say what changed;
  if genuinely nothing did, the **Gaps found** line says so.
- **Input is too vague to decompose confidently.** Produce a
  best-effort recipe, lean hard on the **Assumptions** section,
  and name in **Gaps found** exactly what information would
  sharpen it. Don't refuse — a flagged best-effort recipe beats
  no recipe.
- **Input is a single atomic action.** Then the recipe is one
  step. Say so plainly — "this is already atomic; one step" —
  rather than padding it to look substantial.
- **Input is large** (dozens of deliverables). Group the
  instructions under phase subheadings (`## Phase A — …`) so
  the recipe stays scannable, but keep every individual step
  atomic. Numbering continues across phases.
- **Input has no actionable content** (a question, an
  observation, a vent). Nothing to convert. Say so and point
  the user at the right tool — `/plan` to think it through,
  `/brainstorm` to explore it.
- **Steps touch a framework or external API.** Verify against
  current docs in Step 5. Don't recipe a deprecated API from
  memory.

## When NOT to use this skill

- **Filing a tracked task with an ID and a phase** → use
  `/task`. `/instruct` produces an ephemeral chat recipe, not a
  spec in `tasks/`.
- **Strategic / phase-level thinking** → use `/plan`.
- **Expanding a stub into a full spec** → use `/task`
  Operation 3 — that's a contract with recon, not a step list.
- **Actually doing the work** → just do it, or follow a recipe
  `/instruct` already produced. This skill never executes.
- **Exploring an open-ended problem with no defined endpoint**
  → use `/brainstorm`. `/instruct` needs a goal to decompose
  toward.

## What "done" looks like for a /instruct session

The user has one rendered instruction recipe in chat: a terse
goal, a verifiable done-condition, a flagged assumptions list,
an ordered set of atomic steps each with Do / Produces / Verify
/ Needs, the gaps the mock run-through caught, and an out-of-
scope footer. Nothing written to disk, nothing executed. The
recipe is ready to hand to an AI (or the user) as an
unambiguous, pre-verified instruction set for the next session.
