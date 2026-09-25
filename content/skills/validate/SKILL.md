---
name: validate
description: Re-review a finished artifact — a plan, a recipe, a spec, a user story, a change set — find every gap, fill it, and repeat until two consecutive passes come back clean, each pass using a different lens so the second is not the first asked twice. Three tiers set how hard it runs — short (in-turn, a few minutes), medium (bounded rounds, one fresh-eyes pass), long (unbounded, run under /goal, the /self-heal bar). Appended to the end of other skills (/plan, /instruct, /spec-phase, /mvp, /user-story, /mission) and runnable on its own. Triggered when the user wants work checked before it is called done — e.g. "/validate", "/validate medium this plan", "re-review the whole plan and fill the gaps", "double-check this spec", "validate that until it's clean".
---

# /validate — find the gaps, fill them, prove it twice

Most skills end the moment their output exists. `/validate` is
the step after that: re-read the *whole* artifact against the
*original ask*, find what is missing, wrong, or out of order,
fill it, and keep going until two passes in a row find nothing.

It is the extraction of what makes `/self-heal` trustworthy —
`/mission`'s two-pass re-walk — into one reusable step with a
dial for how long it runs. The rule does not change between
tiers; the depth, the lenses, and the round budget do.

Per CLAUDE.md ethos: done means *verified*, not *produced*. And a
check you ran twice the same way is one check.

## The three things that make a long run trustworthy

`/self-heal` holds up over a long run because three separate
mechanisms stack. Knowing which is which is how the tiers are cut:

| Mechanism | Where it lives | What it buys |
|---|---|---|
| **Stopping rule** — two consecutive clean passes; any gap resets the count; a run that stops converging is a blocker | `mission/SKILL.md` Step 6 → this file | "Done" is a proof, not a feeling |
| **Varied passes** — each pass uses a different lens or different mechanics | this file (§ Lenses) | Pass 2 can catch what pass 1 was structurally blind to |
| **Duration engine** — the harness `/goal` loop keeps turns going until an evaluator sees the condition in the transcript | `autonomy-rules.md` § `/goal` | The run survives many turns and compactions |

Short and medium use the first two. Only long adds the third.

## Behavior contract

- **Validates an artifact that already exists.** It never
  produces the first draft. The host skill (or the user) hands
  it a finished artifact plus the original ask it was built
  from. No artifact → nothing to validate; say so.
- **Validates against the original ask, not the artifact's own
  claims.** Re-read what the user actually asked for. An
  artifact that is internally consistent but answers a
  different question fails.
- **Two consecutive clean passes, every tier.** A pass that
  finds a gap fills it and resets the clean count to zero. The
  run is done at two clean passes in a row — or when the tier's
  round budget runs out, in which case what remains is reported
  as **residual**, never silently dropped.
- **Consecutive passes use different lenses.** A pass may not
  use the same lens as the pass before it. For work that runs
  things (tests, builds, the app), the second pass must also
  change the *mechanics* — see § Varying the mechanics. Re-running
  the identical script is a re-run, not a pass.
- **Fill, don't just list.** A gap found is a gap fixed in the
  artifact, in this run. The host skill's own consent model
  governs *how*: a skill that edits files edits them; a
  conversational skill (`/plan`, `/brainstorm`) drafts the fill
  inline and marks it **proposed** for the user to accept. A gap
  that needs a decision only the user can make is not guessed at
  — it becomes one focused question (conversational hosts) or a
  flagged assumption (autonomous hosts, per `autonomy-rules.md`).
- **Stay in scope.** A gap is something the original ask needs
  and the artifact lacks. An idea the ask did not call for goes
  in the report's **Out of scope** line, not into the artifact.
  Validation that grows the artifact past its ask has failed.
- **Inherits the host's permissions.** `/validate` adds no
  write, commit, or network rights the host skill does not
  already have. Run standalone, it is report-and-fill on the
  artifact the user pointed at, nothing else.
- **Surfaces evidence, not verdicts.** Each pass records what it
  looked at and what it found. "Pass 2 clean" with no evidence
  is not a pass. At the long tier this is load-bearing: the
  `/goal` evaluator reads only the transcript.

## Tiers

