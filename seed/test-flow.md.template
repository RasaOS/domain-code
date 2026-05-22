---
name: <kebab-case-test-name>
kind: flow
description: <one-sentence: what user flow / multi-step scenario this verifies>

runtimes_required: []       # one or more — e.g. [api, web]

verification:
  type: script
  script: "<path to script that walks the flow>"
  expected:
    exit_code: 0
    timeout_seconds: 120    # flows take longer than single-endpoint tests

references:
  - file: "<verification script path>"
    purpose: "Reference flow — sequence of steps a client follows for this scenario"

tags: []                    # e.g. [auth, signup-flow, integration]
---

# <Name>

> Multi-step flow test. Walks a user scenario from start to finish,
> verifying each step.

## What this verifies

<One paragraph: which flow, from what starting state to what ending
state. E.g. "New user signup flow: registers → verifies email →
completes profile → lands on dashboard. Verifies the full sequence
works and intermediate state is correct.">

## Steps walked

1. <Step 1 — e.g. POST /auth/register with new email + password>
2. <Step 2 — e.g. POST /auth/verify with token from email>
3. <Step 3 — e.g. PATCH /users/me with profile fields>
4. <Step 4 — e.g. GET /dashboard returns 200>

## How it works

1. Required runtimes start.
2. Verification script walks each step in sequence, asserting
   intermediate state.
3. Pass if all steps succeed and final state matches.

## Pre-conditions

- All required runtimes healthy
- Test database in a clean state (script may handle reset)
- ...

## Failure modes seen historically

- Step <N> can fail intermittently if <reason>
- ...

## References

- <link to flow docs / mockups>

---

*Last verified working: <YYYY-MM-DD>.*
