---
name: export-project
description: Produce a single beautifully-formatted markdown export that summarizes the entire project — identity, tech stack, architecture, data model, current phase, recent work, in-flight tasks, skills available, and how to run it. Pulls from README.md, CLAUDE.md, PHASES.md, ROADMAP.md, AUDIT.md, foundation.json, recent commits, and `.claude/skills/`. Output lands at `docs/exports/<YYYY-MM-DD>-<repo>.md` with visual rhythm (hero block, badges, section dividers, callouts) so it reads well as a standalone document. Triggered when the user wants a portable project summary — e.g. "/export-project", "export the project", "give me a single doc that explains everything", "I need a one-pager for someone external".
---

# /export-project — Single-doc project export

Synthesize everything the kit knows about a project into one
polished markdown document. Designed to be read by someone
landing cold (a new contributor, a stakeholder, future-you in
six months) without needing to click through the rest of the
repo.

Per CLAUDE.md ethos: honest, specific, no marketing voice. A
beautiful document that says nothing concrete is worse than a
plain one that does.

## Behavior contract

- **Writes durable docs only.** Output lands at
  `docs/exports/<YYYY-MM-DD>-<repo-name>.md`. No source-code
  edits. Never auto-commits.
- **Pull from canonical sources, in order:**
  1. `README.md` — public identity.
  2. `CLAUDE.md` — working contract, tech stack, conventions.
  3. `tasks/PHASES.md` — phase scope.
  4. `tasks/ROADMAP.md` — phase + task registry.
  5. `tasks/AUDIT.md` — recent shipped work.
  6. `.claude/foundation.json` — kit pin + overrides.
  7. `.claude/skills/*/SKILL.md` frontmatter — available
     skills.
  8. `git log --oneline -20` — recent commit signal.
  9. Lockfiles / manifests (`package.json`, `Cargo.toml`,
     Xcode project, `pyproject.toml`, etc.) — actual
     dependency truth.
- **Honest absences.** If `CLAUDE.md` is missing, the export
  says so explicitly — don't substitute README content into a
  CLAUDE.md-shaped section.
- **Cite, don't paraphrase rules.** When `CLAUDE.md` has a
  tight rule, quote it (≤2 lines) with a markdown link.
- **Visual rhythm matters.** This is the one skill where design
  load-bearing matters — the export is meant to be read, not
  scanned for one fact. Use the structure below exactly.
- **Same export, different audiences.** The doc is one
  artifact. If the user wants a stakeholder-only or
  contributor-only version, they ask separately — don't
  branch the template.
- **Don't extrapolate.** No invented architecture diagrams, no
  fictional roadmap items. Everything in the export is sourced
  from a file on disk, with a citation.

## Process

### Step 1 — Resolve the repo identity

- Repo name → from `git rev-parse --show-toplevel | basename`
  or `package.json` name.
- Short SHA → `git rev-parse --short HEAD`.
- Today's date → `YYYY-MM-DD`.
- Detect tech stack from manifests (one or more of: Node, Python,
  Rust, Go, Swift/Xcode, Java/Gradle, etc.).

### Step 2 — Read the canonical sources

Read each source file listed in the behavior contract. Note any
that are absent or empty.

For larger projects, spawn an `Explore` agent to enumerate
`tasks/active/`, `tasks/backlog/`, and `docs/decisions/`. Read
the highest-leverage files yourself.

### Step 3 — Detect what's worth highlighting

- **Active phase** from `PHASES.md` + `ROADMAP.md`.
- **Top 3 in-flight tasks** from `tasks/active/`.
- **Last 3 shipped items** from `tasks/AUDIT.md`.
- **Most-recent decision** from `docs/decisions/` (if present).
- **Available skills** from `.claude/skills/*/SKILL.md`
  frontmatter.

### Step 4 — Render the export

Write to `docs/exports/<YYYY-MM-DD>-<repo>.md` using the
**Output structure** below. Substitute every bracketed
placeholder with real content. Omit sections that genuinely
don't apply (e.g. no UI layer in a CLI tool); don't stub them.

### Step 5 — Closing summary