The host skill names its default tier. The user overrides with
the tier word anywhere in the request ("validate long", "just a
short validate", "skip validation" — the last is honored and
noted in the host's output as `Validation: skipped by request`).

| | **short** | **medium** | **long** |
|---|---|---|---|
| **For** | a single recipe, story, or small plan | a plan, a phase of specs, an MVP bundle | a whole goal executed end to end (`/mission`, `/self-heal`, `/self-improve`) |
| **Wall-clock** | minutes, in the same turn | one sitting | hours; many turns |
| **Lenses** | two from the core set, alternating | three or more, at least one **fresh-eyes** pass | the full catalog, rotated; mechanics varied every pass |
| **Round budget** | 2 resets, then report residual | 4 resets, then report residual | unbounded — stops only on convergence or a non-convergence blocker |
| **Runs things** | no — reads and reasons | only reads the codebase to check claims (**reality**) | yes — builds, tests, the app, per the project's verification commands |
| **Under `/goal`** | no | no | yes, by design |

The round budget is the difference between short and long, not
the standard. All three tiers require two consecutive clean
passes to report `clean`; short and medium are allowed to stop
early and say `residual`, long is not.

## Lenses

A lens is a different question asked of the same artifact.
Rotating lenses is what makes the second pass independent of the
first. Name the lens in each pass's row of the report.

**Core set** (every tier may use these):

1. **Forward walk** — execute it in your head from the first
   step to the last. At each step: are its inputs produced by an
   earlier step? Is there an implicit step nobody wrote down? Is
   anything out of order? (This is `/instruct` Step 6.)
2. **Backward from done** — start at the done condition. What
   must be true just before it? Which step makes that true?
   Keep walking back to the start. Any link with no step behind
   it is a gap.
3. **Requirements trace** — list every requirement in the
   original ask. Each one maps to part of the artifact; each part
   of the artifact maps back to a requirement. An unmapped
   requirement is a gap; an unmapped part is scope creep.

**Extended set** (medium and long):

4. **Reality** — re-read the files, symbols, docs, and commands
   the artifact names. Does each exist, and does it behave the
   way the artifact assumes?
5. **Pre-mortem** — it is three months later and this failed.
   Write the three most likely reasons. Each one the artifact
   does not already guard against is a gap.
6. **Edges** — empty input, the error path, the second run,
   rollback, permissions, concurrency, the migration, the user
   who does it out of order.
7. **Fresh eyes** — spawn a subagent (`Explore` for read-only
   targets, `general-purpose` otherwise) with *only* the original
   ask and the artifact — no conversation history — and ask it
   for gaps. It cannot inherit the author's blind spots because
   it never had them.
8. **Stakeholder swap** — read it as the person who has to run
   it, the reviewer who has to approve it, and the next session
   that has to resume it cold.

A lens that finds nothing on this artifact is still a valid
clean pass — as long as it was actually applied and the report
says what it checked.

## Varying the mechanics

For work that is executed and not only read (long tier, and
`/mission`'s re-walk), a different lens is not enough — the two
clean passes must also differ in *how* things are run, so a
passing result is not an artifact of one setup. Vary at least one
of these between consecutive passes:

- **Build state** — incremental build vs clean build / fresh
  checkout / cleared caches.
- **Test selection and order** — the full suite vs the tests
  nearest the change first; default order vs reversed or
  shuffled where the runner supports it.
- **Entry point** — through the UI vs through the API vs through
  the CLI; the path a new user takes vs a returning one.
- **Data** — seeded fixtures vs empty state vs a realistic
  larger dataset.
- **Who is checking** — you vs a fresh-eyes subagent that is
  handed only the goal and told to verify it independently.

Record which mechanics each pass used. Two passes whose mechanics
columns match are one pass.

## Process

### Step 1 — Pin the target

Name three things before the first pass, in the output:

- **The artifact** — what is being validated (the plan as
  settled, the recipe, the spec files, the branch diff).
- **The original ask** — quoted or tightly paraphrased from the
  user, not from the artifact.
- **The tier** — the host's default or the user's override.

### Step 2 — Run a pass

Pick a lens (and, when executing, a mechanics set) that differs
from the previous pass. Apply it to the whole artifact — not the
part that was just edited. A gap filled in section 3 can open one
in section 7.

Each pass yields one row: pass number, lens, mechanics (if any),
what it checked, gaps found, gaps filled.

### Step 3 — Fill every gap the pass found

Fill each gap in the artifact per the host's consent model (see
Behavior contract). Then reset the clean count to zero and go
back to Step 2 with a different lens.

A gap that cannot be filled from here (needs a user decision, an
external dependency, a gated file) is recorded as **open** with
the reason. It does not reset the count by itself, but it is
always listed in the report.

### Step 4 — Stop

- **Clean** — two consecutive passes found zero gaps. Done.
- **Residual** (short / medium) — the round budget ran out.
  Stop, list every unfilled gap as residual.
- **Non-convergence** (long) — successive passes keep surfacing
  the same gaps with no progress, or each fill keeps opening a
  new gap of the same kind. Stop and report it as a blocker: a
  loop that will not converge is a finding about the artifact
  (usually a missing decision), not a reason to keep spinning.

### Step 5 — Render the validation block

Append it to the host skill's output (or render it alone when run
standalone). Shape below.

