---
name: test
description: The TEST phase — test one recorded build end to end, and add tests to the suites that gate it. `/test` runs `./build/test` against the newest successful `/build` record for HEAD — the gate suite (`tests/suites/pre-deploy.md`, or `prod-gate.md`), then `tests/suites/e2e.md` with its runtimes started, health-checked and always stopped — and writes `tests/runs/TST-*.md`, which `/deploy` and `/release` require before staging or production. `/test add` writes a test stamp and wires it into the right suite (unit / integration / e2e / smoke), including the runtime an e2e test needs. Triggered when the user wants the build tested or a test added — e.g. "/test", "run the tests", "run the e2e tests", "test the build before we deploy", "/test add", "add an e2e test for checkout", "add a smoke test".
---

# /test — test the build, not the source

The second of three phases: **`/build` → `/test` → `/deploy`** (or
`/release`). `/test` does not build and does not test "whatever is
in the tree": it tests the one build `/build` recorded for HEAD,
refuses if those artifacts changed since, and writes a test record
the deploy gate reads. A staging or production deploy with no
passing test record for its commit is refused, with no bypass.

Per CLAUDE.md ethos: real counts from a real run, never "tests
pass". A phase that ran nothing did not pass.

## Behavior contract

- **Script-driven.** `./build/test` owns the mechanics — finding the
  build, the fingerprint check, the suites, the runtime lifecycle,
  the record. This skill routes the user's intent to it, reads its
  output, and reports. Never run suites by hand and call that a test
  phase: no record is written, so nothing downstream accepts it.
- **Build first.** No successful `/build` of HEAD → say so and run
  `/build` (or ask, if the user only asked for tests). Never reach
  around the refusal.
- **Fail-closed, with no bypass.** A suite that runs nothing fails.
  An `e2e.md` that exists is never optional. A runtime that exits,
  never gets healthy, or has no start command fails the run.
- **The runtimes always come down.** Pass, fail, error, Ctrl-C or
  kill: `./build/test` runs each runtime's `commands.stop` (if it has
  one), then stops every process it started and any test still
  running. If a port is still held after a run, that is a defect —
  report it, don't paper over it.
- **Every test has a time limit.** The stamp's `timeout_seconds`, else
  900s. A test that overruns is killed with everything it started and
  counts as failed — a hung test can no longer hang the pipeline.
- **The newest run decides.** The deploy gate reads the most recent
  test run of this source: a pass followed by a failure (or a run that
  was killed) is not verified. Re-run `/test` after a fix; never
  point at an older pass.
- **One run at a time.** A second `/test` while one runs is refused
  (`tests/runs/.lock`) — e2e runtimes bind fixed ports.
- **`/test add` edits the suites, which are the gate.** Adding a test
  to `pre-deploy.md`, `e2e.md` or `smoke.md` changes what every future
  deploy must pass. Say which suite, and why. Never remove a test from
  a suite, or quarantine one, to get a run green — that is a
  reviewable decision for the user, recorded in `tests/TESTS.md`.

## Running the test phase

```bash
./build/test                     # the newest successful build of HEAD
./build/test --build=BLD-…       # a specific build of HEAD
```

| Phase | Suite | What happens |
|---|---|---|
| 1 · gate | `prod-gate.md`, else `pre-deploy.md` | Run strict: listing no tests, or every test quarantined, fails. |
| 2 · e2e | `e2e.md`, if it exists | For each name in its `runtimes:` list: run its `depends_on` checks; refuse if its health check already passes (another process owns the port); start `.claude/runtimes/<name>.md`'s `commands.start` in its own process group; poll its `health_check` (`url` + `expect_status`, or `command`) until healthy or `timeout_seconds`. Then run the suite strict, fail it if a runtime died meanwhile, and stop everything. |

Every test sees `RASA_BUILD_ID`, `RASA_TEST_RUN`, `ENVIRONMENT=test`,
and for each e2e runtime `RUNTIME_<NAME>_HEALTH_URL`. Output lands in
`tests/runs/TST-…/` beside the record: `gate.log`, `e2e.log`, one
`runtime-<name>.log` per runtime.

Exit codes: `0` passed · `1` failed (record written) · `2` usage ·
`3` refused (no build of this source, an uncommitted change anywhere
in the repository, another test run in progress, artifacts changed
since the build — no record written). A run killed part-way leaves an
`aborted` record, which the deploy gate treats as not passed.

### Reading a failure

