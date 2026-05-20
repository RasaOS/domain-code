# Git Flow Rules

These five rules govern branching, merging to `main`, deploy tagging,
and where deploy commands are allowed to run. They protect the
project from agents (Claude included) silently shipping code, merging
unreviewed work into `main`, or deploying without authorization.
**Read this file before any task that touches branches, merges, or
deploys.** It extends `task-rules.md`; the rules are non-negotiable
and apply to every Claude session, every project, every release.

## Git flow discipline (the safety rules)

Five non-negotiable rules. They protect the project from agents
(Claude included) silently shipping code, merging unreviewed work
into `main`, or deploying without authorization. Read these
before any task that touches branches, merges, or deploys.

### Rule 1 — Always branch

**Every change starts on a new branch.** Never edit code on
`main`, never edit code on a release branch you didn't cut, never
edit code on someone else's branch unless the user has explicitly
handed it off to you.

Naming:

| Pattern | Use |
|---|---|
| `task/TASK-XXX-short-slug` | Per-task work (the default) |
| `chore/<slug>` | Non-task work — docs, scaffolding, dep upgrades |
| `hotfix/HOTFIX-NNN-slug` | Emergency production fixes |
| `feat/<slug>` | Feature work bigger than one task or spanning tasks |
| `proto/<slug>` | Prototype work (per `/prototype`) |
| `integration/<range>` | Multi-task integration branch (per Batch handoff) |

If you can't decide which prefix applies, ask. Don't guess.

### Rule 2 — Never merge to `main` without explicit user authorization

`main` is the release branch. The protection lives in this rule,
not in GitHub config (the kit doesn't touch repo settings). User
authorization can take two forms: **per-invocation confirmation**
(the default), or **static authorization** (encoded in this rule
as a named carve-out for a specific user-invoked skill).

- **No skill auto-merges to `main` by default.** Every merge is a
  user-authorized action. The default form is per-invocation
  confirmation in chat. Acceptable phrasings: "yes merge", "ship
  it", "merge integration → main", "go".
- **No agent runs `git push origin main` without authorization.**
  Even if the merge has already been approved on GitHub.
- **No "while you're in there" merges.** If you notice main is
  behind, don't fast-forward silently. Ask first.

#### Static-authorization carve-outs

The following skills have static merge authorization: typing the
skill name **is** the authorization. The carve-out lives in this
rule so it is reviewable; the per-skill SKILL.md cites this rule.

- **`/release` — invocation is consent.** A `/release` run
  merges the integration branch into `main` as part of its
  documented flow (preflight → merge → tag → deploy → push tag).
  The user's `/release` invocation IS the merge authorization.
  No "deploy now?" prompt; no "confirm version?" prompt. This
  carve-out exists because the prior confirmation-heavy contract
  caused alarm fatigue and missed deploys. See `release-rules.md`
  and `kit/skills/release/SKILL.md`. The skill still hard-stops
  on real blockers (failed pre-flight, failed tests, missing
  deploy command, branch-protection refusal).
- **`/peer-review` — accept = approve + merge.** A `/peer-review`
  run that accepts a PR posts an approving review AND merges via
  `gh pr merge --squash --delete-branch`. The user's
  `/peer-review` invocation IS the merge authorization for an
  accepted PR. The skill still respects branch protection — if
  the remote refuses the merge, the approval stays and the PR
  remains open. See `kit/skills/peer-review/SKILL.md`.
- **`/auto-task` and `/auto-phase` — spec-file fast-path.** May
  auto-merge a PR to `main` *iff* every file in the PR matches
  the spec-file allowlist (`tasks/**/*.md`, `tasks/PHASES.md`,
  `tasks/ROADMAP.md`) and the working tree is otherwise clean.
  Push to a short-lived `spec/<id>` branch with a real PR
  record, merge via `gh pr merge --squash`. Any non-spec dirty
  file falls back to "leave uncommitted" — same as the
  pre-v0.32.0 behavior. See `autonomy-rules.md` "Exception 2".

The list is closed. Adding a new merge-bearing user-invoked
skill requires adding it here, in this rule, as a named
carve-out — not silently in the SKILL.md.

The only way `main` updates is: user says yes per-invocation, or
one of the named carve-outs above applies. Otherwise `main` does
not move.

### Rule 3 — Tag every deploy ("tag and bag")

Every successful deploy from `main` is annotated-tagged with a
`v<semver>-<sha>-<env>` version string. No exceptions. The tag is the version-controlled
record of what shipped — `git log --tags` becomes the deploy
history.

The phrase **"tag and bag"** is the operational shorthand: tag
the commit (`git tag -a v<semver>-<sha>-<env>`), bag the app (build the
container or artifact), deploy it. The full sequence — pre-flight
→ merge → tag (local) → deploy → push tag → AUDIT entry — is
what `/release` orchestrates. The tag is created locally before
deploy so the commit's identity is locked; it is pushed after
deploy succeeds so a failed deploy doesn't publish a stale
release tag.

Format, version-bump heuristics, and message body shape: see
"Production deploy tagging (mandatory)" below.

### Rule 4 — Protect `main` like it's prod

`main` reflects production state. Treat any change touching it
with the same care as a deploy:

- **Treat any merge to `main` as release-adjacent**, even if no
  deploy follows. Same authorization discipline — either
  per-invocation confirmation, or a named static-authorization
  carve-out from Rule 2.
- **Never force-push to `main`.** Period. If `main` has a bad
  commit, fix it forward (revert + new commit) — never rewrite
  history. There is no carve-out for force-push.
- **Any agent action touching `main`** (merge, rebase, push,
  force) requires user authorization — either per-invocation in
  chat, or via a Rule 2 carve-out. No agent touches `main`
  without one of those.

### Rule 5 — Deploys route through `/release`; invocation is consent

**Production** deploys are not free-floating actions. They flow
through `/release` (or its platform variants — `/ios-release`,
future `/web-release`, etc.). The skill is the gate.

**Invocation is consent.** Per Rule 2's static-authorization
carve-out, typing `/release` IS the deploy authorization. The
skill does not ask "Deploy now?" or "Confirm version?" at any
soft gate. The contract was inverted in v0.33.0 because the
prior confirmation-heavy contract caused alarm fatigue and
missed deploys.

What the skill still does:

- **Hard-stop on real blockers** — failed pre-flight (dirty
  tree, behind upstream, branch state), failed tests, failed
  build, missing deploy command, branch-protection refusal,
  release-plan mismatch, deploy command itself failing.
- **Compute the version** from the heuristic (or use the arg
  passed: `/release patch`, `/release minor`, `/release major`,
  `/release v1.2.3`), no asking.
- **Merge integration → main, tag locally, deploy, push tag,
  record AUDIT and RELEASES.** The full sequence runs
  end-to-end without intermediate prompts.

**Non-production preview deploys** have one carve-out: `/mission`
MAY run `./build/deploy --env=<env>` against a project-configured
non-prod environment, but only when the goal explicitly asks for
a preview deploy. The carve-out is opt-in (the goal must request
it), bounded (never `prod`/`production`, never via `/release`,
never tags), and best-effort (deploy failure is reported, not
retried, and never rolls back the PR). See `autonomy-rules.md`
"The preview-deploy exception" for the precise conditions.

**Never run deploy commands directly** (`firebase deploy`,
`fastlane release`, `npm run deploy`, `git push --tags` for
release tags, etc.) bypassing `/release`. Even if you know the
command works. The skill is the gate; bypassing it skips the
tag, the AUDIT entry, and the release-plan match check.

If a project doesn't use `/release` (because it has a more
specialized release flow), the **outcome guarantees** still
apply manually:

