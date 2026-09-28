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
  user-authorized. An autonomous skill (auto-* family + /mission)
  never merges to `main`, never pushes `main`, never tags a
  release, never deploys to prod. Five narrow carve-outs for the
  autonomous family, all documented in "The exceptions" below:
  (a) `/mission` may push its own `feat/` branch and open a draft
  PR; (b) any autonomous skill's docs-class outputs land through
  `land.sh docs`, a PR that merges itself after CI; (c) `/mission`
  may run a non-prod preview deploy when the goal asks for it;
  (d) `/auto-merge` may merge PRs that opted in and passed
  `/peer-review`, then deploy them to a non-prod environment;
  (e) `/auto-develop` and `/auto-test` may commit to the task
  branch and open a draft PR, which they never merge.

  Two additional static-authorization carve-outs live in
  `git-flow-rules.md` Rule 2 for the **user-invoked
  merge-bearing skills** — `/release` (invocation = consent to
  the full release flow) and `/peer-review` (invocation = consent
  to merge if accepting). Those skills are not in the autonomous
  family and not governed by this file; they are listed here for
  cross-reference only. The **deploy-to-prod** gate remains
  user-authorized in all cases — either per-invocation or via a
  Rule 2 carve-out.
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
default — outside the documented exceptions, an `auto-*` skill
leaves its work in the working tree, uncommitted, for the user to
review with `git diff` and commit. The exceptions now cover the
family's own outputs: docs land through a PR that merges itself
after CI (Exception 2), and code goes to the task branch in a
draft PR a reviewer merges (Exception 5). Nothing an `auto-*`
skill writes reaches `main` without a PR. The five documented
exceptions are below.

## The exceptions — five narrow carve-outs

The default — "never auto-commit, never merge to `main`, never
deploy" — holds for the `auto-*` family. Five narrowly-scoped
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

### Exception 2 — Docs landing

Specs, ledger moves, audits and decisions are **documentation**,
not code. They describe work; they do not run work. The team needs
visibility into what has been spec'd and decided, and a record
left uncommitted in one session's working tree is gone when the
container is. "Every record waits for a manual commit + PR +
review + merge" is a real tax on the autonomous flow, and "leave
it uncommitted" is how records got lost.

The carve-out:

- **Docs class only, decided by a program.** `land.sh` /
  `land.py` classify every file, and nothing else does. Docs class
  is the `tasks/**` ledger (`tasks/**/*.md`, `tasks/history.tsv`)
  and the records
  (`docs/{audits,decisions,postmortems,retros,notes,handoff,blast-radius,scope,exports,regrets,mvp,wrangle}/**/*.md`,
  `docs/glossary.md`); the full table is in `land/SKILL.md`.
  Never docs class, whatever the path: any `CLAUDE.md` /
  `AGENTS.md`, anything `CLAUDE.md` `@`-imports (e.g.
  `docs/notes/INDEX.md`), `.claude/**`, `.github/**`, and
  `tasks/tasks.config.yml`, which declares the ledger's actors and
  targets and is a decision, not a record. A code-class file refuses the landing (exit 3), with no
  bypass; project config can make docs wait for a person, never
  widen the class.
- **By class, not by name.** Any autonomous skill's docs-class
  outputs land this way. `/auto-task`, `/auto-phase`, `/auto-bug`,
  `/auto-hotfix` and `/reconcile` land their specs, ledger lines
  and run records through it.
- **Path-scoped, from the latest trunk.** Name the files the skill
  wrote, and nothing else:

  ```bash
  bash .claude/skills/land/land.sh docs --skill <name> --title "<what>" [--summary "<why>"] [--tasks "TASK-NNN ..."] -- <file>...
  ```

  It syncs, cuts a short-lived `land/` branch from the freshly
  fetched trunk, opens a PR, waits for CI, and merges pinned to the
  verified head (`--match-head-commit`). Other changes in the
  working tree neither block it nor ride along: the path-scoped
  landing replaces the old clean-tree precondition.
- **CI and branch protection win.** Only a CI pass merges. Checks
  failing or pending, or a merge that branch protection refuses,
  leave the PR open (exit 6) and the autonomy report says so. The
  skill never uses `--admin` or forces the merge. Exit 4 (no `gh`):
  finish with the session's GitHub tooling per `land/SKILL.md`
  "Without `gh`". Exits 5/6/7: report, never retry blindly.