Render in chat (this is short — the artifact is the export
itself):

```markdown
# 📤 Project export written

`docs/exports/<YYYY-MM-DD>-<repo>.md` — <line count> lines, <approx
word count> words.

**Headline.** <one sentence echoing the export's TL;DR>

**Sources.** <list which canonical files were available and which
were absent>

Review with `git diff`, edit anything that misrepresents the
project, and commit when ready.
```

## Output structure

The export file at `docs/exports/<YYYY-MM-DD>-<repo>.md`:

```markdown
<div align="center">

# 📦 <Repo name>

> <one-sentence read of what this project is, from CLAUDE.md or
> README.md>

`<short SHA>` · <YYYY-MM-DD> · <branch>

**`<tech-stack-1>`** · **`<tech-stack-2>`** · **`<tech-stack-3>`**

</div>

---

## 🎯 At a glance

| | |
|---|---|
| **What it is** | <one-line purpose> |
| **Current phase** | <Phase N — name> |
| **Pinned to kit** | <kit SHA> *(last synced <date>)* |
| **Active tasks** | <count> in flight, <count> in backlog |
| **Shipped recently** | <count> items in last 30 days |

---

## 🧭 What this project is

<2-4 paragraph synthesis of README.md + CLAUDE.md project intent.
Not marketing. Specific.>

> **From CLAUDE.md:**
> > <quote the most important contract line — typically the
> > project's central design rule>

---

## 🛠 Tech stack & how it's built

**Languages & runtimes**
- <e.g. TypeScript 5.4, Node 20.x>
- <e.g. Swift 5.10, iOS 17+>

**Key dependencies** *(top 5-10, from manifests)*
- `<package>` — <one-line role>
- …

**Architecture in one paragraph**
<Pulled from CLAUDE.md "Architecture" section, or synthesized
from directory structure if the doc doesn't have one. Honest
about which.>

**Where data lives**
<Schema source, persistence, who owns the schema. From CLAUDE.md
or skip if N/A.>

---

## 🚀 How to run it locally

```sh
<exact clone / install / dev commands from README.md or CLAUDE.md>
```

**Gotchas worth knowing**
- <e.g. ".env is gitignored — symlink it for worktrees">
- <only real ones from the docs; don't fabricate>

---

## 📍 Where things stand

### Active phase: *<Phase N — name>*

> <quote from ROADMAP.md or PHASES.md>

### In flight *(top 3)*
- **TASK-NNN** — <title> *(brief one-line state)*
- …

### Shipped recently *(last 3)*
- ✅ **<title>** — <one-line outcome> *(from AUDIT.md, with date)*
- …

### Next phase
*<Phase N+1 — name>* — <one-line scope from ROADMAP.md>

---

## 🧰 Available skills

Skills currently installed in `.claude/skills/`, grouped by
purpose. Pulled from each SKILL.md frontmatter.

**Discovery & understanding**
- `/onboard` — guided walkthrough for new contributors
- `/audit` — focused codebase review
- `/wrangle` — tame an unfamiliar codebase
- …

**Planning & decisions**
- `/plan` — design new work
- `/decision` — capture an architectural decision
- …

**Execution & delivery**
- `/build`, `/run`, `/release` — verify, launch, ship
- …

*(Group however suits the actual installed set. If only a few
skills, list them flat.)*

For the full list, see `.claude/skills/` or run `/skills`.

---

## 🧱 Recent commits

```
<git log --oneline -10 output, monospace>
```

---

## 📚 Reference docs

- [`README.md`](../../README.md) — public front door
- [`CLAUDE.md`](../../CLAUDE.md) — working contract
- [`tasks/PHASES.md`](../../tasks/PHASES.md) — phase scope
- [`tasks/ROADMAP.md`](../../tasks/ROADMAP.md) — phase + task registry
- [`tasks/AUDIT.md`](../../tasks/AUDIT.md) — shipped work history
- [`.claude/task-rules.md`](../../.claude/task-rules.md) — universal execution rules
- [`docs/decisions/`](../../docs/decisions/) — recorded architectural decisions
- [`docs/postmortems/`](../../docs/postmortems/) — incident notes

*(Only list links to files that actually exist.)*

---

## 🪞 What this export doesn't cover

*(Render this section only if there are real gaps. Otherwise
omit. Reader doesn't need a clean-bill statement.)*

- <e.g. "No data-layer doc — schema lives in code at
  `src/models/`">
- <e.g. "CLAUDE.md is missing — the working contract isn't
  written down yet">

---

<div align="center">

*Generated by `/export-project` on <YYYY-MM-DD>. Re-run anytime;
this file is regenerable.*

</div>
```

