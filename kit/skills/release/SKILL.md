---
name: release
description: Cut a production release end-to-end — preflight, merge integration into main, tag the release commit, deploy, push the tag, append AUDIT entry. Reads the project's CLAUDE.md / DEPLOY.md / manifests to discover the actual deploy command. **Invocation is consent: this skill does not ask for confirmation at any soft gate.** It stops only at hard blockers (auth, failed tests, dirty tree, missing deploy command, etc.). Triggered when the user wants to ship — e.g. "/release", "/release patch", "/release v1.2.0", "ship it", "cut a release".
---

# /release — Cut a production release

Orchestrate the deploy sequence end-to-end. Discover the project's
deploy command from its docs and manifests rather than hardcoding,
then run the canonical sequence: **preflight → merge integration
→ tag → deploy → push tag → record**.

**Invocation is consent.** The user typed `/release` — that is the
release authorization. This skill does not ask "are you sure?",
does not ask "deploy now?", does not ask the user to confirm the
version. Soft confirmation gates were removed in v0.33.0 because
they caused alarm fatigue and missed deploys. The contract now:
**run it, or stop hard on a real blocker**.

See `git-flow-rules.md` Rule 2 carve-out (user-invoked
merge-bearing skills) and Rule 5 (deploys route through
`/release`; invocation is the deploy authorization).

## Behavior contract

- **Invocation is the user confirmation.** No "Deploy now?"
  prompts. No "Confirm version?" prompts. No "Proceed through
  these warnings?" prompts. The user invoked the skill — that is
  the consent. The skill's job is to discover, verify, execute,
  or stop hard on a real blocker.
