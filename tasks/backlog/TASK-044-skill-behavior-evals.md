---
id: TASK-044
category: stub
phase: P7
status: backlog
---

# TASK-044: Behavior evals for shipped skills

**User story.** As a **maintainer**, I want **a test that proves a skill still does what it claims** so that **a skill regression is caught before it ships to every repo**.

**Why.** `bin/check-invocations` verifies shipped commands can be *invoked* — it was written after twelve shipped call sites became unrunnable — and `bin/lint` is markdown. Neither evaluates behavior, and a `find` for test files outside the consumer-facing templates returns nothing.

**Notes.** The prose IS the product. It is the only part of this Element with no gate on it.

STATUS: STUB — full spec drafted before implementation.
