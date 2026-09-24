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
type: change
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

# <TASK-NNN>: <short title -- the outcome, not the method>

> **Type `change`.** Something should exist, or should work differently,
> than it does today. This is the ordinary type: most work is a change.
>
> Leave `## Blocker` empty unless this task is in `blocked/`. When it is,
> that section must say three things: what is blocking it, who or what
> would unblock it, and when to check back.
>
> Before starting, read `.claude/task-rules.md` and `.claude/done-gate.md`.
> The done-gate, not this file, defines what *verified* means here.

## Intent

As a **<who>**, I want **<what>** so that **<why>**.

One or two sentences on what is missing or wrong today without this, and
what it unblocks. If an authority governs this work -- a standard, a policy,
a house convention -- name it here.

## Scope

**In scope**

-

**Out of scope, deliberately**

-

If you find yourself doing something that is not on the in-scope list, that
is a different task. File it rather than widening this one.

## References

Point at the nearest prior art and the authority this work answers to. Use
whatever your project actually produces -- a clause set, a care pathway, a
chapter, a module -- not a fixed shape.

- Nearest existing thing to follow: `<artifact or precedent>`
- Authority being conformed to: `<document or standard>`
- Related task: `<TASK-NNN>`

## Artifacts expected to change

Every artifact you expect to create or alter. If part-way through you find
you must touch something that is not listed, add it here with a one-line
reason *before* you touch it.

-
- (new) `<artifact this task creates>`

## Approach

Ordered steps -- enough that somebody else could pick this up cold without
re-deriving the plan.

1.
2.
3.

## Acceptance criteria

Each item objectively checkable: by a gate, an inspection, or a named
observation. Not by a feeling. At least one real checkbox here is what makes
this a spec-depth task; with none, it is a stub.

- [ ]
- [ ]
- [ ] The done-gate passes (`.claude/done-gate.md`), with the evidence
      recorded in `## Notes`.

## Verification

Write this *before* doing the work, so it is a contract rather than a
description of whatever happened. For each acceptance criterion, say what
will show it true. Do not name a mechanism here -- the mechanism lives in
the done-gate; this section maps this task's criteria onto it.

1. **Starting state:** <what must be in place before you can check anything>
2. **Checks:** <criterion -> what proves it>
3. **Evidence:** <what you will keep: output, an approver's name, a produced
   document -- and where it goes>

## Risks and open questions

- **Risk:** <what could go wrong, and what you would do about it>
- **Open question:** <what you do not yet know, and who can answer it>

## Blocker

## Notes
