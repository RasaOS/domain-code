# Release Rules

This file covers release planning, production deploy tagging format,
version-bump heuristics, the hotfix path for emergencies, and
dependency hygiene (audit cadence and manifest discipline). **Read
this file when shipping a release or auditing dependencies.** It
extends `code-task-rules.md` (and through it `task-rules.md`); the
five Git flow safety rules in `git-flow-rules.md` also apply to
every release.

## Targeted vs Bundled

Every release has two lists, and they are separate **sections**, not two
labels on one list. That separation is what makes the ship-time logic
structurally unable to touch the fluid layer.

### Targeted — the plan

Fluid. A phase or task in **any** stage may be targeted at a release,
moved to another, or untargeted. No gate. `/release-plan` owns it.
`/release` never reads it, so a plan can be wrong all week at no risk.

### Bundled — the manifest

Committed. **Only completed work is bundled**: `tasks/completed/<ID>-*.md`
must exist. The directory decides, because the directory **is** the
state — `task-rules.md` §1 has no `status:` field to disagree with it.
`/release-add` owns it, and `/release` reads it and nothing else.

Bundling is harder to undo than targeting, deliberately:

1. Targeting is ungated; bundling requires completed work.
2. Bundling writes an approval line that did not previously exist.
3. Targeted work is not in the manifest and cannot ship by accident.
4. Shipping is terminal — targeting, bundling and unbundling all refuse
   on a ✅ entry, and the manifest is simultaneously frozen inside the
   annotated tag's message body.

### Approval

**Invocation is approval.** Running `/release-add` is the approval act;
there is no separate sign-off and no prompt. It is recorded once per
release as `**Approved.** <user> via invocation` — the same `invocation`
token the deploy ledger writes, so `grep -r invocation` joins a release
to the run that shipped it.

Do not add a confirmation prompt on top. `/release` has published
invocation-is-consent since v0.33.0, and a prompt cannot be answered from
a tool-driven shell with no controlling terminal anyway. Recording an
approver for a prompt that never fired would put a lie in an audit trail.

### No `release:` field on tasks

The release→work mapping lives in `tasks/RELEASES.md`, in one place.
Tasks do not declare their release: it would drift, and re-targeting
twelve tasks would mean editing twelve files instead of one. (`phase:`
is kept in the task file only because `bin/check-tasks` proves it
agrees with ROADMAP — `task-rules.md` §4. Nothing proves a `release:`
key, and an unrecognized bare key is an error anyway — I-11.)

### Version discipline

Headings are `## v<semver> — <glyph> <State>`. A duplicate version is
refused. A version that has already shipped is refused. A version *below*
the highest shipped one is **allowed** — maintenance lines are legitimate.

🚧 is **derived, not declared**: it means "has bundled work", and the
first successful bundle flips 📋 → 🚧. More than one open release is
legal and expected; `/release` with no argument asks which.

### Validating the ledger

`.claude/skills/release/release.sh check` — exit 0 clean, 3 on drift. It
catches duplicate versions, an id appearing twice, a glyph that
contradicts the bundled count, a shipped entry with no tag or approval,
and a pre-v0.48.0 file. It warns rather than fails on a tag that does not
resolve locally, since that depends on fetch state.

## Release tracking — `tasks/RELEASES.md`

`tasks/RELEASES.md` is the **live release tracker**: a single
timeline of releases, with the current "next" entry at the top
accumulating tasks as they merge to `main`, and shipped entries
below stamped with date + tag.

Tasks **auto-append** to the top "🚧 Next" entry when they land
on `main` (via `/peer-review`'s merge, via `/release`'s
integration merge, or by the user invoking `/release-add` after
a manual merge). The user does not maintain this file by hand.

### Format

