---
id: TASK-XXX
category: bug
phase: <phase-id-of-broken-functionality>
status: backlog | active | blocked | completed
severity: low | medium | high
---

# TASK-XXX: <short title — describe the bug, not the fix>

> Bug-category task. Same user-story shape as a Spec, plus
> bug-specific fields: reproduction, expected vs. actual, root
> cause (where determinable without fixing), and acceptance
> criteria for the fix. Belongs to the phase whose functionality
> is broken — *not* a "bugs" phase.
>
> Before starting: read `CLAUDE.md` and `.claude/task-rules.md`.

## User story

As a **<role>**, I want **<the broken capability>** to **<work
correctly>** so that **<outcome>**.

## Why this matters

What breaks today because of this bug? Who is affected? Frequency
— is this every user, a subset, an edge case? Link the relevant
CLAUDE.md section if applicable.

## Steps to reproduce

Numbered, specific, runnable by another developer who hasn't seen
the bug yet.

1.
2.
3.

**Environment:** <browser/device/OS, build SHA, env (local/staging/prod)>

## Expected behavior

What *should* happen at the end of those steps.

## Actual behavior

What *does* happen. Include error messages verbatim, screenshot
file paths if applicable, stack traces if available.

## Root cause *(where determinable without fixing)*

What you currently suspect or know about why the bug occurs.
Acceptable to be partial — "the request fires, but the response
handler doesn't run; somewhere between dispatch and the reducer."
A guess flagged as a guess is fine. A guess presented as fact is
not.

If the root cause is unknown, say `Unknown — to be determined
during fix.`

## Scope

**In scope:**
- <bullet — what the fix changes>

**Out of scope (explicit):**
- <bullet — adjacent fixes that should be their own bugs>

## References

- Failing test: `<file:line>` (if one exists)
- Adjacent working pattern: `<file>`
- Related issue: `<link>`
- Related CLAUDE.md section: `<heading>`

## Files expected to change

List every file you expect to create or modify.

-

## Execution order

Step-by-step. For bugs, often: write a failing test first that
reproduces the bug, then fix, then verify.

1. Write a failing test in `<test file>` that reproduces the bug
2. Confirm the test fails for the documented reason
3. Fix in `<source file>`
4. Confirm the test now passes
5. Run the full suite — no regressions
6. Manual verification: <the smallest manual check>

## Acceptance criteria

Each item must be checkable. The first criterion is always
"reproduction no longer reproduces."

- [ ] Following "Steps to reproduce" produces "Expected behavior"
- [ ] New test passes (cite it)
- [ ] Full test suite green
- [ ]

## Test plan

The new test that locks the bug down. This test is the
regression contract — it must fail against the broken code and
pass against the fix.

1. **Setup:** <seeded state>
2. **Steps:** <the smallest reproduction>
3. **Assert:** <what the test checks>

## Rollback / blast radius

What else does the fix touch? If a regression slips through, what
gets reverted?
