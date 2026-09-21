---
id: TASK-052
category: stub
phase: P9
status: backlog
---

# TASK-052: Per-cwd lease and kernel-managed worktree per session

**User story.** As an **operator**, I want **two agents in one repo not to share a git index** so that **agent isolation is a substrate primitive rather than a borrowed IDE feature**.

**Why.** Where agents run in parallel today, the shipped git-guard autosave hook cuts a branch keyed to hostname-and-minute and `git add -u`s — so two agents colliding in the same minute silently commit each other's in-progress work onto one branch.

**Notes.** **Cross-repo (`kernel/`)**, though the git-guard half is this repo's and may be worth splitting out.

STATUS: STUB — full spec drafted before implementation.
