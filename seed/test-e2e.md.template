---
name: <kebab-case-test-name>
kind: e2e
description: <one-sentence: end-to-end scenario across multiple runtimes>

runtimes_required: []       # multiple — e.g. [api, web, worker]

verification:
  type: script
  script: "<path to e2e script>"
  expected:
    exit_code: 0
    timeout_seconds: 300    # e2e tests can be slow

# e2e tests often use a framework (Playwright, Cypress, Detox, etc.)
test_framework: "<playwright | cypress | detox | xcuitest | espresso | none>"

references:
  - file: "<verification script path>"
    purpose: "E2E reference — exactly how the system is exercised across runtimes"

tags: []                    # e.g. [smoke, regression, daily, slow]
---

# <Name>

> End-to-end test across multiple runtimes. The "is the system
> actually working together" check.

## What this verifies

<One paragraph: which surfaces are involved, what flow tests the
integration. E.g. "Web frontend submits a form → API processes →
worker enqueues → result appears in the web UI. Verifies the
full pipeline.">

## Runtimes coordinated

| Runtime | Role |
|---|---|
| `<name>` | <what role it plays in this test> |
| `<name>` | <role> |

(Each runtime's full config lives in `.claude/runtimes/<name>.md`.)

## How it works

1. All `runtimes_required` start in parallel (orchestrator waits for
   each to be healthy).
2. The verification script drives the test:
   - <Step description>
   - <Step description>
3. Assertions check state across runtimes.
4. Pass = all assertions hold; fail = any assertion fails.

## Pre-conditions

- All runtimes healthy
- Test data fixtures loaded (script may handle)
- ...

## Reset / cleanup

- <Database reset commands>
- <Cache flush commands>
- ...

## Failure modes seen historically

- Flakiness when <condition> — mitigation: <retry / delay / fix>
- ...

## References

- <link to test framework docs>
- <link to e2e test conventions doc, if any>

---

*Last verified working: <YYYY-MM-DD>.*
