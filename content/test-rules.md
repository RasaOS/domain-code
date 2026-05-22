# Test Rules

Conventions for testing in kit-bootstrapped projects. Tests are first-class — archived, audited, and tied to the deploy pipeline through suites.

The kit provides **structure** and **stamps**. Tests themselves live where their native test framework wants them (XCTest in Xcode, jest alongside source, pytest in `tests/`). The kit never moves your tests — it references them via stamps.

## Core principle

**Tasks need tests.** Every completed task should have at least one test stamp that proves it out. This is documented as a rule for now; enforcement (e.g. `/task done` refusing without a stamp) is opt-in later.

## Folder structure

```
tests/
├── TESTS.md                    # dated registry (like MIGRATIONS.md)
├── stamps/                     # one stamp per test
│   ├── 20260513_001_user-auth-flow.md
│   └── 20260514_001_api-health-check.md
├── suites/                     # named test groupings (gates for stages)
│   ├── pre-deploy.md
│   ├── prod-gate.md
│   └── smoke.md
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
test_kind: unit                       # unit / integration / smoke / regression / container
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
| `test_kind` | yes | enum | unit / integration / smoke / regression / container |
| `language` | yes | string | Test language (swift, typescript, python, bash, etc.) |
| `location` | yes | string | Path to test source (native location, NOT moved) |
| `run_command` | yes | string | Shell command that runs this specific test |
| `task` | no | string | Originating task ID (e.g. T-042) |
| `created` | yes | date (YYYY-MM-DD) | When the stamp was created |
| `status` | yes | enum | active / quarantined / retired |
| `tags` | no | array | Free-form classification |

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
- **Retiring a test:** flip `status: active` → `status: retired`. Leave the stamp in place for audit.
- **Quarantining a flaky test:** `status: quarantined`. Suites that include it skip-and-warn rather than fail.

Don't create a stamp for trivial tests (a single assertion that lives alongside obviously-correct code). Stamps are for tests you'd want to find by name later.

## Test suites and the deploy pipeline

`build/stages/30-test.sh` selects a suite based on environment:

- `prod` deploy → uses `tests/suites/prod-gate.md` if present, else `pre-deploy.md`
- everything else → `tests/suites/pre-deploy.md`

The suite's `tests:` array is iterated. For each name, the stage finds the matching stamp in `tests/stamps/`, extracts `run_command`, and runs it. Any failure aborts the deploy.

To extend: add new suites and reference them from custom stages or per-env logic.

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

## The `TESTS.md` registry

Append-only log, similar to `MIGRATIONS.md`. Records when test stamps were created, what status changes happened, and surface-level audit info.

The kit ships an empty template; the project (or `/setup-deploy`, or a future `/test add` skill) appends rows.

## Reading tests programmatically

Stamps are parseable:

```sh
# Find all active integration tests
for f in tests/stamps/*.md; do
  status=$(awk '/^---$/{f++; next} f==1 && /^status:/{sub(/^status:[[:space:]]*/, ""); print; exit}' "$f")
  kind=$(awk '/^---$/{f++; next} f==1 && /^test_kind:/{sub(/^test_kind:[[:space:]]*/, ""); print; exit}' "$f")
  [[ "$status" == "active" && "$kind" == "integration" ]] && echo "$f"
done
```

The pipeline's `30-test.sh` uses the same parsing pattern.

---

**See also:** `pipeline-rules.md` for how suites gate deploys. `stamps.md` for the universal stamp model conventions.
