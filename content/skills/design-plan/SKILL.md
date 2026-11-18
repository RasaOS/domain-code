---
name: design-plan
description: Plan the UI of a request before it is built: per screen and per size class (compact, medium, expanded), the layout, how the person arrives and where back goes, the five states, feedback per action, accessibility, visuals, and which tokens and components are reused. Fills the UI/UX section of a request plan, or writes a standalone `**Kind.** design` plan from a design audit. Never writes code. Triggered by "/design-plan", "plan the screens for this", "design the mobile and tablet layout".
---

# /design-plan — decide the screens before they are built

Reads an audit and writes a plan. It never edits product code. The rules
are `ui-rules.md`; the flow is `flow-rules.md`.

## The script

`bash <skill-dir>/design-plan.sh` (`.claude/skills/design-plan/` in an
install). Always invoke with `bash`.

```text
design-plan.sh scaffold <slug> --audit <path>   a design plan (Kind design)
design-plan.sh scaffold --in <request-plan>     only the UI/UX block
design-plan.sh validate <file>                  exit 0 compliant, 3 not
```

The audit named by `--audit` (and by the plan's `**Audit.**` line) must
exist and validate: `design-audit.sh validate` for a design audit,
`audit.sh validate` for a request audit.

## One source per subject

The UI/UX block is the single fragment `plan/ui-section.md`, which
`/plan` renders into a request plan and `/develop` pastes into a task
body. When a request plan exists, fill its **UI/UX and screens**
section (`scaffold --in <file>`) and `validate` it; write a standalone
design plan only when there is no request plan. At most one plan
document per request.

## Process

1. Read the audit: the screens, the Design source, the findings.
2. Scaffold. Copy the `### Screen:` block once per screen.
3. Per screen: address and **back target**; layout at compact, medium
   and expanded (regions, order, what collapses or stacks); the five
   states; feedback for each action; accessibility; each data block as
   a chart, colour code, tile or table with the reason and the legend.
4. Tokens and components reused: names from `design-audit.sh discover`
   only. A new one carries a reason.
5. Data fields: the contract stamp. A locked contract stops the work.
6. `validate`. It fails on any `<to-fill`, on a screen with no Back
   target, and on a screen missing a size class.
7. Save under `docs/plans/`. Tasks filed from the plan carry
   `x-ui: true`. A standalone design plan reaches a task with
   `develop.sh link <id> --design <plan path>`, which validates it and
   writes `x-design`; `/develop`'s gate re-validates it.

## What you must NOT do

- Write or edit product code.
- Invent a token, component or colour the Design source does not have.
- Leave a size class out because the screen "is mostly mobile".
