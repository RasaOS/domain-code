# Plan — {{SLUG}}

**Kind.** request
**Audit.** {{AUDIT}}

---

## Goal

<to-fill — the person's words, quoted, then one line on what done looks like.>

## Carried from the audit

One bullet per approach, trap, open question and UI finding in the audit. Each ends with a disposition: `done here`, `dropped because <why>`, or `later as <task id or title>`.

- <to-fill — the audit item — disposition>

## Approach

<to-fill — what changes, where, and why this way.>

## Data

Fill each line, or replace all of them with one line: `Not touched: <why>`.

- **Entities and fields:** <to-fill — read or changed>
- **Schema owner:** <to-fill — per CLAUDE.md and code-task-rules.md §8>
- **Contract stamp:** <to-fill — the stamp, and whether it is locked>
- **Migration file:** <to-fill — name per migration-rules.md>
- **/schema-check:** <to-fill — runs or not, and why>

## UI/UX and screens

Fill each line, or replace all of them with one line: `Not touched: <why>`. Rules: ui-rules.md.

- **Size classes:** <to-fill — compact, medium, expanded: the layout and its evidence at each>
- **States:** <to-fill — loading, empty, error, populated, no permission>
- **Back stack:** <to-fill — addresses, back with state, deep link, replace after create/delete>
- **Accessibility:** <to-fill — contrast, focus order, labels, colour never the only signal>
- **Interaction feedback:** <to-fill — pending, success, failure; destructive confirms>
- **Visuals:** <to-fill — charts, tiles or tables where they read better>
- **Design source:** <to-fill — the files the project uses as its style source, or `none declared`>

## Sources of truth read

<to-fill — the repo's and the tenant's files read (`tenant: none` when there is none). A tenant contract wins over the repo.>

## Tasks to file

One bullet per task. Each names its `x-ui` value so `/develop` knows whether the UI block applies; `x-audit` and `x-plan` are this plan's audit and own path.

- <to-fill — task title — x-ui: true|false>

## Checks that prove it

<to-fill — the command or test per task and what it must show.>

## Risks

<to-fill — what could go wrong and how it is held.>
