---
id: TASK-022
type: change
created: 2026-09-21
created_by: chazzcoin
updated: 2026-09-21
phase: P3
completed_by: chazzcoin
x-origin: manual
x-outcome: shipped
x-owner: unassigned
---
# TASK-022: /peer-review forms its verdict from the artifact, not from memory

**User story.** As a **reviewer**, I want **the merge verdict formed by a
reader that never saw the change being written** so that **an approval is
decorrelated from the reasoning that produced the change**.

## The stub was half right, and the missing half is bigger

The stub said: route judgment through the `auditor` subagent. Recon says the
delegation is the **second**-largest decorrelation. The largest is that
`/peer-review` **does not read the PR at all**.

`grep -rn 'gh pr diff\|gh pr view'` over `content/` returns **zero hits in the
entire Element**. The skill's instruction to "read the diff" is satisfied, in
the authoring session, by memory of having written it.

It was not always so. **v0.48.0 (`72f1149`) deleted a 34-line `## Process`
section**, whose step 3 was exactly:

```
gh pr diff <N>
gh pr view <N> --json files,title,body,headRefName,baseRefName,statusCheckRollup
```

Verified with `git show 72f1149 -- content/skills/peer-review/SKILL.md`. So
roughly half of P3's headline finding is a **regression**, not an original
design flaw — and that is the same commit that botched the spec-file allowlist
repaired in TASK-013.

## What this buys, stated honestly

| Property | Value |
|---|---|
| **Re-derivation from the pushed artifact** | Largest. Needs no subagent — two `gh` calls. |
| **Context isolation** | Real, second-largest. The reviewer never sees the author's reasoning trace. **Partial**: the parent composes the prompt, so framing leaks. |
| **Read-only tools** | Tamper-resistance, not independence — the reviewer cannot quietly fix a defect and then bless it. |
| **Model diversity** | **Zero, and declined deliberately.** A weaker reviewer misses more; there is no second provider here. |

**What it does not buy: separated interest.** Same model, same session, same
process env, same `RASA_ACTOR`, very likely the same `gh` token. This delivers
**decorrelated error, not deterrence of a motivated cheater** — consistent with
the Element's own stated non-adversarial threat model. Any sentence implying a
second *party* reviewed would be a false provenance claim, and TASK-019 was
spent making provenance truthful.

## Two scope corrections

**"Record author-vs-reviewer" cannot ship as stated.** `rasa_actor()` yields
RASA_ACTOR / git name / OS user; `gh pr view --json author` yields a GitHub
login. They are different namespaces with no mapping, so an equality test
compares incomparable strings and would **report independence that was never
verified**. Record the *mechanism* (`review_mode`), the PR number as a join
key, and the PR author as a separately-labeled foreign identity. **No
`independent` boolean, in any form.**

**CRITICAL binds; HIGH does not.** The auditor defines HIGH as "action this
batch" — a backlog horizon, not a merge verdict. Binding HIGH across ~200 repos
produces chronic false rejects on pre-existing debt a diff merely brushes, and
an expensive mandatory step that cries wolf is the step that gets disabled.
HIGH goes in the approval body as a named non-blocking concern.

## Authority

A refusal needs **no new authorization**. Rule 2 grants authority "for an
accepted PR" — declining to exercise a grant falls back to the rule's own
default ("otherwise `main` does not move"). The closed-list sentence governs
*adding* merge-bearing skills; this **narrows** peer-review's authority.
Precedent already ships: the skill hard-gate stops today, a refusal Rule 2 never
names.

"Invocation is consent" forbids **asking**, not **stopping** — so a CRITICAL
terminates in a *verdict*, never in "merge anyway?". The refusal shape is
**reject** (`gh pr review --request-changes`), which hands the PR back to the
authoring agent rather than to a human.

Rule 2 is amended for **disclosure**, not power: one or two sentences appended
to the existing bullet, no new list entry.

## Explicitly NOT closed by this task

`/auto-task` and `/auto-phase` auto-merge their own spec PRs under
autonomy-rules Exception 2, **ungraded by anyone**, and never call
`/peer-review` (11 hits across `content/`, none a call site). That is the door
an autonomous fleet actually walks through. Filed separately — this task closes
one of two.

## Acceptance criteria

- [x] `gh pr diff` / `gh pr view` present — currently zero across the Element
- [x] Process section restored with the delegation inserted before the verdict
- [x] Accept is conditional on the verdict; approve and merge no longer adjacent
- [x] CRITICAL ⇒ reject; HIGH ⇒ non-blocking note in the approval body
- [x] Rule 2 discloses the precondition; still exactly 3 carve-out bullets
- [x] No `independent` boolean anywhere; `review_mode` records the mechanism
- [x] `audit.sh` untouched, so `/audit` output still validates
- [x] All four gates green