- **Never code.** This carve-out exists *because* these files are
  not code. Code, and anything an agent loads as instructions,
  goes by PR and is never merged by the skill that wrote it
  (Exception 5).
- **Not in a composed run.** As a step of `/mission`, `/self-heal`
  or `/self-improve`, a skill does not land on its own: the
  orchestrator's branch and PR carry its files.
- **The class is checked by a program, not by reading.** Until
  v0.52.0 the spec-file allowlist was prose only, and its text was
  silently corrupted from v0.48.0 to v0.49.0 for exactly that
  reason — nothing read it. `land.py` classifies every file before
  the push and again on the **pushed commit** (both sides of any
  rename) before the merge. It replaces the `spec-gate` and
  `spec-only`-label flow.

Rationale: a record is the team's plan and memory, not the team's
runtime. Auto-landing one is the same review-tradeoff as
auto-publishing a draft note to a shared Notion. It is reversible
(`git revert`) and visible (PR record). Lifting the gate for code
would change behavior on `main`; lifting it for docs only changes
what plans and records are visible.

### Exception 3 — `/mission` may run an opt-in preview deploy

When the goal explicitly asks for a deployable preview ("deploy a
preview", "have it running for me to test", "stand it up so I can
validate"), `/mission` MAY run `./build/deploy --env=<env> --intent=deploy`
against a project-configured non-prod environment, but:

- **Opt-in.** The goal must explicitly request a preview deploy.
  If the goal does not mention deployment, `/mission` does not
  deploy. Silence is "do not deploy".
- **Never prod.** The selected env must be `dev`- or
  `staging`-class in the environment registry — decided by class,
  never by name (`class-guard.sh` refuses a prod-class target for
  `--intent=deploy` in any case).
- **Build and test first.** `./build/build && ./build/test` on the
  branch head, then deploy — a staging environment refuses a build
  `/test` did not pass.
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

### Exception 4 — `/auto-merge` merges opted-in PRs and deploys non-prod

`/auto-merge` runs unattended, from a `/loop` or a scheduled routine.
It is the one path by which code reaches `main` without a person
starting the merge. That is why it has more keys than any other
exception:

- **Project opt-in.** `.claude/auto-merge.json` `enabled: true`,
  committed to the trunk through a PR. It is off by default.
- **Per-PR opt-in, two keys.** The PR must carry the `auto-merge`
  label and its merge manifest must say `merge: auto`. A hold label
  (`hold`, `do-not-merge`, `wip`, `blocked`) overrides both.
- **Checked by a program.** `auto-merge.sh plan` applies every rule:
  not a draft, targets the trunk, valid manifest, every `after` PR
  merged, mergeable, and CI green under `peer-review.sh`'s fail-closed
  classifier. It names the first rule each PR fails. The skill never
  overrides a skip.
- **Every merge is a `/peer-review`.** The context-isolated auditor, the
  done-gate pass inside the PR and the CI re-read all apply. The merge
  uses `--match-head-commit`, so a push after the review blocks it.
- **Post-merge actions stay out of production.** `on_merge: deploy:<env>`
  runs build → test → deploy from the trunk
  (`./build/deploy --env=<env> --intent=deploy` last) only when `<env>`
  resolves to dev or staging class. A prod-class, unclassified or unknown environment, and
  every `release:<version>`, is queued for a person and commented on
  the PR. `class-guard.sh` refuses a prod-class `--intent=deploy` in
  any case.
- **Never tags, never releases.** Tags and prod belong to `/release`.

Rationale: the review, the checks and the done-gate are what make a
merge safe, not the person who clicks the button. When all of them pass
on a PR its author opted in, waiting for a click adds latency, not
safety. Production stays a person's decision.

### Exception 5 — `/auto-develop` and `/auto-test` commit to the task branch and open a draft PR

Code left uncommitted in one session's working tree is lost the
same way a record is, and nobody can review what they cannot see.
Code that reaches `main` unreviewed is the failure every other
gate here exists to stop. A draft PR on the task's branch answers
both: the work is durable and visible, and the merge is still a
reviewer's.

- **The task branch, from the latest trunk.** `land.sh sync`
  first, then the task's branch (`task/TASK-NNN-<slug>`, or
  `hotfix/…` for a `priority: now` defect) cut from the fresh
  trunk before any code. Never the trunk.