- **Hard blockers stop the run.** A hard blocker is a *real*
  failure — not "we'd like to double-check." The full list:
  - Auth failure (no credentials, expired token, gh/azure/etc.
    not logged in).
  - Pre-flight failure (dirty working tree, behind upstream,
    branch in a state the deploy can't run from).
  - Verification gate failure (the project's test command exits
    non-zero).
  - Build failure (the project's build command exits non-zero,
    OR emits warnings the project's config marks as fatal).
  - Missing deploy command (no `CLAUDE.md` / `DEPLOY.md` /
    manifest entry, no `package.json` scripts match).
  - Missing release-plan match (a `tasks/RELEASES.md` entry
    declares scope that doesn't match what merged — surface the
    mismatch and stop).
  - Merge refused by branch protection (the integration → main
    merge fails the remote's protection rules).
  - Deploy command itself fails — stop, no retry, report exactly
    what failed.
- **Pick the version; do not ask.** If invoked with a version arg
  (`/release patch`, `/release minor`, `/release major`,
  `/release v1.2.3`), use that. Otherwise compute it from the
  heuristic in `task-rules.md` / `release-rules.md`. The choice
  is logged as a flagged assumption in the closing report.
- **Order: preflight → merge → tag → deploy → push tag.** The
  tag is created on the merge commit *before* deploy runs, so
  the commit's identity is locked. The tag is pushed *after*
  deploy succeeds, so a failed deploy doesn't publish a stale
  release tag.
- **Platform routing is automatic.** If a `<platform>-release`
  skill exists for the detected platform, route to it. Do not
  ask — the user invoked `/release`, they want the right release
  skill for their platform. The closing report names which skill
  actually ran.
- **Discover, don't assume — except for deploy command tie-breaks.**
  Read `CLAUDE.md`, `DEPLOY.md`, manifest files in order. If
  multiple deploy commands are candidates, pick the most-specific
  one (`deploy:prod` over `deploy`, `release:prod` over
  `release`), flag as an assumption. If *no* command is
  documented, hard-stop — guessing prod commands is the one
  inference the skill won't make.
- **Annotated tags only.** `git tag -a` with release notes.
  Lightweight tags do not carry the notes message.
- **AUDIT and RELEASES recorded.** `tasks/AUDIT.md` gets a 🚀
  entry; `tasks/RELEASES.md` flips the version's entry to
  ✅ Shipped with the tag. These edits are committed to `main`
  as part of the release — they are not left dangling.
- **Honest reporting on failure.** Partial state is the worst
  state to leave undocumented. Any failure mid-flow is captured
  in the closing report with the exact step that failed, the
  exact command, the exact error. No retry without explicit user
  re-invocation.

## What changed from the pre-v0.33.0 contract

Pre-v0.33.0 `/release` was a confirmation-heavy skill: ask on
platform delegation, ask on warnings, ask on version, ask on
deploy. Six+ soft gates between invocation and shipped. The
v0.33.0 contract removes all of them. The trade-off is
deliberate:

- **You gain:** no missed deploys from "I thought I already
  confirmed", no alarm fatigue, faster ship cycle.
- **You give up:** the chance to abort mid-flow without
  invoking the project's rollback. If you typo'd `/release`, it
  ships.

The cost of "typo ships" is mitigated by `/release` not being a
common typo target. The cost of "ask 3 times" was missed
deploys, which is documented worse.

## Output structure

This skill produces several outputs across its flow. Each pins a
catalogue entry per `output-rules.md`:

- **Pre-flight check** (Step 1) → §2 Live status dashboard. Each
  check is a row; ● = passed, ◐ = running, ✗ = failed.
- **Version selection** (Step 2) → markdown blockquote stating
  the version and the reasoning. No question; informational only.
- **Merge to main** (Step 3) → §2 dashboard row (or its own
  block if the merge fails).
- **Any failure** (Steps 1–7) → §25 Alert variants (ERROR).
  Stops the flow.
- **Closing report** (Step 8) → §5 Deployment report. The big
  artifact the user takes away.

Concrete templates are inlined in each step below.

## The flow

### Step 0 — Platform detection + auto-routing

Determine the project's platform:

1. **Explicit declaration in `CLAUDE.md`.** A `## Platform`
   section or a `Platform: <name>` header — use it verbatim.
2. **Inferred from manifests** when `CLAUDE.md` is silent:
   - `*.xcodeproj` / `*.xcworkspace` / `Package.swift` → `ios`
   - `package.json` with `"react-native"` dep → `react-native`
   - `package.json` (no react-native) → `web`
   - `pyproject.toml` / `setup.py` → `python`
   - `build.gradle` / `*.gradle.kts` with `android` plugin →
     `android`
   - Otherwise → `universal`

3. **Check for a platform-specific release skill** in
   `.claude/skills/`. If `<platform>-release` exists, **route
   to it automatically** — execute that skill's flow. State
   what's happening in the report; do not ask.

If no platform-specific skill exists, continue with the
universal flow below.

### Step 1 — Pre-flight check

Run in parallel:

- `git rev-parse --abbrev-ref HEAD` — capture the current branch.
- `git status --porcelain` — must be empty (no dirty files).
- `git fetch origin` — capture remote state.
- `git log HEAD..origin/main --oneline` — if non-empty AND on
  main, the local is behind; hard-stop with "behind upstream."
- `git describe --tags --abbrev=0` — capture the previous tag.
- `gh pr list --state open --base main` — for visibility; not
  a stop condition.
- The project's verification gate (test command from `CLAUDE.md`).
  Must exit 0.
- The project's build command (from `CLAUDE.md` / manifest).
  Must exit 0 unless project config marks warnings as fatal.
- Deploy command discoverable per "Discover" in the contract
  above. Must be present.
- `tasks/RELEASES.md` lookup — if a `📋 Planned` or `🚧 In
  progress` entry exists for an upcoming version, check it
  against what merged. Mismatch = hard-stop with the diff.

Render the pre-flight summary as a §2 Live status dashboard:

```
┌─ pre-flight · <version> release ───────────────────────┐
│                                                        │
│  ●  branch          <branch>                           │
│  ●  working tree    clean                              │
│  ●  upstream        in sync                            │
│  ●  tests           <count>/<count> green              │
│  ●  build           clean                              │
│  ●  deploy command  <discovered>                       │
│  ●  release plan    matches                            │
│                                                        │
│  ✓ all checks passed — proceeding to merge             │
└────────────────────────────────────────────────────────┘
```

Glyph semantics: ● = passed, ◐ = running, ✗ = failed. Any ✗ →
the footer becomes a §25 ERROR alert and the skill **stops**:

```
┌─ ✗  ERROR ─────────────────────────────────────────────┐
│  pre-flight failed — <which check>                     │
│  <exact reason; full output above>                     │
│  hard-stop per /release contract.                      │
└────────────────────────────────────────────────────────┘
```

### Step 2 — Pick version

If invoked with a version arg, use it:

- `/release patch` → next patch bump from the previous tag.
- `/release minor` → next minor bump.
- `/release major` → next major bump.
- `/release v1.2.3` → exactly that semver.

If no arg, compute the next version from the
`release-rules.md` / `task-rules.md` heuristic:

- **Patch** — bug fixes, copy/styling tweaks.
- **Minor** — new user-visible features, additive (default).
- **Major** — breaking changes, schema migrations.

State the choice:

> **Version:** `v1.2.0` (minor) — proceeding without
> confirmation per /release contract. Reasoning: <one-line>.
> Override by re-invoking with explicit version arg.

This is informational, not a question. The flow continues.

### Step 3 — Merge integration → main

If the current branch is `main` and pre-flight confirmed nothing
to merge, **skip this step**. The release is being cut on
already-merged work; that's a valid path.

Otherwise, merge the current branch into `main`:

1. `git checkout main`
2. `git pull --ff-only origin main` — must succeed; failure
   means main moved unexpectedly, hard-stop.
3. `git merge --no-ff <integration-branch> -m "Merge
   <integration-branch> into main (<version>)"` — `--no-ff`
   preserves the integration branch's history as a merge bubble,
   matching the project's existing release-merge convention.
4. If the merge has conflicts, hard-stop. Report exactly which
   files; do not attempt to resolve.

The merge commit is the release commit — its SHA is what the tag
will reference. Capture it:

```sh
RELEASE_SHA=$(git rev-parse HEAD)
```

### Step 4 — Tag the release commit (local)

Build the canonical tag string from version + sha + env using
the kit's `environment.sh`:

```sh
TAG="$(bash .claude/skills/environment/environment.sh version prod --semver v1.2.0)"
# Result: v1.2.0-<sha>-prod
```

Create the annotated tag locally (do not push yet):

```sh
git tag -a "$TAG" -m "<release notes — format below>"
```

Release-notes message format (from `release-rules.md`):

```
v1.2.0 — <one-line summary>

Tasks shipped:
- TASK-NNN — <name>
- TASK-NNN — <name>

Deployed: <YYYY-MM-DD HH:MM UTC>
Integration: <branch>
```

Pull the task list from the integration branch's commit history
or from the `tasks/RELEASES.md` entry's scope declaration.

The tag is **local-only** at this point. Push happens in Step 6,
only if deploy succeeds.

### Step 5 — Deploy

Run the deploy command in the foreground. Capture full output.

```sh
<deploy-command>
```

If it succeeds → continue to Step 6.

If it fails → **hard-stop**. Do not retry. Report exactly what
failed, the exact command, the exact error. The local tag from
Step 4 remains — the user decides whether to delete it (it
represents "tried to ship v1.2.0; deploy failed") or keep it as
a record of the attempt.

### Step 6 — Push the tag

After deploy success:

```sh
git push origin main
git push origin "$TAG"
```

Two separate pushes — the main push (carrying the merge commit)
and the tag push are distinct operations and should not be
combined. If the tag push fails (network, auth), report it as a
partial-state warning: the deploy went live but the tag isn't
remote yet. The user resolves by pushing the tag manually.

### Step 7 — Record the release

Two files capture what shipped.

**`tasks/AUDIT.md`** — add a 🚀 entry under today's date header:

```markdown
- 🚀 **Released v1.2.0** — <one-line summary>. Tag
  `v1.2.0-<sha>-prod`. Integration: <branch>.
```

**`tasks/RELEASES.md`** — flip this version's entry to ✅ Shipped
and add a `**Tag.**` line with the git tag. If the release
shipped with no plan entry, add one retroactively as ✅ Shipped.

Commit these edits to `main` as the post-release audit commit:

```sh
git add tasks/AUDIT.md tasks/RELEASES.md
git commit -m "audit: record v1.2.0 release"
git push origin main
```

This commit is part of the contract — partial state ("deploy
shipped but no audit entry") is not acceptable. If the commit
fails, report it as a partial-state warning.

### Step 8 — Closing report

Render the deploy completion report per §5 Deployment report
(per `task-rules.md` "Closing report after deploy"):

````markdown
# Release v1.2.0 — shipped

```
  ▲  DEPLOYMENT   ·   <env>   ·   v1.2.0


  ┌─ release ──────────────────────────────────────────┐
  │                                                    │
  │   ●  pre-flight      passed      <duration>        │
  │   ●  merge to main   <branch>    <duration>        │
  │   ●  tagged          <tag>       <duration>        │
  │   ●  deploy          succeeded   <duration>        │
  │   ●  tag pushed      ✓                             │
  │   ●  audit recorded  ✓                             │
  │                                                    │
  └────────────────────────────────────────────────────┘


  tag           v1.2.0-<sha>-prod
  branch        main  ←  <integration-branch>
  deployed by   <user>
  started       <YYYY-MM-DD HH:MM UTC>
  completed     <YYYY-MM-DD HH:MM UTC>  ·  <duration>


  →  <live URL from CLAUDE.md / DEPLOY.md>
  →  https://github.com/<owner>/<repo>/releases/tag/v1.2.0-<sha>-prod
```

**Tasks shipped**
- TASK-NNN — <name>
- TASK-NNN — <name>

**Decisions made (no confirmation taken per /release contract)**
- ⚠️ Version: `v1.2.0` (minor) — <reasoning>
- ⚠️ Deploy command: `<cmd>` — <source-file>

**Rollback** *(if needed)*
- Hosting rollback: `<command, e.g. firebase hosting:rollback>`
- Note: rollback reverts the live build; the tag stays in place
  per `task-rules.md` "Rollback semantics".
````

Glyph semantics: ● = step succeeded, ◐ = step running, ✗ = step
failed (would have hard-stopped before this report). ▲ marks the
version bump.

If any step partially succeeded (deploy went through, tag push
failed; or deploy went through, audit commit failed), use a §25
WARNING alert instead of §5 — the deployment box implies a clean
release, which a partial state isn't.

## What you must NOT do

- **Don't ask for confirmation at soft gates.** Invocation is
  consent. Soft gates are gone. If you find yourself prompting
  "Proceed?", "Deploy now?", "Confirm version?" — stop. The
  contract was inverted in v0.33.0 for documented reasons.
- **Don't retry a failed step.** Hard-stop, report, let the user
  re-invoke. Partial deploy state is dangerous; investigate
  before retrying.
- **Don't push a tag before deploy succeeds.** Tag is created
  locally in Step 4, pushed in Step 6. A pushed tag for a failed
  deploy is a misleading public record.
- **Don't run lightweight tags.** Annotated only.
- **Don't deploy with a dirty working tree.** Hard-stop at
  pre-flight.
- **Don't auto-route to a platform skill the user didn't intend.**
  Platform routing in Step 0 is the kit's convention. If the
  user wanted the universal flow despite an iOS project, they
  can invoke `/release-universal` (if it exists) or amend
  `CLAUDE.md` with an explicit `Platform: universal`.

## Edge cases

- **No annotated tags exist yet** (first release): bootstrap at
  `v1.0.0` per the project's tagging rule. No version arg
  required; the bootstrap is the choice.
- **Hotfix path**: if the user invoked this skill via a hotfix
  branch (`hotfix/HOTFIX-NNN-slug`), defer to the project's
  hotfix rule (typically: branch off main, patch bump,
  fast-track verification, audit entry tagged 🔥). The contract
  is the same — invocation is consent — but the version
  defaults to patch.
- **No deploy command documented**: hard-stop. Do not infer from
  filename ("ah, `firebase.json` exists, so probably `firebase
  deploy`"). The user documents the command in `CLAUDE.md` /
  `DEPLOY.md` and re-invokes.
- **Release plan mismatch**: a `tasks/RELEASES.md` entry declares
  scope (tasks/phases). Pre-flight checks that the declared
  scope matches what's about to merge. Mismatch = hard-stop with
  the specific diff (planned-but-not-shipped, shipped-but-not-planned).

## When NOT to use this skill

- **Just verifying a build** → `/build`.
- **Running locally** → `/run`.
- **Reverting / rolling back** → use the project's rollback
  command directly. This skill cuts forward releases; rollback
  is its own operation (and should append an AUDIT entry too —
  do that by hand for now).
- **Pre-release / staging deploy** that doesn't tag — most
  projects have a separate `deploy:preview` or `deploy:stage`
  flow. That's not this skill. `/mission` may run a non-prod
  preview deploy when its goal asks for it (per
  `autonomy-rules.md` Exception 3) — that's the preview path.

## What "done" looks like for a /release session

- Pre-flight passed (every check ●).
- Integration branch merged to main (the release commit exists).
- Annotated tag created on the release commit AND pushed.
- Live build deployed.
- `AUDIT.md` entry appended; `RELEASES.md` entry marked ✅
  Shipped; both committed to main.
- Closing report rendered with the tag URL, commit SHA, and the
  rollback escape hatch.

If any of those didn't happen, the release isn't done. Be
explicit about it in the closing report — partial state is the
worst state to leave undocumented.
