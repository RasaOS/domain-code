---
name: auto-test
description: Autonomously write and run the tests for a task or feature — derive the test scenarios from the spec's test plan, write the tests following the kit's test stamp model, run them, and report pass/fail. Every test-design decision is made without asking and flagged as an assumption. Triggered when the user wants a task tested hands-off — e.g. "/auto-test", "test this autonomously", "write and run the tests for TASK-NNN yourself", "auto-test the active task".
---

# /auto-test — autonomous testing

Takes a task or feature and tests it — writes the tests, runs
them, reports. The kit has no non-autonomous `/test` skill;
test *infrastructure* lives in `test-rules.md` and `tests/`, but
deciding and writing the tests has been open conversation.
`/auto-test` is the hands-off path.

Per CLAUDE.md ethos: a test is a contract, not a rationalization
of whatever the code already does. `/auto-test` writes tests
against the spec's intended behavior — if the code diverges from
the spec, the test should fail, and that failure is the finding.

## Behavior contract

- **Autonomous per `autonomy-rules.md`.** Read that file — the
  contract, the hard-gate list, the report template. This
  SKILL.md states only what's specific to `auto-test`.
- **Bound by `test-rules.md`.** Tests follow the kit's stamp model
  — a stamp under `tests/` declaring where the test lives and how
  to run it, grouped into suites. `/auto-test` writes real tests
  in the project's native framework, not pseudo-tests.
- **The spec's test plan is the source.** When a task spec exists,
  its "Test plan" section is the contract — implement those
  scenarios. Where the plan is thin or absent, derive scenarios
  from the acceptance criteria and the observable behavior, and
  flag each derived scenario as an assumption.
- **Test against the spec, not the code.** Assert the *intended*
  behavior. A test written to pass whatever the code currently
  does is worthless. If a test fails, decide — grounded — whether
  it's a test bug or a code bug, and say which in the report.
- **Run what you write.** Writing tests without running them is
  half a job. Run them; the report carries real pass/fail counts.
- **Hard gates stop the run.** Per `autonomy-rules.md`. Never
  auto-commit the tests.

## Process

1. **Read `autonomy-rules.md`, `test-rules.md`, and the task
   spec** (its Test plan + acceptance criteria). Plus `CLAUDE.md`
   for the test command and any test-infrastructure notes.
2. **Derive the scenarios.** From the spec's test plan where it
   exists; from acceptance criteria + observable behavior where it
   doesn't — each derived scenario flagged as an assumption.
3. **Write the tests** in the project's native framework, with a
   stamp under `tests/` per `test-rules.md`.
4. **Run them.** Capture real pass/fail.
5. **Triage failures.** For each failure, decide test-bug vs.
   code-bug, grounded — and say which.
6. **Render the autonomy report** — tests written, pass/fail
   counts, each failure's triage, every assumption, any hard gate.

## When NOT to use this skill

- **You want to design the test strategy yourself** → work it out
  in conversation; `/auto-test` decides the strategy for you.
- **Implementing the feature** → use `/auto-develop`.
- **A failing test reveals a code bug you want fixed** →
  `/auto-test` reports it; fixing routes through `/auto-develop`
  or a normal implementation pass.

## What "done" looks like

The task or feature has real tests — written in the native
framework, stamped per `test-rules.md`, and run — uncommitted. One
autonomy report carries the pass/fail counts, the triage of any
failure, and every test-design decision made. The user reviews,
acts on any code-bug findings, and commits.
