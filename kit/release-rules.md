# Release Rules

This file covers release planning, production deploy tagging format,
version-bump heuristics, the hotfix path for emergencies, and
dependency hygiene (audit cadence and manifest discipline). **Read
this file when shipping a release or auditing dependencies.** It
extends `task-rules.md`; the five Git flow safety rules in
`git-flow-rules.md` also apply to every release.

## Release planning

A release is **planned before it ships**, not assembled after the
fact. `tasks/RELEASES.md` is the plan: one entry per release —
version, status, and the phases / tasks slated for it.

### The release lifecycle

A release entry moves through three states:

- 📋 **Planned** — scope declared (which phases / tasks), not yet
  building toward it.
- 🚧 **In progress** — the integration branch is accumulating the
  release's tasks.
- ✅ **Shipped** — released; the entry records the git tag.

### Declaring scope

Scope is **phases and tasks**, not freeform prose. A release usually
ships one or more whole phases (`Phase 3 — Core CRUD`); a task that
isn't covered by a scoped phase is listed individually
(`TASK-204 — …`). Because phases and tasks carry IDs, the plan
cross-references directly against `ROADMAP.md` and the code.

### How `/release` uses the plan

When you cut a release, `/release` reads the matching `RELEASES.md`
entry and **cross-checks the declared scope against what actually
merged**: every task in a scoped phase should be `done`, and anything
planned-but-not-merged or merged-but-not-planned is surfaced before
the deploy is confirmed. The release plan is the contract; the deploy
verifies it. After a successful deploy, the entry's status moves to
✅ Shipped with the git tag recorded.

### Planning vs. logging

`RELEASES.md` is forward-looking — what *will* ship. `tasks/AUDIT.md`
is the backward-looking log of what *did*. The two meet at ship time:
the release entry flips to ✅ and a 🚀 AUDIT entry is appended.

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

1. **Branch from `main`.** `hotfix/HOTFIX-NNN-slug` (HOTFIX
   numbering is independent of TASK numbering — restart at 001
   for the project, increment per incident).
2. **Single concern.** A hotfix branch fixes exactly one thing.
   Don't bundle a "while I'm here" change. Bundling defeats the
   speed argument.
3. **Verification gate is still required.** The full test gate (per
   `CLAUDE.md`) must be green. Hotfix does not mean "skip tests."
   If the test gate is broken because of the bug, surface that —
   repair it as part of the hotfix, don't bypass.
4. **PR opens with title `HOTFIX-NNN: <summary>`** and a body
   explaining the symptom, root cause, fix, and verification.
   Closing report uses the same shape as a task PR.
5. **Deploy is patch-bump only.** `vX.Y.Z` → `vX.Y.Z+1`. Major or
   minor bumps imply scope; hotfixes are scope-disciplined patches.
6. **Tag with 🔥 in the AUDIT entry** so future readers can find
   the incident chain at a glance:
   ```
   - 🔥 **Hotfix HOTFIX-NNN — <summary>.** Released vX.Y.Z+1.
     Postmortem at docs/postmortems/YYYY-MM-DD-….md.
   ```
7. **Postmortem follows.** Per the postmortem rule below, every
   hotfix triggers a postmortem within 48 hours. The point is
   the lesson, not the absolution.

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
  permission rule. The user approves any add/upgrade/remove.
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
