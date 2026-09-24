---
# -- TEMPLATE ---------------------------------------------------------
# Replace every <...> placeholder before this file goes into a stage
# directory.
#
# HOW THIS BLOCK IS PARSED. A comment is a line that BEGINS with '#'. A
# value is the whole rest of its line, so a '#' written after a value is
# part of that value, not a comment -- and so is any explanation. Every
# note below therefore sits on its own line, and every field line is bare:
# uncomment one and you get a legal line, with nothing to trim off the end.
#
# -- Required, always (5) ---------------------------------------------
# The allocator stamps id / created / created_by / updated. You choose
# the type and the title.
id: <TASK-NNN>
type: inquiry
created: <YYYY-MM-DD>
created_by: <handle>
updated: <YYYY-MM-DD>
#
# -- Required by state: uncomment when that state arrives --------------
# `phase` -- required in backlog/ active/ review/ blocked/ completed/,
# forbidden in triage/, and optional in closed/ (carry it only if the task
# ever had one). The value must equal a phase id declared in
# tasks/ROADMAP.md.
# phase: <phase-id>
#
# `target` -- required if and only if tasks/tasks.config.yml declares a
# non-empty 'targets' list; forbidden otherwise. Always a list. A task
# closed straight out of triage/ never acquired one and carries none.
# target: [<declared-target>]
#
# The three below are written by the command that performs the move, not
# by hand. They are here so you recognise them, not so you add them.
#
# `completed_by` -- an actor handle. completed/ and closed/ only.
# completed_by: <handle>
#
# `resolution` -- closed/ only. One of the four words
# superseded | duplicate | obsolete | wont-do.
# resolution: obsolete
#
# `resolution_ref` -- closed/ only, and only when the resolution is
# superseded or duplicate. The id of the task that replaced this one.
# resolution_ref: <TASK-NNN>
#
# -- Optional ----------------------------------------------------------
# `priority` -- one of now | high | normal | low. Omit it for normal.
# 'now' is a route, not a mood: it files straight into active/.
# priority: normal
#
# `needs` -- ids that must reach completed/ before this one can.
# needs: [<TASK-NNN>]
#
# `x-<anything>` -- project-owned. Preserved verbatim, never interpreted.
# x-<your-key>: <your value>
---

# <TASK-NNN>: <short title -- phrase it as the question>

> **Type `inquiry`.** A question to answer. What this task produces is an
> **answer**, not an alteration. Reviews, investigations, comparisons,
> feasibility questions and "find out whether" all live here.
>
> An inquiry that turns out to need work done does not become that work: it
> finishes with its answer, and the work it recommends is filed as its own
> task or tasks. That is the discipline that stops an inquiry from quietly
> turning into an unbounded project.
>
> Leave `## Blocker` empty unless this task is in `blocked/`. When it is,
> that section must say three things: what is blocking it, who or what
> would unblock it, and when to check back.
>
> Before starting, read `.claude/task-rules.md` and `.claude/done-gate.md`.
> The done-gate, not this file, defines what *verified* means here.

## Question

State it as one answerable question. If you cannot phrase it as a question,
this is probably a `change` in disguise.

>

## Why it matters

What decision waits on the answer, and who is waiting? An inquiry whose
answer changes nothing is an inquiry worth closing instead of running.

## Time box

Investigations expand to fill whatever room they are given, so give this one
a limit up front and honour it.

- **Limit:** <a duration, or a date>
- **If the limit is reached without an answer:** report what is known, what
  is still open, and what it would take to close the gap. That is a complete
  outcome, not a failure -- record it and close the task.

## Method

How the question will be answered, and against what. Sources, comparisons,
who will be asked, what will be examined.

1.
2.

## Deliverable

Where the answer goes when it exists. If the answer belongs somewhere more
durable than this task -- a decision of record, a written finding, a note in
a reference document -- name that destination here, and file a `record` task
for it if it needs to outlive this ledger.

- **The answer will be written in:** <`## Findings` below / `<destination>`>

## Acceptance criteria

- [ ] The question above is answered in `## Findings`, or the answer is
      stated to be unreachable within the time box, with what is missing.
- [ ] Every follow-on the answer implies is filed as its own task, listed in
      `## Findings`.
- [ ] The done-gate passes (`.claude/done-gate.md`), with the evidence
      recorded in `## Notes`.

## Findings

The answer. Written here as the work proceeds, not reconstructed at the end.
Separate what you established from what you inferred, and say which is
which.

**Answer:**

**Established:**

-

**Inferred, with the reasoning:**

-

**Still open:**

-

**Follow-on tasks filed:**

- `<TASK-NNN>` -- <what it covers>

## Blocker

## Notes
