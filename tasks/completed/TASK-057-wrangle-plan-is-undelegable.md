---
id: TASK-057
category: bug
phase: P2
status: completed
owner: unassigned
blocked_by:
outcome: shipped
filed: 2026-09-21 04:25 UTC
origin: manual
---

# TASK-057: /wrangle's remediation plan cannot be delegated

**User story.** As an **operator onboarding a legacy repo**, I want **the
cleanup plan `/wrangle` produces to land in `tasks/`** so that **the work can
be picked up by an agent instead of dying in the transcript**.

## What was wrong

`/wrangle` Phase 1 writes durable docs to `docs/wrangle/` and
`.claude/context/project-map.md`. Phase 2 produces the actual remediation plan
— Tier 1 quick wins with `file:line` citations, Tier 2 targeted reviews — and
**renders it as chat markdown**. Verified: the skill had **zero** references to
`tasks/` anywhere in 600+ lines.

So the most valuable output of wrangling an inherited repo was the most
perishable. The plan cannot be picked up by `/auto-task`, does not appear in
`/status`, and is gone when the session ends.

Same defect class as TASK-020 (the autonomy report was rendered, never
written), in the skill most likely to be the *first* thing run on a repo the
company just inherited.

## What changed

A consent-gated filing step. Tier 1 and Tier 2 items become task stubs in
`tasks/backlog/`; the skill reports the ids so `/status` shows them at once.

Four things the instructions are explicit about, each a way this goes wrong:

- **Use the allocator** (`task-enforce.sh new`), never hand-written ids —
  hand-writing races the id allocator and two items take the same number.
- **`new` sets the current-task pointer**, so filing several leaves the last
  one current. Clear it afterwards.
- **Tier 3 is not filed.** Those are questions for the user — decisions, not
  work. A question filed as a task looks like something an agent can close.
- **Fill in the body** with the `file:line` citations and a cross-reference to
  `docs/wrangle/<area>.md`, so the task carries its own evidence. A stub
  reading only "remove dead code" is not delegable either.

Consent is preserved, not weakened: filing is a write, and this skill's whole
contract is that it proposes rather than applies. It offers and waits, with a
matching entry in the Don'ts beside "Don't auto-run Phase 2".

## Note on the first attempt

The first edit spliced a closing ``` in the wrong place, cutting the plan
template in half and leaving the back half as loose prose. Caught by counting
fences before and after (16 → 19, delta 3 where 2 was intended), reverted with
`git checkout main --`, and redone against the real block boundaries. Final
delta is exactly +2, balanced. Counting the fences is what caught it — reading
the splice region looked fine.

## Acceptance criteria

- [x] Tier 1 + Tier 2 can be filed to `tasks/backlog/`; Tier 3 explicitly is not
- [x] Filing uses the id allocator, and the pointer side effect is documented
- [x] Consent-gated, with a matching Don't
- [x] Markdown fences balanced (18, delta +2 for the one added code block)
- [x] `check-invocations` 0, `bin/lint` 0
