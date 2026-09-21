---
id: TASK-027
category: stub
phase: P4
status: backlog
---

# TASK-027: 60-verify.sh post-deploy verification stage

**User story.** As a **release engineer**, I want **the smoke suite to run against the deployed target after the deploy** so that **"deploy succeeded" means the thing works, not that a shell process exited 0**.

**Why.** The shipped pipeline stops at stage 50. Nothing verifies the deployed artifact, and `release-rules.md` has no post-deploy smoke step.

**Notes.** NOT an architectural problem — `content/build/deploy` collects stages by globbing `stages/*.sh` and sorting, running each as a subprocess, so a `60-verify.sh` runs with no other change. Watch the `--skip-tests` flag, which skips any stage whose *name contains* "test".

STATUS: STUB — full spec drafted before implementation.
