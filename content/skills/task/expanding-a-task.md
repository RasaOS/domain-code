# Expanding an outline into a full task

> Loaded on demand by `/task` for one operation. Everything else in the
> lifecycle is in `SKILL.md`; nothing here applies to filing, moving,
> finishing or closing a task.

An outline says *what* somebody wants. A full task is the contract
between the person planning the work and the person doing it: a worker
should be able to read only the task file, with no memory of the
conversation that produced it, and act. Every question the planner
answers here is a question the worker does not have to come back and
ask.

The reason this is slow is that it is doing the reading once instead of
twice.

## Depth is derived, not declared

A task counts as full-depth when it has an `## Acceptance criteria`
heading holding at least one `- [ ]` item with real text after the
checkbox. There is no depth field to set. When you finish step 11, the
views stop showing `📝` against it on their own.

## The two paths

Eleven steps. Every path runs all of them except step 7, which is
conditional. The numbering is contiguous so this map cannot drift from
the headings below.

- **Ordinary work** — narrow changes, clear corrections, small
  additions: **1 → 2 → 3 → 4 → 5 → 6 → 8 → 9 → 10 → 11.** Skip 7.
- **Consequential work** — anything that changes a canonical or
  authoritative artifact, anything cross-party, anything staged,
  anything that is hard to undo: **1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 →
  10 → 11.**

If you are unsure which path applies, it is the consequential one.

**Step 11 is the only step that writes anything.** A run that stops at
step 10 has left the outline untouched on disk, whatever the
conversation felt like. Do not stop early.

---

## Step 1 — Read the outline

Read the whole file, not the title. Quote the title and the one-line
intent back to the user and confirm you are on the right task. If the
outline contradicts itself, say so now.

## Step 2 — One task, or several?

Ask yourself:

- Are there two or more independent pieces of work here?
- Could they finish at different times?
- Do they touch unrelated artifacts?

Two yeses means propose a split. *"Draft the clause"* and *"add the
clause to the standing playbook"* are one task — one artifact, one
delivery. *"Draft the clause"* and *"reorganize the whole precedent
folder"* are two.

**Propose; do not perform.** If the user agrees to split, file the new
tasks through the normal `/task` path, each as an outline, and continue
expanding only the one they asked for.

## Step 3 — What this project already does

Read, in parallel:

- **`CLAUDE.md`** — what this project is, what is protected, where the
  done-gate lives, the rules that apply everywhere here.
- **`.claude/task-rules.md`**, and any
  `.claude/<domain>-task-rules.md` extension.
- **Anything the outline names** — a document, a template, a prior
  piece of work. If it is referenced, read it.

Write down: how this project shapes this kind of artifact (structure,
naming, layout), which constraints apply, and which artifacts are
protected and need permission before they are touched.

## Step 4 — Precedent

Find work in this project of the same shape as what is being asked for,
and plan to match it. If the task is "add another care pathway", read
an existing pathway. If it is "add a chapter", read the chapters either
side of it. If it is "add a clause", find the closest comparable one.

You are looking for three things: the shape the project uses, the
naming and layout conventions actually in practice (as opposed to the
ones documented), and anything reusable that already exists.

The goal is that no decision in the finished task is arbitrary.

## Step 5 — What has already been tried

Do not re-run a failure someone already paid for.

- **`tasks/completed/` and `tasks/closed/`** — similar work that
  finished, and similar work that was abandoned. A `closed/` task with
  `resolution: wont-do` and a reason in `## Notes` may be the single
  most valuable file in the ledger for this step: someone already
  decided not to do this, and said why.
- **`tasks/active/`, `tasks/review/`, `tasks/blocked/`** — work in
  flight on the same artifacts. Say so and coordinate; a blocker
  sitting on one of them may be about to become yours. If one of them
  must finish before this task can even begin, that is a `needs:`
  entry, not a note — carry it to step 11.
- **Any decision or incident notes this project keeps** — read them if
  they exist; do not assume a location.

Write down: prior attempts and how they went, pitfalls, work in flight
that collides with this, and any decision already taken that constrains
the approach.

## Step 6 — Read the current authority

Your recollection of the authority this work turns on is stale by
construction. A statute is amended, a guideline is revised, a style
bible is updated, an interface changes.

**Identify the one or two authorities this task hinges on, and read
their current text for the specific points the task depends on.** Not
the whole corpus — the points. Capture each with a citation precise
enough that the worker can re-find it without repeating your search.

Which authority, and how to reach it, is this project's business and
lives in `.claude/<domain>-task-rules.md`, never here. Shapes it takes:
the controlling statute or regulation as it currently stands; the
current clinical protocol for the affected pathway; the present state
of the story bible and timeline the work must stay continuous with; the
current form of the interface the work must fit.

From each source, capture: what it says now, what approach it endorses,
what it has superseded or withdrawn, and any precondition it imposes.

## Step 7 — Validate the approach (consequential work only)

Before writing anything, put the approach on the table:

```markdown
## Proposed approach — TASK-N

<one line: what will change, and into what>

**Why this way**
- matches the precedent at <where>
- does not collide with <constraint from step 3 or 5>
- leaves room for <what comes after>

**Checks** (answer each yes / no / not applicable)
- [ ] Changes an authoritative or protected artifact?
- [ ] Scale or volume implications?
- [ ] Hard to reverse?
- [ ] Needs a second party's sign-off beyond the usual gate?
- [ ] Blocks, or is blocked by, another task?  <if yes, name the ids>
- [ ] Needs to land in stages?

**Risks** <if any>

Does this hold up?
```

Wait for an answer. If the user wants a different approach, go back to
step 4 and come forward again. Do not proceed on silence.

