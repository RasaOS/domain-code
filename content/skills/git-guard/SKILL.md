---
name: git-guard
description: Toggle git-hygiene lockdown on/off. When ON, installs hooks that (1) auto-capture work-in-progress as wip: commits so nothing abandoned mid-session is ever lost, (2) fast-forward the branch and surface abandoned work at session start, (3) block commits and pushes directly to the trunk branch, and (4) block commits containing secret-shaped files. Built for working a project across multiple machines without merge conflicts or stranded work. Per-machine (Claude Code hooks in settings.local.json + git hooks in .git/hooks). Subcommands: on, off, status. Triggered when the user wants git safety automated — e.g. "/git-guard on", "/git-guard off", "/git-guard status", "lock down git", "never lose uncommitted work", "stop me committing to main", "keep my machines in sync".
---

# /git-guard — git-hygiene lockdown

A toggle that makes the safe git workflow automatic and the unsafe
state impossible to miss. Built for the real failure mode: you walk
away mid-session, forget where you were, start fresh — maybe on a
different machine — and the work just sits, uncommitted and unknown.

`/git-guard on` installs a hook set that closes that gap. You don't
have to remember anything.

Builds on **`/install-hook`** (deterministic JSON edits to
`settings.local.json`). The script `git-guard.sh` owns every
mechanic; this SKILL.md only routes the `on` / `off` / `status`
choice.

## What it installs

| Hook | Type | What it does |
|---|---|---|
| `SessionStart` → `audit` | Claude Code | `git fetch`, fast-forward the current branch if cleanly behind, then surface any abandoned work (dirty trees, unpushed branches, `wip/` branches, dirty worktrees) into the session |
| `Stop` → `checkpoint` | Claude Code | After each turn, autosave **if** a change threshold tripped (lines / files / time) |
| `PreCompact` → `autosave` | Claude Code | Capture the tree before context compaction |
| `SessionEnd` → `session-end` | Claude Code | Final capture, then warn on anything still unsaved |
| `pre-commit` → `guard-commit` | git | **Reject** commits on the trunk branch + commits with secret-shaped files |
| `pre-push` → `guard-push` | git | **Reject** pushes to the trunk branch |
| `pull.ff = only` | git config | A stale pull errors loudly instead of making a surprise merge commit |

Claude Code hooks land in `.claude/settings.local.json` (per-user,
gitignored). Git hooks land in the repo's shared hooks dir
(worktree-aware via `git rev-parse --git-common-dir`). Both are
**per-machine** — run `/git-guard on` once on each machine.

## How the auto-capture works

The `Stop` hook runs `checkpoint` after every turn. It autosaves
only when one of these trips:

- **lines changed** ≥ `GIT_GUARD_LINES` (default 80)
- **files changed** ≥ `GIT_GUARD_FILES` (default 5)
- **minutes since last autosave** ≥ `GIT_GUARD_MINUTES` (default 20)

The time backstop is the one that catches forgetfulness — a tiny
change left abandoned still gets saved.

An autosave: rescues you onto an isolated `wip/<host>-<date>` branch
if you were on trunk or detached → stages tracked changes + untracked
files → **skips and warns on secret-shaped or oversized untracked
files** → makes a `wip: autosave [<host>] <ts>` commit → pushes it
(best-effort; commit still succeeds offline). Squash-merge collapses
all the `wip:` noise at PR time, so it never reaches trunk.

## Interface

```text
bash <skill-dir>/git-guard.sh on        Install all hooks + pull.ff only.
bash <skill-dir>/git-guard.sh off       Remove everything git-guard installed.
bash <skill-dir>/git-guard.sh status    Report ON / OFF / PARTIAL.
```

Hook handlers — called by hooks, not invoked directly: `audit`,
`checkpoint`, `autosave`, `session-end`, `guard-commit`, `guard-push`.
One operator-useful handler:

```text
bash <skill-dir>/git-guard.sh scan-secrets [--staged]
    Scan tracked (or staged) files for secret-shaped names/content.
    Exit 3 if any found. Does NOT scan history — use `gitleaks` for that.
```

Exit codes: `0` success/clean, `1` operational, `2` usage, `3` refused.

### Tunables (environment variables)

| Var | Default | Effect |
|---|---|---|
| `GIT_GUARD_LINES` | `80` | autosave trigger — changed lines |
| `GIT_GUARD_FILES` | `5` | autosave trigger — changed files |
| `GIT_GUARD_MINUTES` | `20` | autosave trigger — time backstop |
| `GIT_GUARD_MAX_MB` | `5` | skip untracked files larger than this |
| `GIT_GUARD_PUSH` | `1` | `0` = commit only, never push |
| `GIT_GUARD_ALLOW_MAIN` | unset | `1` = permit one commit/push to trunk |
| `GIT_GUARD_ALLOW_SECRET` | unset | `1` = permit one commit with a secret-shaped file |

