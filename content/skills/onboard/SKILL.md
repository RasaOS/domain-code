---
name: onboard
description: Onboard a new contributor (or future-you) to this project. Synthesizes README, CLAUDE.md, task-rules, PHASES, ROADMAP, AUDIT into a guided "where to start" walkthrough — what the project is, how it's built, how work flows, what's shipped, what's next, and the first concrete things to do. Triggered when the user wants an onboarding read — e.g. "/onboard", "I'm new here, walk me through this", "onboard a new contributor", "where do I start".
---

# /onboard — Guided onboarding

Synthesize the project's docs into a clear, ordered walkthrough
for someone landing in this repo cold. Not a doc dump — a
*sequence*: what to know first, what to know next, what to do
first.

Per CLAUDE.md: honest. If a doc is missing or contradictory,
flag it (and route a fix through `/update-docs`). Don't paper
over gaps.

## Behavior contract

- **Read the canonical sources, in order:**
  1. `README.md` — the public front door.
  2. `CLAUDE.md` — the working contract (tech stack, conventions,
     gotchas).
  3. `.claude/task-rules.md` — execution rules.
  4. `tasks/PHASES.md` — phase-level scope.
  5. `tasks/ROADMAP.md` — phase + task registry.
  6. Top of `tasks/AUDIT.md` — most recent shipped work + recent
     rule changes.
  7. The skill index (`.claude/skills/*/SKILL.md`) — what tools
     are available.

  Any of these may be absent; render the section without them
  rather than guessing.

- **Render as a guided walkthrough, not a digest.** Group by
  "what you need before you do anything" → "how the work
  actually flows" → "what's shipped + in flight" → "your first
  concrete steps". The reader follows the sections in order.

- **Cite, don't paraphrase.** When the project's `CLAUDE.md`
  has a tight rule, quote it (≤2 lines) and link to it. The
  reader needs to know where the rule lives, not your retelling.

- **Tell them how to ask for help.** Surface the relevant skills
  (`/stuck` for "I'm lost", `/status` for "where do things stand",
  `/backlog` for "what could I pick up").

- **Don't lecture.** Be specific. "Read X. Run Y. Open Z."
  The reader wants to be productive in 30 minutes, not entertained.

- **Don't skip honesty about rough edges.** If the project has
  documented gotchas (env-var symlinks for worktrees, version
  pins, schema discipline), they go in the walkthrough — not the
  appendix.

## Output structure

