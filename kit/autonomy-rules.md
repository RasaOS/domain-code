# Autonomy Rules

The shared contract for the kit's **autonomous skills**:

- The **`auto-*` family** — `/auto-task`, `/auto-phase`,
  `/auto-develop`, `/auto-test` — each an autonomous variant of a
  single kit operation.
- **`/mission`** — the orchestrator: it runs a whole goal end to
  end by decomposing it and composing the family.

Each makes every decision itself and runs to completion without
returning to the user for clarification. **Read this file before
authoring or running any of them.** Every such SKILL.md defers its
autonomy behavior here rather than re-stating it. Where the rest of
this file says "`auto-*` skill", the rule applies to `/mission`
too — it is bound by the same contract.

The autonomous variant differs from its base skill in exactly one
way: **who decides.** The base skill asks the user; the autonomous
variant decides itself. It does not differ in diligence, quality,
or what counts as done.

## The autonomy contract

- **Decide, don't ask.** Wherever the base skill would ask the user
  a clarification or preference question, the autonomous variant
  makes the most reasonable decision and continues. It does not
  return to the user mid-operation for a preference call.
- **Flag every assumption.** Every call the user would normally
  have made is recorded as a flagged assumption — ⚠️, with the
  reasoning. Same discipline as `/instruct`. A decision is never
  buried silently inside the work; it surfaces in the autonomy
  report so the user can review and override. The user's review
  happens *after*, in one pass, instead of as N interruptions.
- **Ground decisions in reality.** Autonomy is not guessing. Read
  the repo, read the current docs, follow the patterns already in
  the codebase. A decision grounded in code or docs is just a
  decision. A decision that needs knowledge the repo doesn't
  contain — a business call, a product preference, an external
  constraint — is a flagged assumption, surfaced *prominently*,
  because it's the most likely thing to be wrong.
- **Run to completion.** The skill runs until its deliverable is
  done, or until it hits a hard gate (below). It does not stop
  early to "check in." A half-finished autonomous run with no hard
  gate hit is a bug.

## Hard gates — where autonomy STOPS

Autonomy removes the "what do you prefer?" gate. It does **not**
remove the safety gates. When an `auto-*` skill hits any of the
following, it **stops, does not proceed, and surfaces the
situation** in its report:

- **A locked `/contract`.** Per `contract-rules.md`, a locked
  contract blocks a change to it. The skill stops and reports — it
  never unlocks a contract itself. Unlocking is always the user's
  call.
- **Gated files.** Files that require explicit permission to touch,
  per `task-rules.md` and the CLAUDE.md "Gated files" section. The
  skill does not modify them; it surfaces exactly what it needs.
- **Merging or pushing to `main`, release tagging, deploys.** Per
  `git-flow-rules.md` Rules 2, 4, and 5 these are always
  user-confirmed. An autonomous skill never merges to `main`,
  never pushes `main`, never tags a release, never deploys to
  prod. It works on a branch and leaves it for the user. Three
  narrow carve-outs, all documented in "The exceptions" below:
  (a) `/mission` may push its own `feat/` branch and open a draft
  PR; (b) `/auto-task` and `/auto-phase` may auto-merge
  spec-only PRs to `main`; (c) `/mission` may run a non-prod
  preview deploy when the goal asks for it. The
  **merge-to-`main`-with-code** gate and the **deploy-to-prod**
  gate are absolute — no carve-outs.
- **Destructive or irreversible operations.** History rewrites,
  force-pushes, data deletion, schema-destroying migrations,
  removing real content. Never auto-decided — the skill stops.
- **A genuine hard blocker.** Something the skill cannot resolve
  after real effort — a build that won't pass, a missing
  credential, an external service down, a spec that contradicts
  itself. The skill stops, records the blocker, and surfaces it.

A hard gate is not a failure — it is the system working as
designed. The skill names the gate plainly and hands the decision
back to the user.

## The quality bars still apply

