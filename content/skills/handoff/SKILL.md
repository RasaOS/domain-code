---
name: handoff
description: Snapshot in-flight project context into a single durable doc that another contributor (or future-you in six months) can pick up cold. Captures active branches, dirty working tree, in-flight tasks, blockers, recent decisions, recent postmortems, and the things you almost figured out before stepping away. Output lands at `docs/handoff/<YYYY-MM-DD>.md` AND a tight 10-15 line summary at `.claude/welcome.md` (the file Claude reads on session start). Distinct from `/onboard` (which assumes a stable, documented project) — `/handoff` is for in-flight handovers when things are unfinished. Triggered when the user is stepping away mid-project — e.g. "/handoff", "I'm going on leave", "snapshot the context", "create a handoff doc", "package what I know for the next person".
---

# /handoff — Snapshot in-flight context for a clean handover

You're stepping away — for a week, a month, or just the
weekend. This skill captures everything someone (or future-you)
needs to pick up where you left off without losing the threads
that only exist in your head right now.

Per CLAUDE.md ethos: brutally honest about what's done, what's
half-done, and what's stuck. The handoff doc's value is
proportional to its honesty about the messy parts.

## Behavior contract

- **Writes durable docs only.** Two outputs per run:
  1. **Deep snapshot** at `docs/handoff/<YYYY-MM-DD>.md` — the
     full multi-section handoff doc.
  2. **Welcome rewrite** at `.claude/welcome.md` — a tight
     10-15 line "where you left off" summary. This is the file
     Claude reads on session start (via the CLAUDE.md `@`-import).
     Always rewritten in full on each `/handoff` run.

  No source-code edits. Never auto-commits.
- **Read multiple sources, synthesize one doc.** A handoff is
  not a doc dump — it's a curated synthesis. Pull from git
  state, tasks/, docs/decisions/, docs/postmortems/, and
  recent CHANGELOG (if present).
