---
name: open-pr
description: Hand one task from build to review — get onto the task's branch, commit and push the work, open the pull request in the shape code-task-rules.md §10 requires (title `TASK-NNN: <title>`, the task, its acceptance criteria ☑/☐, files changed against the spec's expected list, "How I verified" with real output), `task submit` it into review/, and post the hand-off table. Refuses a PR the spec does not support (an unmet criterion, an empty "How I verified"). Never merges. Triggered when the work on a task is done and the user wants it up for review — e.g. "/open-pr", "/open-pr TASK-042", "open the PR for this task", "put this up for review", "submit TASK-042".
---

# /open-pr — from built to in review

The step between "the code is written" and "a reviewer can look at
it". `/auto-develop` and `/auto-test` end with uncommitted work;
`/push` commits and pushes but deliberately does not open a PR.
Code-task-rules §10 says exactly what a task's PR must look like
and that `task submit` happens when it opens — `/open-pr` is the
skill that does it.

Per CLAUDE.md ethos: a PR is a claim that the spec is met. This skill
refuses to make that claim until the task file, the test run and the
PR body all say the same thing.

## Behavior contract

- **Script-driven mechanics.** `open-pr.sh` owns reading the task
  (through `bin/task`, never by parsing its file), the branch name,
  the body skeleton, the submittability check, opening the PR, and
  `task submit`. Commit and push go through `/push`'s `push.sh`,
  unchanged — one staging path, one secret guard. The AI owns the
  commit message and the body's prose. Per `script-craft.md`.
- **Invocation is consent** to commit, push, open the PR and submit
  the task — the same deliberate exception `/push` makes to "never
  auto-commit". Nothing is asked. It never merges, never touches the
  trunk, never force-pushes.
- **One task per run.** The task id comes from the user, or from the
  one task in `tasks/active/` the current branch belongs to. Two
  candidates → name them and stop; do not guess.
- **The task must be in `active/`.** A backlog task was never
  started, so its work was never tracked; `plan` says so and the skill
  stops. A task already in `review/` is a no-op that reports its PR.
- **Fail-closed on the body.** `open-pr.sh check` refuses a ready PR
  while any acceptance criterion other than the done-gate one is
  unticked in the task file, while a placeholder is unfilled, while
  "How I verified" is empty, or while files deviate from the spec's
  expected list and "Deviations" says none. The fix is to finish the
  work or open a **draft** — never to edit the check away.
- **A draft stays in `active/`.** Per `code-task-rules.md` §2,
  `review/` means "the PR is open and ready". `--draft` opens the PR
  and does not submit; `submit` runs when it is marked ready.
- **The submit rides on the PR.** `task submit` moves the file from
  `active/` to `review/`; the script commits that ledger change onto
  the PR branch and pushes it, so the tree is clean and the branch
  carries its own transition.
- **Not chained from autonomous skills.** `/auto-develop`,
  `/auto-test` and `/mission` do not call this skill: opening a PR
  from an autonomous run is not one of `autonomy-rules.md`'s
  exceptions. `/mission` opens its own draft PR under Exception 1.

## Interface

```text
bash .claude/skills/open-pr/open-pr.sh plan   <TASK-ID>
bash .claude/skills/open-pr/open-pr.sh branch <TASK-ID> --slug <kebab-slug>
bash .claude/skills/open-pr/open-pr.sh body   <TASK-ID>
bash .claude/skills/open-pr/open-pr.sh check  <TASK-ID> <body-file> [--draft]
bash .claude/skills/open-pr/open-pr.sh open   <TASK-ID> <body-file> [--draft]
bash .claude/skills/open-pr/open-pr.sh submit <TASK-ID> --pr <url>
```

Exit codes: `0` ok · `1` error · `2` usage · `3` refused (a
precondition failed; nothing written) · `4` no `gh` — open the PR with
the session's GitHub tooling, then `submit`. Surface stderr verbatim
on any non-zero exit.

## Process

### Step 1 — Plan

```bash
bash .claude/skills/open-pr/open-pr.sh plan <TASK-ID>
```

Read `stage`, `branch`, `dirty_paths`, `unpushed`, `open_pr` and
`plan`. `plan=refuse` → surface it and stop. `plan=nothing` → report
the existing PR and stop.

### Step 2 — Get onto the task's branch

```bash
bash .claude/skills/open-pr/open-pr.sh branch <TASK-ID> --slug <kebab-slug>
```

On the trunk it cuts `task/TASK-NNN-<slug>` (`hotfix/…` for a
`priority: now` defect). On a side branch it keeps that branch — a
pushed branch is never renamed. Derive the slug from the task title.

### Step 3 — Run the full gate once

