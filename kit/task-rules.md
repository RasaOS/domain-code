# Task Execution Rules

These rules apply to **every** task in `tasks/`. They extend
`CLAUDE.md` (which owns project-specific conventions, tech-stack
specifics, schema ownership, and concrete commands). Read both before
starting work.

> **Note on commands.** This file is generic by design. Specific
> commands (build, test, run, deploy) are documented in `CLAUDE.md`
> for each project. Where this file says "the project's verification
> command," see `CLAUDE.md` for the actual string.

> **Platform extensions.** Files in `.claude/` named with a platform
> prefix — e.g. `ios-task-rules.md`, `web-task-rules.md`,
> `python-task-rules.md` — extend this file for platform-specific
> work. **Read the relevant prefix files based on the work at hand**:
>
> - Working on iOS code or anything affecting the iOS app → read
>   `ios-task-rules.md`
> - Working on web code → read `web-task-rules.md`
> - Working on Python code → read `python-task-rules.md`
> - Cross-boundary work (e.g. iOS HTTP client to a Python API) →
>   read both relevant prefix files
> - Pure cross-platform work → just this file
>
> Same convention applies across the whole `.claude/` tree:
> `ios-conventions.md`, `web-deploy.md`, etc., and skills like
> `ios-release/`, `web-deploy/`. The prefix is a discovery hint, not
> a gate — every project pulls all files; each work session reads the
> ones that apply.

> **Craft rules.** Universal code-quality discipline — build it right
> the first time, no copy-paste, modular by default, no magic strings,
> minimal comments, no dead code, no premature abstraction. Read
> `craft-rules.md` before writing code. Applies to every project,
> every language. Sits between this file (process) and the platform
> extensions (stack).

> **Script craft.** When a skill ships a script (`kit/skills/<name>/<name>.sh`
> or similar), follow `script-craft.md`. It covers how to create,
> update, and run scripts in the kit — the deterministic-mechanics
> layer that locks down "what plumbing happens every time" so the AI
> doesn't re-interpret it on each invocation. Canonical example is
> `kit/skills/save/save.sh`. Read before writing or modifying a script.

> **Output styles.** Structured outputs — status reports, deployment
> reports, audits, backlogs, test results, decisions, and similar
> deliverables — render via the kit's output catalogue. The
> catalogue itself is at `.claude/output-styles.md`; the selection
> and composition rules (which template applies to which situation,
> when to compose, glyph and color discipline) are at
> `.claude/output-rules.md`. Read both when producing a structured
> output. Plain conversation, narration, Q&A, and brainstorming stay
> as normal markdown — `output-rules.md` defines what counts as
> "structured" vs. "conversational."

> **Git flow discipline.** Five non-negotiable rules covering
> branching, merging to `main`, deploy tagging, and where deploy
> commands are allowed to run. Read `git-flow-rules.md` before any
> task touching branches, merges, or deploys.

> **Release rules.** Production deploy tagging format, version-bump
> heuristic, hotfix path, dependency hygiene. Read `release-rules.md`
> when shipping a release or auditing dependencies.

> **Batch handoff.** Multi-task integration flow, post-handoff
> standby state, and the merge-to-main confirmation gate. Read
> `batch-handoff.md` when wrapping a phase / batch of tasks.

> **Vocabulary.** Canonical definitions of kit terms — `batch`,
> `tag and bag`, lifecycle states, version-bump semantics, etc.
> Kit defaults at `.claude/vocabulary.md`. Project-specific
> overrides live in `.claude/vocabulary-overrides.md` (e.g. iOS
> projects override `patch` semantics due to the Apple
> build-number constraint). Skills resolve terms by reading
> overrides first, falling back to defaults. Read both before
> assuming what a term means.

## Scope discipline

- One task = one PR. Do not bundle unrelated changes.
- Touch only the files listed in the task's "Files expected to change"
  section. If you need to touch something outside that list, **add it
  to the task file with a one-line justification before editing.**
- Do not refactor adjacent code "while you're in there." Out of scope.
- Do not add features, abstractions, or config not required by the
  acceptance criteria.

## Every change is task-linked (the change-audit rule)