- **Surface what's not written down.** The skill explicitly
  prompts the user for tacit knowledge ("what were you about to
  try?", "what's blocked?", "what surprised you?"). The
  doc-driven sources alone won't capture the threads that live
  in the user's head.
- **Distinct from `/onboard`.** `/onboard` assumes the project
  is stable and well-documented; it walks a newcomer through
  what exists. `/handoff` assumes the project is mid-stride
  and explicitly captures what's in flight, blocked, or unsure.
- **One handoff per day.** If `docs/handoff/<YYYY-MM-DD>.md`
  already exists, ask whether to update in place, append, or
  date-suffix.
- **Doesn't move tasks.** Tasks in `tasks/active/` stay where
  they are. The handoff describes their state; it doesn't
  reorganize them.

## Process

### Step 1 — Read the doc-driven state

In parallel:
- `git status` — uncommitted changes.
- `git branch -vv` — local branches, remote tracking, ahead/behind.
- `git log --oneline -10` — recent commits.
- `git stash list` — stashed work.
- `tasks/active/*.md` — in-flight tasks (read each).
- `tasks/backlog/*.md` — top 5 by recency, brief.
- `docs/decisions/*.md` — last 3.
- `docs/postmortems/*.md` — last 3.
- `tasks/AUDIT.md` (top of file) — last 5 shipped.
- Open PRs (via `mcp__github__list_pull_requests` or `gh pr
  list` if available) — title + state.

### Step 2 — Prompt for tacit knowledge

Render this block and wait for answers:

```markdown
The doc-driven state I can read from disk. The handoff doc
gets ~3× more useful with the threads only you know about.
Quick answers — bullet form is fine, skip questions that don't
apply.

1. **What were you in the middle of?** The thing you'd resume
   first if you came back tomorrow.
2. **What's actually blocked, and on what?** Not "I haven't
   gotten to it" — actually waiting on something/someone.
3. **What were you about to try?** Half-formed approaches that
   weren't worth committing yet.
4. **What surprised you recently?** Bugs, behaviors, anything
   that contradicted what you expected — even if you didn't
   chase it.
5. **What would you warn the next person about?** Sharp edges,
   gotchas, "don't touch that without reading X".
6. **Anything else they need to know?** Open question.
```

If the user wants to skip and just have you generate from disk
state, that's fine — note it explicitly in the doc ("tacit
knowledge not captured this round").

### Step 3 — Render the handoff doc

Write to `docs/handoff/<YYYY-MM-DD>.md` using the **Output
structure** below.

### Step 4 — Rewrite `.claude/welcome.md`

Always rewrite (don't append) `.claude/welcome.md` with a tight
summary derived from the same inputs. Keep it under ~15 lines.
This is what future Claude sessions read on start.

```markdown
# 👋 Welcome back

> First thing read on session start. Auto-updated by `/handoff`.
> For the deep snapshot, see [most recent handoff in `docs/handoff/`].

## Where I left off

<2-3 sentences from "What were you in the middle of" + state.>

## Heads up

- <one or two sharp-edge items, terse>

## Active branch

- `<branch>` — `<short SHA>` *(working tree: clean / dirty: <N> files)*

## Open PRs / in-flight tasks

- <#NNN — title> *(if any)*
- <TASK-NNN — title>

---

*Last updated by `/handoff` on <YYYY-MM-DD>. Deep snapshot:
[`docs/handoff/<YYYY-MM-DD>.md`](../docs/handoff/<YYYY-MM-DD>.md).*
```

If `.claude/welcome.md` doesn't exist yet (project pre-dates the
welcome.md template), create it.

### Step 5 — Closing summary

```markdown
# 📨 Handoff snapshot written

- **Deep snapshot.** `docs/handoff/<YYYY-MM-DD>.md` — <line count> lines.
- **Welcome.** `.claude/welcome.md` — rewritten (~<line count> lines).
  Future sessions read this on start.

**The three things most worth knowing:**
1. <terse>
2. <terse>
3. <terse>

Review with `git diff`, edit anything that misrepresents reality,
commit when ready.

If you come back to this project later, run `/onboard` first
(for the documented context), then read the most recent handoff
doc.
```

## Output structure

The handoff doc at `docs/handoff/<YYYY-MM-DD>.md`:

```markdown
# 📨 Handoff — <project name>

> **Stepping away.** <one sentence — when, why, expected return
> if known. Empty if user prefers.>
>
> **State.** <one sentence — what shape the project is in
> right now, honestly. e.g. "Mid-refactor of the auth layer;
> tests broken on `auth/v2` branch.">

**Date.** <YYYY-MM-DD>
**Branch where I left off.** `<branch>` (`<short SHA>`)
**Working tree.** <clean | dirty: N files>

---

## 🔥 Pick this up first

The thing the next session should look at before anything else.

<2-4 sentences, drawn from "what were you in the middle of"
plus any blocking issues. Specific. Cites file paths and PR
numbers.>

---

## 🌿 Branches in flight

For each non-default local branch with unpushed commits or open
PR:

### `<branch>`
- **Status:** <ahead/behind tracking, dirty/clean>
- **Open PR:** <#NNN — title, state> *(if any)*
- **What it's doing:** <one line>
- **Where you left it:** <one line>

*(Skip this section if no in-flight branches.)*

---

## 🚧 Active tasks

For each task in `tasks/active/`:

### TASK-NNN — <title>
- **State:** <one line — what's done, what's left>
- **Last touched:** <date from git log of the task file or
  source it covers>
- **Blocked on:** <if applicable>
- **Path:** [`tasks/active/<file>`](../../tasks/active/<file>)

---

## 🛑 Blockers

Things actually waiting on something or someone.

- **<short claim>** — waiting on <what/whom>. Last update:
  <date>.
- …

*(If nothing's blocked, render: "Nothing blocked right now.")*

---

## 🧪 Things you were about to try

Half-formed approaches that weren't worth committing yet but
shouldn't evaporate.

- <bullet — keep it specific enough that a fresh reader
  understands the angle>
- …

---

## 😲 Surprises worth knowing

Behaviors, bugs, gotchas that contradicted expectations during
the recent stretch. Even if not chased down.

- **<short claim>** — <where you saw it; what you'd verify
  first>
- …

---

## ⚠️ Sharp edges

Don't-touch-that-without-reading-X stuff. Things the next
person will hurt themselves on if they don't know.

- **<short claim>** — <one-line warning + pointer to docs or
  file>
- …

---

## 📜 Recent decisions

Last 3 items from `docs/decisions/`. One-line each, with link.

- [<date> — <title>](../../docs/decisions/<file>) — <one-line
  outcome>
- …

*(Skip if `docs/decisions/` is empty or missing.)*

---

## 🩹 Recent postmortems

Last 3 from `docs/postmortems/`. One-line each, with link.

- [<date> — <title>](../../docs/postmortems/<file>) — <one-line
  takeaway>
- …

*(Skip if absent.)*

---

## 📦 Recently shipped

Last 5 from `tasks/AUDIT.md`. One-line each.

- ✅ <date> — <title>
- …

*(Skip if absent.)*

---

## 🗺 Where to go for more

- [`CLAUDE.md`](../../CLAUDE.md) — working contract
- [`tasks/PHASES.md`](../../tasks/PHASES.md) — phase scope
- [`tasks/ROADMAP.md`](../../tasks/ROADMAP.md) — task registry
- Most recent prior handoff: <link if present, else "first
  handoff">

---

*Captured by `/handoff` on <YYYY-MM-DD>. Re-run anytime; each
handoff is dated and additive.*
```

## Style rules

- **Imperative, specific, cited.** "Resume by reading
  `auth/v2.ts:142` and running `npm test -- auth`." not
  "Continue the auth work".
- **Emoji are load-bearing.** 📨 (handoff), 🔥 (pick up first),
  🌿 (branches), 🚧 (active), 🛑 (blockers), 🧪 (about to try),
  😲 (surprises), ⚠️ (sharp edges), 📜 (decisions), 🩹
  (postmortems), 📦 (shipped), 🗺 (more). Don't add others.
- **Bold the claim, dash, reason.** `- **Claim** — reason.`
- **Empty sections render an honest one-liner**, not a stub.
  "Nothing blocked right now." beats an empty "## Blockers"
  bullet.
- **Cite via relative paths from `docs/handoff/`** — i.e.
  `../../foo.md` so links work when the file is opened
  directly.

## What you must NOT do

- **Don't write a generic onboarding.** That's `/onboard`'s
  job. Handoff is about *this moment* — what's broken, in
  flight, or unsure right now.
- **Don't omit the messy parts.** A handoff that says "all
  going great" is worse than no handoff. The next person needs
  the friction points.
- **Don't reorganize tasks.** Active tasks stay in
  `tasks/active/`. Don't move them to backlog or completed as
  part of handoff.
- **Don't capture secrets.** If the user mentions an API key,
  password, or credential while answering tacit-knowledge
  questions, **flag it and refuse to write it down**. Suggest
  they put it in a secret-manager note or password vault.
- **Don't auto-commit.** Same rule as every kit-write skill.
- **Don't fabricate state.** If `tasks/active/` is empty,
  say so.
- **Don't spam the project's CLAUDE.md.** This skill writes one
  handoff doc; it doesn't edit the working contract.

## Edge cases

- **No tasks/, docs/decisions/, or docs/postmortems/.** That's
  fine — the relevant sections render "Not yet — no <X> on
  disk." or are omitted. Don't fail on missing dirs.
- **Same-day handoff already exists.** Ask: update in place
  (replace), append (under a "Mid-day update" subheading), or
  date-suffix (`<date>-2.md`).
- **User skips all tacit-knowledge questions.** Render the doc
  from disk state only, and prepend a note: "*Tacit knowledge
  not captured this round — handoff is doc-driven only.*"
- **Multiple worktrees / branches with diverged state.** Surface
  each in "Branches in flight." Don't try to consolidate.
- **Project is so chaotic the user can't summarize state.**
  Suggest running `/wrangle` first to produce baseline context;
  then `/handoff` adds the in-flight layer on top.
- **The "next person" is an LLM session, not a human.**
  Same doc shape works. Optionally tell the user: "future
  sessions can be primed by reading this file alongside
  CLAUDE.md."

## When NOT to use this skill

- **Onboarding a new contributor to a stable project** →
  `/onboard`.
- **Capturing one rule** → `/codify`.
- **Capturing one decision** → `/decision`.
- **Capturing an incident** → `/postmortem`.
- **Capturing an architectural regret** → `/regret`.
- **Generating a portable project summary** → `/export-project`.
- **You haven't actually done anything in flight** — there's
  nothing to hand off. Skip.

## What "done" looks like for a /handoff session

Two artifacts on disk, uncommitted:
1. The deep dated snapshot at `docs/handoff/<YYYY-MM-DD>.md`
   — full state, doc-driven + tacit knowledge.
2. A rewritten `.claude/welcome.md` (~15 lines) that future
   Claude sessions auto-load on start via the CLAUDE.md
   `@`-import.

The user knows the next person (or next session) can read
`.claude/welcome.md` for the quick orient, then drill into
`docs/handoff/<YYYY-MM-DD>.md` for the deep state — without
you in the room.
