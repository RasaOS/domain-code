---
name: reconcile
description: Clean the task ledger against reality — compare every open task (triage, backlog, active, review, blocked) with its branch, its commits, its pull request and how long it has sat, then move it where the evidence says. Evidence-certain moves happen without asking (a merged PR → run the done-gate and pass; a PR closed unmerged → reject; an open ready PR → submit); judgment calls (stale active work, long-blocked tasks, old triage items and stubs) are proposed in one batch for the user to approve. Every transition lands through one ledger pull request, never a direct commit to the trunk. Pairs with the enforcement that keeps it clean: the session-start staleness report, the `task start` guard, and the /release ledger gate. Triggered when the backlog needs cleaning — e.g. "/reconcile", "clean up the backlog", "what's stale", "close out merged tasks", "why is TASK-042 still in review", "tidy the task ledger".
---

# /reconcile — make the ledger say what actually happened

A task's stage changes by a separate act from the work: `task submit`
when the PR opens, `task pass` when it merges. Skip the act and the ledger
lies — merged work sits in `review/`, abandoned branches leave tasks in
`active/` for months, triage fills with things nobody will do. `/reconcile`
reads the evidence and moves each task where it belongs.

Per CLAUDE.md ethos: the ledger is a record, not a wish list. A task is in
`completed/` because the gate passed and the PR merged — never because
closing it made a number smaller.

## Behavior contract

- **Script-driven evidence.** `reconcile.sh scan` owns the evidence and
  the classification: each task's days in its stage (from
  `tasks/history.tsv`), its branches and last commit, its PR (via `gh`),
  and the thresholds in `.claude/task-hygiene.json`. The skill applies what
  it says; it never re-derives staleness by eye.
- **Certain moves are made without asking.** Three, all decided by
  evidence rather than judgment:

  | Evidence | Move |
  |---|---|
  | `review/` (or `active/`), PR **merged** | run the done-gate on the trunk → `pass` (gate green) or `reject` (gate red) |
  | `review/`, PR **closed without merging** | `reject` → back to `active/` |
  | `active/`, PR **open and ready** | `submit` → `review/` |

- **Judgment calls are proposed, once.** Stale active work, a review with
  no PR, a long-blocked task, an old triage item, a forgotten stub — one
  table, a recommended action per row, the user approves the batch (or
  edits it). Never close, park or re-plan a task silently.
- **`pass` keeps the done-gate.** A merged PR is not the gate. Run the
  gate once on the trunk head — it covers every merged task at once — and
  write each task's `## Completion report` with the evidence before
  `pass`. A red gate means `reject` with the failing gate named, never a
  waived one.
- **Merge evidence must be proven.** `gh` proves a merge. Without it,
  `scan` infers merges from trunk commit subjects and marks them
  judgment; confirm each with the session's GitHub tooling (e.g.
  `mcp__github__pull_request_read`) before treating it as certain.
- **Through a pull request.** The trunk changes only through a merged PR
  (`git-flow-rules.md`). Every transition from one run is committed on
  `chore/ledger-reconcile-<YYYYMMDD>` and opened as one PR. Never commit
  ledger moves to the trunk.
- **`bin/task` moves tasks.** Never `mv` a task file or write `status:`.
  Run `.claude/bin/check-tasks --fix` after editing any task body.

## Process

### Step 1 — Scan

```bash
bash .claude/skills/reconcile/reconcile.sh scan          # table
bash .claude/skills/reconcile/reconcile.sh scan --json   # for the details
```

Nothing but `ok` rows → say the ledger is clean and stop.

### Step 2 — Prove the merges