```markdown
# Releases

🚧 v0.38.0  ◆  next release — accumulating since v0.37.0

- TASK-042 — fix login bug on iOS
- TASK-043 — add filter UI to the inbox
- TASK-044 — patch RBAC bypass on /admin

---

✅ v0.37.0  ◆  /sync-all — autonomous variant of /sync
              shipped 2026-05-20 · tag `v0.37.0-<sha>-prod` · sha f77a843

- TASK-040 — /sync-all skill
- TASK-041 — /sync When-NOT cross-reference

---

✅ v0.36.0  ◆  status overhaul — `blocked` added, `done` → `completed` (BREAKING)
              shipped 2026-05-20 · tag v0.36.0 · sha 8274f0f

- TASK-038 — done → completed rename
- TASK-039 — blocked state + Blocker discipline

---

✅ v0.35.0  ◆  task categories + intake layer
              shipped 2026-05-20 · tag v0.35.0 · sha 78c3e9a

- TASK-035 — categories (stub / spec / bug / hotfix)
- TASK-036 — intake.md layer
- TASK-037 — /auto-bug + /auto-hotfix
```

Format conventions, line by line:

- **Status glyph + version + diamond + summary line.** The 🚧
  marker means "in progress" (accumulating); ✅ means "shipped."
  The diamond `◆` separates the version from the one-line
  summary. The summary is the *release theme* — what makes this
  version coherent — not a task list.
- **Detail line** (shipped only). `shipped <YYYY-MM-DD> · tag
  <tag> · sha <short-sha>`. Indented two spaces under the version
  line.
- **Task list.** One bullet per task (hotfixes included) that
  landed in the release. `TASK-NNN — <title>`.
  Order is merge order (oldest first).
- **`---` separator** between entries.

### The lifecycle of an entry

Three states, but only two appear in the file at any given time:
the **one** "🚧 Next" entry at the top, and the **N** "✅
Shipped" entries below.

1. **🚧 Next** — the active accumulator. Always exactly one of
   these, at the top. The version number is the *next expected*
   version (computed from the last shipped version + the
   default bump). Tasks append as they merge.
2. **✅ Shipped** — terminal. `/release` flips the "🚧 Next"
   entry to "✅ Shipped" at ship time, fills in the date / tag /
   sha, then creates a **new** "🚧 Next" entry above it for the
   following release.

(Superseded in v0.48.0. The 📋 Planned state is back and is the whole
point: a release is declared BEFORE anything is in it, and work is
targeted at it while still in progress. The single-🚧-accumulator model
this paragraph used to describe never worked on a fresh install — the
seed produced zero 🚧 entries and `/release-add` hard-stopped on its
first run, which `/peer-review` then downgraded to a non-blocking note.
See CHANGELOG v0.48.0.)

### How tasks land in the "🚧 Next" entry

Auto-append happens on **merge to `main`** — the moment a task
becomes part of "what will ship next." Three paths land here:

1. **`/peer-review` merges a PR** → calls `/release-add` with the
   merged TASK-NNN.
2. **`/release` merges an integration branch** → calls
   `/release-add` for every TASK-NNN in the integration's commits.
3. **Manual `gh pr merge`** (no kit skill involved) → the user
   runs `/release-add` after the fact, or `/release-add
   --since-last-tag` to bulk-catch up.

`/release-add` is **idempotent** — re-running it for the same
task is a no-op. A task only appears once in the "🚧 Next"
entry regardless of how many times the merge is replayed.

### How `/release` uses the tracker

`/release` reads the "🚧 Next" entry as the **release manifest**.
At ship time:

1. **Cross-check** against what actually merged (commit log
   since last tag). Any TASK-NNN in commits-since-last-tag that
   isn't in the "🚧 Next" entry → flag and add (the user
   skipped a `/release-add`). Any TASK-NNN in the entry that
   isn't in commits-since-last-tag → flag and remove (the entry
   has a stale claim).
2. **Stamp the entry**: change `🚧` to `✅`, fill in `shipped
   <YYYY-MM-DD> · tag <tag> · sha <short-sha>`, fill in the
   release theme summary if it was a placeholder.
3. **Create the next "🚧 Next" entry** above the stamped entry,
   with the next expected version and an empty task list.
4. **Commit** the RELEASES.md change as part of `/release`'s
   audit commit (per `/release` Step 7).

### What's no longer here — moved to AUDIT