- **A test failed** → quote its output from the suite log; the fix is
  in the code or the test, then `/build` again (new commit) and
  `/test`.
- **`exited before it was healthy`** → the tail of
  `runtime-<name>.log` is printed; it is usually a missing env var or
  a wrong start command.
- **`not healthy after Ns`** → the app is up but the health check
  never matched: wrong port or path in `health_check.url`, or
  `timeout_seconds` too short for a cold start.
- **`dependency '<x>' is not available`** → a `depends_on` check
  failed (the database, the queue); start it, then re-run.
- **`health check already passes before it was started`** → something
  else is serving that port — an old run's server, a dev server. Stop
  it; the run refused to test it instead of the build.
- **`timed out after Ns`** → a test hung. Raise `timeout_seconds` on
  its stamp only if it is genuinely that slow.
- **`no commands.start`** → the stamp only has `commands.dev`. Add
  `start:` — the command that serves the **built** app (its
  production server command: a `docker run …` of the image, the
  compiled binary, `gunicorn app:app`, `java -jar …`). Point it at the dev
  server only as a deliberate choice, and say it tests source, not the
  build.

## `/test add` — put a test where it gates

Ask only what you cannot read from the code: what the test proves,
and when it must pass.

1. **Pick the kind and the suite.**

   | The test proves… | `test_kind` | Suite |
   |---|---|---|
   | one unit behaves | `unit` | `pre-deploy.md` |
   | parts work together, no running app | `integration` | `pre-deploy.md` |
   | the running, built system works across runtimes | `e2e` | `e2e.md` |
   | a deployed environment is up and serving | `smoke` | `smoke.md` |
   | today's behavior of untested code is pinned | `characterization` | `pre-deploy.md` — use `/pin-behavior` |

2. **Write the stamp** at `tests/stamps/YYYYMMDD_NNN_<name>.md`, in the
   one format the pipeline reads (`test-rules.md`):

   ```yaml
   ---
   name: checkout-e2e
   kind: test
   test_kind: e2e
   language: typescript
   location: e2e/checkout.spec.ts
   run_command: "npx playwright test e2e/checkout.spec.ts"
   runtimes_required: [api, web]
   timeout_seconds: 300          # optional; default 900
   created: 2026-09-26
   status: active
   ---
   ```

   `run_command` runs from the project root and must exit non-zero on
   failure. Run it once by hand before adding it to a suite.

3. **Add its `name` to the suite's `tests:` list.** For an e2e test,
   make sure every runtime it needs is in `e2e.md`'s `runtimes:` list
   and that each `.claude/runtimes/<name>.md` has `commands.start` and
   a `health_check`. Create `e2e.md` or `smoke.md` from the shape in
   `test-rules.md` if it does not exist yet.

4. **Log it.** Append a row to `tests/TESTS.md`: date, name, suite,
   why.

5. **Prove it gates.** `/build` then `/test` — the new test appears in
   the run's counts. A test that never ran in a suite is not a gate.

## Output structure

```markdown
## 🧪 Test run TST-… — build BLD-… (`<sha>`)

| Phase | Suite | Ran | Failed | Result |
|---|---|---|---|---|
| gate | pre-deploy | <n> | <n> | ✓ / ✗ |
| e2e | e2e (runtimes: api, web) | <n> | <n> | ✓ / ✗ / none |

**Verdict.** <passed — `/deploy` and `/release` will accept this
build | failed — <the first failure, quoted>>

**Next.** <`/deploy staging` | the fix>
```

When there is no `e2e.md`, say so under the table: nothing end to end
was run.

## What you must NOT do

- **Don't test without a build record**, and don't hand-write one.
- **Don't edit a suite to make a run pass** — no removing,
  quarantining or retiring a failing test without the user's
  explicit decision.
- **Don't leave a runtime running.** If one is, it is a bug to report.
- **Don't summarize away a failure.** Quote it.

## When NOT to use this skill

- **Write tests for a task, autonomously** → `/auto-test`.
- **Pin legacy behavior before changing it** → `/pin-behavior`.
- **Just compile** → `/build`.
- **Ship** → `/deploy` (dev / staging) or `/release` (prod).

## What "done" looks like for a /test session

A `TST-…` record for HEAD naming the build it tested, with real
counts per phase, every runtime it started stopped, and a verdict
the deploy gate will act on — or, for `/test add`, a stamp in
`tests/stamps/`, its name in the suite that should gate it, a
`TESTS.md` row, and a run that shows it counted.