```markdown
# 👋 Welcome to <project name>

> **What this is.** <one-sentence read of the project from the
> README / CLAUDE.md. Not marketing — actual purpose.>
>
> **Where it's at today.** <one sentence — current production
> version + active phase + roughly what's in flight, from
> PHASES.md / AUDIT.md.>

---

## 1. What you need first

A 60-second tour of the constraints that matter before touching
code. Pulled from `CLAUDE.md`.

- **Tech stack.** <from CLAUDE.md — the "Tech stack" section, terse>
- **Required toolchain.** <Node version, Python version, Xcode
  version, etc. — from `.nvmrc` / `.tool-versions` / docs>
- **Hard rules to know now.** <2–4 bullets. Schema discipline,
  gated files, anything that will trip a newcomer.>
- **Where data lives / who owns it.** <if relevant — e.g. "iOS
  owns the schema; field names are byte-identical to Realm
  classes">

---

## 2. Get it running locally

Pulled from `README.md` + `CLAUDE.md` "Local dev" section.

```sh
<exact clone / install / env-setup / dev commands, copy-paste
ready>
```

**Gotchas to know:**
- <e.g. ".env is gitignored — symlink it for worktrees">
- <e.g. "nvm use must be sourced explicitly in non-interactive
  shells">
- …

If a step doesn't work for you, that's a real bug — say so
rather than working around it silently.

---

## 3. How work flows here

Pulled from `.claude/task-rules.md` + the available skills.

The shape of work in this repo, in one paragraph: <e.g. "Tasks
are filed in `tasks/backlog/` as stubs, expanded to full specs
when picked up, moved to `tasks/active/` while in-flight, then
to `tasks/completed/` after merge. One task = one PR. Every task
has a paired E2E spec.">

**Day-to-day commands:**
- `/status` — "where do things stand"
- `/backlog` — "what could I pick up"
- `/roadmap` — "what's the bigger plan"
- `/task` — file or organize tasks
- `/stuck` — when you can't see the next step
- `/build`, `/run` — verify + launch locally
- `/release` — cut a production release (gated)

**Skills index (full list):** see [`.claude/skills/`](.claude/skills/)
or run `/skills`.

**Hard rules — the three that bite first:**
1. <pull the most-likely-to-bite rule from task-rules.md, ~1 line>
2. <…>
3. <…>

---

## 4. What's been built + what's next

Pulled from `tasks/PHASES.md`, `tasks/ROADMAP.md`, top of
`tasks/AUDIT.md`.

**Shipped recently:** <last 3–5 entries from AUDIT, terse>

**Active phase:** *<Phase N — name>*
> <scope paragraph from ROADMAP.md, quoted>

Tasks in flight or queued under it: *(top 5)*
- TASK-NNN — <title>
- …

**Next phase:** *<Phase N+1 — name>* — <scope, one line>

For the full picture, run `/roadmap`.

---

## 5. Your first concrete steps

A specific order, not generic advice.

1. **Read [`CLAUDE.md`](CLAUDE.md) end-to-end.** It's the
   working contract — every gotcha is in there.
2. **Read [`.claude/task-rules.md`](.claude/task-rules.md).**
   Know the rules before you propose a change.
3. **Run the project locally** with the commands in section 2.
   If anything breaks, file it as a real bug, don't paper over.
4. **Run `/status`** to see where things stand.
5. **Run `/backlog`** and pick a stub that interests you. Ask
   the user before claiming anything from `active/`.
6. **For your first task:** pick something tagged simple /
   small. Open it as a draft PR early — feedback comes faster
   that way.

---

## 6. Asking for help

- **"I'm lost on a problem"** → `/stuck`. Walks through it
  with you.
- **"Did I miss a doc?"** → `/update-docs` to reconcile.
- **"How do I X in this codebase?"** → ask directly; don't
  go through a skill. Be specific.

The contract is honest reporting both ways. If you don't know,
say so. If you disagree with a rule, say why — `task-rules.md`
isn't sacred, but it's the current contract until we change it
together.

---

## ⚠️ Doc gaps I noticed *(if any)*

*(Only render this section if the docs were genuinely
incomplete or contradictory. Otherwise skip it. Reader doesn't
need a clean-bill statement.)*

- <gap with file path — e.g. "README.md install steps don't
  mention the .env symlink for worktrees, which CLAUDE.md
  documents">
- …

To address these, run `/update-docs`.
```

## Style rules

- **Imperative voice.** "Read X. Run Y. Open Z."
- **Real commands, not placeholders.** If `CLAUDE.md` documents
  `npm run dev`, the walkthrough says `npm run dev` — not
  `<run dev server>`.
- **Quote, don't paraphrase, the rules.** "From task-rules.md:
  <quoted line>".
- **Markdown links to source docs.** Reader can click through.
- **Section numbers (1–6).** They're a sequence, not a list.

## What you must NOT do

- **Don't extrapolate beyond what's documented.** If a section
  isn't in `CLAUDE.md`, don't fill it from training data. Note
  the gap.
- **Don't recommend rule changes inside this skill.** That's
  `/plan` or just a normal conversation.
- **Don't list every task** — top 5 is enough; full registry is
  `/roadmap`.
- **Don't pad.** Sections that don't have content (no doc gaps,
  no second phase yet) get omitted entirely.

## When NOT to use this skill

- **Already onboarded** → `/status` for current state, `/backlog`
  for what to pick up.
- **One specific question** ("how does auth work here?") → ask
  directly; don't run the full walkthrough.
- **Doc reconciliation** → `/update-docs`.
- **Project setup from scratch** (no docs exist yet) → this skill
  needs source docs. If they don't exist, `/plan` or just a
  conversation makes more sense.

## What "done" looks like for an /onboard session

A single rendered walkthrough. The newcomer reads it top-to-bottom
in ~10 minutes, knows what the project is, how to run it, how
work flows, what's shipped, and what their first 3–5 concrete
moves are. No file edits, no commits.
