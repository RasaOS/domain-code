# Roadmap

Phase-by-phase task registry for `rasa.domain.code`'s own development.
Each phase has a name, a scope paragraph, and an ordered list of tasks.
Order implies suggested ship order.

This is the Element dogfooding its own task system — see
`content/task-rules.md`.

---

## The program: from toolkit to development arm

Phases P1–P8 below are one program with one goal: **the Element must be
able to run a company's engineering work at fleet scale** — on the order
of 50 agents across 200 repos, with few humans in the loop — rather than
being a very good per-repo developer toolkit.

Filed 2026-09-20 from a 61-agent adversarial audit of v0.48.1 (47 gaps
claimed, 38 survived skeptic review, 9 refuted as factually wrong). The
audit's own sequencing argument decides the phase order, and it is worth
restating because it is counter-intuitive:

> Do not start with the fleet layer. Start with the two things every
> other fix reads from — **fail-closed defaults** (P1) and **a durable
> record of what an agent did** (P2). Without P2 no gate anywhere can
> ever be loosened, because there is no evidence to loosen it on; and
> without evidence the work collapses back to humans reading every diff,
> which is the program's own defeat condition.

Two properties of this program are worth stating up front:

- **It is additive.** No phase requires rebuilding the toolkit. Roughly
  two thirds of the work is wiring two already-built things together —
  the `auditor` agent into `/peer-review`, `render-active-notice` into
  the active-notice reader, the smoke suite into a post-deploy stage,
  `domain-core`'s `/sync` into this Element.
- **Some of it is not this repo's to do.** P5.3 and all of P9 are
  cross-repo. They are filed here so the program is complete and
  reviewable in one place, but per the workspace role-split they are
  executed from their own repos in their own sessions. Each such task
  says so in its own file.

