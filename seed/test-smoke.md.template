---
name: <kebab-case-test-name>
kind: smoke
description: <one-sentence: minimal "does it boot?" check>

runtimes_required: []       # usually one — the thing being smoke-tested

verification:
  type: script
  script: "<path to smoke check script>"
  expected:
    exit_code: 0
    stdout_contains: "ok"
    timeout_seconds: 60

tags: [smoke, fast]
---

# <Name>

> Smoke test — minimal verification that the runtime boots and
> responds. Fast by design; not a substitute for proper testing.

## What this verifies

<One sentence: e.g. "API boots and the /health endpoint returns 200.">

## How it works

1. Required runtime starts.
2. Verification script does a single minimal check (health endpoint,
   process running, port responsive, etc.).
3. Pass = exit 0.

## Pre-conditions

- Runtime's required env vars set
- Runtime's dependencies (postgres, redis, etc.) reachable

## When to run

- Before every deploy
- In CI on every push
- After any config or dependency change
- When the system feels off and you want a fast "is anything obvious broken?"

## What this does NOT verify

- Correctness of any business logic
- Performance characteristics
- Cross-runtime integration (use `kind: e2e` for that)

---

*Last verified working: <YYYY-MM-DD>.*