The 🚀 AUDIT entry on ship still happens (per the audit-log
rule, `code-task-rules.md` §12). RELEASES.md is the *release-shaped*
record; AUDIT.md is the *chronological* record. The two are
complementary, not redundant.

## Production deploy tagging (mandatory)

Every successful production deploy from `main` is tagged. Tags are
the version-controlled record of what shipped to users and when —
`git log --tags` becomes the deploy history.

### Format

Release tags carry the full build stamp:
`v<MAJOR>.<MINOR>.<PATCH>-<shortsha>-<env>` — e.g.
`v1.2.0-9f3a1c7-prod`. The semver is what the closer proposes and the
reviewer confirms; the `-<sha>-<env>` suffix is appended by
`environment.sh version`, so the tag records exactly which commit
shipped and to which environment. Always lowercase `v`. Lightweight
tags are not allowed — use **annotated** tags so the message can
carry release notes. See `environment-rules.md` for the version
model.

### Bootstrap

The first tagged release is **`v1.0.0`**. If the project has been
deployed before this rule existed, that history is "pre-versioning"
and is not retroactively tagged. Versioning starts forward from the
first invocation of this rule.

### Version-bump heuristic

The closer proposes a version with reasoning; the reviewer confirms
or overrides. Do not deploy without an agreed version.

- **Patch** (`vX.Y.Z+1`) — bug fixes, copy / styling tweaks, no new
  user-visible features.
- **Minor** (`vX.Y+1.0`) — new user-visible features, additive
  changes. The default for most batches.
- **Major** (`vX+1.0.0`) — breaking changes (route changes users had
  bookmarked, removed features, schema migrations that affect
  existing users). Rare. Always paired with a user-facing note.

### Deploy + tag flow (after "yes, deploy")

The deploy command is project-specific. See `CLAUDE.md` for the
exact command, or use `/release` which orchestrates the full
sequence. The shape:

```sh
<project's deploy command per CLAUDE.md>     # e.g. npm run deploy, fastlane release, etc.
# After deploy succeeds — build the tag, then tag and push:
TAG="$(bash .claude/skills/environment/environment.sh version prod --semver vX.Y.Z)"
git tag -a "$TAG" -m "<release notes>"       # on main HEAD
git push origin "$TAG"
```

Release-note message format (annotated tag body, multi-line):

```
vX.Y.Z — <one-line summary>

Tasks shipped:
- TASK-NNN — <name>
- TASK-NNN — <name>

Deployed: <YYYY-MM-DD HH:MM UTC>
Integration PR: #N
```

### Closing report after deploy

Include in the deploy completion report:

- The tag (`vX.Y.Z`) with a clickable link to its GitHub page
  (`https://github.com/<owner>/<repo>/releases/tag/<tag>`)
- Confirmation the tag was pushed to origin
- The merge-commit SHA that the tag points to

### Rollback semantics

The project's rollback command (per `CLAUDE.md`) reverts the live
build but does **not** move git tags. If a tagged release is rolled
back, the tag stays in place as a historical record of what was
deployed, and a new tag (a patch bump — `v<semver>-<sha>-<env>` as
usual) marks the restored version. Document the rollback in the new
tag's message.

## Hotfix path (emergencies)

The Batch Handoff and deploy flow assume the happy path: a batch
of features stabilized, integration-tested, then shipped. When
production is broken, that flow is too slow. The hotfix path
exists for "fix is needed *now*, the queue can wait."

### When to invoke

- Production is bricked or in a clearly-bad state.
- A deployed bug is causing data loss, security exposure, or
  user-blocking errors.
- A regression caught in stage that would block the next deploy
  if shipped.

If the bug is annoying-but-not-urgent, **don't hotfix.** File a
normal task and ship in the next batch. Hotfix is a privilege
that costs queue discipline; spend it carefully.

### Flow

1. **File it, then branch from `main`.** A hotfix is a `defect`
   with `priority: now` — there is no separate `HOTFIX-` id space
   (`code-task-rules.md` §4). `.claude/bin/task new --type defect
   --priority now --phase <P> "<what is broken>"` lands it in
   `tasks/active/`. Branch `hotfix/TASK-NNN-slug`.