Autonomy changes *who decides*, never *how good the work is*. Every
`auto-*` skill remains fully bound by `task-rules.md`,
`craft-rules.md`, `test-rules.md`, and `git-flow-rules.md`.
Autonomy never lowers a verification bar, never skips a test, never
ships unreviewed work. **"Never auto-commit" still holds** as the
default — an `auto-*` skill leaves its work in the working tree,
uncommitted, for the user to review with `git diff` and commit.
The three documented exceptions are below.

## The exceptions — three narrow carve-outs

The default — "never auto-commit, never merge to `main`, never
deploy" — holds for the `auto-*` family. Three narrowly-scoped
exceptions are encoded in the contract. Each is opt-in by *intent*
(the skill triggers the carve-out only when its specific
conditions hold), bounded (each names its scope precisely), and
documented here so the carve-out is reviewable.

### Exception 1 — `/mission` commits and opens a draft PR

A pull request *is* `/mission`'s deliverable and its review
surface. A `/mission` run commits each completed task to its
`feat/` branch (durable checkpoints that let a long run, looped
under `/goal`, resume after a context compaction), and as a
terminal step pushes the branch and opens a **draft PR** — but
only once its verification re-walk confirms the goal is met.

The draft PR waits for the user to validate and merge. The commit
and the PR are `/mission`'s to make; **the merge to `main` is
always the user's**.

### Exception 2 — `/auto-task` and `/auto-phase` may auto-merge spec-only PRs

Task and phase **spec files** are documentation, not code. They
describe work; they do not run work. The team needs visibility
into what has been spec'd, and the friction of "every spec file
waits for a manual commit + PR + review + merge" is a real tax on
the autonomous flow.

The carve-out:

- **Allowlist.** Every file in the PR must match the spec-file
  allowlist: `tasks/**/*.md`, `tasks/PHASES.md`,
  `tasks/ROADMAP.md`. Any file outside the allowlist disqualifies
  the fast-path.
- **Clean tree precondition.** The working tree must contain no
  non-spec dirty files at the moment the fast-path runs. If it
  does, fall back to "leave uncommitted" — same as the default.
- **Short-lived branch + real PR.** Push to a `spec/<id>` branch
  (e.g. `spec/TASK-NNN-slug`, `spec/PHASE-X-slug`), open a PR
  labeled `spec-only` with the autonomy report's assumptions in
  the body, then merge via `gh pr merge --squash --delete-branch`.
- **Branch protection wins.** If branch protection refuses the
  merge, the PR stays open and the autonomy report says so. The
  skill does not use `--admin` or force the merge.
- **Never code.** This carve-out exists *because* spec files are
  not code. The moment any non-allowlist file is in the change
  set, the fast-path is off — no exceptions.

Rationale: spec content is the team's plan, not the team's
runtime. Auto-merging a spec is the same review-tradeoff as
auto-publishing a draft note to a shared Notion. It is reversible
(`git revert`) and visible (PR record). Lifting the gate for code
would change behavior on `main`; lifting it for specs only
changes what plans are visible.

### Exception 3 — `/mission` may run an opt-in preview deploy

