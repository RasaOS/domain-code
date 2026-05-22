---
name: user-story
description: Take a short description and return a fully fleshed out spec-task user story in chat — As-a/I-want/So-that, scope, acceptance criteria, references. Raw text only. No file is written, nothing lands in the backlog, no task ID is assigned. Triggered when the user wants a one-shot user-story draft to think with or paste elsewhere — e.g. "/user-story", "draft a user story for X", "fleshed-out story for this idea", "I have a rough idea, give me the structured version".
---

# /user-story — draft a spec-task user story

One-shot. Input: a rough description ("users should be able to
filter the inbox", "we need offline mode for the iOS app"). Output:
a fully-formed user story, structured like a task spec's user-story
header, rendered in chat. **No file is written. Nothing is added
to the backlog. No `TASK-NNN` is assigned.**

This is a thinking tool, not a tracking tool. Use it to converge
on phrasing, sanity-check scope, or hand the resulting block to
`/task` (or `/auto-task`) when you decide to actually file it.

Per CLAUDE.md ethos: blunt, calibrated, no narratives. The story
states what the user wants and what counts as "done" — nothing
more. Acceptance criteria are verifiable, not aspirational.

## Behavior contract

- **Chat-only output.** The skill produces text in the assistant
  message. It does not call Write, Edit, Bash, or any side-effect
  tool. If the user wants to file the story as a task, they invoke
  `/task` (or `/auto-task`) afterward.
- **One story per invocation.** If the input describes multiple
  distinct stories, render the most central one and note the
  others in a "Related stories" tail — don't dump five blocks at
  once.
- **Spec-task shape.** Use the shape from `task-template.md`'s
  "User story" + "Scope" + "Acceptance criteria" sections,
  trimmed. Skip the file-list, execution-order, and test-plan
  sections — those belong to a filed task, not a story.
- **Fleshed out, not invented.** Fill the As-a/I-want/So-that
  with what the user described, plus reasonable inferences
  grounded in the project (read `CLAUDE.md` if available). Where
  the user's input didn't say, mark it `⚠️ <assumption>` so they
  see the gap. Same discipline as `/instruct` and the autonomous
  skills.
- **Acceptance criteria are verifiable.** Each item must be
  checkable by either an E2E test, a build/lint command, or a
  one-line manual verification. "Works well" is not a criterion.
- **No persona inflation.** If the input doesn't name a role, use
  the most concrete one the project supports (read `CLAUDE.md`
  for users/personas) and flag it. Do not invent a "power user"
  persona that doesn't exist in the product.

## Process

1. **Read `CLAUDE.md`** if present — pick up the project's
   personas, vocabulary, and any relevant context. If absent,
   work from the user's input alone.
2. **Parse the user's description.** Extract: the role (who),
   the capability (what), the outcome (why). Anything missing →
   flag as an assumption.
3. **Render the story** in the format below, in one chat message.
   No file writes. No tool calls beyond reads for context.

## Output format

Render exactly this shape, replacing the bracketed parts:

```markdown
## User story

As a **<role>**, I want **<capability>** so that **<outcome>**.

## Why this matters

<One or two sentences. What breaks today without this? What
context from CLAUDE.md applies?>

## Scope

**In scope:**
- <bullet>
- <bullet>

**Out of scope (explicit):**
- <bullet>
- <bullet>

## Acceptance criteria

- [ ] <verifiable item — E2E test / build command / one-line check>
- [ ] <verifiable item>
- [ ] <verifiable item>

## Assumptions

- ⚠️ <decision made without explicit user input> — <reasoning>
- ⚠️ <decision> — <reasoning>

*(If none: "No assumptions — every detail came from the input.")*

## Related stories *(if any)*

- <one-line for each adjacent story the input implied>
```

If a section has nothing real to say (e.g. no out-of-scope
items), say so plainly: `- *(none)*`. Don't pad.

## When NOT to use this skill

- **You want to actually file the task** → use `/task` (or
  `/auto-task` for the autonomous variant). `/user-story` is
  upstream of those — it converges the phrasing, not the
  artifact.
- **You want a roadmap or phase plan** → `/plan` or `/roadmap`.
  A user story is one unit; a plan is many.
- **You want to brainstorm an idea space** → `/brainstorm`. A
  user story names one specific capability; brainstorming
  explores a problem space.

## What "done" looks like

A single chat message carrying the user story in the format
above. Nothing on disk. Nothing in the backlog. The user reads,
edits in their head or in the next prompt, and either invokes
`/task` to file it or moves on.
