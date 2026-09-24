---
id: TASK-066
type: defect
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P2
---
# TASK-066: Resolve the install root without leaving the enclosing repository

**Why.** Scripts find their project with `git rev-parse --show-toplevel`. In a per-package install inside a monorepo that lands on the monorepo's root, so records and ledgers are written in the wrong place; a naive "nearest ancestor with a lockfile" rule is worse, because it can walk into an unrelated parent repository.

## Acceptance criteria

- [x] Resolution order: an explicit root argument or `RASA_ROOT`; then walk up from the script's own directory to the first `.claude/rasa.lock.json`; then walk up from the current directory. Both walks stop at the enclosing git toplevel and never cross a `.git` directory or file; otherwise exit 70.
- [x] Replaces `show-toplevel` in every shipped script that locates the project; the count of `show-toplevel` in `content/skills` is 0 afterwards.
- [x] Fixtures: a single repo; a monorepo package; a nested worktree; a repository nested inside a parent that has its own lockfile (the parent's `git status --porcelain` stays empty); a package with no lockfile; a worktree at a commit from before the lockfile existed.
- [x] `task-enforce.sh set` run from inside a package finds that package's task file.

## Notes

- Stabilization plan Step 1 (the plan's TASK-63), renumbered.
- `rasa_root` added to the shared library: explicit root / `RASA_ROOT`, then a walk from the calling script's directory (captured when the library is sourced, before the script can `cd`), then from the current directory; each walk stops at the first `.git` directory or file; rc 70 otherwise.
- 16 scripts converted (audit, auto-save, contract, deploys, env-sync, environment, git-guard, install-hook, push, release, runs, runtime, secrets, sync, task-enforce, task-guard). `show-toplevel` remains only where the question is git's own: `load.sh` (which worktree is this) and `export-project`'s repository name; `build/gates/git-clean.sh` keeps whole-repository cleanliness. `script-craft.md` and the `/new-skill` template now teach `rasa_root`.
- `bin/test-root`: 21 cases pass under /bin/bash 3.2 — the six plan fixtures, explicit roots, the Element's own source layout, and `task-enforce.sh set TASK-192` from a monorepo package and from its monorepo root. In CI under mawk and macOS bash 3.2.
- `bin/test-contract` lays its temp project out as `bin/init` does (library + lockfile): 37/37.
- Smoke: every converted script resolves its install from the project root and from a subdirectory of a fresh `bin/init` install.
- Consequence to know: the Element's scripts run inside the Element's own source checkout (which has no lockfile) need `RASA_ROOT=.`.