When the goal explicitly asks for a deployable preview ("deploy a
preview", "have it running for me to test", "stand it up so I can
validate"), `/mission` MAY run `./build/deploy --env=<env>`
against a project-configured non-prod environment, but:

- **Opt-in.** The goal must explicitly request a preview deploy.
  If the goal does not mention deployment, `/mission` does not
  deploy. Silence is "do not deploy".
- **Never prod.** The selected env must be one of the project's
  non-prod envs configured in `build/environments/`. The names
  `prod` and `production` are forbidden, period.
- **Never via `/release`.** The release skill remains the gate
  for prod. This preview path is a separate, narrower channel.
- **Never tags.** No `git tag -a v…-…-…` happens. Tags belong to
  `/release`.
- **Best-effort.** Deploy failure is reported in the autonomy
  report and does not roll back the PR. The PR is the deliverable;
  the deploy is a convenience on top.
- **After the PR.** The deploy runs *after* the PR is opened, so
  the PR exists regardless of whether the deploy succeeds.

Rationale: a UI preview lets the user validate a `/mission` PR
against running behavior, not just code review. The same opt-in
gating that protects prod (route through `/release`) does not
apply to ephemeral testing envs — those exist to be deployed to.

## The autonomy report

Every `auto-*` skill ends with exactly one report — the user's
single review surface, standing in for the questions they were not
asked. Render it in chat at the end of the run:

```markdown
# 🤖 Autonomous run — <operation> · <target>

> **Outcome.** <completed | stopped at a hard gate>
> **Deliverable.** <what was produced — file paths, or "—">

## Decisions made

Calls the skill made on your behalf. Re-run with a correction to
override any of them.

- ⚠️ <decision> — <the reasoning that grounds it>
- ⚠️ <decision> — <reasoning>

*(If none: "No assumptions — every decision was grounded in the
spec, the code, or the docs.")*

## Hard gates hit

<Each gate that stopped the run, and what it needs from the user.
Omit this whole section if the run completed cleanly.>

- 🔒 <gate> — <what the user must do to unblock it>

## What's next

<One or two lines — the immediate next step. e.g. "Review the spec
and commit", or "Unlock contract `user-schema` and re-run".>
```

## Looping to a verified end state with `/goal`

An `auto-*` skill runs its operation to completion within one
invocation. For work that genuinely spans many turns — implement a
spec until every acceptance criterion holds, work a phase until
every stub is spec'd — pair the skill with Claude Code's built-in
**`/goal`** command (Claude Code v2.1.139+).

`/goal <condition>` sets a completion condition and loops turns
until a separate fast-model evaluator confirms it holds. `/goal`
is the loop engine; the autonomous skill is the methodology.

`/mission` is the skill built for this loop. A whole goal
genuinely spans many turns, so a mission is most often run as
`/goal /mission <goal> — done when <condition>`. The four `auto-*`
skills are looped this way for a single long operation; `/mission`
is looped this way by design.

**A skill cannot invoke `/goal`.** Slash commands are the
user-input layer — a SKILL.md is instructions *to* Claude, and
Claude does not type slash commands at itself. `/goal` is therefore
never *embedded* in an `auto-*` skill. The **user** runs the skill
under a goal: set a `/goal` whose condition names the operation's
measurable end state. Claude reads the `auto-*` skill when relevant
and works toward the condition.

```bash
claude -p "/goal /auto-develop has implemented TASK-042 — every
acceptance criterion in the spec holds and the build exits 0"
```

**Writing the condition:**

- **The evaluator only reads the transcript.** It runs no tools
  and reads no files — it judges what Claude has surfaced in the
  conversation. Write conditions Claude's own output demonstrates:
  a build exit code, a test summary, a file count that actually
  appears in the transcript.
- **Encode the hard gates as an escape clause.** `/goal` loops
  relentlessly; the hard gates above require an `auto-*` skill to
  *stop*. A loop with no escape clause will spin against a gate it
  is contractually bound not to cross. Always include one — e.g.
  *"…or stop and report if a locked contract, a gated file, or a
  required merge to main blocks progress."* The hard gates still
  govern each individual turn; the escape clause is what lets the
  *loop itself* terminate at a gate.
- **Bound the run.** Add *"…or stop after N turns"* so a goal that
  cannot converge ends instead of burning turns.

**Requirements.** `/goal` needs Claude Code v2.1.139+, an accepted
trust dialog, and hooks enabled. It is a harness feature — the kit
references it but cannot ship or version it. An `auto-*` workflow
that relies on `/goal` carries that version dependency; without
`/goal` the `auto-*` skills still run, just as a single invocation
rather than a verified multi-turn loop.

> Not to be confused with the **Goal** *section* in `CLAUDE.md`
> (the project's current objective, a static planning artifact).
> `/goal` is a harness command — a loop. Different things that
> happen to share a name.

## Authoring an `auto-*` skill

An `auto-*` skill is **thin**. It does two things and no more:

1. **Names its operation.** Either by deferring to a base skill
   ("this is `/task` run autonomously — follow `task/SKILL.md`")
   or, when there is no base skill, by defining the operation
   itself (`auto-develop`, `auto-test`).
2. **Defers all autonomy behavior to this file.** Do not re-paste
   the contract, the hard-gate list, or the report template into
   the SKILL.md. Reference `autonomy-rules.md`. One contract, one
   place to evolve it.