A yes to *"blocked by another task"* is the one check here that has a
field waiting for it. Get the ids now; step 11 writes them into
`needs:`. A yes to *"blocks another task"* does **not** get recorded on
this task — there is no `blocks:` key, because it is the inverse of
`needs:` and derived. It belongs on the other task, as its own
`needs:`, and only with that task's owner in agreement.

## Step 8 — Show the context report

The user sees this **before** any task text is drafted, so they can
correct your read of the territory while correcting it is still cheap.

```markdown
## Context — TASK-N

### How this project does this (step 3)
- **Shape:** <structure, naming, layout for this kind of artifact>
- **Constraints:** <protected artifacts, ownership, project rules>

### Precedent (step 4)
- <the existing piece at <where> that this will match>
- <reusable material at <where>>

### Already tried (step 5)
- **Prior work:** TASK-M, <when>. Outcome: <what happened>. Lesson: <what>.
- **Pitfall:** <the specific thing that went wrong before>
- **In flight:** TASK-K touches <artifact>. Sequencing: <what to do>.
- **Must finish first:** TASK-J — <why this cannot begin until it does>
- **Standing decision:** <what was decided, when, and why>

### What exists here now
- <artifact, where — one line>

### Where this connects
- <the seam, where — what passes across it>

### The authority says (step 6)
- **<source> · <point>** — <what it says now>. Cite: <where>
- **Caution** — <what it warns against or has withdrawn>. Cite: <where>

### Open questions
- <what none of the above settles>
```

Wait. An empty section is a signal, not a formality: if "Already tried"
is empty because step 5 found nothing, say that; if it is empty because
you skipped step 5, go back.

## Step 9 — Drill the acceptance criteria

This is the part that decides whether the task is worth anything.

- **Each criterion is one observable outcome**, stated so that a second
  person can say yes or no without asking what was meant. Not "the work
  is good". Not "it is finished".
- **Name the edge cases** this particular work has: empty, maximum, the
  error path, the boundary. Generic edge cases are not edge cases.
- **Name what must not change.** Which artifact is off limits, which
  convention holds, which limit must be respected, what must keep
  working as it does today.
- **Map each criterion to the gate.** For every criterion, say how it
  gets checked, using only what `.claude/done-gate.md` actually
  provides. If a criterion has no check available in the gate, that is
  a finding — raise it rather than inventing a mechanism.

Push back on vague answers. *"Make it clear"* is not a criterion.
*"One paragraph per party, no boilerplate, signature block last,
matching the existing intake summary"* is.

## Step 10 — The questions only the user can answer

Scan the draft in your head for judgement calls that the precedent does
not settle, the authority does not settle, and you have no standing to
settle. Every one you leave is a question the worker will have to come
back and ask.

The recurring kinds:

- **Naming, wording, preference between two valid options.**
- **Audience.** Who reads this, at what level, in what register.
- **A genuine trade-off** where precedent shows both paths in use.
- **How the world actually behaves** — volumes, timing, what people do
  in practice, which the material cannot tell you.
- **Constraints from outside this project** — an agreement, a deadline,
  another party's schedule.

```markdown
## Before I write this — questions only you can answer

1. <a specific question, with two or three concrete options>
2. <a specific question, and what is at stake in getting it wrong>

If all of this is settled, say "write it".
```

If there are genuinely none, say so in one line — *"No open judgement
calls; everything is grounded in the precedent and the authority."* Do
not manufacture questions to look thorough.

## Step 11 — Write it

1. Show the full task text and get a yes.
2. **Write it into the existing task file**, over the outline. Use the
   shape of `.claude/task-templates/<type>.md`. Do not create a second
   file; the id, the created date and the attribution are already on
   disk and must not be reissued.
3. **Write `needs:` if steps 5 and 7 found one.** Same edit, same
   moment — one line in the frontmatter, a flow list of the ids that
   must finish first:

   ```yaml
   needs: [TASK-LIT-038]
   ```

   This is the one frontmatter key you may write by hand; `SKILL.md`
   **Declare a dependency** has the full rule and the errors it can
   raise. Do it here, in the same edit as the body, so one `--fix`
   covers both. Only ids the user agreed to — an expansion is not a
   licence to impose an order on someone else's queue.
4. **Run `.claude/bin/check-tasks --fix`** so `updated` moves to today
   and the new content is accepted as current. A file this size that
   leaves the date behind is a hard validator error, and it is the one
   thing about this operation that is easy to forget. If it reports
   I-26 or I-27 against your `needs:`, `--fix` cannot repair either —
   an id is wrong, and only you and the user know which.
5. Tell the user: the path, that the task is now full-depth, and any
   `needs:` you recorded.

The finished file carries, at minimum:

- the H1, unchanged: `# <id>: <title>`
- **what this is and why** — a worker with no context starts here
- **`## Acceptance criteria`** — the list from step 9, each item a
  `- [ ]` with real text
- **how each criterion gets checked**, by reference to
  `.claude/done-gate.md` — never a written-out check
- **what changes** — every artifact, each with what changes about it
  and which criterion it serves. The list is exhaustive: a worker who
  needs to touch something outside it updates the task first.
- **what was read** — the precedent from step 4 and the authority from
  step 6, with citations
- **open questions and risks** — whatever step 10 did not close
- **`needs:`**, when another task must finish first — in the
  frontmatter, not only in the prose. A dependency stated in a
  paragraph is invisible to the validator and to every view; stated in
  `needs:` it is checked for existence and for loops, and it shows up
  against this task in `/backlog` and `/roadmap`.

And only when they apply: why this approach over the alternative; what
this one blocks, in prose (there is no `blocks:` key — it is derived);
scale limits; checkpoints along the way; a staged order of landing;
audience constraints; what breaks for existing users and what to do
about it.
