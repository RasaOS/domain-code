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
type: defect
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

# <TASK-NNN>: <short title -- what is wrong, not what will fix it>

> **Type `defect`.** Something is wrong and should be put right. Use this
> when the work already exists and does not do what it is supposed to do.
> Urgency is not a type: an urgent defect is `priority: now`, which routes
> it straight into `active/`.
>
> Leave `## Blocker` empty unless this task is in `blocked/`. When it is,
> that section must say three things: what is blocking it, who or what
> would unblock it, and when to check back.
>
> Before starting, read `.claude/task-rules.md` and `.claude/done-gate.md`.
> The done-gate, not this file, defines what *verified* means here.
>
> **Evidence handling.** Quote only as far as your project's own handling
> rules allow. Where your project classifies material as confidential,
> privileged, sealed, or personal, reference it by identifier and redact the
> quotation -- and say in `.claude/done-gate.md` what that costs you at
> verification time. A task file is an ordinary readable document; treat it
> as one.

## Intent

As a **<who>**, I want **<the thing that is broken>** to work as intended so
that **<why it matters>**.

What is happening today, to whom, and how often -- everyone, a subset, an
edge case?

## Steps to reproduce

Numbered, specific, and re-runnable by somebody who has never seen this go
wrong. The point is that a second person can stand the failure back up on
demand -- that is what makes the fix checkable.

1.
2.
3.

**Conditions:** <the state this needs -- the inputs, the matter or document
in hand, who the actor is, which version of the work>

## Expected result

What *should* happen at the end of those steps.

## Observed result

What *does* happen. Quote it exactly, within the evidence-handling limits
above. Cite where the evidence lives rather than pasting it when the
material is sensitive.

## Cause, so far as it is known without fixing it

What you know or suspect about why this happens. Partial is fine. A guess
labelled as a guess is fine. A guess presented as fact is not. If you do not
know, write `Not yet known.` and say so plainly.

## Scope

**In scope**

-

**Out of scope, deliberately**

- <adjacent things that are also wrong, and should be their own tasks>

Do not put adjacent problems right "while you are in there". File them.

## Artifacts expected to change

-

## Acceptance criteria

The first criterion is always that the reproduction no longer reproduces.

- [ ] Following "Steps to reproduce" now produces the expected result.
- [ ] The reproduction is captured somewhere it can be re-run later, and
      cited here: `<where>`
- [ ]
- [ ] The done-gate passes (`.claude/done-gate.md`), with the evidence
      recorded in `## Notes`.

## Verification

1. Reproduce the failure against the unfixed state, and confirm it fails for
   the documented reason rather than an adjacent one.
2. Apply the fix.
3. Re-run the reproduction: it must now come out as expected.
4. Check the nearest neighbours of what you touched for new damage.
5. Run the done-gate.

## Recurrence guard

The reproduction, kept so this cannot come back unnoticed. It must fail
against the unfixed state and succeed against the fixed one. *How* it is
mechanised is your project's call and belongs in `.claude/done-gate.md` -- a
check that exits zero, a continuity pass against the bible, an authority
check, a rule validation.

1. **Setting up:** <the state the guard needs>
2. **Doing:** <the smallest reproduction>
3. **Reading:** <what tells you the result is right>

## Blast radius and reversal

What else does the fix touch? If the fix turns out to be wrong after it
lands, what has to be undone, and how is the prior state restored? Name the
dependents so a reviewer can judge the risk.

## Blocker

## Notes
