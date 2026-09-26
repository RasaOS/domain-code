---
name: release
description: Cut a production release end-to-end — preflight, merge integration into main, tag the release commit, deploy, push the tag, append AUDIT entry. Ships through the build → test → deploy chain: builds and tests the release commit (`./build/build`, `./build/test`), deploys that build to staging, then promotes the same build to production with `./build/deploy --intent=release`; falls back to a deploy command discovered from CLAUDE.md / DEPLOY.md only for a project with no pipeline. **Invocation is consent: this skill does not ask for confirmation at any soft gate.** It stops only at hard blockers (auth, failed build or tests, dirty tree, a refused gate, no pipeline and no deploy command, etc.). Triggered when the user wants to ship — e.g. "/release", "/release patch", "/release v1.2.0", "ship it", "cut a release".
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
  heuristic in `release-rules.md`. The choice
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
- The tree must be clean **of source**: `build/gates/git-clean.sh`
  with `ENV_CLASS=prod` (it ignores the pipeline's own records —
  `deploys/`, `builds/`, `tests/runs/`). A bare `git status
  --porcelain` counts those records and would stop every release.
- `git fetch origin` — capture remote state.
- `git log HEAD..origin/main --oneline` — if non-empty AND on
  main, the local is behind; hard-stop with "behind upstream."
- `git describe --tags --abbrev=0` — capture the previous tag.
- `gh pr list --state open --base main` — for visibility; not
  a stop condition.
- **Pipeline present?** `./build/deploy`, `./build/build` and
  `./build/test` exist → the release goes through the chain (Step 5)
  and there is no separate build or test to run here: Step 5 builds
  and tests the exact commit that ships. **No pipeline** → the
  fallback: the project's test command and build command (from
  `CLAUDE.md`) must exit 0, and a deploy command must be
  discoverable per "Discover" above.
- `tasks/RELEASES.md` lookup — read the release being shipped and
  cross-check it against commits since the last tag. **Report only;
  this step does not write** (see "Release tracker" below).

Render the pre-flight summary as a §2 Live status dashboard:

```
┌─ pre-flight · <version> release ───────────────────────┐
│                                                        │
│  ●  branch          <branch>                           │
│  ●  working tree    clean                              │
│  ●  upstream        in sync                            │
│  ●  build + test    in Step 5 (chain) | <n> green      │
│  ●  ship path       pipeline chain | fallback: <cmd>   │
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

**Release tracker (v0.48.0).** Run
`bash .claude/skills/release/release.sh check` — exit 3 is a **hard
blocker**, the tracker is malformed and the manifest cannot be trusted.

Then resolve which release is shipping: an explicit argument, else the
single 🚧 release, else **ask**. More than one open release is legal now,
so never guess.

`release.sh manifest <version>` prints the bundled bullets. That is the
release manifest — `### Targeted` is NOT part of it and must not be read
here. Work can merge to `main` and legitimately not belong to this
release.

**This step does not write.** It previously *silently added* missed task
ids during preflight — a write during the step that just asserted the
tree is clean, on a path the production clean-tree gate counts. Report
instead:

- ids in commits since the last tag that are bundled nowhere → list them
  as "not in any release; `/release-add` them if they belong here";
- ids bundled into this release with no commit since the last tag → list
  them as "bundled but not seen in commits".

Both are **reports**. Neither edits the file, and neither blocks.

### Step 2 — Pick version

If invoked with a version arg, use it:

- `/release patch` → next patch bump from the previous tag.
- `/release minor` → next minor bump.
- `/release major` → next major bump.
- `/release v1.2.3` → exactly that semver.

If no arg, compute the next version from the
`release-rules.md` heuristic:

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

**Build, test, stage, then promote.** Production accepts only a build
that `./build/test` passed **and** that ran — and passed its smoke
check — in staging (`gates/verified-build.sh`, `gates/promoted-build.sh`;
neither has a bypass). On the release commit from Step 3:

```sh
./build/build && ./build/test
./build/deploy --env=<staging-env> --intent=deploy
```

`<staging-env>`: `environment.sh classes`, the `staging` row. If the
build and test already ran on the integration branch and Step 3's merge
did not change the source (main had nothing the branch lacked), the
records still match — the chain keys on the source fingerprint, not the
commit — and the build is reused; otherwise it is rebuilt here, which is
correct. Any failure in these three is a deploy failure: take the
hard-stop branch below, naming the phase. A project that declares no
staging environment skips the staging deploy (the gate warns).

