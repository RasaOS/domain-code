---
name: deploys
description: Show the ship log — every deploy and release, what went out, where it went, when, by whom, and whether it worked. Reads `deploys/records/` via `deploys.sh`. Use for "/deploys", "what went to staging", "when did we last ship to prod", "who deployed this", "did that release succeed", "show me the deploy history". Read-only; it never deploys anything.
---

# /deploys — What shipped, where, and when

The ledger answers questions a git log cannot: *which environment*
received *which tag*, *when*, *who sent it*, and *did it work*.

`deploys/records/<id>.md` is the truth — one file per execution.
`deploys/DEPLOYS.md` is a regenerated view of it and is never
hand-edited. The engine is `.claude/skills/deploys/deploys.sh`.

**This skill is read-only.** It never runs `build/deploy`. To ship, use
`/deploy` (lower environments) or `/release` (production).

## Steps

### 1 — Answer the question that was actually asked

| They asked | Run |
|---|---|
| "what's shipped lately" | `deploys.sh list` |
| "what went to staging" | `deploys.sh list --env staging` |
| "when did we last ship to prod" | `deploys.sh list --env prod --limit 1` |
| "details on that deploy" | `deploys.sh show <id>` |
| "is the ledger healthy" | `deploys.sh check` |

```bash
.claude/skills/deploys/deploys.sh list --env staging --limit 10
```

If the ledger does not exist yet, say so plainly — "nothing has been
deployed through `./build/deploy` on this project yet" — rather than
reporting an empty history as if it were a fact about shipping.

### 2 — Read the record, not just the table

`deploys.sh show <id>` prints the full record. The fields that usually
matter:

| Field | Why you care |
|---|---|
| `kind` | `deploy` (lower) or `release` (production, tagged) |
| `class` | the environment's class at the time it shipped |
| `tag` / `sha` / `branch` | exactly what went out |
| `status` | `success`, `failed`, or `in-flight` |
| `error_stage` | which stage failed |
| `approval` | how the human consented — see below |
| `user` / `host` | who sent it, from where |

### 3 — Interpret `approval` honestly

`approval: invocation` means **invocation was the consent**: a human ran
`/release`, and that skill's contract is that invoking it IS the
approval. No prompt appeared. That is the normal value for a release
driven through the skill, and it is recorded that way deliberately —
writing an approver for a prompt that never fired would put a lie in an
audit trail.

`approval: none` means a lower-environment deploy, which needs no
approval.

If someone asks "who approved this production release", the honest
answer is the `user` field plus "by invoking /release" — not a separate
sign-off, because there isn't one.

### 4 — Report `in-flight` and drift as real findings

An `in-flight` record means a run died without closing — the process was
killed, the machine slept, CI timed out. It is not a deploy in progress
unless one genuinely is. Say which, and when it started.

`deploys.sh check` exits 3 when `DEPLOYS.md` disagrees with the records.
That means someone hand-edited the view or a record arrived via a merge
without a regeneration. Fix with `deploys.sh index` and say you did.

## What the ledger does not contain

**No secrets, ever.** Not values, not env-file contents, not command
output that might carry either. A record holds *what* shipped, *where*,
*when*, and *by whom*. If someone asks the ledger what the staging
database password was, the answer is that it does not and will not know.

It also does not record deploys that never ran: a run refused by
`class-guard.sh` leaves no record, because a refusal is not a deploy.

## Related

- `/deploy` — ship to a lower environment.
- `/release` — ship to production, tagged.
- `/environment` — the registry, and each environment's class.
- `.claude/pipeline-rules.md` — the stage and gate contract.