**Every code change and every running-configuration change is
linked to a task.** No exception — not a planned feature, not a
one-line hotfix, not a "quick fix" made under pressure. The task is
the audit trail; a change with no task is a hole in the record that
no one can review later.

This applies to **source code and runtime / user-facing
configuration**. It does not apply to documentation, the task files
themselves, or `.claude/` meta — those carry no runtime risk and
need no task.

- **Before a code/config change, there should be a task.** Working
  a quick fix? It still gets a task. If a full spec is overkill for
  a trivial change, a one-line stub is enough — but the task must
  exist and be linked.
- **A stub is acceptable; nothing is not.** The bar is "a task
  exists," not "a task is fully spec'd." An honestly-flagged stub —
  title, why it wasn't spec'd, the files touched — keeps the audit
  trail whole. Spec it retroactively with `/task` if it matters.
- **The change ledger.** `tasks/CHANGES.md` is the append-only
  record: every code/config commit, its linked task, the author,
  the date, the files. This is the long-term audit-and-review
  surface.

**Enforcement.** The `/task-guard` skill makes this automatic — a
pre-commit hook that, when a commit touches code/config with no
active task, auto-creates a stub task and appends the ledger row,
both riding into the commit. The rule holds whether or not the hook
is installed; `/task-guard` just removes the need to remember. Do
not bypass the hook with `git commit --no-verify` — forbidden
regardless (see "Verification gates").

## Schema discipline (extends CLAUDE.md)

Some projects mirror schemas owned by another team or platform (iOS
Realm models, backend protobufs, OpenAPI specs, partner API contracts,
etc.). When that's true:

- **The canonical source owns the schema.** Field names are
  byte-identical to the canonical definition.
- **Never invent, rename, or "correct" a field.** If a field name
  isn't in the project's mirror models or referenced in the task's
  source, **stop and write a blocker note** — do not guess.
- **Never modify the project's schema-registry file** (the file that
  `CLAUDE.md` identifies as the canonical mapping — typically a
  `paths.js` / `types.ts` / `schema.go` / similar) without a referenced
  source-of-truth.

If the project does not have an externally-owned schema, this section
is informational only. `CLAUDE.md` should state explicitly whether the
project owns its schema or mirrors one.

## Active orchestrator notices

If this project is a sub-repo of a multi-stack company (per
`CLAUDE.md` "Macro architecture" section), the company's
orchestrator may drop coordination signals into this repo's
`.claude/`. These are **read-only** files written by orchestrator
skills like `/migration` — they describe cross-repo state this
project needs to be aware of.

### Files in scope

Any file matching `.claude/active-*.md`. Examples:

- `.claude/active-migrations.md` — open cross-repo migrations
  affecting this codebase, written by the orchestrator's
  `/migration` skill.

Future variants (`.claude/active-adrs.md`, etc.) follow the same
discipline.

### What to do

- **Read each `active-*.md` file on session start.** If any contain
  open entries, surface them in your initial orientation — what's
  open, what's expected of this repo, link back to the orchestrator
  file. Don't bury this in detail; the user needs to know without
  asking.
- **Re-read at task start.** Migrations open and close while a user
  is mid-task; don't trust an early read indefinitely.
- **Treat as authoritative.** If a migration entry says this repo's
  part is `🟡 in progress`, that's the orchestrator's view of state.
  If the local PR has actually shipped, the next move is to update
  the orchestrator (`/migration update` from the orchestrator
  instance) — not to edit the file here.

### What you must NOT do

- **Don't edit `.claude/active-*.md` by hand.** They're auto-managed
  by orchestrator skills. Hand edits get overwritten on the next
  orchestrator write and confuse the source-of-truth.
- **Don't delete them.** When the orchestrator closes the last
  applicable concern, it deletes the file itself. A stale empty
  file is the orchestrator's bug, not something to clean up here.
- **Don't propagate orchestrator state into project files.** The
  orchestrator is the source for cross-repo state; mirroring it
  into this project's `CLAUDE.md` or task specs creates two
  truths. Reference, don't copy.

### If no orchestrator is set

If `CLAUDE.md`'s "Macro architecture" section has the orchestrator
path as `n/a — solo project`, this rule doesn't apply. There's no
upstream orchestrator dropping notices; any `.claude/active-*.md`
files that appear are from a previous setup or accidental — flag
to the user, don't read.

