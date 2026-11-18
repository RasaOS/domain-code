---
name: design-audit
description: Audit how a screen, or the screens a request touches, look and behave across the three size classes (compact, medium, expanded). Finds the project's style sources (the Design source), then records what breaks per size class, the five states, the back stack, accessibility, interaction feedback, data shown, visuals and one-off values where a token exists. Fills the UI/UX section of a request audit, or writes a standalone `**Kind.** design` audit. Triggered by "/design-audit", "audit the UI of the inspection screen", "how does this look on mobile and tablet", "what is our design source".
---

# /design-audit — read the UI before changing it

Read-only. Produces a report; it never edits product code. The rules it
holds screens to are in `ui-rules.md`; the flow it belongs to is in
`flow-rules.md`.

## The script

`bash <skill-dir>/design-audit.sh` (`.claude/skills/design-audit/` in an
install). Always invoke with `bash`.

```text
design-audit.sh discover             style sources + chart libraries, by name and path
design-audit.sh scaffold <slug>      a standalone design audit (Kind design)
design-audit.sh scaffold --in <file> only the UI/UX block, for a request audit
design-audit.sh validate <file>      exit 0 compliant, 3 not
```

`discover` prints `source | path | kind | confidence`, one row per
find, or `none found` (exit 0). It reads names and paths only, never a
value, and never invents a token. The tenant is not looked up here: the
tenant's `design/` folder is listed when `develop.sh sources` (the
`/develop` skill) reports a tenant, whose first output line is
`tenant: none` or `tenant: <path>`.

## One source per subject

The UI/UX block is a single fragment, `audit/ui-audit-section.md`. The
request audit (`audit.sh scaffold-request`) and this skill use the same
one. When a request audit exists, fill and validate its
**UI/UX and screens** section (`scaffold --in <file>`, then
`validate <file>`); write a standalone design audit only when there is
no request audit. At most one audit document per request.

## Process

1. Run `discover`. Name the Design source: tokens, theme, component
   library. If none, write `none declared` and raise it as an open
   question; do not invent one.
2. List the screens in scope, each with its address and its back
   target.
3. For each screen, at compact, medium and expanded: what breaks, what
   is cut off, what reflows. Then the five states, interaction
   feedback and accessibility, per `ui-rules.md`.
4. Data shown: the fields, the contract stamp, and whether it is
   locked. A locked contract stops the work.
5. Visuals: data shown as text that reads better as a chart, colour
   code or tile; charts that mislead or lean on colour alone.
6. Uniformity: one-off colour, spacing or type values where a token
   exists.
7. `validate`, then save: `bash <skills>/audit/audit.sh save <slug>
   <file>` lands it in `docs/audits/`.

## What you must NOT do

- Edit product code, or write a plan. The plan is `/plan`'s.
- Screenshot production, or commit a screenshot.
- Paste values from the style source into the report; cite the file.
