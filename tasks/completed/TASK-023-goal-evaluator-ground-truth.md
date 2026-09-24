---
id: TASK-023
type: defect
created: 2026-09-21
created_by: chazzcoin
updated: 2026-09-21
phase: P3
completed_by: chazzcoin
x-origin: manual
x-outcome: shipped
x-owner: unassigned
---
# TASK-023: the only independent grader reads narration, not evidence

**User story.** As an **operator running work under `/goal`**, I want **the
transcript the evaluator reads to contain proof rather than prose** so that
**a loop cannot terminate on a claim nobody checked**.

## The stub is not implementable as written

It said: "give the `/goal` evaluator tools and file access." **`/goal` is a
Claude Code harness command, not an Element skill** — it ships no SKILL.md and
`bin/check-invocations` lists it as a dangling reference for exactly that
reason. An Element cannot change how a harness evaluator works.

`autonomy-rules.md` states the limit accurately:

> The evaluator only reads the transcript. It runs no tools and reads no files
> — it judges what Claude has surfaced in the conversation.

So the lever is not the evaluator. It is **what the transcript contains.**

## The actual gap

The Element already tells the *operator* the right thing: "write conditions
Claude's own output demonstrates — a build exit code, a test summary, a file
count that actually appears in the transcript."

Nothing told the *skill* to put those there.

`/auto-test` promised "the report carries real pass/fail counts" — and **the
autonomy report template had nowhere to put them.** Its only slots were
`Outcome` and `Deliverable`, both prose. So an agent satisfies the instruction
by writing "all tests pass", and the evaluator — which cannot open the repo —
has no way to tell that from a genuine green run.

Both halves of the contract were present except the one that closes it.

## What changed

- The autonomy report template gains an **Evidence** section: verbatim command,
  exit code, and enough real output to read the result. With an explicit form
  for a run that made no verifiable claim, so the section cannot be quietly
  skipped by pretending there was nothing to show.
- The `/goal` advice now carries the skill's half beside the operator's, and
  says plainly why this is the only available lever: the evaluator cannot be
  given tools from inside an Element; what can change is whether what it reads
  is proof or prose.
- Evidence belongs in the run record too — the transcript is gone when the
  session ends, `tasks/runs/<RUN-id>.md` is not.
- `/auto-test` and `/auto-develop` now say *show it, don't summarize it*, and
  name the Evidence section.

## Honest limit

This does not make the evaluator independent. It makes the thing it reads
falsifiable. A model can still write a plausible fake transcript, and nothing
here prevents that — the Element's threat model is honest-mistake, not
adversarial. What it removes is the far commoner failure: a true-sounding
summary of work that was never actually run.

## Acceptance criteria

- [x] The report template has an Evidence section with a no-claim form
- [x] The `/goal` section states the skill's obligation, not only the operator's
- [x] It says plainly that `/goal` is a harness command and not ours to change
- [x] `/auto-test` and `/auto-develop` point at Evidence
- [x] All four gates green
