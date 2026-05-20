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

### Rule 2 — Never merge to `main` without explicit user confirmation

`main` is the release branch. The protection lives in this rule,
not in GitHub config (the kit doesn't touch repo settings).

- **No skill auto-merges to `main`.** Every merge is a user-
  confirmed action in chat. Acceptable phrasings: "yes merge",
  "ship it", "merge integration → main", "go".
- **No agent runs `git push origin main` without confirmation.**
  Even if the merge has already been approved on GitHub.
- **No "while you're in there" merges.** If you notice main is
  behind, don't fast-forward silently. Ask first.
- **Narrow carve-out — spec-file fast-path.** `/auto-task` and
  `/auto-phase` MAY auto-merge a PR to `main` *iff* every file in
  the PR matches the spec-file allowlist (`tasks/**/*.md`,
  `tasks/PHASES.md`, `tasks/ROADMAP.md`) and the working tree is
  otherwise clean. The user's confirmation for this carve-out is
  *static* — encoded in `autonomy-rules.md` as a deliberate
  exception, not requested per-invocation. The merge runs via a
  short-lived `spec/<id>` branch with a real PR record. Any
  non-spec file in the working tree falls back to "leave
  uncommitted" — same as today. See `autonomy-rules.md` "The
  spec-file fast-path exception" for the full conditions.

The only way `main` updates is: user says yes (per-invocation), or
the spec-file carve-out above (which the user authorized once, in
this rule). Otherwise `main` does not move.

### Rule 3 — Tag every deploy ("tag and bag")

Every successful deploy from `main` is annotated-tagged with a
`v<semver>-<sha>-<env>` version string. No exceptions. The tag is the version-controlled
record of what shipped — `git log --tags` becomes the deploy
history.

The phrase **"tag and bag"** is the operational shorthand: tag
the commit (`git tag -a v<semver>-<sha>-<env>`), bag the app (build the
container or artifact), deploy it. The full sequence — merge →
build → deploy → tag → push tag → AUDIT entry — is what
`/release` orchestrates.

Format, version-bump heuristics, and message body shape: see
"Production deploy tagging (mandatory)" below.

### Rule 4 — Protect `main` like it's prod

`main` reflects production state. Treat any change touching it
with the same care as a deploy:

- **Treat any merge to `main` as release-adjacent**, even if no
  deploy follows. Same confirmation discipline.
- **Never force-push to `main`.** Period. If `main` has a bad
  commit, fix it forward (revert + new commit) — never rewrite
  history.
- **Any agent action touching `main`** (merge, rebase, push,
  force) is a user-confirmed action. No agent does any of these
  without an explicit go from the user in chat.

### Rule 5 — Deploys route through `/release`

**Production** deploys are not free-floating actions. They flow
through `/release` (or its platform variants — `/ios-release`,
future `/web-release`, etc.). The skill is the gate.

**Non-production preview deploys** have one carve-out: `/mission`
MAY run `./build/deploy --env=<env>` against a project-configured
non-prod environment, but only when the goal explicitly asks for
a preview deploy. The carve-out is opt-in (the goal must request
it), bounded (never `prod`/`production`, never via `/release`,
never tags), and best-effort (deploy failure is reported, not
retried, and never rolls back the PR). See `autonomy-rules.md`
"The preview-deploy exception" for the precise conditions.

Reasons:

- The skill enforces pre-flight (clean tree, tests green, build
  clean, on `main`, no surprise upstream commits).
- The skill prompts for version with reasoning and waits for
  user confirmation.
- The skill prompts for final deploy go-ahead.
- The skill tags the commit, pushes the tag, and writes the
  AUDIT entry.

**Never run deploy commands directly** (`firebase deploy`,
`fastlane release`, `npm run deploy`, `git push --tags` for
release tags, etc.) bypassing the skill. Even if you know the
command works. The skill is the gate.

If a project doesn't use `/release` (because it has a more
specialized release flow), the same five gates still apply
manually:

1. Pre-flight green.
2. User-confirmed version.
3. User-confirmed deploy.
4. Annotated tag pushed.
5. AUDIT entry appended.

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
