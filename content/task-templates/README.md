# Task templates

Seven files ship here. Six are task templates; this one explains how the
set is put together and which file to start from.

## The set

| File | When to start from it |
|---|---|
| `stub.md` | You want the work tracked and counted, not specified yet. |
| `change.md` | Something should exist, or should work differently, than it does now. |
| `defect.md` | Something is wrong and should be put right. |
| `upkeep.md` | Maintenance. The observable result must not change. |
| `inquiry.md` | A question to answer. What gets produced is an answer, not a change. |
| `record.md` | A fact, decision or agreement worth writing down and citing later. |

Five of those names are the five legal values of `type:`. There is no
sixth type: `stub.md` is not a type, it is a **depth** — a short file that
still carries one of the five types in its frontmatter.

## Type and depth are two different axes

`type:` says *what kind of work this is*. It is a frontmatter field, it is
required on every task, and it never changes meaning as the task moves.

**Depth** says *how fully the task is specified*. It is not a field and
never was in v1.0.0 — it is derived from the file itself:

> A task is **stub depth** if it has no `## Acceptance criteria` heading,
> or that heading holds no `- [ ]` / `- [x]` item with real text after the
> checkbox. Otherwise it is **spec depth**.

This is why there is no marker string to write and no depth field to keep
in step with anything. Add a real acceptance-criteria checkbox and the task
*is* spec depth; delete them all and it *is* stub depth. Nothing can
disagree with anything else, because there is only one copy of the fact.

Every type can be at either depth. An urgent `record` is expressible; so is
a fully specified `upkeep` and a one-line `change`. Pick the type from the
table, then pick the depth from how much you actually know.

## The placeholder convention

Every template ships **grammar-valid frontmatter**: line 1 is `---`, every
other line in the block is either a whole-line comment or `key: value`. You
can copy any of these files into a stage directory and the validator will
read it — and then tell you precisely which placeholders you left unfilled,
rather than refusing to parse the file at all.

Two rules make that work, and both are easy to break by accident:

1. **A value you must supply is written `<like-this>`.** Angle brackets
   never appear in a real value, so an unfilled field is unmistakable both
   to a reader and to the validator.
2. **Comments are whole-line only.** A `#` that follows a value is *part of
   the value*, not a comment — the frontmatter grammar has no trailing
   comments. Every explanation in these templates therefore sits on its own
   line, above the field it explains. If you add a note of your own, put it
   on its own line too.

Conditional fields (`phase`, `target`, `completed_by`, `resolution`,
`resolution_ref`, `priority`, `needs`) ship **commented out**, because most
of them are forbidden in the state a new task starts in. Uncomment one when
the state it belongs to arrives.

## `## Blocker` ships empty, deliberately

Every template carries a `## Blocker` heading with nothing under it.

A task in `blocked/` must have that section filled with three things: what
is blocking it, who or what would unblock it, and when to check back. The
validator proves the section is non-empty for anything in `blocked/`, so
shipping prompt text under the heading would satisfy the check without
anyone having said anything. Empty is the honest default: park a task
without stating the blocker and the ledger says so out loud.

Everywhere except `blocked/`, leave the section empty and ignore it.

## What a template does not decide

None of these files says what *verified* means. That is the one thing that
varies by project, and it lives in the project-owned `.claude/done-gate.md`.
The templates point at it; they never duplicate it. If a template ever
starts telling you which command to run, it has stopped being portable and
the file is wrong.
