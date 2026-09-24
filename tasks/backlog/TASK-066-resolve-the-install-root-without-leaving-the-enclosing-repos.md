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

- [ ] Resolution order: an explicit root argument or `RASA_ROOT`; then walk up from the script's own directory to the first `.claude/rasa.lock.json`; then walk up from the current directory. Both walks stop at the enclosing git toplevel and never cross a `.git` directory or file; otherwise exit 70.
- [ ] Replaces `show-toplevel` in every shipped script that locates the project; the count of `show-toplevel` in `content/skills` is 0 afterwards.
- [ ] Fixtures: a single repo; a monorepo package; a nested worktree; a repository nested inside a parent that has its own lockfile (the parent's `git status --porcelain` stays empty); a package with no lockfile; a worktree at a commit from before the lockfile existed.
- [ ] `task-enforce.sh set` run from inside a package finds that package's task file.

## Notes

- Stabilization plan Step 1 (the plan's TASK-63), renumbered.
