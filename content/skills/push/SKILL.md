---
name: push
description: Commit and push the working tree in one step — the "save my work" button. No questions. On a side branch it commits and pushes there; on the trunk it creates a new branch first, commits, and pushes it PR-ready (without opening the PR). A quicker, lighter step than /save — /save snapshots thread context, /push just gets the work into git so it can't be lost. Triggered when the user wants their work committed and pushed now — e.g. "/push", "push my work", "commit and push", "push it", "save this to the branch", "don't lose this".
---

# /push — commit and push, no questions

The save button for your git work. One command: it commits
everything and pushes it. No prompts, no decisions handed back —
like hitting save on a document.

`/push` is a step down from `/save`. `/save` snapshots the *thread*
— what you did, what's open, what's next. `/push` just gets the
*code* into git so a crash, a context switch, or another machine
can't lose it.

Per CLAUDE.md ethos: just do the job. The user invoked `/push` to
have their work pushed — don't ask them which branch, what message,
or whether they're sure. Decide and do it.

## Behavior contract

- **Script-driven mechanics.** `push.sh` owns the git plumbing —
  branch logic, staging, the secret-shaped skip, commit, push, the
  PR-ready note. Per `script-craft.md`. The AI synthesizes the
  commit message and, when on the trunk, the branch name; the
  script does everything else. Always invoke as
  `bash <skill-dir>/push.sh …`.
- **No questions.** This is the defining trait. The commit message
  and the branch name are decided by the AI, not asked. Run it.
- **It commits and pushes — on purpose.** Every other kit skill
  leaves changes uncommitted ("never auto-commit"). `/push` is the
  deliberate exception: committing and pushing *is* its job. That
  is what the user asked for by invoking it.
- **Never touches the trunk.** On the trunk (or detached HEAD),
  `push.sh` creates a new branch and commits there — it never
  commits to or pushes `main`. This keeps `/push` inside
  `git-flow-rules.md` Rules 1 and 4.
- **Branches from the trunk are PR-ready, not PR'd.** When `/push`
  cuts a branch off the trunk, it pushes it with upstream tracking
  and surfaces the PR link. It does **not** open the PR — opening
  it stays the user's call.
- **Secret-shaped files are skipped, not pushed.** `push.sh` leaves
  out files that look credential-bearing (and oversized ones) and
  reports what it skipped. This is not a question — it's the job
  done safely. The skipped file is still on disk; it just doesn't
  get pushed.

## Interface

```text
bash <skill-dir>/push.sh status
    Report what a run would do — branch, trunk-or-not, dirty
    count, unpushed count, the plan.

bash <skill-dir>/push.sh run --message <msg> [--branch <name>]
    Commit all changes and push.
      - On the trunk: create <name> (or a fallback), commit, push.
      - On a side branch: commit and push to it.
    --message is required. --branch is used only on the trunk.
```

Exit codes: `0` success, `1` operational (push failed — commit is
still safe locally), `2` usage, `3` refused (rebase/merge in
progress). Surface stderr verbatim on non-zero.

## Process

### Step 1 — Check the state

```bash
bash .claude/skills/push/push.sh status
```

Tells you the branch, whether it's the trunk, and what a run will
do.

### Step 2 — Synthesize the commit message

From `git diff --stat` and `git status` — one concise, factual
line describing what changed. Not "wip", not a paragraph. The
message is decided, never asked.

### Step 3 — If on the trunk, synthesize a branch name

When `status` shows you're on the trunk, decide a branch name:
kebab-case, following `git-flow-rules.md` naming — `chore/<slug>`
by default, `feat/<slug>` or `task/<slug>` if the change is
clearly one. Derive the slug from what changed.

### Step 4 — Run it

```bash
bash .claude/skills/push/push.sh run --message "<message>" [--branch "<name>"]
```

Pass `--branch` only when on the trunk.

### Step 5 — Surface the result

Show the script's output. If it created a branch off the trunk,
surface the PR-ready line as-is — the branch is pushed and ready,
and the PR is deliberately left for the user to open.

## What you must NOT do

- **Don't ask the user anything.** Not the message, not the
  branch, not "are you sure". `/push` exists to be frictionless.
- **Don't open the PR.** `/push` leaves a PR-ready branch. Opening
  the PR is a separate, deliberate user action.
- **Don't commit or push the trunk.** If on the trunk, the script
  branches first — never override that.
- **Don't paraphrase the script output.** Surface it as-is.
- **Don't force-skip the secret guard.** If `push.sh` skipped a
  file, report it; don't re-add it to sneak it through.

## Edge cases

- **Clean tree, nothing unpushed** — `push.sh` reports "nothing to
  do" and exits 0. Surface it; don't manufacture a commit.
- **Clean tree, commits unpushed** — `push.sh` just pushes; no new
  commit.
- **Only skipped files are dirty** — nothing real to commit;
  `push.sh` reports "nothing to push" and does not push.
- **Push failed (offline)** — the commit is safe locally; the
  script says so and exits 1. Tell the user to re-run `/push` when
  back online.
- **Rebase/merge in progress** — `push.sh` refuses (exit 3).
  Surface it; the user finishes the operation first.

## When NOT to use this skill

- **Snapshotting thread context** (what you did, what's open) →
  use `/save`.
- **A durable handoff for someone else** → use `/handoff`.
- **Cutting a production release** (merge, tag, deploy) → use
  `/release`. `/push` never merges or tags.
- **Automatic background capture** without invoking anything →
  that's `/git-guard`'s autosave. `/push` is the manual button.

## What "done" looks like for a /push session

The working tree is committed and pushed — to the current branch
if you were on one, or to a freshly created branch if you were on
the trunk. Nothing is left uncommitted (except deliberately
skipped secret-shaped files). If a branch was cut from the trunk,
it's pushed and PR-ready, and the user has the link to open the PR
when they choose. No questions were asked.