1. Pre-flight green.
2. Version chosen (heuristic or explicit).
3. Annotated tag created on the release commit.
4. Deploy run.
5. Tag pushed.
6. `AUDIT.md` entry appended; `RELEASES.md` updated.

These rules apply to every Claude session, every project, every
release. Don't soften them.

## Working across machines

When the same project lives on more than one machine, the five
rules above still hold — but a new failure mode appears: work
**stranded** on one machine, invisible to the other. A session is
abandoned mid-task, the next session starts elsewhere, and
uncommitted work just sits. These rules keep the machines
convergent. They are enforced by the `/git-guard` skill — read on.

### Pull before you branch

Start every session on a fast-forwarded trunk. Before cutting a
branch: `git fetch`, then `git pull --ff-only`. `--ff-only` is
mandatory — it refuses *loudly* instead of silently creating a
merge commit when history has diverged. Make it the default:
`git config pull.ff only`.

### Never end a session with stranded work

Uncommitted or unpushed work is invisible to every other machine.
Before stepping away: commit it to the branch and push, or run
`/handoff`. `git stash` does **not** count — a stash is
machine-local and does not travel.

### Cross-machine context lives in the repo, not in memory

Claude's per-machine memory does not travel between machines.
Anything the next session needs — wherever it runs — must live in
a git-tracked file: `/handoff` (writes `.claude/welcome.md`),
`/inbox @self`, or `CLAUDE.md`. Never rely on memory to carry
context across machines.

### Automate it — `/git-guard`

Every rule above depends on a human remembering. `/git-guard on`
makes them automatic: it installs hooks that auto-capture
work-in-progress as `wip:` commits on an isolated branch,
fast-forward and surface abandoned work at session start, and
block commits or pushes that land directly on trunk. Run it once
per machine, per project. The hook set is per-machine; the
discipline is universal.