2. **Single concern.** A hotfix branch fixes exactly one thing.
   Don't bundle a "while I'm here" change. Bundling defeats the
   speed argument.
3. **Verification gate is still required.** The full test gate (per
   `CLAUDE.md`) must be green. Hotfix does not mean "skip tests."
   If the test gate is broken because of the bug, surface that —
   repair it as part of the hotfix, don't bypass.
4. **PR opens with title `TASK-NNN: <summary>`** and a body
   explaining the symptom, root cause, fix, and verification;
   `.claude/bin/task submit <id>` moves the task to `review/`.
   Closing report uses the same shape as a task PR.
5. **Deploy is patch-bump only.** `vX.Y.Z` → `vX.Y.Z+1`. Major or
   minor bumps imply scope; hotfixes are scope-disciplined patches.
6. **Tag with 🔥 in the AUDIT entry** so future readers can find
   the incident chain at a glance:
   ```
   - 🔥 **Hotfix TASK-NNN — <summary>.** Released vX.Y.Z+1.
     Postmortem at docs/postmortems/YYYY-MM-DD-….md.
   ```
7. **Postmortem follows.** Per the postmortem rule
   (`code-task-rules.md` §13), every hotfix triggers a postmortem
   within 48 hours. The point is the lesson, not the absolution.

### What hotfix does NOT change

- The verification gate is still the contract.
- The deploy-tagging rule still applies (annotated tag, pushed to
  origin, AUDIT entry).
- **Invocation is consent — same as a normal release.** Per
  `git-flow-rules.md` Rule 5 and `kit/skills/release/SKILL.md`,
  typing `/release` on a hotfix branch IS the deploy
  authorization. "Hotfix" doesn't change the contract — it
  changes the route (skip the integration-batch buffer, default
  to a patch bump) but not the authorization model. The skill
  still hard-stops on real blockers (failed tests, failed build,
  missing deploy command).

## Dependency hygiene

Dependencies drift. Drift becomes vulnerabilities. This rule keeps
the project honest about its dependency surface without turning
dependency management into a daily chore.

### Adding / upgrading / removing dependencies

- Touching the project's manifest file(s) (`package.json`,
  `Cargo.toml`, `go.mod`, `Gemfile`, `pyproject.toml`,
  `Package.swift`, etc.) is a **gated file** per the existing
  permission rule (`code-task-rules.md` §9). The user approves any
  add/upgrade/remove.
- The PR that touches the manifest also commits the lockfile
  update (`package-lock.json`, `Cargo.lock`, `go.sum`,
  `Gemfile.lock`, etc.). Lockfile out of sync with manifest is a
  blocker.
- Major-version upgrades require explicit acknowledgment — they
  often ship breaking changes that need a release-notes scan.

### Audit cadence

- **On every release** (every `/release` invocation): run the
  project's audit command (`npm audit`, `cargo audit`,
  `bundle audit`, `pip-audit`, `gradle dependencyCheck`, etc.).
  Surface any HIGH or CRITICAL findings in the deploy closing
  report. Don't auto-block on advisories — the user decides
  whether to ship-then-patch or fix-first.
- **Quarterly sweep** — once per quarter, run a full dependency
  audit + targeted upgrade pass. File the work as a task so it's
  tracked, not done as a side-effect of other work.

### What this rule does NOT require

- Daily / weekly auto-PRs from Renovate / Dependabot (fine to have,
  not required).
- Pinning every transitive dependency (rely on lockfile).
- Upgrading on every release (cadence is quarterly, with
  release-time advisory awareness).

### Linkage to AUDIT

Significant dependency events get an AUDIT entry:

- Major-version upgrades of a foundation dependency (framework,
  build tool, language runtime).
- Security patches for HIGH/CRITICAL advisories.
- Switching out a dependency for an alternative.

Routine patch-level upgrades don't need their own AUDIT entry —
they ride on the release entry.
