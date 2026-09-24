---
id: TASK-019
type: defect
created: 2026-09-21
created_by: chazzcoin
updated: 2026-09-21
phase: P2
completed_by: chazzcoin
x-origin: manual
x-outcome: shipped
x-owner: unassigned
---
# TASK-019: Thread RASA_ACTOR through every provenance site

**User story.** As an **auditor**, I want **the ledger to record which actor
performed an action** so that **"who approved this production release" does not
resolve to a service account**.

## What was wrong

Five sites called `$(whoami)` directly, so an agent running under a service
account was recorded exactly as a human would be — in the deploy ledger, the
env-sync ledger, and the release approval line:

| Site | Recorded |
|---|---|
| `content/build/deploy:138` | `DEPLOY_USER` |
| `content/build/gates/approval.sh:84` | "✓ Approved by …" |
| `content/skills/deploys/deploys.sh:138` | `user:` in every deploy record |
| `content/skills/env-sync/env-sync.sh:176` | `user:` in every transfer record |
| `content/skills/release/release.sh:514` | `**Approved.**` in RELEASES.md |

A sixth resolution existed in `task-guard.sh`, on a **different** order
(git identity → `$USER`), so two answers to "who" shipped side by side.

## What changed

One resolution order, applied at all six sites and documented once:

1. `RASA_ACTOR` — the knob a runner, CI job or agent harness sets
2. the clone's git identity
3. the OS user

`content/env-rules.md` gains a `RASA_ACTOR` section — it is where env vars are
documented, so it is where someone will look. It states that the variable is
not a secret and carries **no authorization**: it says who acted, not who
approved. It also says why it is deliberately not a per-environment `env.sh`
value — that file is sourced into the deploy driver's own shell, and identity
should not be settable by the thing being deployed (the same reasoning that
closed the `BUILD_DIR` hijack in TASK-012).

`stamps.md` → `Stamp: run` → `actor` now states the full order rather than
"`RASA_ACTOR`, falling back to `$(whoami)`".

## Verified by running

Against a real `deploys.sh` record, all three fallback levels:

| Condition | Recorded |
|---|---|
| no `RASA_ACTOR`, git identity set | `Git Identity` |
| `RASA_ACTOR=agent:mission-runner` | `agent:mission-runner` |
| neither set | the OS user |

`release.sh`'s helper resolves identically. Every remaining `$(whoami)` in
`content/` is the third fallback *inside* the helper, or its comment.

## Deliberately not done here

`DEPLOY_APPROVAL` has **one reader** (`build/deploy:247`,
`${DEPLOY_APPROVAL:-invocation}`) and **zero writers**, so the ship log always
records the literal `invocation` regardless of how approval was actually
obtained. That is a truthfulness problem about *how*, not *who* — `TASK-039`
owns it, and fixing it here would have meant designing the tty / token /
force-bypass distinction that `TASK-038` has not built yet.

## Acceptance criteria

- [x] One resolution order, used at all six sites
- [x] `RASA_ACTOR` wins; git identity and OS user are the fallbacks — each verified
- [x] No bare `$(whoami)` remains as a provenance source
- [x] Documented where env vars are documented, with its non-authorization stated
- [x] `check-manifest` 184, `check-bash32` 0, `check-invocations` 0, `lint` 0
