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
> (bootstrap-only, skip-if-exists, never overwritten). Skills that
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
  Batch handoff in `task-rules.md` ships one. If the user says
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

The state machine for task spec files:

```
tasks/backlog/  →  tasks/active/  →  tasks/completed/
```

- **Backlog** — task is filed but not yet being worked. Lives in
  `tasks/backlog/`. May be a stub or a full spec (see "Stub vs
  spec" below).
- **Active** — task is being worked right now. Lives in
  `tasks/active/`. **At most one task at a time per agent.** Move
  the file with `git mv` as you transition states.
- **Blocked** — task was active but hit an external dependency
  (missing credential, waiting on another team, third-party
  outage, undecided product call). Lives in `tasks/blocked/` with
  a `## Blocker` section naming what's blocking and what would
  unblock. Returns to `active/` when unblocked. *Not* for "I
  don't know how" (that's a recon problem) or "this is hard"
  (that's just work). See `task-rules.md` "The blocked state".
- **Completed** — task has shipped: PR merged to `main`. Lives
  in `tasks/completed/`. Open-but-unmerged PRs stay in `active/`
  — `completed` means *merged*, not *opened*. (Renamed from
  `done` in kit v0.36.0; `done` was the prior term.)

> Override in `.claude/vocabulary-overrides.md` if your project
> tracks task state somewhere else (issue tracker, kanban tool,
> etc.) and the directory layout doesn't apply.

## Stub vs. spec

Two maturity levels for a task file. Both are valid lifecycle
states; the one you write depends on whether implementation is
imminent.

- **Stub** — minimal placeholder. Title + 1-line user story +
  1-line "why" + `STATUS: STUB — full spec drafted before
  implementation`. Anything more is speculative. The default when
  a task is filed without a priority signal — full specs are
  expanded *close to implementation*, not at filing time. See
  `.claude/task-rules.md` "Adding tasks to the backlog (priority
  rule)" for what triggers a full spec at filing time.

- **Spec** — full implementation contract per
  `.claude/task-template.md`. Self-sufficient: a developer reading
  only the spec, with no chat context, should be able to
  implement. Includes user story, scope (in/out), references
  (internal patterns + external doc URLs), files-expected-to-
  change with WHAT/WHY per file, acceptance criteria, test plan,
  manual verification steps, and open questions / risks. Stubs
  expand into specs via `/task` Operation 3 or `/spec-phase`.

> Override in `.claude/vocabulary-overrides.md` if your project
> uses different maturity levels (e.g., "draft / RFC / spec") or
> a different template shape.

## Phase

Phases are first-class organizational units. **Every task belongs
to exactly one phase** — no orphans, no "we'll figure out where
this fits later." Per `.claude/task-rules.md` "Phase structure",
each phase has three things:

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

`tasks/ROADMAP.md` is the registry. Phase membership lives there,
nowhere else. Tasks don't declare their phase in their own spec
file (that would drift).

> Override in `.claude/vocabulary-overrides.md` if your project
> uses a different organizational unit (epic, milestone, sprint,
> theme) or stores phase membership elsewhere.

## Verification gate

The project's contract test command — the headless / non-
interactive test invocation that **must** pass before a PR is
opened. The specific command lives in `CLAUDE.md` under
"Commands." The contract is the same across projects:

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
work. The kit lists generic categories in `.claude/task-rules.md`
"Files that require explicit permission to modify"; the
authoritative project-specific list lives in `CLAUDE.md` under
"Gated files."

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
confirmation. Per `.claude/task-rules.md` "Hotfix path":

- Branch from `main` as `hotfix/HOTFIX-NNN-slug`. HOTFIX numbering
  is independent of TASK numbering, restarts at 001 for the
  project, increments per incident.
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
`bootstrap/<thing>.md.template`, scaffold the `.claude/<things>/`
directory in MANIFEST, document in CHANGELOG, optionally add a
SKILL.md / script for skill integration.

> Override in `.claude/vocabulary-overrides.md` if your project
> uses a different framing for this pattern. Most projects won't
> need to — the term is descriptive, not prescriptive.

---

## Closing report

The mandatory completion report posted in chat when a task's PR is
opened (or a release ships, or a chore PR opens). Shape per
`.claude/task-rules.md` "Closing report (mandatory)" and "Closing
report after deploy". The point is one-glance status — the
reviewer scans the table in 5 seconds and decides whether to dig
in.

The report is non-negotiable for shipping work. The
`What you need to do next` section is non-negotiable for every
task. Three status states only: ✅ Ready for review / ⚠️ Blocked
/ ❌ Failed. No "almost ready," no "mostly done."

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