Per `code-task-rules.md` §10: run the project's **unfiltered**
headless test command and its build (from `CLAUDE.md`), once. Keep
the real output — counts and time — for "How I verified". A failure
you cannot fix inside the task's scope is a `task block`, not a PR.

Tick the criteria the run proves in the task file, then:

```bash
.claude/bin/check-tasks --fix
```

### Step 4 — Commit and push

Write the commit message in the repository's style (`git log` first):
a one-line summary naming the task, a blank line, a body saying why.

```bash
bash .claude/skills/push/push.sh run --message "<message>"
```

Surface anything `push.sh` reports it skipped.

### Step 5 — Draft the body

```bash
bash .claude/skills/open-pr/open-pr.sh body <TASK-ID>
```

It writes a skeleton to a temp file **outside the repository** and
prints `body_file=<path>` — edit that file, never one in the working
tree (`push.sh` would commit it onto the PR). The skeleton already
carries the task, its criteria with ☑/☐ from the task file, and every
changed file checked against the spec's "Artifacts expected to
change". Fill in:

- **What changed** — one to three sentences.
- **Deviations** — every bolded file line explained, or `none`.
- **How I verified** — the commands from Step 3 and their real
  output. Never "tests pass".

### Step 6 — Validate the body

Follow `validate/SKILL.md` at the **short** tier. The artifact is the
PR body; the original ask is the task's spec. The mechanical half is:

```bash
bash .claude/skills/open-pr/open-pr.sh check <TASK-ID> <body-file> [--draft]
```

The judgment half is a second, different lens — read the diff
(`git diff <trunk>...HEAD`) against "What changed": does the body
describe what the diff actually does, and nothing it doesn't? Fill
any gap in the body, then re-run `check` until it passes twice in a
row.

### Step 7 — Open and submit

```bash
bash .claude/skills/open-pr/open-pr.sh open <TASK-ID> <body-file> [--draft]
```

It re-checks, refuses dirty or unpushed work, opens the PR against
the trunk with the title `TASK-NNN: <task title>` (or reuses the one
already open for the branch), runs `task submit`, and commits and
pushes that ledger transition onto the branch.

**Exit 4 (no `gh`):** open the PR with the session's GitHub tooling
(e.g. `mcp__github__create_pull_request`) using the base, head, title
and body file it printed; then:

```bash
bash .claude/skills/open-pr/open-pr.sh submit <TASK-ID> --pr <url>
```

Skip `submit` for a draft.

### Step 8 — Post the hand-off

The §10 hand-off table, in chat. Nothing is done yet — the task is in
`review/`, so there is no Outcome row.

## Output structure

```markdown
## 📬 TASK-NNN in review — <title>

| | |
|---|---|
| **Branch** | `task/TASK-NNN-slug` |
| **PR** | [#N](url) <· draft> |
| **Tests** | full headless gate: <count> green · <time> |
| **Build** | clean / <new warnings> |

**What changed.** <one to three sentences>

**Reviewer next.** <what to look at first, and how to run it>

<validation block from Step 6>
```

## What you must NOT do

- **Don't merge.** Review and merge are `/peer-review`'s or a
  person's. This skill stops at an open PR.
- **Don't submit a draft.** A draft is `active/` work.
- **Don't tick a criterion the run did not prove** to get past
  `check`. The body is a claim the reviewer will test.
- **Don't write "tests pass".** Real counts and time, from Step 3.
- **Don't draft the body in the working tree.** Use the temp file
  `body` printed.
- **Don't move the task file by hand.** `bin/task` is the only thing
  that changes a task's stage.

## Edge cases

- **Already on a `/mission` `feat/` branch.** Kept; the PR title still
  names the task. `branch` notes the mismatch.
- **A PR is already open for the branch.** `open` reuses it and only
  submits.
- **Push fails after submit.** The transition is committed locally;
  push the branch and the PR picks it up.
- **The task has no acceptance criteria.** It is a stub — `check`
  refuses. Expand it (`/task`) first.
- **Several tasks' work is mixed in the tree.** Stop: one PR is one
  task. Split the work, or name the one task this PR carries.

## When NOT to use this skill

- **Just save the work to a branch** → `/push`.
- **Review or merge a PR** → `/peer-review`.
- **A whole goal end to end** → `/mission`, which opens its own draft
  PR.
- **Work that is not a task** → `/push` onto a `chore/` branch.

## What "done" looks like for an /open-pr session

The task's work is committed and pushed on its branch, a PR titled
`TASK-NNN: <title>` is open with a body the spec supports (criteria
☑/☐, files against the expected list, real verification output), the
task is in `review/` with the PR URL in its transition log — the move
committed on the branch — and the hand-off table is in chat. Or, for
a draft: the PR is open and the task is still in `active/`.