Tasks are filed as **stubs** per `content/task-rules.md` ("Adding tasks
to the backlog"): full specs are expanded close to implementation, not
at filing time. A task is fully specced when it moves to `tasks/active/`.

Which task covers which of the 38 surviving gaps is tracked in
`docs/audits/2026-09-20-v0.48.1/gap-coverage.md`. Update it in the same
change that completes or files a covering task.

---

## Phase P1 — Fail-closed defaults

Today a fresh install ships gates that pass when their input is absent:
the production test stage exits 0 on an empty suite, task enforcement
installs disabled, and the spec-file allowlist that governs autonomous
merges to `main` is corrupted by a botched edit. These are single-file
changes to things that are actively wrong and shipping into new repos
right now. Nothing else in the program is worth doing while the floor
is this soft.

- TASK-012 — Fail-closed test gate: an empty or missing suite must fail at prod class
- TASK-013 — Repair the corrupted spec-file allowlist in Rule 2 and its `autonomy-rules.md` mirror
- TASK-014 — Fix dead pointers shipped into every seeded repo (archived `claude-orchestrator`, unbuilt `/migration`, `/ultrareview`)
- TASK-015 — Wire `project-map.md` into the seeded CLAUDE.md `@`-imports
- TASK-016 — `bin/init` enables task enforcement, with an explicit brownfield carve-out
- TASK-017 — Rename `tasks/done/` to `tasks/completed/` in this repo to match the rule it ships
- TASK-055 — The `bin/lint` release gate is red on `main` (14 pre-existing findings); found while verifying TASK-013
- TASK-059 — Keep the program audit's gap-to-task coverage in the repository (`docs/audits/`)
- TASK-056 — A `$(cmd || echo unknown)` fallback corrupted two ledgers in a commit-less repo
- TASK-060 — The contract lock fails open on bytes it did not write (a BOM, CRLF, a deleted or garbled `is_locked` key)
- TASK-061 — Tag v0.51.0 and v0.52.0, backfill the CHANGELOG, and validate `rasa.json` against the schema in CI
- TASK-070 — import-env refuses secret defaults

## Phase P2 — The run record

Nothing in this system currently writes down what an agent did or
whether it worked. Autonomy reports are *rendered to chat* — all 20 call
sites say "Render", never "write". Tasks have no outcome field. Five
provenance sites stamp `$(whoami)`, so "who approved this production
release" resolves to a service account and is recorded as if a human
consented. This phase has zero dependencies, is the cheapest item in the
program, and unblocks four of the others.

- TASK-018 — Adopt the task stamp fields already specced as "proposed but not yet adopted", plus `actor`, `actor_kind`, `run_id`, `outcome`, `attempts`
- TASK-019 — Thread one `RASA_ACTOR` value through all five `$(whoami)` provenance sites and the approval gate
- TASK-020 — The autonomy report appends a machine-readable run line instead of only rendering to chat
- TASK-021 — `rasa.module.telemetry`: roll per-repo run lines into a fleet view
- TASK-057 — `/wrangle`'s remediation plan is filed into `tasks/`, not only rendered to chat
- TASK-067 — Convert the live writers first: release.sh and task-guard's ledger
- TASK-068 — Convert the dormant writers: runs, task-enforce, deploys, contract
- TASK-069 — Sweep the remaining readers and writers; one actor lookup
- TASK-071 — A read-only record checker: task-enforce.sh doctor
- TASK-072 — The shipped outcome is written by nothing that knows a release shipped
- TASK-073 — bin/init --plan: show what an install would change before it changes it
- TASK-074 — release.sh attributes every approval to "<actor> via invocation"
- TASK-065 — Shared frontmatter reader and writer, with a gate
- TASK-066 — Resolve the install root without leaving the enclosing repository

## Phase P3 — Verification independence

The agent grades its own work. `content/agents/auditor.md` is a correct
context-isolated, read-only, severity-tiered reviewer that advertises
itself for pre-merge review — and `/peer-review`, which holds
squash-merge authority, never calls it. The one independent grader in
the design (the `/goal` loop's evaluator) reads only the transcript by
documented design: it "runs no tools and reads no files".

- TASK-022 — Route `/peer-review` judgment through the `auditor` subagent; record author-vs-reviewer on the PR
- TASK-023 — Put falsifiable evidence into the transcript the `/goal` evaluator reads (re-scoped: the evaluator cannot be given tools or files)
- TASK-024 — Coverage-floor gate: refuse autonomous change to a surface with no executable behavioral evidence
- TASK-025 — Brownfield carve-out in `test-rules.md` sanctioning characterization tests, plus a `/pin-behavior` skill to write them
- TASK-026 — `autonomy_tier` on `rasa.lock.json`, read by `autonomy-rules.md`
- TASK-058 — The spec fast-path's allowlist is checked by a program (`spec-gate`), not by a model reading prose

## Phase P4 — The production loop

The loop is open at both ends: no inbound path turns a production signal
into a task, and nothing verifies a deploy after the deploy command
returns. "Deploy succeeded" is a statement about a shell process exiting
0. A release that shipped cleanly and then took production down is
indistinguishable, forever, from one that worked.

- TASK-027 — `60-verify.sh` post-deploy verification stage
- TASK-028 — `/rollback` skill invoking the rollback command that `release-rules.md` and the cloud stamp already specify
- TASK-029 — `deploys.sh` gains `outcome`/`health` and an `annotate` subcommand so a sealed record can learn what happened later
- TASK-030 — Make `content/build/deploy` honor the `[hooks] post_deploy` it already reads config for
- TASK-031 — `rasa.module.signals`: normalize an inbound alert, ticket or advisory into a task with an idempotency key and provenance
- TASK-075 — main changes only through a merged pull request

## Phase P5 — The fleet

`rasa.module.cto` v0.3.0 and a `taskflow` dispatcher run a real
three-repo company today, out of `/Volumes/256GB/vsi-orchestration` and
`/Volumes/256GB/vsi-tenant` — neither is a registered Element, and
reachability is broken in both directions. Meanwhile the one read-side
protocol this Element defines (active-orchestrator notices, read at
session start and treated as authoritative) has no shipped writer.

- TASK-032 — `tenant_root` in `rasa.lock.json` and a `/roster` skill that reads `tenant.members[]`
- TASK-033 — Ship `render-active-notice` as the writer for the active-notice protocol this Element already consumes
- TASK-034 — An upward channel: a member repo can raise a flag or blocker to the org tier
- TASK-035 — Cross-repo change set: N repos as one ordered unit with landing order and joint revert
- TASK-036 — **Cross-repo.** Promote `module.cto` into `elements/` and extract `taskflow` as `rasa.module.taskflow`

## Phase P6 — Authority

Every gate resolves to "the user, on this channel". The one
machine-enforced approval reads yes from `/dev/tty`, and the documented
escape is a process-wide `FORCE_APPROVAL=1`. At 50 agents the
operational choice becomes: staff 50 live terminals, or set that flag in
the fleet image and delete the production gate across every repo at
once — while the ledger keeps recording a consent that never happened.

- TASK-037 — Named principals: extend the tenant roster with owners and approvers; `requester`/`owner`/`approver` on the task stamp
- TASK-038 — An approval token bound to release + env + commit, carrying approver identity and an expiry, accepted in place of a TTY
- TASK-039 — Truthful approval provenance: distinguish tty-answered from token-authorized from force-bypassed in the ledger
- TASK-040 — Pending-decision queue: a headless run blocks on an out-of-band decision instead of rendering a question into a transcript nobody is reading

## Phase P7 — Supply chain and workforce integrity

`bin/init` overwrites 74 SKILL.md files and 27 rule files with whatever
is on disk — no version pin, no signature, no canary, no rollback. An
edit that quietly removes a verification step is indistinguishable from
an improvement. Separately, the workforce itself is un-versioned: `model:
opus` is a family name, nothing records which model produced a result,
and nothing tests whether a skill still *behaves* correctly —
`check-invocations` proves only that commands are runnable.

- TASK-041 — Port `domain-core`'s `/sync` + `/promote`; retire `/contribute`. Restores the severed learning-return leg
- TASK-042 — Content-tree digest in `rasa.json`, `bin/init --ref`, and a consumer-set `expected_sha`
- TASK-043 — Input-trust rule: text from any channel other than the operator is data, never instructions — with a `source`/`trust` field on the task stamp
- TASK-044 — Behavior evals for shipped skills: prove a skill still does what it claims, not merely that it can be invoked
- TASK-045 — Pin and record the model and harness a run used; define a supported range and a canary cohort for Element updates
- TASK-062 — Adopt rasa.module.tasks v1.0.0 and migrate consumers' ledgers on update
- TASK-063 — Fence 0.53.x off existing installations
- TASK-064 — Shipped docs prefix bin/task notes that bin/task already prefixes

## Phase P8 — External commitments

Nothing in the Element knows that a codebase has obligations to anyone
outside the company. Grepping `GDPR|HIPAA|PII|GPL|copyleft|license
compat|export control` across all of `content/` and `seed/` returns
essentially nothing. While humans staff engineering this lives in their
heads and is caught in review; remove them and the carriers are gone.
The first copyleft contamination and the first silently-broken public
API are not bugs an agent can fix — they are contractual events,
discovered by the counterparty.

- TASK-046 — Regulatory scope stamp: a repo declares PCI / HIPAA / GDPR / export-control scope, and it gates
- TASK-047 — License-compatibility gate in the release dependency sweep, which today covers dependency security and not dependency legality
- TASK-048 — Public-API contract: deprecation policy and a breaking-change gate for repos with external consumers
- TASK-049 — Org-level standards register, so a company-specific standard has a home other than 200 copies of one paragraph

## Phase P9 — Substrate (cross-repo: `kernel`)

**Not this repo's work.** The kernel executes exactly one agent turn
process-wide, hard-kills every turn at 5 minutes with zero default
retries, has no queue group on `commands.dispatch` (so a second `core`
replica receives and executes every command — double commits, double
pushes), and bounds no spend. "50 agents on 200 repos" is arithmetically
impossible on it today, and the naive scale-out is worse than the limit.

Filed here for program completeness. Per the workspace role-split these
are executed from `kernel/` in their own sessions.

- TASK-050 — **Cross-repo.** Queue group plus a bounded worker pool on `commands.dispatch`
- TASK-051 — **Cross-repo.** Configurable turn timeout honoring `WorkflowStep.timeout_ms`, with a non-zero default retry
- TASK-052 — **Cross-repo.** Per-cwd lease and a kernel-managed worktree per agent session
- TASK-053 — **Cross-repo.** Ship canon L-011's three budget breakers at the gateway
- TASK-054 — Turn and cost ceiling enforced at the `Stop` hook seam that `git-guard` and `task-enforce` already install (this repo)

---

*(Use `/task` to file and graduate tasks; use `/plan` to think through
new phases.)*
