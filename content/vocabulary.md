# Kit vocabulary

Canonical definitions of terms used across the kit — `task-rules.md`,
the skills, the templates, and chat. When one of these words appears
in a request, it means **exactly** what's defined here. Not broader,
not narrower.

The point of this file: stop re-deriving the same definitions in
every project's `CLAUDE.md`. If your project means something
different by one of these terms, override it cleanly in
`.claude/vocabulary-overrides.md` (see "How overrides work" at the
bottom). Don't fork the definition into prose somewhere else.

> **Where this file lives.** The kit ships this as
> `kit/vocabulary.md`. After `/sync`, it lands at
> `.claude/vocabulary.md` (file-replace each sync). Project
> overrides live at `.claude/vocabulary-overrides.md`
> (seed-only, skip-if-exists, never overwritten). Skills that
> resolve a term read overrides first and fall back here.

---

## Versioning

Semver for production deploys: `vMAJOR.MINOR.PATCH` — always
prefixed with lowercase `v`, always annotated tags.
The closer **proposes** a version with reasoning; the reviewer
confirms or overrides. Don't deploy without an agreed version.

- **Patch** (`vX.Y.Z+1`) — bug fixes, copy / styling tweaks,
  no new user-visible features.
- **Minor** (`vX.Y+1.0`) — new user-visible features, additive
  changes. The default for most batches.
- **Major** (`vX+1.0.0`) — breaking changes (route changes users
  had bookmarked, removed features, schema migrations that affect
  existing users). Rare. Always paired with a user-facing note.

> Override in `.claude/vocabulary-overrides.md` if your project
> means something different. Common reason: platform constraints
> that change the practical meaning of a bump.

**Known override case — iOS build-number monotonic constraint.**
On iOS, `CFBundleVersion` (build number) must be strictly
increasing per `CFBundleShortVersionString` (marketing version),
enforced by Apple at upload time. A "patch" in iOS terms often
means *bump the build number, keep the marketing version* — not
the same as a semver patch where the marketing version moves. iOS
projects typically tag as `vMAJOR.MINOR.PATCH-BUILD` (e.g.
`v5.0.10-110`) and override `patch` to mean "build-number bump
under the existing marketing version." See
`.claude/ios-task-rules.md` "Apple build-number constraint" for
the underlying rule.

## Tasks

- **Batch** — *a phase of tasks.* The set of tasks in one named
  phase from `tasks/ROADMAP.md`. "Working through a batch" =
  working through a phase. Not "any group of PRs." Not "a
  sprint." A phase. The `/spec-phase` skill prepares a batch; the
  Batch handoff in `batch-handoff.md` ships one. If the user says
  "let's batch up Phase N," they mean "treat Phase N's tasks as
  the unit of work."

- **Tag and bag** — *do everything needed to deploy everything
  ready right now.* Specifically: merge all branches that are
  ready for deployment into the release branch (via the Batch
  handoff integration flow if multiple are pending), build if the
  deploy command requires it, run the deploy, tag the resulting
  commit with an annotated semver tag, push the tag, and append
  the AUDIT entry. Equivalent to invoking `/release` once the
  queue is ready. Not "just tag the current commit." Not "just
  deploy without tagging." It's the full pipeline. If the user
  says "tag and bag," they're authorizing the whole release flow
  on whatever is currently green.

> Override in `.claude/vocabulary-overrides.md` if your team uses
> "batch" or "tag and bag" with a different operational scope.

## Lifecycle states

The state machine for task files — seven directories under
`tasks/`, and the directory **is** the state (there is no
`status:` field; see `.claude/task-rules.md` §1–§2):

```
triage/ → backlog/ → active/ → review/ → completed/
              ↕          ↕        ↕
              └──── blocked/ ─────┘
   (any state) ──────────────────→ closed/
```

A task moves **only** through `.claude/bin/task <verb>` (or `/task`)
— never `git mv`, never `mv`, never a frontmatter edit. The verb
writes the frontmatter, appends to `tasks/history.tsv` and moves
the file in one act.

- **Triage** — filed, has an id, nothing promised yet. Lives in
  `tasks/triage/` with no phase. `/task graduate` gives it one.