Then promote — the same build, to production:

```sh
FORCE_APPROVAL=1 DEPLOY_APPROVAL=invocation ./build/deploy --env=<prod-env> --intent=release
```

`FORCE_APPROVAL=1` because invocation is this skill's consent and the
approval prompt needs a terminal an agent does not have; `DEPLOY_APPROVAL
=invocation` records that truthfully in the ship log. The pipeline skips
`20-build` (it ships the tested artifacts), runs `45-migrate` if the
environment has migrations, deploys, and `60-verify` smoke-tests
production — retrying while it warms up, rolling back through
`rollback.sh` if it still fails. A `60-verify` failure fails the release;
say whether the rollback put production back on a verified build.

**Prefer the pipeline.** If `./build/deploy` exists, that is the deploy
command — not something discovered from CLAUDE.md. Routing through it is
what makes a release pass the class guard, run the production approval
gate, and land in the ship log. A release that went around the pipeline
is a release nobody can audit.

Resolve `<prod-env>` from the registry rather than guessing:

```sh
.claude/skills/environment/environment.sh prod-env
```

If it returns exactly one environment, use it. More than one (per-region
production) — ask which. None — the project has declared no production
class; say so and stop, because `--intent=release` will be refused and
you should say why before spending the user's time.

`--intent=release` is required and is what permits a production target.
`/deploy` cannot reach production; this is the sanctioned route.

**Consent.** Invocation is consent — this skill's whole contract. The
pipeline records `approval: invocation` in the ship log, which is the
truth: a human ran `/release`. Do not add a confirmation prompt on top;
that contradicts the contract this skill states five times over. A human
running `./build/deploy` by hand on a terminal still gets
`gates/approval.sh`, because there a prompt can actually be answered.

**Fallback — no pipeline.** If `./build/deploy` does not exist, use the
deploy command discovered in Step 1 and run it in the foreground. Say
explicitly in the release report that the deploy did **not** go through
the pipeline, so it has no ship-log record, no class guard and no
approval gate. Then suggest `/setup-deploy`.

Capture full output either way.

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

**`tasks/RELEASES.md`** — three sub-steps per
`release-rules.md`:

1. **Stamp the "🚧 Next" entry** as shipped:
   - Change `🚧` to `✅`.
   - Replace `next release — accumulating since vX.Y.Z` with
     the actual release theme summary (from the release notes
     drafted in Step 4).
   - Add the detail line: `shipped <YYYY-MM-DD> · tag
     <tag> · sha <short-sha>` (two-space indented under the
     version line).
2. **Cross-check the task list** against commits since the
   last tag. Add any TASK-NNN missed by manual
   merges (silently — these were caught at pre-flight in
   Step 1). Remove any stale claims (none should exist
   because pre-flight would have hard-stopped).
3. **Create a new "🚧 Next" entry** above the just-stamped
   entry:

```markdown
🚧 v<next-version>  ◆  next release — accumulating since <this-version>

(no tasks yet)

---
```

The next version is the previous version plus the default bump
(minor, unless project convention says otherwise). The empty
task list `(no tasks yet)` is the placeholder — the first
`/release-add` invocation will replace it with a real bullet.

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
(per `release-rules.md` "Closing report after deploy"):

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
  per `release-rules.md` "Rollback semantics".
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
  branch (`hotfix/TASK-NNN-slug` — a `priority: now` defect,
  `code-task-rules.md` §4), defer to the project's
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
- **Reverting / rolling back** → a failed `60-verify` rolls back
  automatically when `build/environments/<env>/rollback.sh` exists;
  otherwise use the environment's rollback command directly and
  append an AUDIT entry by hand.
- **A staging or dev deploy** that doesn't tag → `/deploy`.

## What "done" looks like for a /release session

- Pre-flight passed (every check ●).
- Integration branch merged to main (the release commit exists).
- Annotated tag created on the release commit AND pushed.
- The build that passed `./build/test` deployed to staging, then
  promoted to production, and `60-verify` passed in both.
- `AUDIT.md` entry appended; `RELEASES.md` entry marked ✅
  Shipped; both committed to main.
- Closing report rendered with the tag URL, commit SHA, and the
  rollback escape hatch.

If any of those didn't happen, the release isn't done. Be
explicit about it in the closing report — partial state is the
worst state to leave undocumented.
