# Test Rules

Conventions for testing in kit-bootstrapped projects. Tests are first-class — archived, audited, and tied to the deploy pipeline through suites.

The kit provides **structure** and **stamps**. Tests themselves live where their native test framework wants them (XCTest in Xcode, jest alongside source, pytest in `tests/`). The kit never moves your tests — it references them via stamps.

## Core principle

**Tasks need tests.** Every completed task should have at least one test stamp that proves it out. This is documented as a rule for now; enforcement (e.g. a `.claude/done-gate.md` gate refusing `/task`'s `pass` without a stamp) is opt-in later.

## Folder structure

```
tests/
├── TESTS.md                    # dated registry (like MIGRATIONS.md)
├── stamps/                     # one stamp per test
│   ├── 20260513_001_user-auth-flow.md
│   └── 20260514_001_api-health-check.md
├── suites/                     # named test groupings (gates for stages)
│   ├── pre-deploy.md           # the gate suite: ./build/test phase 1, 30-test.sh
│   ├── prod-gate.md            # replaces pre-deploy.md at prod class, if present
│   ├── e2e.md                  # ./build/test phase 2, with its runtimes: up
│   └── smoke.md                # 60-verify.sh, against the deployed environment
├── runs/                       # ./build/test records (TST-*.md) + logs — written, never hand-edited
├── scripts/                    # fallback: actual test scripts for projects
│   ├── api-health-check.sh    # without a native test framework
│   └── ...
└── container/                  # container-specific tests (if project ships images)
    ├── greenlight.sh           # composes validate + run-local + check-logs
    ├── validate-image.sh       # static checks (hadolint, trivy)
    ├── run-local.sh            # docker run + smoke endpoints
    └── check-logs.sh           # parse logs for expected/forbidden patterns

.claude/
└── test-rules.md               # this file (synced)
```

## Stamps

Two stamp models (see `stamps.md` for the universal pattern):

### Stamp: `test`

**Where it lives:** `tests/stamps/<YYYYMMDD>_<NNN>_<slug>.md`
**Purpose:** Identify a single test — what it proves, where it lives, how to run it.

```yaml
---
name: user-auth-flow
kind: test
test_kind: unit                       # unit / integration / e2e / smoke / regression / container / characterization
language: swift                       # swift / typescript / python / bash / ...
location: ios/MyAppTests/UserAuthFlowTests.swift
run_command: xcodebuild test -scheme MyApp -only-testing:MyAppTests/UserAuthFlowTests
task: T-042                           # task ID this test was born from
created: 2026-05-13
status: active                        # active / quarantined / retired
tags: [auth, critical]
---

# Test: user-auth-flow

What this test covers, why it matters, what failure mode it catches.

**Covers:**
- Successful sign-in with valid credentials
- Rejected sign-in with invalid credentials
- Token refresh after expiry

**Why it matters:**
Auth failures are user-facing and prod-impacting. Member of `pre-deploy` suite.
```

**Fields:**

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string (kebab-case) | Stable identity. Matches filename slug. |
| `kind` | yes | const `test` | Stamp discriminator. |
| `test_kind` | yes | enum | unit / integration / e2e / smoke / regression / container / characterization |
| `language` | yes | string | Test language (swift, typescript, python, bash, etc.) |
| `location` | yes | string | Path to test source (native location, NOT moved) |
| `run_command` | yes | string | Shell command that runs this specific test |
| `task` | no | string | Originating task ID (e.g. T-042) |
| `created` | yes | date (YYYY-MM-DD) | When the stamp was created |
| `status` | yes | enum | active / quarantined / retired |
| `tags` | no | array | Free-form classification |
| `runtimes_required` | e2e: yes | array | Runtime names (`.claude/runtimes/<name>.md`) the test needs running. Every one must be in `e2e.md`'s `runtimes:` list. |

### Stamp: `test-suite`

**Where it lives:** `tests/suites/<name>.md`
**Purpose:** Group related tests for use as a pipeline gate.

```yaml
---
name: pre-deploy
kind: test-suite
suite_kind: gate                       # gate / regression / smoke / nightly
runs_for: [dev, staging, prod]
tests:
  - user-auth-flow
  - api-health-check
  - container-greenlight
---

# Suite: pre-deploy

Tests that must pass before any deploy. Invoked by `build/stages/30-test.sh`.

**Membership criteria:** Anything that, if broken, would cause user-facing failure within the first 5 minutes of deploy.
```

**Fields:**

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string | Suite identity. Matches filename. |
| `kind` | yes | const `test-suite` | Stamp discriminator. |
| `suite_kind` | yes | enum | gate / regression / smoke / nightly |
| `runs_for` | yes | array | Which environments this suite gates |
| `tests` | yes | array | Names of test stamps (by `name`, not filename) |

The `tests:` array references test stamps by `name`. The pipeline resolves names by reading frontmatter of every file in `tests/stamps/`, finding the one whose `name` matches.

## Naming

Test stamps use date-sequence naming (same as migrations):

```
YYYYMMDD_NNN_slug.md
```

Examples:

```
20260513_001_user-auth-flow.md
20260513_002_api-health-check.md
20260514_001_container-greenlight.md
```

`NNN` resets per day. The date is when the stamp was created (i.e. when the test was first added to the registry), not when it was last modified.

Suite files use plain names: `pre-deploy.md`, `prod-gate.md`, `smoke.md`. There are few suites and they're long-lived — no date prefix needed.

## When to write a test stamp

- **Adding a new test:** create the stamp.
- **Moving a test:** update the `location` and `run_command` fields. Don't rename the stamp.
- **Retiring a test:** flip `status: active` → `status: retired`. Leave the stamp in place for audit. **Remove it from any suite first** — a retired stamp still listed in a selected gate suite FAILS that suite. Treating it as skippable would make `status: retired` a permanent silent bypass.
- **Quarantining a flaky test:** `status: quarantined`. Suites that include it skip-and-warn rather than fail. A quarantined member does **not** count as having run, so quarantining every member of a suite makes it an empty suite — which fails at prod class. Quarantine is not a way to un-gate production.
- **An unknown or missing `status:`** causes the test to RUN, with a warning. Skipping on an unrecognized value would let a typo disarm the gate.

Don't create a stamp for trivial tests (a single assertion that lives alongside obviously-correct code). Stamps are for tests you'd want to find by name later.

## Test suites and the deploy pipeline

`build/stages/30-test.sh` selects a suite based on environment **class**, not name:

- class `prod` → `tests/suites/prod-gate.md` if present, else `pre-deploy.md`
- everything else → `tests/suites/pre-deploy.md`

Selection is first-match-on-existence, by filename. This is why the Element ships **no** `prod-gate.md`: an empty one dropped beside a populated `pre-deploy.md` would win and remove production coverage.

The suite's `tests:` list is iterated. For each name the stage resolves the stamp whose `name:` matches **exactly**, extracts `run_command`, and runs it. Two stamps sharing a name is an error, not a coin toss.

### The exit rule

A gate that runs no tests is not a gate. One condition, applied by both `30-test.sh` and `build/gates/tests-required.sh`:

- any test **fails** → the suite fails, at every class
- **nothing ran** and the class is `prod` → the suite fails
- otherwise → pass

"Nothing ran" covers an empty list, a list whose members are all quarantined, a `tests:` key in a form the parser will not guess at, and members whose stamps are missing or ambiguous. Below `prod` class all of these warn and pass, so dev and staging work is unaffected.

`--skip-tests` is **refused** at `prod` class. To ship without running a test, remove it from the suite — an explicit, reviewable edit — rather than silencing the gate.

### Suite file format

Both YAML list forms are accepted, at any indent:

```yaml
tests:
  - api-health-check
```
```yaml
tests: [api-health-check, user-auth-flow]
```

A `tests:` key in any other form is a hard failure at prod class rather than a silent zero. Comment lines under the key are ignored.

`suite_kind` and `runs_for` are **advisory metadata and are not read at runtime.** Suite selection is by filename and class. Do not rely on `runs_for` to keep a suite out of an environment.

**Suite files are consumer-owned.** `tests/suites/pre-deploy.md` is seeded once on install and is never overwritten by an update — the membership list is your data, not the Element's.

To extend: add new suites and reference them from custom stages or per-env logic.

## The test phase — `./build/test` (`/test`)

The build → test → deploy chain (`pipeline-rules.md`) tests a **recorded
build**, not the tree. `./build/test` refuses unless `./build/build` built
HEAD and its artifacts still match their fingerprint, then runs, strict
(`TEST_STRICT=1` — a suite that runs nothing fails at every class):

1. **the gate suite** — `prod-gate.md` if present, else `pre-deploy.md`.
   None at all fails the run.
2. **`e2e.md`**, when it exists — with its runtimes running (below).
   An `e2e.md` that exists is never optional: listing no tests fails.

It writes `tests/runs/TST-<utc>.md` naming the build it tested. Staging
and production deploys require a passed one for HEAD
(`gates/verified-build.sh`, no bypass).

### End-to-end: `e2e.md` and its runtimes

```yaml
---
name: e2e
kind: test-suite
suite_kind: gate
runtimes: [api, web]                   # .claude/runtimes/<name>.md — started in this order
tests:
  - checkout-e2e
---
```

For each runtime, in order, `./build/test`:

1. starts `commands.start` from `.claude/runtimes/<name>.md` in its own
   process group, logging to `tests/runs/TST-…/runtime-<name>.log`;
2. polls `health_check` — `url` until it answers `expect_status`
   (default 200), or `command` until it exits 0 — for up to
   `timeout_seconds` (default 30). A runtime that exits first, or never
   gets healthy, fails the run;
3. after every runtime is healthy, runs the suite; then **stops every
   runtime and any test still running — on pass, fail, error, Ctrl-C or
   kill.**

`commands.start` must serve the **built** app — its production server
command (a `docker run …` of the image, the compiled binary, `gunicorn
app:app`, `java -jar …`) — not the dev server: the e2e phase tests
the build. A stamp with only `commands.dev` fails, naming the field.

Tests read `RUNTIME_<NAME>_HEALTH_URL` (name upper-cased, `-` → `_`),
`RASA_BUILD_ID` and `RASA_TEST_RUN` from the environment.

### After deploy: `smoke.md`

`build/stages/60-verify.sh` runs `smoke.md` against the environment just
deployed; smoke tests read `ENVIRONMENT`, `DEPLOY_TO` and `DEPLOY_TAG` to
find it. Required at prod class — the deploy is refused up front without
one — and a warning below.

## Container projects

Container projects get a special test pattern: **green-light** before deploy.

```
tests/container/
├── greenlight.sh        # composes the three below; exit 0 = green-lit
├── validate-image.sh    # static: hadolint Dockerfile, trivy scan, etc.
├── run-local.sh         # docker run -d, wait ready, hit health endpoint
└── check-logs.sh        # parse logs for expected startup, no errors
```

`greenlight.sh` is wired into `pre-deploy.md` as a regular test (with a stamp named `container-greenlight`). When the suite runs, the green-light scripts execute. Pass = deploy proceeds.

**Why this matters:** the image proves it can boot, log normally, and respond to health checks on the deploy runner before it ever touches an environment. Image-level bugs (missing entrypoint, broken runtime config, log format regression) get caught before any environment damage.

Customization points:
- `validate-image.sh` — add/remove static scanners (hadolint, trivy, snyk)
- `run-local.sh` — health endpoint path, ready timeout, port mapping
- `check-logs.sh` — expected startup patterns, forbidden error strings

## Fallback: `tests/scripts/`

Some projects don't have a native test framework — pure container services, infrastructure repos, etc. For these, write bash/python test scripts in `tests/scripts/` and stamp them like any other test:

```yaml
---
name: api-health-check
kind: test
test_kind: integration
language: bash
location: tests/scripts/api-health-check.sh
run_command: tests/scripts/api-health-check.sh
created: 2026-05-13
status: active
---
```

This is the lowest-friction way to make a project testable without forcing a framework decision.

## Brownfield: pinning behavior you did not specify

The default rule is **test against the spec, not the code** — assert the
*intended* behavior, because a test written to pass whatever the code currently
does proves nothing about whether the code is right. That rule is correct for
feature work and it stays the default.

It does not fit a repo you inherited. A ten-year-old service with no tests and
no surviving author has no spec to test against, and an agent is about to change
it. The only honest assertion available is *what it does today*. Refusing to
write that leaves the code permanently ungated — and at prod class the deploy
gate now refuses an empty suite, so "no tests" is no longer a state you can
deploy from.

So: **a characterization test is legitimate, and it is a different thing from an
intent test.** It records observed behavior as a baseline so a later change that
alters that behavior is visible. It makes no claim that the behavior is correct.

```yaml
---
name: checkout-totals-baseline
kind: test
test_kind: characterization           # <- not unit/integration: the distinction is the point
language: bash
location: tests/scripts/checkout-totals-baseline.sh
run_command: tests/scripts/checkout-totals-baseline.sh
created: 2026-09-21
status: active
tags: [brownfield, baseline]
---
```

`test_kind: characterization` is **required** on these, and is why the enum
gained a value rather than letting them hide as `regression`. A reader — human
or agent — must be able to tell which of your tests encode intent and which
merely encode history. Without the label, the two become indistinguishable
within a release or two, and then nobody can tell whether a red test means
"this broke" or "this changed, which may be fine".

**The boundaries:**

- **Never write one where a spec exists.** If the task spec has a test plan,
  implement it. Characterization is for behavior nobody wrote down.
- **A characterization test failing is not automatically a bug.** It means
  behavior changed. Decide, grounded, whether the change was intended — and if
  it was, update the baseline in the same commit and say so.
- **They are a floor, not a ceiling.** Pinning current behavior is what makes a
  legacy surface safe to touch. It is not a substitute for testing intent once
  intent is known.
- **Do not pin a bug.** If the observed behavior is plainly wrong, that is a
  finding, not a baseline. Record it and surface it rather than freezing it.

`/pin-behavior` writes these. See also "Fallback: `tests/scripts/`" above — a
brownfield repo usually needs both: a place to put a test, and permission to
write the only kind it can honestly have.

## The `TESTS.md` registry

Append-only log, similar to `MIGRATIONS.md`. Records when test stamps were created, what status changes happened, and surface-level audit info.

The Element ships an empty template; the project (or `/setup-deploy`, or `/test add`) appends rows.

## Reading tests programmatically

Stamps are parseable — through the Element's one frontmatter reader,
`.claude/lib/domain-code/frontmatter.sh`, never a hand-written awk:

```sh
# Find all active integration tests
. .claude/lib/domain-code/frontmatter.sh
for f in tests/stamps/*.md; do
  status="$(rfm_get_scalar "$f" status 2>/dev/null || true)"
  kind="$(rfm_get_scalar "$f" test_kind 2>/dev/null || true)"
  [[ "$status" == "active" && "$kind" == "integration" ]] && echo "$f"
done
```

The pipeline's `30-test.sh` reads stamps the same way (`suite-lib.sh`'s
`stamp_field`). The awk this section used to show — `/^---$/{f++; next}` —
matched exact fences anywhere in the file: a stamp with a BOM, CRLF line
endings or a blank after a fence read as empty, and a `---` rule in the body
opened a second "frontmatter". Python readers use the library's twin,
`frontmatter.py` (`split`, `get`, `scalar`, `child`, `title`).

---

**See also:** `pipeline-rules.md` for how suites gate deploys. `stamps.md` for the universal stamp model conventions.