- **Backlog** — task is phased but not yet being worked. Lives in
  `tasks/backlog/`. May be a stub or a full spec (see "Stub vs
  spec" below).
- **Active** — a branch is being worked (no PR, or a draft).
  Lives in `tasks/active/`. Keep it small — one task at a time
  per agent is the advice.
- **Review** — the PR is open and ready; the done-gate
  (`.claude/done-gate.md`) has not passed yet. Lives in
  `tasks/review/`. `bin/task submit` puts it here when the PR
  opens; `bin/task reject` sends it back to `active/`.
- **Blocked** — task hit an external dependency (missing
  credential, waiting on another team, third-party outage,
  undecided product call). Enterable from backlog, active or
  review. Lives in `tasks/blocked/` with a `## Blocker` section
  naming what's blocking and what would unblock. `bin/task
  unblock` returns it to wherever it came from. *Not* for "I
  don't know how" (that's a recon problem) or "this is hard"
  (that's just work). See `task-rules.md` §10.
- **Completed** — the done-gate passed **and** the PR merged to
  `main`. Lives in `tasks/completed/`, moved there by `bin/task
  pass`. An open-but-unmerged PR is `review/` — `completed`
  means *merged*, not *opened*. (Renamed from `done` in
  v0.36.0; `done` was the prior term.)
- **Closed** — ended *without* being done: superseded,
  duplicate, obsolete, or wont-do. Lives in `tasks/closed/`,
  moved there by `bin/task close --resolution <R>`. Never folded
  into `completed/`.

> Override in `.claude/vocabulary-overrides.md` if your project
> tracks task state somewhere else (issue tracker, kanban tool,
> etc.) and the directory layout doesn't apply.

## Stub vs. spec

Two maturity levels (depths) for a task file. Both are valid at
any stage; the one you write depends on whether implementation is
imminent. Depth is **derived, not declared** — there is no stub
type, no depth field and no marker string. A task is a stub until
its `## Acceptance criteria` holds a real checkbox.

- **Stub** — minimal placeholder (`/task` calls it an outline).
  Title + 1-line user story + 1-line "why", no real acceptance
  criterion yet (`.claude/task-templates/stub.md`). Anything more
  is speculative. The default when a task is filed without a
  priority signal — full specs are expanded *close to
  implementation*, not at filing time. See
  `.claude/code-task-rules.md` §11 ("Filing: stub first") for
  what triggers a full spec at filing time.

- **Spec** — full implementation contract per
  `.claude/task-templates/<type>.md`. Self-sufficient: a
  developer reading only the spec, with no chat context, should be
  able to implement. Includes user story, scope (in/out),
  references (internal patterns + external doc URLs), files-
  expected-to-change with WHAT/WHY per file, acceptance criteria,
  test plan, manual verification steps, and open questions /
  risks. Stubs expand into specs via `/task` ("flesh out TASK-N")
  or `/spec-phase`.

> Override in `.claude/vocabulary-overrides.md` if your project
> uses different maturity levels (e.g., "draft / RFC / spec") or
> a different template shape.

## Phase

Phases are first-class organizational units. **Every task outside
`triage/` belongs to exactly one phase** — no orphans. "We'll
figure out where this fits later" is exactly what `triage/` is
for, and a triage task carries no phase. Per
`.claude/task-rules.md` §4, each phase has three things:

1. **A name.** "Phase N: <short noun-phrase>". Communicates the
   scope at a glance — e.g. "Phase 3: Core module CRUD",
   "Phase 8: Code cleanup".
2. **A scope paragraph.** 2–4 sentences in `tasks/ROADMAP.md`
   directly under the phase heading. States what's in, what's
   out, and (when useful) what success looks like. The scope is
   the *contract* — if a task doesn't fit it, the task belongs in
   a different phase.
3. **An ordered list of tasks.** Bulleted under the scope
   paragraph in ROADMAP. Order matters — top-down implies
   suggested ship order.

`tasks/ROADMAP.md` declares the phases (`## Phase <id> — <name>`)
and lists each task under its phase. The task file carries the
same fact as `phase: <id>`, written by `/task graduate`. The two
copies are proven to agree — `.claude/bin/check-tasks` fails on
a mismatch (I-20, I-22) — rather than one being forbidden.

> Override in `.claude/vocabulary-overrides.md` if your project
> uses a different organizational unit (epic, milestone, sprint,
> theme) or stores phase membership elsewhere.

## Verification gate

The project's contract test command — the headless / non-
interactive test invocation that **must** pass before a PR is
opened. The specific command lives in `CLAUDE.md` under
"Commands"; `.claude/done-gate.md` names it as the "Verification
suite" gate. The contract is the same across projects:

- **Headless / non-interactive.** Agents must run the version
  that doesn't require a display. Watched / headed variants are
  for inner-loop iteration, not the gate.
- **Unfiltered before opening the PR.** Running just the new
  test's filter is fine while iterating; the unfiltered run is
  the gate.
- **Failing the gate is a blocker.** Don't disable tests. Don't
  bypass hooks (`--no-verify` and equivalents). If you can't fix
  it in scope, write a blocker note and stop.

> Override in `.claude/vocabulary-overrides.md` if your project's
> "verification gate" includes more than tests (e.g., contract
> tests + lint + type-check as a single gate, or a CI workflow
> that gates on more than headless test pass).

## Gated file

A file or directory that **requires explicit permission to
modify**. Touching it without approval = blocker, not autonomous
work. The Element lists generic categories in
`.claude/code-task-rules.md` §9 ("Files that need permission to
change"); the authoritative project-specific list lives in
`CLAUDE.md` under "Gated files."

Common categories (kit defaults):
- Infrastructure / deploy config (`firebase.json`, `*.tf`, CI
  workflow files, `Dockerfile`, hosting config)
- Security / secrets (`.env`, `.env.example`, security-rules
  files, IAM config)
- Dependency manifests (`package.json`, `Cargo.toml`, `go.mod`,
  `Gemfile`, `pyproject.toml`, `Package.swift`) — adding,
  upgrading, or removing
- Build / runtime config (`vite.config.*`, `webpack.*`,
  `tsconfig*.json`, `babel.config.*`)
- Process / kit files (`CLAUDE.md`, `.claude/` contents,
  `.github/`, `.git/`)

> Override in `.claude/vocabulary-overrides.md` if your project
> has a different working definition (e.g., "any file with a
> CODEOWNERS entry" or "anything generated by the build").

## Hotfix

An emergency production fix that bypasses the integration-batch
buffer and goes straight to a tagged release after user
confirmation. Per `.claude/code-task-rules.md` §4 and
`.claude/release-rules.md` "Hotfix path":

- A hotfix is a `defect` with `priority: now` — there is no
  separate `HOTFIX-` id space. File it with `.claude/bin/task new
  --type defect --priority now --phase <P> "<what is broken>"`,
  which lands it in `tasks/active/`.
- Branch from `main` as `hotfix/TASK-NNN-slug`.
- Single concern per hotfix branch — no "while I'm here" bundling.
- Verification gate is still required.
- Deploy is **patch-bump only** (`vX.Y.Z` → `vX.Y.Z+1`). Major or
  minor bumps imply scope; hotfixes are scope-disciplined.
- Tagged with 🔥 in the AUDIT entry; pairs with a postmortem
  within 48 hours.

When NOT to invoke: if the bug is annoying-but-not-urgent. File a
normal task instead. Hotfix is a privilege that costs queue
discipline; spend it carefully.

> Override in `.claude/vocabulary-overrides.md` if your project
> uses a different word for the same concept ("incident fix",
> "patch", "emergency") or a different escalation discipline
> (e.g., on-call rotation triggers, paging policy).

## Reference stamp

The YAML frontmatter at the top of a kit-conventional markdown
file — the machine-readable identity that skills parse. The body
below the stamp is the qualitative context for humans and AI
synthesis. One file per resource, one directory per concept.

```markdown
---
name: <kebab-case-name>
kind: <discriminator>
<other structured fields>
---

# <Name>

Body content — prose, gotchas, references...
```

Used by `.claude/clouds/` (v0.16.0), `.claude/runtimes/` and
`.claude/tests/` (v0.18.0), and existing skill / agent files.
The pattern is "structured fields where it helps + prose where
it helps + one file" instead of "two files per resource" or
"prose blobs that AI has to parse."

Adding a new resource type that follows this pattern: ship a
`seed/<thing>.md.template`, scaffold the `.claude/<things>/`
directory in `rasa.json`, document in CHANGELOG, optionally add a
SKILL.md / script for skill integration.

> Override in `.claude/vocabulary-overrides.md` if your project
> uses a different framing for this pattern. Most projects won't
> need to — the term is descriptive, not prescriptive.

---

## Closing report

The mandatory completion report — written into the task file as a
`## Completion report` section before `.claude/bin/task pass`
moves it, and posted in chat when a task's PR is opened (or a
release ships, or a chore PR opens). Shape per
`.claude/task-rules.md` §11 and `.claude/code-task-rules.md` §10,
plus `.claude/release-rules.md` "Closing report after deploy".
The point is one-glance status — the reviewer scans the table in
5 seconds and decides whether to dig in.

The report is non-negotiable for shipping work. The
`What to do next` section is non-negotiable for every
task. Three outcomes only: ✅ done / ⚠️ blocked / ❌ failed.
No "almost ready," no "mostly done."

> Override in `.claude/vocabulary-overrides.md` if your project
> has additional required sections, a different status state set,
> or routes the report somewhere other than chat (e.g., the PR
> body only, a Slack channel).

---

## How overrides work

Projects override kit defaults in `.claude/vocabulary-overrides.md`.
When a skill resolves a term, it reads the project file first,
falling back to kit defaults here. Override only what your project
means differently — leave the rest implicit (inheriting the kit
default).

For each override, document:

- **The term being overridden** (use the same section name as in
  this file, so the mapping is unambiguous).
- **Your project's definition.**
- **The rationale** — often a platform constraint (Apple's build-
  number rule), a team convention (issue tracker is the source of
  truth, not `tasks/`), or a tool boundary (CI workflow gates on
  more than tests).

Don't restate kit defaults in the overrides file. The signal is
which terms are listed at all — silent inheritance is the desired
shape for everything you don't need to redefine.