## Files that require explicit permission to modify

Touching any of these = blocker, not autonomous work. The exact list
varies per project — `CLAUDE.md` should enumerate the gated files for
this project. Common categories:

- **Infrastructure / deploy config** (e.g. `firebase.json`, `*.tf`,
  CI workflow files, `Dockerfile`, hosting config)
- **Security / secrets** (`.env`, `.env.example`, security-rules
  files, IAM config)
- **Dependency manifests** (`package.json`, `Cargo.toml`, `go.mod`,
  `Gemfile`, `pyproject.toml`, `Package.swift`) — adding, upgrading,
  or removing
- **Build / runtime config** (e.g. `vite.config.*`, `webpack.*`,
  `tsconfig*.json`, `babel.config.*`)
- **Process / kit files** (`CLAUDE.md`, `.claude/task-rules.md`,
  `.claude/task-template.md`, `.claude/task-template-stub.md`,
  `.claude/task-template-bug.md`, `.claude/task-template-hotfix.md`,
  `.claude/intake-template.md`, `.claude/skills/`, `.github/`, `.git/`)

If a task requires one of these, surface it in the task file's blocker
section and stop.

## Branch and PR rules

- Branch name: `task/TASK-XXX-short-slug` (or `hotfix/HOTFIX-NNN-slug`,
  or `chore/<slug>` for non-task work).
- Commit style: matches existing repo style — typically a one-line
  summary, blank line, prose body explaining the *why*, blank line,
  `Co-Authored-By` trailer. Check recent `git log` to confirm.
- PR title: `TASK-XXX: <task title>` (or the equivalent for other
  branch types).
- PR body must include:
  - Link or path reference to the task file
  - Checklist copy of the acceptance criteria with ☑/☐
  - "Files changed" matching the task's expected list (call out
    deviations explicitly)
  - "How I verified" — manual steps + test command output

## Verification gates (must pass before opening PR)

The specific commands come from `CLAUDE.md`. The contract is the same
across projects:

1. **Build** — the project's build command (per `CLAUDE.md` or
   `/build`) must succeed with no new warnings.
2. **Verification suite** — the project's contract test command (per
   `CLAUDE.md`) must pass headless / non-interactive. **This is the
   gate**, not the watched/headed variant. Agents must run the
   non-interactive version because there is no display.
3. **Local run check** — the project's run command (per `CLAUDE.md`
   or `/run`) boots and the implemented flow works.
4. **No console / log errors** on the affected screens or paths.

Every new feature task should pair with a test artifact per the
project's convention (e.g. an E2E spec named after the task, a unit
test file, a scenario in a feature spec). `CLAUDE.md` documents the
project's test-pairing convention.