For each `pass-after-gate` row marked judgment ("no gh: merge not
proven"), look the PR up with the session's GitHub tooling. Merged → it
is certain. Not merged, or no PR → keep it in the judgment batch.

### Step 3 — Branch

From an up-to-date trunk: `git checkout -b chore/ledger-reconcile-<YYYYMMDD>`.

### Step 4 — Apply the certain moves

Actor: `bash .claude/skills/task-enforce/task-enforce.sh who`.

- **submit:** `.claude/bin/task submit <id> --by <actor> --note "PR #<n> open"`
- **reject (closed PR):** `.claude/bin/task reject <id> --note "PR #<n> closed without merging"`
- **pass-after-gate:** run the done-gate **once** on the trunk head —
  `./build/build && ./build/test` in a project with the pipeline chain,
  otherwise the gates in `.claude/done-gate.md` with the commands from
  `CLAUDE.md`. Keep the real output (counts, time, the `TST-…` id).
  - Gate **green** → for each merged task: append its `## Completion
    report` (PR, merge commit, gate evidence), run
    `.claude/bin/check-tasks --fix`, then (from `active/`, `submit` first)
    `.claude/bin/task pass <id> --by <actor> --note "PR #<n> merged <sha>; <evidence>"`.
  - Gate **red** → `.claude/bin/task reject <id> --note "gate not passed on the trunk: <which gate>"`
    for each, and report the failure — the trunk is broken, which is its own finding.

### Step 5 — Propose the judgment batch

One table, recommended action first:

| Finding | Default recommendation | Alternatives |
|---|---|---|
| `stale-active` | `task park <id>` (back to backlog, keeps the spec) | `close --resolution obsolete/wont-do`; keep, with a note why |
| `closed-unmerged-active` | `task park` | `close` |
| `stale-review` | nudge the reviewer; keep | `reject` if the PR is abandoned |
| `no-pr` | `task reject` (back to active) | `/open-pr` |
| `stale-blocked` | re-check the blocker; `unblock` if gone | `close`; escalate |
| `stale-triage` | `graduate --phase <P>` if it is real work | `close --resolution wont-do/duplicate --ref` |
| `stale-stub` | `close --resolution obsolete` | expand it (`/task`) if still wanted |

Ask once for the batch. Apply exactly what the user approved.

### Step 6 — Validate, commit, open the PR

Follow `validate/SKILL.md` at the **short** tier: re-run `scan` — every
certain row must now be `ok`, and every approved judgment row applied as
approved. Then `.claude/bin/check-tasks` (must pass), commit
`tasks/` (`Ledger: reconcile <date> — <n> transitions`), push, and open the
PR (`gh pr create`, or the session's GitHub tooling). The body is the
evidence table: each task, from → to, and why.

## The enforcement that keeps it clean

`/reconcile` cleans up; these stop the mess returning. All read
`.claude/task-hygiene.json` (thresholds, `wip_limit`, `block_start`,
`release_gate`), and are installed by `bin/init`
(`task-enforce.sh hooks`):

- **Session start** — `reconcile.sh check --session` prints the stale
  tasks into every new session. Lead with them.
- **`task start` guard** — a PreToolUse hook refuses `task start` while
  the actor holds stale active work, is at the WIP limit, or merged work
  waits to be passed. The fix is `/reconcile`, not the switch.
- **`/release`** — refuses while merged work sits unpassed
  (`check --release`).
- **`/peer-review`** — passes the task on the PR branch before it
  merges, so the move to `completed/` lands inside the merge.
- **CI** — `reconcile.sh check --ci` fails when anything is stale.

## Output structure

```markdown
## 🧹 Ledger reconcile — <date>

**Applied (certain):** <n>
| Task | From → to | Evidence |
|---|---|---|

**Proposed (needs your call):** <n>
| Task | Stage · age | Finding | Recommend |
|---|---|---|---|

**Gate:** <TST-… passed | commands + counts> · **PR:** [#N](url)
```

## What you must NOT do

- **Don't pass without the gate.** Merged is not done.
- **Don't close to shrink the list.** Every close names a resolution, and
  `superseded`/`duplicate` name the other task.
- **Don't commit ledger moves to the trunk.** One PR per run.
- **Don't turn off `block_start` to get past the guard.** Reconcile.

## When NOT to use this skill

- **One task, one move you already know** → `/task`.
- **Opening a task's PR** → `/open-pr`.
- **Planning what's next** → `/plan` or `/backlog`.

## What "done" looks like for a /reconcile session

`reconcile.sh scan` shows only `ok` rows (or the user deliberately kept a
flagged task, with a note in it saying why), every merged task passed on
real gate evidence or rejected with the failing gate named, and one
ledger PR open carrying every move and its evidence.
