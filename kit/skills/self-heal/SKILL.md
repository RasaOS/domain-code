---
name: self-heal
description: Audit a screen, a functionality area, or the entire system for problems and fix everything found, iterating until two consecutive full passes find nothing left to heal. Composes /mission — preflight, audit, decompose into fix-tasks, develop, verify, repeat. Triggered when the user wants the system swept clean of issues end-to-end — e.g. "/self-heal", "/self-heal the inbox screen", "find and fix everything broken in the auth flow", "make the whole app stop being broken".
---

# /self-heal — find every problem, fix it, repeat until clean

A `/mission` with a preset goal template: **audit the target,
fix every real issue found, iterate until two consecutive
verification re-walks find no remaining issues.** The skill does
not invent its own methodology — it follows `mission/SKILL.md`
with a fixed goal recipe. Read that file; this SKILL.md only
states what is specific to `/self-heal`.

Per CLAUDE.md ethos: a problem is something verifiably broken,
not something subjectively bad. "This test fails" is a problem.
"This could be cleaner" is not — that's `/self-improve`'s job.
The cleanest separation between the two is the test the user can
run to confirm: if there's a green/red answer, it's a heal target;
if it's taste, it's improvement.

## Behavior contract

- **Follows `/mission`.** Every step, gate, report shape, and
  exception is inherited from `mission/SKILL.md`. The two-pass
  verification re-walk (Step 6) is exactly what the user's
  "two full passes" requirement names. See `autonomy-rules.md`
  for the broader autonomous-skill contract.
- **The goal template is fixed.** `/self-heal` does not ask the
  user what to fix. It runs against the goal recipe described in
  "The goal" below. The only user input is the optional scope
  argument.
- **What counts as a problem.** A real, verifiable failure of the
  system to behave as specified. See "What counts as a problem"
  below for the canonical list. Subjective improvements
  (refactoring, naming, polish) are explicitly out of scope —
  use `/self-improve` for those.
- **Behavior-preserving fixes preferred.** The fix should restore
  intended behavior, not redesign it. A bug that requires a
  redesign to fix is a flagged assumption — the skill names the
  redesign in the report rather than executing it silently.
- **Ends at a draft PR.** Same as `/mission`. The fixes commit to
  a `feat/self-heal-<scope-slug>` branch; the draft PR opens
  when the two-pass re-walk is clean. Merge to main remains the
  user's call per `git-flow-rules.md` Rule 2 — there is no
  carve-out for self-heal.

## The scope argument

`/self-heal` accepts one optional argument naming the target:

- **No argument** — the entire system (the whole project).
- **A screen / route / page** — e.g. `/self-heal inbox`,
  `/self-heal /settings/profile`.
- **A functionality area / feature** — e.g.
  `/self-heal auth flow`, `/self-heal billing`.
- **A module / file** — e.g. `/self-heal src/api/users.ts`,
  `/self-heal apps/web`.

The scope is the target the audit pass walks against. Issues
found *outside* the scope are surfaced in the report but not
fixed in this run — fixing them would expand the contract beyond
what the user asked for.

## What counts as a problem

A `/self-heal` target. Concrete and verifiable:

- **Failing tests.** Anything red in the project's test suite.
- **Build failures.** Compile errors, type errors, missing
  imports.
- **Linter errors** (not warnings — those are `/self-improve`).
- **Runtime errors / crashes** discoverable via the project's
  verification commands (smoke tests, integration tests).
- **Unhandled error paths** the spec or codebase already calls
  out as expected to be handled.
- **Security vulnerabilities** the project's existing security
  tooling flags (`npm audit`, `cargo audit`, `pip-audit`, etc.).
- **Accessibility violations** the project's a11y tooling flags
  (axe, pa11y, etc.) — when a UI scope is targeted.
- **Broken contracts.** A function whose behavior contradicts
  its documented signature or its caller's expectations.
- **Dead references.** Imports that don't resolve, calls to
  functions that no longer exist, route paths to deleted pages.

What is *not* a `/self-heal` target (route to `/self-improve` or
log a finding):

- Subjective code style (formatting, naming, structure).
- Refactoring opportunities.
- Test coverage gaps (unless a spec acceptance criterion is
  explicitly unmet).
- Optimization (unless the project's perf budget is breached).
- Documentation gaps.
- Modernization (old patterns → new patterns).

## The goal

`/self-heal` runs `/mission` against this goal recipe:

> Audit `<scope>` for problems per the kit's `/self-heal`
> definition. For each issue found, file a `TASK-NNN` fix-task
> and execute it through the per-task lifecycle. Continue
> iterating — find issues, fix them, re-verify — until **two
> consecutive verification re-walks** find zero remaining
> issues in scope.
>
> Stop at hard gates per `autonomy-rules.md`. Open a draft PR at
> the end per `/mission`'s Step 7.
>
> Findings outside the scope are surfaced in the report but not
> fixed; they become candidates for a follow-on `/self-heal` run
> with an expanded scope.

This goal feeds `/instruct` (Step 3 of `/mission`) which expands
it into a verified, ordered, gap-checked recipe. The expanded
recipe is what the mission actually runs against.

## Process

1. **Resolve the scope** from the user's argument (or default to
   the whole system). Render the mission brief naming the scope.
2. **Follow `/mission`** with the goal recipe above. Every step
   of `mission/SKILL.md` applies — branch setup, instruct,
   decompose into tasks, execute, **two-pass re-walk**, deliver,
   report.
3. **Render the autonomy report** at the end — `/mission`'s
   shape, with the scope, the issues found, the fixes
   committed, the two re-walk results, the PR URL, and any
   out-of-scope findings.

The branch name is `feat/self-heal-<scope-slug>` (e.g.
`feat/self-heal-inbox`, `feat/self-heal-whole-system`).

## When NOT to use this skill

- **You want to improve subjectively-better code** →
  `/self-improve`. That's the polish skill; this is the
  repair skill.
- **You know the specific issue and want to fix just that** →
  `/auto-task` + `/auto-develop` + `/auto-test`. `/self-heal`'s
  audit-and-iterate is overhead for a known problem.
- **You want to design or replan, not fix** → `/plan` or
  `/brainstorm`. `/self-heal` repairs existing behavior; it does
  not invent new behavior.
- **You want the system shipped, not healed** → `/release`.
  `/self-heal` ends at a draft PR; `/release` deploys.

## What "done" looks like for a /self-heal session

A `feat/self-heal-<scope-slug>` branch with one commit per fix,
every fix's task spec in `tasks/done/`, **two consecutive clean
verification re-walks** with zero in-scope issues remaining, and
a **draft PR** open for review. The autonomy report names every
issue fixed, every assumption made (especially redesigns the
skill declined to execute silently), and any out-of-scope
findings surfaced for follow-on. Merge to main remains the
user's call.