## Output structure

```markdown
## ✓ Validation — <tier> · <clean | residual | blocked> after <N> passes

> **Artifact.** <what was validated>
> **Against.** <the original ask, one line>

| # | Lens | Mechanics | Checked | Gaps | Filled |
|---|------|-----------|---------|------|--------|
| 1 | Forward walk | — | 9 steps, inputs + order | 2 | ✓ 2 |
| 2 | Requirements trace | — | 5 asks ↔ 9 steps | 1 | ✓ 1 |
| 3 | Backward from done | — | done → step 1 | 0 | — |
| 4 | Fresh eyes | subagent, ask + artifact only | whole plan | 0 | — |

**Filled.**
- <gap> → <what changed in the artifact>

**Open / residual.** *(omit if none)*
- <gap> — <why it could not be filled here; what would close it>

**Out of scope.** *(omit if none)*
- <idea the ask did not call for>
```

Use `✗` in the heading instead of `✓` when the result is
`residual` or `blocked`. Keep the table even when the result is
clean on passes 1 and 2 — the evidence is the point.

## Style rules

- Glyphs per `output-rules.md`: `✓` filled / clean, `✗`
  residual / blocked. Don't invent more.
- **Checked** is concrete — counts, names, paths, exit codes.
  Never "looked good".
- One row per pass. Don't merge passes to make the table shorter.

## What you must NOT do

- **Don't repeat a lens back to back.** Pass N and pass N+1 use
  different lenses — the whole mechanism depends on it.
- **Don't re-run the same script and call it a second pass.** At
  the executing tiers, vary the mechanics or it does not count.
- **Don't validate against the artifact.** Validate against the
  original ask. An artifact agreeing with itself proves nothing.
- **Don't only re-check the part you just edited.** Every pass
  covers the whole artifact.
- **Don't expand scope.** Filling a gap is not adding a feature.
- **Don't loop forever.** Short and medium stop at their budget;
  long stops at non-convergence. Both report what is left.
- **Don't exceed the host's permissions.** `/validate` inside
  `/plan` does not edit PHASES.md; inside `/instruct` it writes
  no files.

## Edge cases

- **The first two passes are clean.** Fine — report
  `clean after 2 passes`. Don't manufacture gaps to look
  thorough.
- **The artifact is tiny** (one step, one sentence). Run the
  short tier with two lenses and say it was trivially clean.
- **The user asked for long on a plan.** Honor it: run the full
  lens catalog with no round budget, but without `/goal` —
  nothing is being executed, so there is nothing to loop turns
  on. Say so.
- **A gap's fill needs the user** in an autonomous host. Per
  `autonomy-rules.md`: decide, flag it as an assumption, keep
  going. In a conversational host: ask the one question, then
  finish the remaining passes after the answer.
- **Fresh-eyes subagent unavailable.** Substitute the
  stakeholder-swap lens and note the substitution in the row.

## Running the long tier under `/goal`

A skill cannot invoke `/goal`; the user runs the host under it
(see `autonomy-rules.md`). Write the condition so the evaluator
can see it in the transcript — this file's validation block is
exactly that surface:

```bash
claude -p "/goal /self-heal auth flow — done when the Validation
block reads 'long · clean' with two consecutive passes whose Lens
and Mechanics differ; stop and report at a hard gate; stop after
40 turns"
```

## Which skills append this, and at what tier

| Host | Default tier | Where it runs |
|---|---|---|
| `/instruct` | short | after the mock run-through, before rendering |
| `/user-story` | short | before rendering the story |
| `/plan` | medium | when a planning decision is settled, before hand-off |
| `/spec-phase` | medium | after every stub is expanded, before the working order |
| `/mvp` | medium | after the bundle is written, before iterate-or-close |
| `/mission` (and so `/self-heal`, `/self-improve`) | long | Step 6, the two-pass re-walk |

Adding a host is one short step in its Process that names the
tier and says what the artifact and the original ask are.

## When NOT to use this skill

- **Nothing exists yet** → run the skill that produces it first.
- **You want the codebase swept for bugs** → `/self-heal`. That
  is `/validate`'s long tier aimed at a whole system, with fixes
  committed as tasks.
- **You want a line-by-line quality critique** → `/review`.
- **You want a PR accepted or rejected** → `/peer-review`.
- **You want to know how big a change really is** →
  `/scope-check`.

## What "done" looks like for a /validate run

The artifact has been re-walked against the original ask with a
different lens each pass, every gap found was filled (or listed
as open with its reason), and a validation block shows the passes
as evidence: `clean` after two consecutive clean passes, or an
honest `residual` / `blocked` with exactly what is left.