`GIT_GUARD_ALLOW_*` are the deliberate escape hatches — used instead
of `--no-verify`, which `task-rules.md` forbids.

## Behavior contract

- **Per-machine.** Claude Code hooks → `settings.local.json`
  (gitignored); git hooks → `.git/hooks/` (not version-controlled).
  Run `on` once per machine per project.
- **Idempotent.** `on` twice is a no-op; `off` when off is a no-op.
  Git-hook edits use sentinel blocks (`# >>> git-guard >>>`), so
  `off` removes cleanly and pre-existing hooks are preserved.
- **Hooks never abort a session.** `audit`, `checkpoint`, `autosave`,
  `session-end` always exit 0 — a session-lifecycle hook must not
  break the session. Only the git guards (`guard-commit`,
  `guard-push`) exit non-zero, and only to reject.
- **Never touches the tree mid-operation.** Autosave bails if a
  rebase / merge / cherry-pick / revert / bisect is in progress.
- **Never auto-commits to trunk.** Autosave rescues off trunk first;
  the pre-commit guard blocks it as a backstop.
- **Secret-shaped files never enter a commit** — the autosave bouncer
  skips them and the pre-commit guard rejects them. `.gitignore`d
  files are already excluded by git; this covers the *un-ignored*
  untracked gap.
- **Quiet during normal operation.** `checkpoint` is silent unless it
  actually saved. Autosave prints one line when it commits.

## Process

### Step 1 — Map intent to a subcommand

- "turn on git-guard" / "/git-guard on" / "lock down git" → `on`
- "turn it off" / "/git-guard off" → `off`
- "is git-guard on?" / "/git-guard status" → `status`

### Step 2 — Run it

```bash
bash .claude/skills/git-guard/git-guard.sh <on|off|status>
```

Surface the script's stdout verbatim.

### Step 3 — Note the lifecycle

On `on`: tell the user the Claude Code hooks take effect on the
**next** session start (this session's `SessionStart` already fired).
The git hooks and `pull.ff` are active immediately.

## Style rules

- **Toggle output is brief.** One block for `on` / `off`, one line
  for `status`. No preamble.
- **Don't render hook-handler output in chat** as if the user asked
  for it — `audit` / `checkpoint` / etc. are for the hook system.
- **When `audit` surfaces abandoned work at session start, lead with
  it.** That report is the whole point — don't bury it.

## What you must NOT do

- **Don't hand-edit `settings.local.json` or `.git/hooks/`** for these
  hooks — use `on` / `off`. Direct edits break idempotent removal.
- **Don't run a history rewrite** (`git filter-repo`, `filter-branch`,
  BFG) to "clean" a secret. That rewrites every SHA, force-pushes,
  and breaks every other clone. If `scan-secrets` finds a tracked
  secret: untrack it + `.gitignore` it going forward, and **rotate
  the credential** — assume it's burned the moment it was pushed.
  A full history purge is a separate, human-driven, coordinated op.
- **Don't bypass the guards with `--no-verify`.** Use the
  `GIT_GUARD_ALLOW_*` env vars — deliberate and visible.
- **Don't enable git-guard and assume `audit` already ran** this
  session. `SessionStart` fired before the hook existed.

## Edge cases

- **`settings.local.json` malformed** — `install-hook.sh` refuses and
  surfaces the parse error. User fixes by hand.
- **`python3` missing** — `install-hook.sh` can't run, so `on`/`off`
  fail; `audit` falls back to plain stdout instead of injected
  context.
- **Not in a git repo** — every subcommand no-ops or errors cleanly.
- **Worktrees** — git hooks are shared across worktrees (resolved via
  `--git-common-dir`); `audit` reports dirty sibling worktrees.
- **Pre-existing git hooks** — git-guard inserts a sentinel block
  rather than overwriting; `off` removes only that block.
- **Offline** — autosave still commits locally; the push is deferred
  and retried by the next autosave.
- **Autosave commit blocked by the secret guard** — autosave reports
  it and leaves the tree for the user; nothing is lost.

## When NOT to use this skill

- **A repo you only ever touch from one machine for quick edits** —
  the lockdown earns its keep across machines and long sessions.
- **A shared branch that triggers CI on every push** — autosave's
  `wip:` pushes would spam CI. Set `GIT_GUARD_PUSH=0` (commit-only)
  or keep git-guard off on that repo.
- **Pair / mob sessions** — autosave assumes one author per session.

## What "done" looks like

The user runs `on` / `off` / `status`, the script does its work, the
user sees the brief result. From the next session on: work is
captured automatically, the trunk is un-committable by accident, and
every session opens with a clean bill of health or a loud list of
what was left behind.