## Style rules

- **Hero block centered.** The `<div align="center">` blocks
  render properly on GitHub and most markdown viewers. They're
  the design love.
- **Emoji are load-bearing.** 📦 (project), 🎯 (at-a-glance),
  🧭 (identity), 🛠 (stack), 🚀 (run), 📍 (status), 🧰 (skills),
  🧱 (commits), 📚 (refs), 🪞 (gaps). One emoji per major
  section. Don't add others.
- **Backtick-bold for tech stack badges.** Renders as visually
  distinct chips: **`TypeScript`**, **`React`**, **`Firebase`**.
- **Two-column "At a glance" table.** Forces tight summaries.
- **Quote blocks for citations.** When pulling a rule from
  CLAUDE.md, use `>` quote with the file link above it.
- **Horizontal rules between major sections.** They're the visual
  rhythm. Don't nest sections deeper than 2 levels.
- **Monospace for commit log.** Triple-backtick block, no
  language hint — preserves alignment.
- **No tables for lists.** Tables imply uniform fields; in-flight
  tasks aren't uniform, so they're a list.

## What you must NOT do

- **Don't fabricate.** Every claim cites a source file. If a
  section can't be sourced, it's omitted or marked as a gap —
  not made up.
- **Don't write marketing copy.** "A revolutionary platform
  that…" is banned. The export is for people who need to work
  with the project, not buy it.
- **Don't pad sections.** Empty in-flight task list? Section
  shows "Nothing in flight right now." in italic. Don't invent
  filler.
- **Don't auto-commit.** Same rule as every kit skill that
  modifies files.
- **Don't overwrite previous exports silently.** Each export is
  date-stamped. Multiple exports per day get suffixed
  `-<YYYY-MM-DD>-2.md`, `-3.md`, etc.
- **Don't extrapolate the architecture.** If CLAUDE.md doesn't
  describe the architecture, the architecture section is short
  and honest about it.

## Edge cases

- **No CLAUDE.md.** The "What this project is" and "Tech stack"
  sections fall back to README + manifest detection. Add a
  "What this export doesn't cover" entry noting CLAUDE.md is
  missing.
- **No tasks/ directory.** Skip "Where things stand" entirely
  and note in the gaps section.
- **Repo not git-initialized.** Skip the SHA + commits sections;
  use directory name as repo name.
- **Multiple exports same day.** Suffix with `-2`, `-3`, etc.
  Don't overwrite.
- **Huge dependency list.** Show top 10 by importance (heuristic:
  listed in CLAUDE.md / `dependencies` rather than
  `devDependencies`). Link to the manifest for the full set.
- **Monorepo / multiple subprojects.** Ask the user to pick a
  scope before generating; don't try to export everything as one
  doc.

## When NOT to use this skill

- **Onboarding a new contributor** → use `/onboard` for the
  guided walkthrough. Export is for portability outside the
  repo.
- **Focused audit of one slice** → `/audit`.
- **Wrangling a chaotic repo** → `/wrangle`. Wrangle produces
  multiple deep docs; export produces one polished summary.
- **Status update for a sprint review** → `/status` is faster
  and more targeted.

## What "done" looks like for an /export-project session

A single polished markdown file at
`docs/exports/<YYYY-MM-DD>-<repo>.md`, sourced entirely from
real files in the repo, with visual rhythm that makes it pleasant
to read top-to-bottom. Uncommitted. The user reviews, optionally
edits, and commits — or sends the file directly to whoever asked
for it.
