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
type: record
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

# <TASK-NNN>: <short title -- what is being written down>

> **Type `record`.** A fact, decision, agreement or account that is worth
> writing down and citing later. Documentation, a decision of record, a
> hand-off, an account of an incident after the fact, a summary somebody
> will need in a year.
>
> A record task is done when the record **exists and is findable**, not when
> somebody has read it.
>
> Leave `## Blocker` empty unless this task is in `blocked/`. When it is,
> that section must say three things: what is blocking it, who or what
> would unblock it, and when to check back.
>
> Before starting, read `.claude/task-rules.md` and `.claude/done-gate.md`.
> The done-gate, not this file, defines what *verified* means here.

## What is being recorded

One or two sentences. What this is, and who will come looking for it.

## Context

What was happening that makes this worth recording? Enough that the record
still makes sense to a reader who was not there, and who has forgotten
everything you currently find obvious.

## The record

The substance. For a decision, say what was decided, what the alternatives
were, and why this one -- a decision without its alternatives is an
assertion, and the next person will re-litigate it. For an account of
something that happened, say what happened, in order, and what was done
about it. For a hand-off, say what the next person needs and what they must
not assume.

## Consequences

What follows from this. What is now settled and should not be re-opened
without a new record; what is now expected of whom; what this closes off.

- **Settled:**
- **Now expected:**
- **Closed off:**

## Where it lives, and for how long

A record inside a task file is a record nobody will find in a year. Say
where the durable copy lives and how long it is meant to last.

- **Durable copy:** `<artifact or location>`
- **Retention:** <how long this must be kept, and under what authority, if
  your project has one>
- **Cited from:** <what points at it>

## Acceptance criteria

- [ ] The record exists at the durable location named above.
- [ ] Anybody who needs it can find it from `<the place they would look>`.
- [ ]
- [ ] The done-gate passes (`.claude/done-gate.md`), with the evidence
      recorded in `## Notes`.

## Blocker

## Notes
