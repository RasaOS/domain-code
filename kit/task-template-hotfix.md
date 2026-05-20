---
id: HOTFIX-XXX
category: hotfix
phase: null
status: active | done
severity: high | critical
filed: <YYYY-MM-DD HH:MM UTC>
---

# HOTFIX-XXX: <short title — describe what's broken in prod>

> Hotfix-category task. **Production is broken or imminently
> failing. This task ships ASAP.** Filed straight to
> `tasks/active/` — no backlog stop, no phase placement, not in
> `ROADMAP.md`. Branch: `hotfix/HOTFIX-XXX-slug` per
> `git-flow-rules.md` Rule 1.
>
> Before starting: read `CLAUDE.md` and `.claude/task-rules.md`.
> If this is *not* genuinely urgent, re-categorize as `bug` and
> route through the normal lifecycle.

## What's broken in production

One paragraph. The user-visible symptom AND the technical root
cause (where known). Be precise — a hotfix template that says
"login doesn't work" without saying which step / which user /
which API is harder to ship than one with the specifics.

## Why this is a hotfix and not a bug

Bug or hotfix is a procedural distinction, not a technical one.
Name the urgency. Acceptable justifications:

- "Prod is down for all users."
- "Data is being corrupted on every write."
- "A regulatory deadline ships in <N hours>."
- "<Customer X>'s release goes out tomorrow and they're blocked."
- "Security vulnerability flagged at <severity> by <tooling>."

Not justifications: "It would be nice to fix soon." "I want this
in the next release." Those are bugs, not hotfixes.

## The smallest fix

Hotfix discipline: **the smallest change that solves the
problem**. Not "the right architectural answer" — that's a
follow-on. Name what the fix changes; flag anything left
deliberately undone.

### What the fix changes
-
-

### What this fix does NOT do *(deliberate)*
- <follow-on improvements that should be a `bug` task afterward>

## Files expected to change

List exactly. A hotfix that touches a sprawling diff is not a
hotfix; it's a rewrite under pressure.

-

## Verification

The fastest verification that proves the fix works. Often a
single manual reproduction or a focused test, not the full
suite — speed matters, but never skip *the* verification that
proves the user-visible symptom is gone.

1. **Reproduce the bug on the pre-fix build:** <steps>
2. **Apply the fix.**
3. **Re-run the reproduction:** must now succeed.
4. **Smoke-test adjacent functionality:** <the smallest sanity check>

## Rollback plan

If the hotfix itself breaks something, what reverts it? Capture:

- **Revert command:** `git revert <commit>` — or the project's
  rollback command for the deployed surface.
- **What state we'll be in after rollback:** still broken on the
  original symptom, but no new regressions from the hotfix.
- **Who can authorize a rollback decision:** the user, on this
  channel, or a named on-call human if escalation is needed.

## Post-fix follow-ups

The smallest-fix discipline leaves work undone. Capture each
follow-on as a stub `bug` task (file path here so they get filed
after the hotfix ships, not during it).

- TASK-XXX (to be filed) — <follow-on>
- TASK-XXX (to be filed) — <follow-on>

## AUDIT entry *(when shipped)*

Per `release-rules.md`, a 🔥 Hotfix entry in `tasks/AUDIT.md`:

```
- 🔥 **HOTFIX-XXX shipped** — <one-line description>. Branch
  `hotfix/HOTFIX-XXX-slug`. Tag `vX.Y.Z-<sha>-prod`.
```
