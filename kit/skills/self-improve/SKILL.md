---
name: self-improve
description: Audit a screen, a functionality area, or the entire system for obvious professional improvements and apply them, iterating until two consecutive full passes find nothing left worth improving. Behavior-preserving only — no redesigns, no scope creep. Composes /mission — preflight, audit, decompose into improvement-tasks, develop, verify, repeat. Triggered when the user wants the codebase swept for polish — e.g. "/self-improve", "/self-improve the auth module", "tighten up the inbox screen", "find every obvious win in the billing flow".
---

# /self-improve — find every obvious win, apply it, repeat until clean

A `/mission` with a preset goal template: **audit the target for
obvious professional improvements, apply every one found, iterate
until two consecutive verification re-walks find nothing left
worth improving.** The skill does not invent its own methodology
— it follows `mission/SKILL.md` with a fixed goal recipe. Read
that file; this SKILL.md only states what is specific to
`/self-improve`.

Per CLAUDE.md ethos: an improvement is something the kit's own
rules (`craft-rules.md`, `test-rules.md`, `task-rules.md`) and
the codebase's own conventions can *verify* — not a matter of
taste. "This function is 200 lines and craft-rules.md caps
functions at 80" is improvable. "I'd write this differently" is
not.

## Behavior contract

- **Follows `/mission`.** Every step, gate, report shape, and
  exception is inherited from `mission/SKILL.md`. The two-pass
  verification re-walk (Step 6) is exactly what the user's
  "two full passes" requirement names. See `autonomy-rules.md`.
- **The goal template is fixed.** `/self-improve` does not ask
  the user what to improve. It runs against the goal recipe
  described in "The goal" below. The only user input is the
  optional scope argument.
- **Behavior-preserving only.** Every improvement must leave
  observable behavior unchanged. Tests that were green stay
  green; tests that were red stay red (red tests are
  `/self-heal`'s job). A change that alters behavior — even
  "obviously for the better" — is out of scope and gets flagged
  in the report, not executed.
- **Obvious wins only.** The bar is "the codebase's own rules,
  conventions, or tooling can verify the win." A judgment call
  on architecture or design is not obvious — it's a
  `/brainstorm` or a `/plan`. See "What counts as an
  improvement" below for the canonical list.
- **Ends at a draft PR.** Same as `/mission`. The improvements
  commit to a `feat/self-improve-<scope-slug>` branch; the draft
  PR opens when the two-pass re-walk is clean. Merge to main
  remains the user's call per `git-flow-rules.md` Rule 2 — there
  is no carve-out for self-improve.

## The scope argument

`/self-improve` accepts one optional argument naming the target:

- **No argument** — the entire system (the whole project).
- **A screen / route / page** — e.g. `/self-improve inbox`.
- **A functionality area / feature** — e.g.
  `/self-improve auth flow`.
- **A module / file** — e.g. `/self-improve src/api/users.ts`.

Issues found outside the scope are surfaced in the report but
not fixed.

## What counts as an improvement

Concrete and verifiable — each item is checkable by a linter, a
config rule, a craft-rules clause, or a "before/after diff that
preserves test behavior":

- **Linter warnings** (not errors — those are `/self-heal`).
- **Dead code** flagged by the project's tooling (`ts-prune`,
  `vulture`, `unimport`, etc.) or visible via import-graph
  walks.
- **Magic numbers / strings** that have an obvious named
  constant home (per `craft-rules.md` or codebase convention).
- **Outdated patterns** where the codebase has adopted a newer
  pattern elsewhere (e.g. `var` → `const` in a file that uses
  `const` everywhere else; callback → async in a file where
  every other handler is async).
- **Naming inconsistencies** where a symbol breaks the
  codebase's own convention (camelCase vs snake_case, file
  naming, etc.). The convention is read from the codebase, not
  imposed.
- **Missing JSDoc / docstrings on public APIs** where the
  codebase documents other public APIs.
- **Long functions / classes** that exceed limits the project
  configures (eslint `max-lines`, `complexity`, etc.) or the
  kit's `craft-rules.md` clauses.
- **Test coverage gaps in modified files** — when the project's
  coverage tool has a threshold and a file is below it, add
  tests until the file meets the threshold.
- **Import order / formatting** that violates the project's
  config (prettier, isort, etc.) — if not already auto-applied
  by a hook.

What is *not* an improvement target (log a finding, do not
execute):

- Refactors that change behavior (even "for the better").
- Architectural redesigns — different file structure, different
  module boundaries, different abstractions.
- Rewrites in a different style (functional → OO, OO →
  functional, etc.).
- Performance optimization (unless an existing perf budget is
  documented and breached — and even then, the redesign call
  is `/auto-develop`'s, not `/self-improve`'s).
- Subjective taste — "I'd structure this differently."

## The goal

`/self-improve` runs `/mission` against this goal recipe:

> Audit `<scope>` for obvious professional improvements per the
> kit's `/self-improve` definition. For each improvement found,
> file a `TASK-NNN` improve-task and execute it through the
> per-task lifecycle. Every improvement must be
> **behavior-preserving** — the test suite's green/red profile
> must be unchanged before vs. after.
>
> Continue iterating — find improvements, apply them, re-verify
> — until **two consecutive verification re-walks** find zero
> remaining improvements in scope.
>
> Stop at hard gates per `autonomy-rules.md`. Open a draft PR at
> the end per `/mission`'s Step 7.
>
> Improvements that would change behavior are surfaced in the
> report as candidate redesigns, not executed.

This goal feeds `/instruct` (Step 3 of `/mission`) which expands
it into a verified recipe.

## Process

1. **Resolve the scope** from the user's argument (default whole
   system). Render the mission brief naming the scope.
2. **Capture the behavior baseline.** Before any improvement
   runs, capture the test suite's green/red profile. After each
   improvement, re-run; behavior must match the baseline. This
   is the canonical "behavior-preserving" check.
3. **Follow `/mission`** with the goal recipe above. Every step
   of `mission/SKILL.md` applies — branch setup, instruct,
   decompose into improvement-tasks, execute, **two-pass
   re-walk**, deliver, report.
4. **Render the autonomy report** at the end — `/mission`'s
   shape, with the scope, the improvements applied, the two
   re-walk results, the PR URL, and any candidate redesigns
   surfaced but not executed.

The branch name is `feat/self-improve-<scope-slug>`.

## When NOT to use this skill

- **The system is broken and you need it fixed** → `/self-heal`.
  That's the repair skill; this is the polish skill.
- **You want a redesign or architectural change** →
  `/brainstorm` or `/plan`. `/self-improve` is behavior-
  preserving by contract; a redesign is by definition not.
- **You want one specific change** → `/auto-task` +
  `/auto-develop`. `/self-improve`'s audit-and-iterate is
  overhead for a known target.
- **You want the system shipped, not polished** → `/release`.

## What "done" looks like for a /self-improve session

A `feat/self-improve-<scope-slug>` branch with one commit per
improvement, every improvement's task spec in `tasks/completed/`, the
test suite's green/red profile unchanged from baseline, **two
consecutive clean verification re-walks** with zero in-scope
improvements remaining, and a **draft PR** open for review. The
autonomy report names every improvement applied, every candidate
redesign declined (and why), and any out-of-scope findings.
Merge to main remains the user's call.
