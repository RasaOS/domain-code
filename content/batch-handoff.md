# Batch Handoff

This file covers the multi-task integration flow used when a phase /
batch of tasks reaches "all closing reports posted, all PRs open, all
gates green." It defines the integration branch, the post-handoff
standby state, and the merge-to-main confirmation gate. **Read this
file when wrapping a phase / batch of tasks.** It extends
`code-task-rules.md` (and through it `task-rules.md`); the Git flow
safety rules in `git-flow-rules.md` and the deploy tagging rules in
`release-rules.md` also apply.

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
  surfaces during testing. File them with `/task` from a checkout of
  the trunk, not the integration branch (its ledger carries the
  batch's own transitions, which ride its PR, so `land.sh docs`
  refuses a ledger landing from it): `git worktree add ../trunk-land
  origin/<trunk>`, then in that worktree `.claude/bin/task new`
  (`tasks/triage/`, or `tasks/backlog/` with `--phase`), draft the
  specs, and land them with `land.sh docs` (the task files,
  `tasks/history.tsv` and `tasks/ROADMAP.md`). The integration
  worktree stays clean for the reviewer's session, and the specs
  reach the trunk.
- **Do** answer questions about what's in the integration branch.
- **Do not** start new feature work. Don't speculatively merge more
  PRs. Don't auto-deploy. Don't kill the running process.
- **Do** keep the local run going until the reviewer signals done.

This is a behavioral state, not a blocking wait — the reviewer may
take minutes or hours.

### Step 4a — On approval ("merge", "ship it", "looks good")

- Sync the integration branch with the latest trunk first: on it,
  `bash .claude/skills/land/land.sh sync` (a merge, never a rebase or
  force), push, and let CI run on the new head. Exit 5 (conflict) or
  7 (push refused): report, do not merge, never retry blindly.
- Once CI has passed on that head, check it is still fresh (the trunk
  may have moved during the wait): `bash .claude/skills/land/land.sh
  fresh --sha <sha>`. Exit 5 → sync again and wait for CI again.
- Merge integration → main pinned to that head with
  `gh pr merge --merge --delete-branch --match-head-commit <sha>`
  (`<sha>` = the synced head CI passed on; a refusal means something
  was pushed after it — stop and report)
- Verify the child PRs auto-close as merged, then
  `.claude/bin/task pass <id> --by <who>` each task — its PR is
  merged, so the done-gate's "Merged" gate now holds (`review/` →
  `completed/`). Land the passes in one call, never committed by
  hand: both paths of each moved task file, `tasks/history.tsv`, and
  any `tasks/RELEASES.md` edit:

  ```bash
  bash .claude/skills/land/land.sh docs --skill batch-handoff --title "pass <ids>" --tasks "<ids>" -- <files>
  ```

  Exit 4 (no `gh`): finish with the session's GitHub tooling per
  `land/SKILL.md` "Without `gh`". Exits 5/6/7: report, never retry
  blindly. Put the landing line (`Landed: PR #N merged` or
  `Not landed: exit N — <message>`) in the reply.
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
   subset. Send only the failing ones back with
   `.claude/bin/task reject <id> --note "<the reviewer's feedback>"`,
   and bake that feedback into the spec.

Recommend (2) by default — it salvages the work that did pass.
Recommend (1) only if the failure is structural (e.g., a shared
foundation task is broken and everything depending on it is suspect).

Wait for the reviewer's decision before doing anything.
