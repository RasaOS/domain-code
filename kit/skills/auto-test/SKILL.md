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
- **Pick the right kind of test for the change.** Decide the test
  *type* from what the diff touches and the project's existing
  conventions, not from a default. See "Test type selection"
  below.
- **Bootstrap when missing — or stop at a hard gate.** If the
  project has no test infrastructure for the type needed, attempt
  to set it up autonomously (the framework, a smoke test, a stamp
  and suite). If the bootstrap needs a user-only call (a paid
  service account, a device ID, a credential that can't be
  inferred from the repo), stop and surface exactly what's
  blocked. See "Bootstrap when missing" below.
- **Loop under `/goal` or `/mission` for multi-pass test work.**
  When a single run finishes but the goal (e.g. "every acceptance
  criterion has a passing test") is not yet met, the user runs
  this skill under Claude Code's `/goal` loop, or `/mission`
  composes it through its task lifecycle. `/auto-test` does not
  invoke `/goal` or `/mission` itself — slash commands are the
  user-input layer (per `autonomy-rules.md`).
- **Hard gates stop the run.** Per `autonomy-rules.md`. Never
  auto-commit the tests.

## Test type selection

Pick the test *type* from what the change actually touches.
Multiple types can apply to a single change — write the smallest
real test for each layer that the diff affects, not "one of each
to be safe."

| If the change touches… | Default test type |
|---|---|
| A pure function, a model, a service class, a reducer | **Unit** — assert input → output without mounting a UI or hitting a network. |
| A component's render / interaction / state | **Component** — mount the component, simulate user input, assert DOM / props. |
| A user-visible flow across components / routes | **E2E (UI)** — drive the real app via the project's E2E runner (Playwright / Cypress / Detox / XCUITest), assert observable behavior. |
| A backend endpoint, a CLI command, a script | **Integration / API** — exercise the actual handler / process with realistic inputs, assert the observable result. |
| Build, lint, type-check, config | **No new test** — the existing verification command is the gate. Run it; don't write a meta-test about it. |
| Docs, prose, spec files | **No new test.** A spec is not testable in code. |

Read the project's existing tests *before* picking. If the
project has only unit tests for similar code, a brand-new E2E
suite for one task is over-reach — match what's there. If a UI
flow has existing E2E coverage and the change is in a render
path, an E2E test is the natural extension. Mismatched test types
are a flagged assumption.

## Bootstrap when missing

If the type needed has no infrastructure in the project:

1. **Detect what's available.** Read `package.json`,
   `pyproject.toml`, `Cargo.toml`, `Gemfile`, etc. for installed
   test deps. Read `tests/` for existing stamps and suites. Read
   `CLAUDE.md` for any test-infrastructure note.
2. **Pick the smallest viable framework.** Default to what the
   project's stack expects: `vitest` / `jest` for JS, `pytest`
   for Python, `XCTest` for Swift, `cargo test` for Rust, etc.
   Match an adjacent project if there's a clear convention.
3. **Install and configure.** Run the install command. Add a
   minimal config. Add a stamp under `tests/` and a suite that
   references it. The smoke test for the new framework is the
   first real test — "framework loaded, one assertion passes."
4. **If blocked, stop.** A paid CI account, a device ID, a
   credential that can't be inferred from the repo, an API key
   without an obvious local source — these are user-only calls.
   Stop, report what's needed under "Hard gates hit", do not
   guess.

A bootstrap counts toward "tests written" only when the bootstrap
itself includes at least one real test for the actual change —
not just a framework-smoke. Frame­work installs without real
tests are surfaced in the report but do not satisfy the
operation.

## Process

1. **Read `autonomy-rules.md`, `test-rules.md`, and the task
   spec** (its Test plan + acceptance criteria). Plus `CLAUDE.md`
   for the test command, the test-infrastructure note, and any
   environment-specific gotchas.
2. **Select the test type(s)** per "Test type selection" — what
   the diff touches, matched against the project's existing
   conventions.
3. **Bootstrap if needed** per "Bootstrap when missing". If
   blocked by a user-only call, stop and report — that's a hard
   gate.
4. **Derive the scenarios.** From the spec's test plan where it
   exists; from acceptance criteria + observable behavior where
   it doesn't — each derived scenario flagged as an assumption.
5. **Write the tests** in the project's native framework, with a
   stamp under `tests/` per `test-rules.md`.
6. **Run them.** Capture real pass/fail.
7. **Triage failures.** For each failure, decide test-bug vs.
   code-bug, grounded — and say which.
8. **Render the autonomy report** — tests written, pass/fail
   counts, each failure's triage, every assumption, any hard gate,
   and the test type(s) chosen.

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
