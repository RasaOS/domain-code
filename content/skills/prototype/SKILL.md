---
name: prototype
description: Mini task manager for an isolated prototype phase. Creates and manages a `proto/<slug>` branch + parallel task tree at `tasks/proto/<slug>/`, mirroring the kit's task system but kept entirely separate from main backlog/roadmap. Subcommands — start, resume, add, spec, move, status, list, graduate, shelve, drop. Triggered when the user wants to "prototype", "play with", "spike", "test out", or "rapid-build" a feature in isolation — e.g. "/prototype", "let's prototype X", "spike Y", "I want to try Z without touching the roadmap".
---

# /prototype — Isolated prototype phase

Set up a prototype as its own little task system, branched and
folder'd off the main work. The skill handles the **lifecycle** —
scaffolding, task ops within the prototype scope, graduation, and
exit hatches — without ever touching main `tasks/` or main
`ROADMAP.md`.

Per CLAUDE.md ethos: **calibrate honestly.** A prototype is R&D.
It's allowed to be rough. But the WORK inside follows the kit's
normal task discipline — full specs, acceptance criteria,
branch-per-task, the works. Just isolated from the production
roadmap so it doesn't pollute mainline planning.

## What this skill creates

Every prototype lives in its own complete bubble:

```
proto/<slug>                  # git branch, off main (or current)
tasks/proto/<slug>/
├── PHASES.md                 # one phase: this prototype
├── ROADMAP.md                # the phase + ordered task list
├── backlog/                  # task spec files (stubs and full specs)
├── active/
└── completed/
docs/proto/<slug>.md          # prose brief — what / why / acceptance / out-of-scope
```

Two parts:

- **Branch + task tree** — where the work happens. The task tree
  mirrors the kit's main `tasks/` shape but every path is scoped
  to `tasks/proto/<slug>/`. Skills like `/task`, `/spec-phase`,
  `/backlog`, `/roadmap` operate on main `tasks/` and **don't**
  reach into the prototype scope. `/prototype` handles all task
  ops within the prototype itself.
- **Brief** — `docs/proto/<slug>.md` describes the prototype's
  purpose, acceptance bar, out-of-scope, and iteration log. Read
  first by anyone (you included) coming back cold.

## Behavior contract

- **Isolation is the load-bearing rule.** Never read or write
  main `tasks/` files (`tasks/ROADMAP.md`, `tasks/PHASES.md`,
  `tasks/AUDIT.md`, `tasks/{backlog,active,blocked,completed}/`). The
  prototype is invisible to main planning by design. Graduation
  is the **only** path from prototype scope into main.
- **Work happens on `proto/<slug>` and its sub-branches.** Per
  the git-flow Rule 1 in `task-rules.md`, each task within the
  prototype gets its own sub-branch (`task/TASK-XXX-<slug>` off
  `proto/<slug>`). `/prototype` does NOT implement tasks — it
  manages spec lifecycle. Implementation follows the same
  task-rules.md discipline as everything else.
- **Slug discipline.** Slugs are kebab-case, single-word
  preferred — `streaming-ui`, `webhook-test`, `auth-redesign`.
  Used as both branch suffix and directory name; must match.
- **Graduation is explicit.** Promoting prototype tasks into
  main `tasks/` is a deliberate user action via `/prototype
  graduate`. Until then, none of the prototype's work is visible
  to `/roadmap`, `/backlog`, `/status`, etc.
- **Never auto-merge to main.** Per git-flow Rule 2, no path in
  this skill merges to `main`. Graduation stages file moves;
  the user merges through the normal path (their feature branch,
  per Rule 2).
- **Never auto-commit.** All file writes land in the working
  tree uncommitted. The user reviews with `git diff` and commits
  when ready.

## Output structure

**Catalogue entry.** §2 Live status dashboard for `status` (shows
phase + task counts + branch state). §25 Alert variants for
confirmations and warnings (start / move / drop). §1 Hero
completion card for graduation.

Concrete templates inlined per subcommand below.

## Subcommands

