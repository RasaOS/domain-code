# Batch Handoff

This file covers the multi-task integration flow used when a phase /
batch of tasks reaches "all closing reports posted, all PRs open, all
gates green." It defines the integration branch, the post-handoff
standby state, and the merge-to-main confirmation gate. **Read this
file when wrapping a phase / batch of tasks.** It extends
`task-rules.md`; the Git flow safety rules in `git-flow-rules.md` and
the deploy tagging rules in `release-rules.md` also apply.

## Batch handoff (mandatory)

When a task or batch of tasks reaches "all closing reports posted,
all PRs open, all gates green," **do not stop and wait**. The loop
has more steps. Run them automatically:

### Step 1 — Merge approved tasks into a temp integration branch

Create `integration/<lowest-id>-to-<highest-id>` (or
`integration/<short-name>` if the batch isn't a contiguous range).
Branch off latest `origin/main`. Merge each task branch into it
with `git merge --no-ff`. Resolve conflicts (shared helper files
are typical offenders — keep the canonical version, drop duplicates).

Push the integration branch. **Do not merge to main yet.**

### Step 2 — Spin up the local run

Use `/run` (or the project's run command per `CLAUDE.md`) to bring
up the local environment so the reviewer sees the integration build
the moment the closing report finishes posting. No manual setup, no
clicking through tabs to find a URL.

### Step 3 — Enter "notes & task creation standby"

Wait for the reviewer's verdict. While waiting:

- **Do** accept new task ideas, bug reports, or notes the reviewer
  surfaces during testing. Draft full task specs into
  `tasks/backlog/` **without committing** — keep the worktree clean
  for their session. Same pattern used during the prior review window.
- **Do** answer questions about what's in the integration branch.
- **Do not** start new feature work. Don't speculatively merge more
  PRs. Don't auto-deploy. Don't kill the running process.
- **Do** keep the local run going until the reviewer signals done.

This is a behavioral state, not a blocking wait — the reviewer may
take minutes or hours.

### Step 4a — On approval ("merge", "ship it", "looks good")

- Merge integration → main with `gh pr merge --merge --delete-branch`
- Verify the child PRs auto-close as merged
- Clean up local + remote stale branches and pull main fresh
- **Ask** explicitly: "Deploy now, or hold? If yes, I'll tag the
  release as `vX.Y.Z` — confirm the version." Do not auto-deploy.
  Production deploys are user-confirmed every time. See "Production
  deploy tagging" below for version semantics.

### Step 4b — On rejection ("no", "wait", "broken")

Halt. Do not merge. Do not deploy. Propose a triage plan with two
options:

1. **Scrap the whole batch.** Close the integration branch and the
   offending PRs, leave main as it was. Re-task as needed.
2. **Per-task isolation.** Identify which specific task(s) failed
   verification. Drop those PRs from the integration merge, keep the
   passing ones. Re-build the integration branch from the passing
   subset. Re-task only the failing ones with the reviewer's feedback
   baked into the new spec.

Recommend (2) by default — it salvages the work that did pass.
Recommend (1) only if the failure is structural (e.g., a shared
foundation task is broken and everything depending on it is suspect).

Wait for the reviewer's decision before doing anything.
