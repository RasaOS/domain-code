---
name: <kebab-case-test-name>
kind: endpoint-test
description: <one-sentence: what this verifies about a single API endpoint>

runtimes_required: []       # e.g. [api] — refers to .claude/runtimes/<name>.md
  # The orchestrating skill starts these before running the verification.

verification:
  type: script
  script: "<path to script, e.g. tests/scripts/chat-happy-path.sh>"
  expected:
    exit_code: 0
    stdout_contains: ""     # optional substring expected in stdout
    stderr_empty: false
    timeout_seconds: 30

# A test's script is also a reference implementation. Other clients
# wanting to call the same endpoint can copy this shape.
references:
  - file: "<path to verification script>"
    purpose: "Reference implementation — how to call this endpoint from a shell client"

tags: []                    # e.g. [chat, smoke, api-contract, fast]
---

# <Name>

> Endpoint test. Stamp at the top is the machine-readable identity;
> the body is context for humans and AI.

## What this verifies

<One paragraph: which endpoint, what request, what response shape.
E.g. "POST /chat with a user message returns 200 with a JSON body
containing a non-empty `response` field, within 30s.">

## How it works

1. Required runtimes start (per `.claude/runtimes/<name>.md` files
   in `runtimes_required`).
2. Wait for health: each runtime's `health_check` URL returns 200.
3. Run the verification script: `<script path>`.
4. Check expected outcome (exit code, stdout, timeout).

## Reference implementation

The verification script doubles as documentation for clients wanting
to call this endpoint:

```sh
<command from the script, or excerpt of the core request>
```

Mirror this shape in iOS / web / other clients.

## Pre-conditions

- Required env vars set (see each runtime's `env.required`)
- ...

## Expected outcome

- HTTP status: `<code>`
- Body shape: `<JSON schema or example>`
- Response time: `<seconds>`

## Failure modes seen historically

- ...

## References

- <link to endpoint docs>
- <link to related tests>

---

*Last verified working: <YYYY-MM-DD>.*