The skill routes on the verb after `/prototype`. Bare
`/prototype` (no verb) runs `status` if a proto branch is
checked out; otherwise prompts to `start`.

| Command | Effect |
|---|---|
| `start <slug>` | create branch + scaffolding + brief |
| `resume <slug>` | switch to existing prototype |
| `add <title>` | file a stub task in the prototype's backlog |
| `spec <id>` | expand stub → full spec (same rigor as /task Op 3) |
| `move <id> active` | mv backlog/<id> → active/ |
| `move <id> completed` | mv active/<id> → completed/ |
| `status` | §2 dashboard of prototype state |
| `list` | all proto/* branches + their state |
| `graduate` | promote prototype tasks → main `tasks/` (explicit) |
| `shelve` | exit, leave everything in place |
| `drop` | delete branch + dir + brief (confirm twice) |

### Step 1 — start <slug>

Pre-flight:

1. **Slug validity.** Kebab-case, no slashes, no spaces. If
   invalid, ask for a re-spelled slug.
2. **Collisions.** Check for existing branch `proto/<slug>` or
   directory `tasks/proto/<slug>/`. If either exists, surface
   that and offer `resume`.
3. **Working tree.** Must be clean. If dirty, surface and ask.
4. **Base branch.** Branch off `main` by default. If the user
   wants to branch off something else, they say so explicitly.

Gather (one block, terse — don't accept vague answers):

```
Prototyping: <feature, one sentence>
Acceptance bar: <one line — what counts as "the prototype works">
Out of scope: <comma list>
Constraints: <comma list, or "none">

Sound right?
```

Wait for confirmation. Push back on "it should work" — demand a
concrete acceptance bar.

On confirmation, scaffold:

```sh
git checkout -b proto/<slug> main
mkdir -p tasks/proto/<slug>/backlog tasks/proto/<slug>/active tasks/proto/<slug>/blocked tasks/proto/<slug>/completed
# write PHASES.md, ROADMAP.md, brief
```

Files to create:

**`tasks/proto/<slug>/PHASES.md`**:
```markdown
# Phases — <slug> prototype

## Phase 1: <slug> prototype

<scope paragraph derived from the gather: 2–4 sentences. What's
in, what's out, what success looks like. The scope IS the
contract; if a task doesn't fit, it doesn't belong here.>
```

**`tasks/proto/<slug>/ROADMAP.md`**:
```markdown
# Roadmap — <slug> prototype

## Phase 1: <slug> prototype

<copy phase scope here>

(no tasks yet — add via `/prototype add <title>`)
```

**`docs/proto/<slug>.md`**:
```markdown
# Prototype: <feature title>

**Date**: YYYY-MM-DD
**Branch**: proto/<slug>
**Status**: Active

## What it is

<from the gather, 1 paragraph>

## Why prototype this

<motivation — what question is being explored>

## Acceptance bar

<bullet list — what makes the prototype "work">

## Out of scope

<bullet list — what we deliberately don't do here>

## Iteration log

- YYYY-MM-DD — prototype started.
```

Render a §25 SUCCESS alert with the next-step hint:

````markdown
```
┌─ ✓  PROTOTYPE STARTED ──────────────────────────────────────┐
│  proto/<slug>                                               │
│                                                             │
│  scaffolding written:                                       │
│    tasks/proto/<slug>/{PHASES,ROADMAP}.md                   │
│    tasks/proto/<slug>/{backlog,active,blocked,completed}/                │
│    docs/proto/<slug>.md                                     │
│                                                             │
│  next · /prototype add <first task title>                   │
└─────────────────────────────────────────────────────────────┘
```
````

### Step 2 — resume <slug>

Pre-flight:
- Branch `proto/<slug>` exists locally.
- Directory `tasks/proto/<slug>/` exists.

If both exist, `git checkout proto/<slug>` and run `status`.

If branch exists but directory doesn't (or vice versa), surface
the inconsistency and ask before proceeding — don't auto-repair.

If no slug given, list available proto branches and ask which.

### Step 3 — add <title>

File a stub task into the prototype's backlog.

1. **Detect current proto slug** from current branch (must be
   on `proto/<slug>`). If not, surface and stop:
   *"Not on a proto branch. Run `/prototype resume <slug>` first."*
2. **Determine next TASK-NNN** by scanning
   `tasks/proto/<slug>/{backlog,active,blocked,completed}/` for highest ID.
   Zero-padded three digits.
3. **Write stub** at
   `tasks/proto/<slug>/backlog/TASK-NNN-<slug>.md`:
   ```markdown
   # TASK-NNN: <title>

   **Phase**: Phase 1: <prototype slug> prototype
   **Status**: STUB — full spec drafted before implementation

   <one-line user story or "TODO: user story">
   <one-line why or "TODO: why">
   ```
4. **Append to ROADMAP.** Add the task line under the phase's
   bullet list in `tasks/proto/<slug>/ROADMAP.md`.
5. Render a §25 INFO alert with the file path:

````markdown
```
┌─ ⓘ  STUB FILED ─────────────────────────────────────────────┐
│  TASK-NNN — <title>                                         │
│  tasks/proto/<slug>/backlog/TASK-NNN-<slug>.md              │
│                                                             │
│  next · /prototype spec TASK-NNN  (when ready to implement) │
└─────────────────────────────────────────────────────────────┘
```
````

### Step 4 — spec <id>

Expand a stub into a full spec, using the **same rigor as
`/task` Operation 3** — code reconnaissance, requirements
drilling, per-file rationale. Scope is
`tasks/proto/<slug>/backlog/`, not main.

The flow mirrors `/task` Operation 3 exactly:

1. Read the stub.
2. **Code reconnaissance.** Read CLAUDE.md (project facts),
   referenced files in the stub, grep for existing patterns
   matching the task's domain, identify likely-touched files
   from topic + repo structure. Render a summary: *"here's what
   exists / what you're extending / where it integrates."*
3. **Requirements drilling.** Push for concrete answers:
   observable behavior (no "feature works"); edge cases (empty,
   max, error); what MUST NOT change; specific test scenarios.
4. **Per-file rationale.** For each file in "Files expected to
   change," state WHAT changes and WHY.
5. Render the full spec via `task-template.md` shape, written
   to `tasks/proto/<slug>/backlog/TASK-NNN-<slug>.md`,
   overwriting the stub.
6. Show the rendered spec; wait for sign-off; write.

This step writes ONE file (the spec). No commits. No branch
creation — implementation happens on a separate
`task/TASK-NNN-<slug>` sub-branch off `proto/<slug>` per Rule 1,
which the user creates when starting the work.

### Step 5 — move <id> active|blocked|completed

Lifecycle the task through the prototype's pipeline.

`active`:
```sh
git mv tasks/proto/<slug>/backlog/TASK-NNN-*.md tasks/proto/<slug>/active/
```
Implementation begins on a sub-branch
(`task/TASK-NNN-<slug>` off `proto/<slug>`, per git-flow Rule 1).

`completed`: same pattern, active → completed. Run after the task's PR
merges back into the proto branch.

Render a §25 INFO alert:

````markdown
```
┌─ ⓘ  TASK-NNN MOVED → ACTIVE ────────────────────────────────┐
│  tasks/proto/<slug>/active/TASK-NNN-<slug>.md               │
│                                                             │
│  next · branch off proto/<slug> as task/TASK-NNN-<slug>     │
│         and implement                                       │
└─────────────────────────────────────────────────────────────┘
```
````

### Step 6 — status

Render the prototype's current state as §2 Live status dashboard
followed by tabular detail:

````markdown
# /prototype — <slug> · YYYY-MM-DD

```
┌─ proto · <slug> · HH:MM UTC ─────────────────────────────────┐
│                                                              │
│  ● Branch       proto/<slug> · <clean|N changes uncommitted> │
│  ● Phase        Phase 1: <slug> prototype                    │
│  ◐ In flight    <N> active                                   │
│  ○ Backlog      <N> stubs · <M> spec'd                       │
│  ● Done         <N>                                          │
│                                                              │
│  next · <task at top of active, or "spec next backlog item">  │
└──────────────────────────────────────────────────────────────┘
```

## Active

- **TASK-NNN — <title>** — <one-line status>

## Backlog

| ID | Title | State |
|---|---|---|
| TASK-NNN | <title> | 📝 stub |
| TASK-NNN | <title> | 📄 spec'd |

## Done

(collapsed if many)

→ Brief: `docs/proto/<slug>.md`
````

### Step 7 — list

Show all `proto/*` branches with their state.

```
PROTOTYPES

▸ <slug-1>      <N> active · <M> backlog · <K> completed   (this branch)
▸ <slug-2>      <N> active · <M> backlog · <K> completed
▸ <slug-3>      shelved (no commits in 30+ days)
```

### Step 8 — graduate

Promote the prototype's tasks into main `tasks/`. Explicit user
action — confirm scope before moving anything.

1. **Read all task spec files** in
   `tasks/proto/<slug>/{backlog,active,blocked,completed}/`.
2. **Propose a target phase** in main `tasks/ROADMAP.md` — an
   existing phase or a new phase to be created. Ask the user to
   confirm: *"Graduating N tasks → Phase X. Confirm?"*
3. **On confirm:**
   - For each task, `git mv tasks/proto/<slug>/<state>/<file>
     tasks/<state>/<file>`. Renumber IDs if they collide with
     existing main task IDs (warn).
   - Append task lines to main `tasks/ROADMAP.md` under the
     chosen phase.
   - Update each spec file's "Phase" header to match the new
     phase name.
   - Add an entry to main `tasks/AUDIT.md`:
     `🏗 Graduated prototype <slug> — <N> tasks → Phase <name>.`
4. **Don't merge.** Per Rule 2, the user owns any merge-to-main
   step. Graduation produces uncommitted file moves; the user
   commits and routes through the normal review/merge flow.
5. **Optionally drop the proto branch + dir + brief** if the
   user explicitly says so (`/prototype drop` after graduate).
   Don't auto-drop.

Render §1 Hero completion card:

````markdown
```
╭─────────────────────────────────────────────────────────────╮
│                                                             │
│   ✦  PROTOTYPE GRADUATED                                    │
│                                                             │
│      <slug>                                                 │
│      <N> tasks → Phase <name>                               │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│                                                             │
│      tasks/proto/<slug>/  →  tasks/                         │
│      AUDIT entry appended                                   │
│      working tree dirty — review and commit                 │
│                                                             │
│   →  next: implement per main task pipeline                 │
│                                                             │
╰─────────────────────────────────────────────────────────────╯
```
````

### Step 9 — shelve

Exit the skill cleanly. Leaves the branch, directory, and brief
in place. The prototype can be resumed any time.

Update the brief's status header to `Status: Shelved (YYYY-MM-DD)`.

Render a brief §25 INFO alert:

````markdown
```
┌─ ⓘ  PROTOTYPE SHELVED ──────────────────────────────────────┐
│  proto/<slug> stays on disk and in git.                     │
│  Resume with /prototype resume <slug>.                      │
└─────────────────────────────────────────────────────────────┘
```
````

### Step 10 — drop

Destructive. Confirm twice.

1. **First confirm.** *"Drop prototype <slug>? This deletes
   branch proto/<slug>, tasks/proto/<slug>/, and
   docs/proto/<slug>.md. Irreversible without `git reflog`.
   Type 'drop' to confirm."*
2. **On 'drop':**
   ```sh
   git checkout main      # or whatever branch was previous
   git branch -D proto/<slug>
   rm -rf tasks/proto/<slug>/
   rm docs/proto/<slug>.md
   ```
3. Render a §25 WARNING alert confirming what was deleted:

````markdown
```
┌─ ⚠  PROTOTYPE DROPPED ──────────────────────────────────────┐
│  branch         proto/<slug>     deleted                    │
│  task tree      tasks/proto/<slug>/  removed                │
│  brief          docs/proto/<slug>.md removed                │
│                                                             │
│  recover via `git reflog` if needed.                        │
└─────────────────────────────────────────────────────────────┘
```
````

## Style rules

- **Render structured deliverables per `output-rules.md`.** §2
  for status dashboards, §25 for confirmations and warnings,
  §1 for graduation. Glyph and color discipline follow the
  canonical set.
- **Isolation is the load-bearing rule.** If you find yourself
  about to read or write a path under main `tasks/` (NOT
  `tasks/proto/<slug>/`), STOP. Either you mis-resolved the
  slug, or you're outside the skill's scope.
- **Speak in prototype scope.** When the user says "add a task,"
  the file goes to `tasks/proto/<slug>/backlog/`, not
  `tasks/backlog/`. Same naming, different path.
- **Never narrate the lifecycle.** A successful add → §25 INFO
  alert with the file path. Not a paragraph about what happened.
- **Push back on vague gathers.** "It should work" isn't an
  acceptance bar. Demand a concrete checkable claim before
  scaffolding.

## What you must NOT do

- **Don't touch main `tasks/`.** Not its ROADMAP, not its PHASES,
  not its AUDIT, not its backlog/active/blocked/completed. The prototype is
  invisible to main task planning by design.
- **Don't merge to `main`** during a prototype session. Per
  git-flow Rule 2, every merge to main is user-confirmed.
  Graduation only stages tasks; it doesn't merge.
- **Don't auto-graduate.** Graduation is explicit user action.
- **Don't infer slugs.** If the user says "/prototype add a thing"
  but the current branch isn't `proto/<slug>`, ask which
  prototype.
- **Don't subdivide tasks** unless the user explicitly says so.
  Same rule as `/task`.
- **Don't skip the brief.** `docs/proto/<slug>.md` is part of
  the prototype's identity — created on `start`, updated on
  `shelve` / `graduate`.
- **Don't auto-commit.** All file writes land in the working
  tree uncommitted. The user reviews and commits.
- **Don't refactor adjacent code** the prototype touches. Note
  smells in the brief's "Iteration log" if relevant; leave the
  code alone.

## Edge cases

- **Slug already exists** (branch + dir): offer `resume`. Don't
  overwrite.
- **Slug exists as branch but no dir** (or vice versa): surface
  the inconsistency and stop. Don't auto-repair — that's a
  judgment call the user owns.
- **Working tree dirty on `start`**: stop. Don't branch over
  uncommitted work.
- **User on a non-proto branch when running task ops** (`add`,
  `spec`, `move`): require they checkout a proto branch first.
- **Graduation with ID collision**: rename the graduating task
  to next-available main ID, warn the user, document the
  rename in AUDIT.
- **`git mv` on untracked file**: use plain `mv` instead. Same
  effect, no git error.
- **No `proto/*` branches exist** when running `list`: render a
  §26 Empty state with a hint to `/prototype start <slug>`.

## When NOT to use this skill

- **The work is real and going to ship to production.** Use the
  normal task pipeline (`/task` + main `tasks/`). The prototype
  isolation is overhead you don't need.
- **Exploring an idea without writing code** → use `/brainstorm`.
- **The work needs MVP scoping** (greenfield app, big feature) →
  use `/mvp`.
- **You're inheriting an unfamiliar codebase** → use `/wrangle`
  first, then prototype within it.
- **Adding tasks to an existing main phase** → `/task`.
  `/prototype add` only operates on the active prototype scope.

## What "done" looks like for a /prototype session

The user leaves with one of:

- A new prototype scaffolded — branch + dir + brief — ready for
  task work.
- A new task in the prototype's backlog (or active, blocked, or completed).
- A clear status read of the current prototype.
- A graduated prototype, with tasks now staged in main `tasks/`
  (uncommitted), ready for the user to review and merge per the
  normal flow.
- A shelved or dropped prototype with a clear paper trail.

The deliverable is filesystem state plus the §-templated chat
output. No commits unless the user committed; no merges to
`main` ever (without the explicit user-confirm path of
`graduate` → user-driven merge per Rule 2).