**Iteration vs. gate:** while working a task, run only that task's
test (using the project's filtering/watched mode per `CLAUDE.md`).
Re-running the full suite on every edit wastes time. Before opening
the PR, run the unfiltered verification command once to confirm the
gate is green.

If any gate fails and you can't fix it in scope, **stop and write a
blocker note**. Do not disable tests. Do not bypass hooks
(`--no-verify` and equivalents).

## Honest reporting

- If acceptance criteria can't all be met, the task is **not done**.
  Open the PR as draft, mark unchecked criteria, write a blocker.
- If you discover the task's premise is wrong (e.g., an upstream
  source doesn't behave the way the task assumes), stop and write a
  blocker. Do not silently redesign the feature.
- Never mark a checklist item complete that you didn't actually verify.
- "Tests pass" means you ran them and saw green, not "the code looks
  like it should pass."

## State machine

```
tasks/intake.md  →  tasks/triage/  →  tasks/backlog/  →  tasks/active/  ⇄  tasks/blocked/  →  tasks/completed/
   (raw)            (formalized,        (phase +              (in              (parked,            (PR merged)
                     no phase/cat)       category assigned)    flight)          ext. dep)
```

- **`intake.md`** is a single markdown file holding raw notes,
  observations, and complaints that haven't yet decided to become
  tasks. Pre-triage. No `TASK-NNN` id. The lowest-friction capture
  layer. See "The intake layer" below.
- **`triage/`** holds tracked-but-untriaged tasks — filed with a
  `TASK-NNN` id but no phase, no category, and no priority. A task
  sits here until it is *graduated* (category + phase assigned →
  `git mv` to `backlog/`) or pulled straight to `active/` to be
  worked. Triage tasks are the one exception to the phase rule —
  they are deliberately not in `ROADMAP.md`. See "The triage
  holding area" below.
- **`backlog/`** holds phase-placed, category-assigned tasks ready
  to be worked. The category (Stub / Spec / Bug / Hotfix) is
  declared in the task's frontmatter. See "Categories" below.
- **`active/`** should hold at most one task at a time per agent.
- **`blocked/`** is a *parked state* for tasks that were in
  `active/` but hit an external blocker (missing credential,
  waiting on another team, third-party outage, undecided product
  call). The task file moves to `tasks/blocked/`; status becomes
  `blocked`; the blocker is named in the file under a "Blocker"
  section. See "The blocked state" below.
- **`completed/`** is the terminal state — PR merged, work shipped.
  (This directory was named `done/` before v0.36.0; the
  state-machine value was also `done`. Both renamed for clarity.
  See the v0.36.0 changelog for the migration.) Open-but-unmerged
  PRs stay in `active/`.
- Move the task file with `git mv` as you transition states.

**Hotfixes skip part of the lifecycle.** A Hotfix-category task
uses the `HOTFIX-NNN` id space (not `TASK-NNN`), is filed directly
to `tasks/active/`, and bypasses phase placement entirely — it
doesn't go in `ROADMAP.md`. See "Categories" below for the full
contract.

### The status field

Every task spec declares `status:` in its frontmatter, matching
the directory it lives in:

```yaml
status: triage | backlog | active | blocked | completed
```

Status and directory must agree — they are the same fact recorded
twice for ease of inspection. The directory move (`git mv`) and
the frontmatter change happen together. A task in
`tasks/blocked/` with `status: active` is a bug; fix the
frontmatter or fix the directory.

### The blocked state

A task in `blocked/` is one that was being worked but ran into an
external dependency that prevents progress. Examples:

- A third-party API is down or undocumented.
- Waiting on a decision from another team / the product owner /
  the user.
- Missing a credential or access that only a specific person can
  grant.
- Waiting on an upstream task (cross-repo) that hasn't shipped.

The blocked file must have a `## Blocker` section at the bottom
with: what's blocking, who or what would unblock it, when to
check back. Without that section, the task is not blocked — it's
abandoned, and that's a different problem.

Returning from blocked to active is a `git mv` back to `active/`
plus a frontmatter status flip. The Blocker section moves into
the task's "Notes" or stays as a record of why it was parked.

A task is **not blocked** if:

- The blocker is "I don't know how to do this." (That's a recon
  problem — read more code, ask the user, do `/instruct`.)
- The blocker is "this is hard." (That's just work.)
- The blocker is "I forgot about it." (Move back to `backlog/`.)

Blocked is for *external* dependencies. Internal-to-the-task
problems get fixed inside the task.

## Closing report (mandatory)

When a task's PR is opened, the closer **must** post a completion
report in chat with this exact shape. The point is one-glance
status — the reviewer scans the table in 5 seconds and decides
whether to dig in. The "What you need to do next" section is
non-negotiable; every task tells the reviewer exactly what action
to take.

```markdown
## TASK-XXX completion report

| | |
|---|---|
| **Name** | <descriptive name from the task spec> |
| **Status** | ✅ Ready for review / ⚠️ Blocked / ❌ Failed |
| **Branch** | `task/TASK-XXX-slug` |
| **PR** | [#N](url) |

**Tests**
- Full headless gate: <count> green · <time>
- TASK-XXX focused run: ✅/❌ · <time>

**Build**: clean / <warnings if any>

**What changed**
- One-line bullets, the actual deltas

**What you need to do next** (in order)
1. Concrete action
2. Concrete action

**Things I noticed** (not blockers — can be empty)
- ...
```

Rules:
- **Status** is one of three states. Never "almost ready" or
  "mostly done." If acceptance criteria aren't met, status is
  ⚠️ Blocked or ❌ Failed and the report explains why.
- **Test results are real numbers**, not "tests pass." Cite the
  actual count and the actual time from the run output.
- **Don't tick boxes you didn't verify.** Same rule as the rest
  of this file.
- Optionally include the same block in the PR body so it's also
  visible on GitHub. The chat report is the contract; the PR
  embed is convenience.

**Chore PRs follow the same shape.** A chore is any PR that isn't
a feature task — process docs, scaffolding, dependency upgrades,
config tweaks. The closing report is identical except:

- The status states are the same. ✅ / ⚠️ / ❌. No middle ground.
- "Tests" cites the verification gate result. **Even a docs-only
  chore runs the project's verification command before opening the
  PR** — proves the change didn't accidentally break anything. If
  you skip it, say so explicitly with a one-line reason.
- "What changed" can be terse — one line is fine.

## Audit log (mandatory)

`tasks/AUDIT.md` is the curated, append-only chronological record of
meaningful actions taken on the project — releases, task ships, rule
changes, scaffolding events. Git log is the ground truth; this file is
the human-readable layer on top.

### What to log

- 🚀 **Production deploys.** Every tagged release gets an entry.
  Include the version, the tag's commit SHA, and the integration PR
  number.
- 📦 **Task ships** (PR merged to `main`). One line per task.
- 📜 **Rule / process changes** in `task-rules.md`. One line
  describing the rule.
- 🏗 **Major scaffolding** (new doc, new convention, new tooling that
  affects everyone).
- 🔥 **Hotfixes.** One line per hotfix release, with link to the
  postmortem.
- ⚠️ **Incidents** and **honest tradeoff calls** that future readers
  will need to understand. Receipts matter.

### What NOT to log

- Every commit. Git log already has those.
- Routine refactors that don't change behavior.
- Drafts that don't ship.
- Per-line code review feedback.

### How to write entries

- **Newest entries on top** within their date section.
- ISO date headers (`## YYYY-MM-DD`).
- One to a few lines per entry. Bullet form. Lead with the *what*
  and end with the receipts (PR number, tag, commit SHA).
- Use the emoji set sparingly: 🚀 for releases, 📦 for task ships,
  📜 for rules, 🏗 for scaffolding, 🔥 for hotfixes, ⚠️ for incidents
  / tradeoffs.
- Don't backdate. If you forgot to log something, log it today with
  `(retroactive)` in the entry.

### Maintenance trigger

Every batch's closing report is the prompt to update `AUDIT.md`.
Specifically:

- When a task PR merges → append a "task shipped" entry.
- When a deploy completes → append a "🚀 Released vX.Y.Z" entry.
- When `task-rules.md` changes → append a "📜 rule added/changed"
  entry.
- When a hotfix ships → append a "🔥 Hotfix" entry with link to the
  postmortem.

If a batch ships multiple things in one chat turn, append all the
entries together. If more than one date is involved, split across
the date headers.

## Phase structure (mandatory)

Phases are first-class. Every task **in `ROADMAP.md`** belongs to
exactly one phase — no orphans, no "we'll figure out where this fits
later." This keeps the planned work scoped and the backlog navigable.
The one exception is the **triage holding area** (see "The triage
holding area" below): tasks parked in `tasks/triage/` are tracked but
deliberately unphased, and are not in `ROADMAP.md` until they graduate.

### Each phase has three things

1. **A name.** "Phase N: <short noun-phrase>". The name should
   communicate the scope at a glance — e.g. "Phase 3: Core module
   CRUD", "Phase 8: Code cleanup".
2. **A scope paragraph.** 2–4 sentences in `tasks/ROADMAP.md`
   directly under the phase heading. Says what's in, what's out, and
   (when useful) what success looks like. The scope is the *contract*
   — if a task doesn't fit it, the task belongs in a different phase.
3. **An ordered list of tasks.** Bulleted under the scope paragraph
   in ROADMAP. Each entry is `- TASK-NNN — <title>`. Order matters —
   top-down implies suggested ship order.

### `tasks/ROADMAP.md` is the registry

Phase membership lives in ROADMAP.md, nowhere else. Tasks don't
declare their phase in their own spec file (that would drift). The
skills (`/roadmap`, `/backlog`) parse ROADMAP to build the task→phase
map.

### Adding a task

1. Decide the phase first. If unclear, ask the user. If there is no
   phase for it yet, file it to the triage holding area instead
   (`tasks/triage/`, see below) and stop — don't force a phase.
2. Add the task line under that phase's bulleted list in `ROADMAP.md`.
3. Create the spec file in `tasks/backlog/` (per the priority rule).

If a task doesn't fit any existing phase, either **propose a new
phase** or **file it to triage** — don't dump it into "cross-cutting"
or fudge the fit.

### Creating a new phase

1. Pick a name.
2. Write the scope paragraph (2–4 sentences). Make in/out explicit.
3. Add the phase section to `ROADMAP.md` in its sequence position.
4. Then file tasks under it.

Don't create empty phases speculatively. A phase exists because it
has work in it.

### Moving a task between phases

Single edit to `ROADMAP.md`: remove the task line from the old phase's
list, add it to the new phase's list. The spec file itself doesn't
move (it stays in `backlog/active/blocked/completed` based on state, not phase).

### Cross-cutting tasks

Reserved for genuinely orthogonal work that doesn't belong to a named
phase — typically infrastructure that any phase might depend on. Use
sparingly. If two or more cross-cutting items accumulate that share a
theme, that's a signal to lift them into a named phase.

## Categories (mandatory)

Every task in `backlog/`, `active/`, `blocked/`, or `completed/` has a **category** in
its frontmatter. The category answers: *what kind of work is this,
and how do we treat it?* Four categories:

```yaml
---
id: TASK-042            # or HOTFIX-042 for Hotfix category
category: spec          # stub | spec | bug | hotfix
phase: phase-3          # null for hotfix (skips ROADMAP)
status: backlog         # triage | backlog | active | blocked | completed
---
```

### `stub` — track lightly, no full spec

A Stub-category task is one the team has decided to **track but
not spec further**. Title, brief description, optional notes, and
that's it. The category signals: don't expand this; it exists to
be visible and counted, not to be implemented from a contract.

Use Stub when the work is small enough that a full spec is
overhead, or when the user has named the task but doesn't have the
detail yet. The template is `task-template-stub.md` — short and
shallow by design.

Stub tasks still belong to a phase, still appear in `ROADMAP.md`,
still move through the state machine. They just don't get a full
implementation contract. (For "not yet a task at all," see the
intake layer below.)

### `spec` — full task, user-story-based

A Spec-category task is the default — feature work, new
functionality, the canonical implementation contract. As-a /
I-want / so-that, scope, acceptance criteria, test plan. The
template is `task-template.md` (the original).

A Spec-category task may start as stub-content at filing time
(per the priority rule below) and be expanded close to
implementation. The *category* says "this will be fully spec'd";
the *content* may or may not be there yet.

### `bug` — fix broken behavior

A Bug-category task is a full spec for fixing something that
doesn't work as intended. Same user-story shape as Spec, plus
bug-specific fields: steps to reproduce, expected vs. actual
behavior, root-cause notes (where determinable without fixing),
and acceptance criteria for the fix. The template is
`task-template-bug.md`.

Bugs belong to the phase whose functionality is broken — not
their own "bugs" phase. A login bug belongs to the auth phase,
not "Phase B: bug fixes." This keeps the broken work co-located
with the working work.

### `hotfix` — urgent fix, separate ID space

A Hotfix-category task is a Bug that needs to ship NOW. The
distinction is procedural, not technical: hotfixes bypass normal
planning. They get:

- **A separate ID space.** `HOTFIX-NNN` (not `TASK-NNN`),
  matching the existing branch convention from
  `git-flow-rules.md` Rule 1 (`hotfix/HOTFIX-NNN-slug`) and the
  🔥 AUDIT emoji.
- **No phase placement.** Hotfixes do not go in `ROADMAP.md`.
  They are emergency work, not planned work.
- **Direct routing to `tasks/active/`.** A hotfix is filed
  straight to active — there is no backlog stop, because by
  definition it's being worked immediately.
- **A hotfix-specific template.** `task-template-hotfix.md`:
  urgency justification, what's broken in production, the
  smallest fix that solves it, rollback plan, post-fix
  verification.
- **An AUDIT entry with 🔥** when shipped, per
  `release-rules.md`.

If the urgency dissipates before the fix ships — or it turns out
not to be urgent after all — re-categorize as `bug`, change the
ID prefix to `TASK-NNN`, and route through the normal lifecycle.
Hotfix is a commitment to act fast; it is not a label you carry
forever.

### What about the existing "stub vs full spec" rule?

The priority signal rule (below) governs *content level* at
filing time — stub-content vs. full-content. The category
governs *intended shape* of the work. Both apply:

| Category | Stub-content at filing | Full-content at filing |
|---|---|---|
| `stub` | ✓ (and stays this way) | — (would change category to `spec`) |
| `spec` | ✓ default, expanded close to implementation | only on urgency signal |
| `bug` | ✓ default, expanded close to implementation | only on urgency signal |
| `hotfix` | — never (hotfixes always have full content) | ✓ always |

### Backwards compatibility

Tasks that predate categories (no `category:` frontmatter)
default to `category: spec`. Adding categories does not require
re-filing existing tasks; the absence of the field is the same
as declaring `spec`.

## Adding tasks to the backlog (priority rule)

When the user says "add a task" without specifying urgency, **append
to `tasks/backlog/` as a minimal stub and stop there.** Don't:

- Promote it ahead of other tasks in the roadmap.
- Draft a full spec when a stub will do — full specs are expanded
  *close to implementation*, not at filing time.
- Reshuffle phase ordering, sequence diagrams, or roadmap prose to
  "make room."
- Subdivide the task into siblings unless the user explicitly asks.
  Filing one task means filing one task, not five.

A minimal stub is title + 1-line user story + 1-line "why" +
`STATUS: STUB — full spec drafted before implementation`.
Anything more is speculative work.

## Full spec vs. stub: the priority signal rule

**Default: stub.** A full spec is created *only* if the user
explicitly says one of these exact phrases:
- "emergency", "urgent", "do it now"
- "needs to ship before X"
- "this is next up"
- "top priority"

These signals trigger both placement (ahead in the roadmap) AND
an immediate full spec. Anything else → stub + ask clarification.

**Placement without spec:** The signals below are about *where*
the task goes in the roadmap, not whether to spec it immediately:

- **"Needs to ship before X"** → place ahead of X in the roadmap
  and flag any sibling dependencies. Full spec later, via `/task`
  Operation 3 (unless "emergency" was also said).
- **"X needs to ship first, then this can come next"** → place
  immediately after X. Stub until X ships; then spec it.
- **"For a future phase"** / **"later"** → backlog only, no
  re-sequencing. Stub.
- *No qualifier given* → backlog only, no re-sequencing. Stub.
  Default behavior. Cheaper to ask later than re-task now.

When unsure, ask: *"backlog only, or should this jump the queue?"* —
one round trip beats a wrong placement.

## The triage holding area

`tasks/triage/` holds tasks you want **tracked long-term but not yet
triaged** — no phase, no priority, no commitment on when (or whether)
they get worked. The holding pen for "good idea, file it, sort out the
placement later."

A triage task is a real task — a `TASK-NNN` id and a spec file
(usually a stub) in `tasks/triage/`. What it lacks is a phase, so by
the phase rule above it is **not in `ROADMAP.md`**. That is the
deliberate line: *in `ROADMAP.md` ⟺ has a phase ⟺ triaged.* The triage
folder is everything tracked but not yet in the roadmap.

### Filing to triage

When the user files a task with no phase for it yet — or can't name
one — file it to `tasks/triage/` rather than forcing a phase. A stub
is the norm: title + 1-line user story + 1-line "why" +
`STATUS: STUB`. Do **not** edit `ROADMAP.md` — triage tasks are not
in it.

This differs from the priority rule's default ("no urgency signal →
backlog stub"): that still assumes a phase. Triage is for when there
is no phase yet at all.

### Graduating a task out of triage

A triage task leaves the holding area one of two ways:

- **Graduated into a phase.** Assign a phase, `git mv` the spec file
  from `tasks/triage/` to `tasks/backlog/`, and add its task line to
  that phase's list in `ROADMAP.md`. It is now a normal backlog task.
- **Pulled straight to work.** `git mv` it to `tasks/active/`. It
  still needs a phase for the roadmap — assign one and add the
  `ROADMAP.md` line as part of starting it.

Don't let `tasks/triage/` rot. When it accumulates, that is the
signal for a triage pass: graduate what matters, and move what won't
be done to `.claude/wont-do.md`.

## The intake layer

`tasks/intake.md` is the **pre-triage capture surface** — a single
markdown file where raw notes, complaints, observations, and rough
ideas land before anyone has decided whether they should become
tasks. The lowest-friction layer in the lifecycle.

```
intake.md (raw)  →  triage/ (TASK-NNN, no phase/category)
                  →  backlog/ (phase + category)
                  →  ...
```

### Why a separate file from triage

Triage tasks are real — they have IDs, files, a place in the state
machine. Filing to triage commits a small but real cost: an ID is
spent, a file exists. For a half-formed thought ("the dashboard
flickers on first load — did anyone else see that?") that may or
may not be a task, that's too much ceremony.

Intake is a one-line append: a bullet in `intake.md`. No ID. No
file. No commitment beyond "I wrote it down."

### Format

A single markdown file at `tasks/intake.md`. Loosely structured —
the contract is "easy to add to" first, "consistent" second.

```markdown
# Task Intake

Pre-triage capture. Raw notes that may or may not become tasks.
When an entry matures, promote it to triage via `/task promote`
(creates a TASK-NNN in `tasks/triage/`) — or delete it.

## 2026-05-20

- **Login is slow on mobile** — felt during demo, 4-5s cold start.
  Probably the analytics SDK init.
- **Onboarding "skip" button** — multiple users asked.

## 2026-05-19

- **Dashboard timezone weirdness** — sometimes shows yesterday's
  date.
```

H2 by date, bulleted entries with a bolded short title and a
sentence or two of context. The date header groups related notes
naturally; if a single day is sparse, the header is fine
remaining empty until the next entry.

### Promoting an entry to triage

`/task promote "<short identifier>"` (or by selecting an entry)
creates a `TASK-NNN` stub-content file in `tasks/triage/`,
removes the entry from `intake.md`, and stops there. The new
task has no phase, no category — the user (or `/task` itself, on
the next operation) decides those when graduating from triage to
backlog.

### Deleting an entry

`/task drop "<short identifier>"` removes the entry from
`intake.md` without creating a task. Use for ideas that have been
considered and discarded. Optionally moved to `.claude/wont-do.md`
if the rationale is worth keeping.

### Not for messages or scratchpad

`tasks/intake.md` is for *future tasks* — work the project might
do. For messages between contributors or personal scratchpad, use
`/inbox` (which writes to `.claude/inbox/`). The two surfaces are
adjacent but not interchangeable.

## Postmortem rule (incidents get captured)

The audit log records what shipped. The postmortem doc records
what *broke* and what we changed to prevent recurrence.

### When to write a postmortem

- Any production outage or rollback.
- Any hotfix (per the rule above — every 🔥 entry pairs with a
  postmortem).
- Any data loss / corruption / mis-stamp event.
- Any regression caught in production rather than pre-deploy.
- Near-misses that revealed a real gap, even if the user wasn't
  affected.

Bugs caught in code review or normal test runs do **not** need
postmortems — those are the system working.

### Where it lives

`docs/postmortems/YYYY-MM-DD-short-slug.md`. Create the directory
on first use. Use the `/postmortem` skill to draft.

### Linkage to AUDIT

Every postmortem appends an entry to `tasks/AUDIT.md` with the ⚠️
emoji and a link to the postmortem file. Hotfix-driven postmortems
also link to the 🔥 entry that triggered them.

### Action items become tasks

A postmortem with no action items isn't done — it's a story. Real
postmortems end with concrete, owned, linked tasks. File them via
`/task` immediately after the postmortem is drafted. "Pending
discussion" is acceptable for genuinely-unresolved items, but not
as a default.

## Final review run (the parade)

When the reviewer is ready to manually test a stack of merged or
about-to-be-merged tasks, they will run the project's full
verification suite in its watched/headed/observable mode (per
`CLAUDE.md`). Without filters, this runs every test in sequence
so the reviewer can spot anything that looks off and use it as the
lead-in to their own manual testing.

Don't redirect them to "just run the new test." The whole-suite
parade run is the contract — it's how regressions across tasks
get caught. The single-test focused mode is for inner-loop
iteration, not final review.
