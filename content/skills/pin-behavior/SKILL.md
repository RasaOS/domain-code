---
name: pin-behavior
description: Pin the current observable behavior of an untested surface as a characterization baseline, so a legacy repo becomes safe to change and can pass the production test gate. Writes runnable test scripts plus `test_kind: characterization` stamps, wires them into a suite, and reports what it could NOT pin. For brownfield code with no spec and no tests — not a substitute for testing intent. Triggered when the user says "/pin-behavior", "pin this behavior", "characterize this module", "I inherited this and need to change it safely", "the prod gate is refusing because we have no tests".
---

# /pin-behavior — make untested code safe to change

You inherited a surface with no tests, no spec, and often no
surviving author. Something has to change in it. The only honest
assertion available is **what it does today** — so record that,
label it as a baseline rather than as intent, and let the next
change become visible.

This exists because the production test gate refuses a suite that
would run nothing (`gates/tests-required.sh`), and "this repo has
no tests" is no longer a state you can deploy from. The escape
hatch is not a bypass flag; it is writing one real test.

## What a characterization test is, and is not

- **It records observed behavior.** Run the code, capture what it
  produces, assert that it keeps producing it.
- **It makes no claim that the behavior is correct.** That is the
  whole difference from an intent test, and why the stamp carries
  `test_kind: characterization`. A reader must be able to tell
  which of a repo's tests encode intent and which encode history.
- **It is a floor.** It makes the surface safe to touch. It does
  not discharge the obligation to test intent once intent is known.

Read `test-rules.md` → "Brownfield: pinning behavior you did not
specify" before writing any. The boundaries there are binding.

## Behavior contract

- **Never pin where a spec exists.** If the task spec has a test
  plan, that is the contract — implement it with `/auto-test`
  instead. Characterization is only for behavior nobody wrote down.
- **Never pin a bug.** If the observed behavior is plainly wrong —
  a crash, a corrupted value, an obvious off-by-one — that is a
  **finding**, not a baseline. Record it, surface it, and do not
  freeze it. Pinning a bug makes it permanent and makes the fix
  look like a regression.
- **Pin the riskiest surface first.** The value is concentrated in
  whatever the next change is most likely to break. One test on the
  checkout total beats six on a formatting helper.
- **Run what you write.** A baseline that has never run is not a
  baseline. The report carries real pass/fail counts.
- **Say what you could not pin.** Non-determinism, network
  dependence, wall-clock behavior and hidden global state are the
  usual blockers. An honest "these three surfaces resisted pinning,
  here is why" is the useful half of the output — those are exactly
  the surfaces a later change will break silently.
- **Do not refactor while pinning.** Touching the code changes the
  behavior you are trying to record. Pin first; change after.

## Process

1. **Scope.** Take the target from the argument (a path, a module,
   a feature). With no argument, ask — do not guess a whole repo.

2. **Find the seams.** Identify where behavior is observable
   without modifying the code: CLI output, HTTP responses, a pure
   function's return, a file written, an exit code. Prefer the
   outermost seam that still pins something specific.

3. **Check for non-determinism before writing.** Run the candidate
   twice and compare. Timestamps, ordering, random ids and
   locale-dependent formatting all produce a baseline that fails on
   the next run. Normalize them explicitly in the script, or record
   the surface as unpinnable — never paper over it with a retry.

4. **Write the script.** Put it in `tests/scripts/` per
   `test-rules.md` → "Fallback: `tests/scripts/`". It must exit
   non-zero when behavior changes, and print the actual-vs-expected
   difference when it does — a baseline that fails with no output
   sends the next person straight to `--skip-tests`.

5. **Stamp it.** `tests/stamps/YYYYMMDD_NNN_slug.md`, with
   `test_kind: characterization`, `status: active`, a real
   `run_command`, and `tags: [brownfield, baseline]`. The
   `test_kind` value is required, not decorative.

6. **Wire it into the suite.** Add the stamp's `name` to
   `tests/suites/pre-deploy.md`. A stamp no suite references runs
   nowhere and does not satisfy the gate — `tests-required.sh`
   lists exactly these when it refuses.

7. **Verify against the gate.** Run
   `ENV_CLASS=prod bash build/stages/30-test.sh <env>` and confirm
   it now passes having actually run something. Before this skill,
   that command exited 0 having run nothing.

## Output structure

```markdown
# 📌 Behavior pinned — <target>

> **Pinned.** <N> baselines, all passing
> **Unpinnable.** <N> surfaces — see below

## Baselines written

- `<stamp-name>` — <what observable behavior it records>

## Could not pin

- `<surface>` — <why: non-determinism / network / global state>

## Findings (NOT pinned)

<Behavior that looked wrong. Each one is a candidate bug, deliberately
left unfrozen. Omit this section if there were none.>

- ⚠️ <what looked wrong> — <why it looks like a bug rather than a baseline>

## What's next

<The intent tests that should eventually replace these, or the
change this surface was being pinned for.>
```

## Don'ts

- **Don't stamp a characterization test as `regression` or
  `unit`.** The label is the point; hiding it makes the repo's
  tests indistinguishable within a release or two.
- **Don't pin behavior you are about to change** in the same run.
  Pin, commit, then change — otherwise the baseline records the new
  behavior and proves nothing.
- **Don't treat a red characterization test as automatically a
  bug.** It means behavior changed. Decide, grounded, whether the
  change was intended; if it was, update the baseline in the same
  commit and say so in the report.
- **Don't use this to satisfy the gate cosmetically.** One test
  that asserts `exit 0` on `--help` technically passes the gate and
  protects nothing. The gate is a floor for the real goal, not the
  goal.