- **Commit the named files, open a draft.** Name the files the
  run wrote, and nothing else:

  ```bash
  bash .claude/skills/land/land.sh pr --skill <name> --title "<what>" [--tasks TASK-NNN] [--draft] [--summary "<why>"] [--verified "<commands and results>"] -- <file>...
  ```

  Always with `--draft`, and `--tasks` naming the task. It commits
  only those files, merges the latest trunk in (a merge, never a
  rebase or a force), pushes the branch, and opens a **draft** PR
  whose merge manifest says `merge: manual`. An open PR for the
  branch is reused.
- **Never merges.** The merge is `/peer-review`'s, `/auto-merge`'s
  (Exception 4) or a person's; `/open-pr` marks the draft ready.
  Exit 4 (no `gh`): finish with the session's GitHub tooling per
  `land/SKILL.md` "Without `gh`". Exits 5/6/7: report, never retry
  blindly.
- **Not when composed by `/mission`.** Inside a mission the work
  commits to `/mission`'s `feat/` branch and rides its draft PR
  (Exception 1); the step opens no PR of its own. The same holds
  under `/self-heal` and `/self-improve`.

Rationale: a commit on a branch nobody runs changes nothing on
`main`, and a draft PR is a review surface, not a merge. It is the
smallest step past "leave it uncommitted" that makes code durable,
and it leaves the one decision that changes behavior — the merge —
with a reviewer.

## The autonomy report

Every `auto-*` skill ends with exactly one report — the user's
single review surface, standing in for the questions they were not
asked.

**The report is rendered *and* recorded.** Rendering alone was the whole
problem: a run that died mid-way left no trace at all, and a gate hit died in
a transcript nobody was watching. You cannot compute a success rate, an escape
rate or a cycle time from chat scrollback, and without those numbers no gate
anywhere can ever be loosened — which collapses the work back to a human
reading every diff.

So an autonomous run brackets itself with a run record:

```bash
RUN=$(.claude/skills/runs/runs.sh open <kind> "TASK-NNN, TASK-MMM")   # BEFORE the work
# ... the operation ...
.claude/skills/runs/runs.sh close "$RUN" completed
# or: close "$RUN" stopped-at-gate "locked contract user-schema"
# or: close "$RUN" failed
```

`<kind>` is the skill that ran — `mission`, `auto-task`, `auto-develop`,
`auto-test`, `auto-phase`, `auto-bug`, `auto-hotfix`.

**Open it before the work, not after.** A record written only at the end
cannot represent a run that died, and that is the outcome most worth knowing
about. `runs.sh list --open` is the list of runs that never closed.

The rendered report and the record carry the same facts; the record is the one
that survives. See `stamps.md` → `Stamp: run`, and `runs.sh` for the ledger's
shape. A task's attempt count is derived from these records
(`runs.sh attempts TASK-NNN`), never stored on the task.

Render this in chat at the end of the run:

```markdown
# 🤖 Autonomous run — <operation> · <target>

> **Outcome.** <completed | stopped at a hard gate>
> **Deliverable.** <what was produced — file paths, or "—">
> **Landing.** <Landed: PR #N merged | PR: #N open (draft), never merged by this skill | Not landed: exit N — message>

## Evidence

Every claim the goal condition rests on, shown rather than asserted.
Verbatim command, its exit code, and enough output to read the result.

```
$ <command>
<the last few lines of real output>
exit <N>
```

*(If the run made no verifiable claim: "No verifiable claim — this run
produced <X> and asserted nothing about its behavior.")*

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

<One or two lines — the immediate next step. e.g. "Review draft
PR #N and mark it ready", or "Unlock contract `user-schema` and re-run".>
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
- **Which is why the skill must SURFACE that output, not describe
  it.** The operator's half of this is writing a checkable
  condition; the skill's half is putting the check in the
  transcript. "All tests pass" is a claim, and the evaluator has no
  way to distinguish a true one from a false one — it cannot open
  the repo and look. `$ npm test` followed by real output and
  `exit 0` is evidence. The autonomy report's **Evidence** section
  is where that goes, and it is the only lever this Element has
  here: `/goal` is a Claude Code harness command, so its evaluator
  cannot be given tools from inside an Element. What can be changed
  is whether the transcript it reads contains proof or prose.
- **Evidence belongs in the run record too.** The transcript is
  gone when the session ends; `tasks/runs/<RUN-id>.md` is not. A
  claim worth putting in front of the evaluator is worth keeping.
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
