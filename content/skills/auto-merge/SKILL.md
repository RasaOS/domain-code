---
name: auto-merge
description: Merge open pull requests unattended once each has opted in and proven itself. A run lists the open PRs and merges each eligible one. Eligible means it carries the auto-merge label and its merge manifest says `merge: auto`, CI is green, it is mergeable and contains the latest trunk, every PR it waits on has merged, and nothing holds it. A PR behind the trunk gets the trunk merged into its branch and waits for the next run. Every merge goes through /peer-review with the manifest's merge method. After each merge the run carries out the manifest's `on_merge`, but only for non-production targets. A deploy to a dev or staging environment runs build → test → deploy on the trunk; production and releases are queued for a person. Off by default; scheduled with /loop or a Claude routine. Also owns the merge manifest every PR body carries (pr-manifest.sh) and the PR template. Triggered by "/auto-merge", "/auto-merge run", "turn on auto-merge", "merge the ready PRs", "what would auto-merge do", "why didn't PR 42 merge".
---

# /auto-merge: ready PRs merge themselves; nothing else does

A PR that is reviewed, green and opted in should not wait for someone
to click merge. A PR that is none of those should never merge unattended.
`/auto-merge` holds that line mechanically. `auto-merge.sh` decides
eligibility by rule, `/peer-review` reviews and merges, and the PR's own
**merge manifest** says what happens after the merge.

Per CLAUDE.md ethos: unattended is not unreviewed. Every merge passes
the same context-isolated review, the same CI gate and the same done-gate
as a `/peer-review` a person started.

## The merge manifest: what a merger needs to know

Every PR body carries one fenced block. The seeded
`.github/pull_request_template.md` has it, `/open-pr` fills it from the
ledger, and the seeded `pr-manifest` CI check refuses a ready PR without
it:

````markdown
```yaml merge-manifest
kind: task                 # task | chore | release | hotfix
tasks: [TASK-042]          # the ledger ids this PR carries
phase: P3                  # roadmap phase, or none
release: v1.4.0            # the release it is targeted at, or none
merge: auto                # auto (with the label) | manual
method: squash             # squash | merge | rebase
after: [#41]               # PRs that must merge first
on_merge: deploy:staging   # hold | deploy:<env> | release:<version>
migrations: none           # or what runs and whether it reverses
rollback: revert           # or the steps that undo it
```
````

After the block come the sections a merger reads: **What & why**,
**Part of**, **How I verified**, **Risk & rollback** and **After merge**.
`pr-manifest.sh check` refuses a body with a missing or unfilled key, an
unknown key, a missing section or an empty one. It also refuses
contradictions: `on_merge: release:v2` with `release: none`, or
migrations with `rollback: revert`. One parser serves CI, `/open-pr`,
`/peer-review` and this skill:

```bash
bash .claude/skills/auto-merge/pr-manifest.sh check <body-file | - | --pr N>
bash .claude/skills/auto-merge/pr-manifest.sh get <key> <body-file | - | --pr N>
bash .claude/skills/auto-merge/pr-manifest.sh block --kind chore --merge auto --on-merge hold
```

Any skill that opens a PR puts a manifest in its body. For PRs that are
not a task (a `/mission` draft, a `land.sh pr` change; `land.sh docs`
writes its own),
`block` prints a valid block to paste in.

## Behavior contract

- **Off by default.** `.claude/auto-merge.json` ships with
  `enabled: false`. `run` refuses while it is off. Turning it on changes
  a committed file, and a scheduled run reads the trunk, so enabling it
  lands through a PR like any other change.
- **A two-key opt-in, per PR.** A PR is merged only when it carries the
  `auto-merge` label and its manifest says `merge: auto`. The label
  shows the choice on GitHub; the manifest records it in the PR body.
  Neither one alone is enough. A hold label (`hold`, `do-not-merge`,
  `wip`, `blocked`) overrides both.
- **Eligibility is decided by the script.** `auto-merge.sh plan` applies
  every rule in one fixed order and names the first one a PR fails. The
  skill never overrides a skip. A skip is a reason, and the PR's author
  fixes the reason.
- **Only on the latest trunk.** A PR that is mergeable but does not
  contain the latest trunk is `behind` (GitHub's `BEHIND` flag, or git
  against `refs/pull/N/head`). That is the one reason the run fixes
  itself: it merges the trunk into the PR's branch (never a rewrite) and
  leaves it for the next run, when CI has run on the synced head.
- **Every merge is a `/peer-review`.** It reviews with the
  context-isolated auditor, passes the task inside the PR, re-reads CI,
  then merges with the manifest's `method` and
  `--match-head-commit <sha>`, so a push after the review blocks the
  merge. A CRITICAL finding rejects the PR, and the next run skips it
  until it changes.
- **Post-merge actions stay out of production.** `auto-merge.sh after`
  decides:
  - `hold`: nothing runs.
  - `deploy:<env>`: build → test → deploy on the trunk, only when
    `<env>` resolves to **dev or staging class** in
    `.claude/environments.json`.
  - A prod-class, unclassified or unknown env: queued for a person.
  - Every `release:<version>`: queued for a person, who runs `/release`.
  - `deploy: false` in the config queues everything.

  The decision goes to the PR as a comment.
- **One run at a time.** `run` takes a lock; `finish` releases it. A
  lock older than two hours belongs to a run that died and is taken
  over. Schedule **one** runner, a `/loop` or a routine, not both.
- **Bounded.** At most `max_per_run` merges per run (default 5). A PR
  whose `after` names a PR merging in the same run waits for the next
  run.

## Interface

```text
bash .claude/skills/auto-merge/auto-merge.sh status
bash .claude/skills/auto-merge/auto-merge.sh on | off
bash .claude/skills/auto-merge/auto-merge.sh plan [--json] [--from-json <file>]
bash .claude/skills/auto-merge/auto-merge.sh run  [--json] [--from-json <file>]
bash .claude/skills/auto-merge/auto-merge.sh finish
bash .claude/skills/auto-merge/auto-merge.sh after <N> [--execute]
bash .claude/skills/auto-merge/auto-merge.sh log <N> <event> [detail]
```

Exit codes: `0` ok · `1` error · `2` usage · `3` refused (off, locked,
not merged, dirty tree) · `4` no `gh` · `7` the post-merge deploy
failed. Surface stderr verbatim.

## Process

### `/auto-merge` or `/auto-merge status`: report

Run `status` and `plan`. Render the plan table (see Output) and say
whether it is on and how it is scheduled. Merge nothing.

### `/auto-merge on`: enable

1. `auto-merge.sh on`. It flips `enabled` and prints the next steps.
2. Land the change: commit `.claude/auto-merge.json` on a
   `chore/auto-merge-on` branch and open a PR. Its manifest is
   `kind: chore`, `merge: manual`, `on_merge: hold`.
3. Offer the schedule. Pick one:
   - **In this session:** `/loop 30m /auto-merge run`. It runs while the
     session is open.
   - **Unattended:** a Claude routine that starts a fresh session on
     this repository every hour with the prompt `/auto-merge run`.
     Create it with the session's routine tooling if it has one;
     otherwise, give the user the prompt and schedule.

`/auto-merge off` is the same in reverse. Then stop the loop or routine.

### `/auto-merge run`: one pass

1. **Start.**

   ```bash
   bash .claude/skills/auto-merge/auto-merge.sh run
   ```

   - Exit 3 (off or locked): report it and stop. A scheduled run that
     finds it off says so in one line.
   - Exit 4 (no `gh`): list the open PRs with the session's GitHub
     tooling (e.g. `mcp__github__list_pull_requests`, then
     `pull_request_read` for each PR's body, head branch, mergeability,
     merge state and check runs). Write them to a JSON file in the
     scratchpad in the shape `plan --from-json` documents, including
     `headRefName` and `mergeStateStatus` (`BEHIND` marks a PR behind
     the trunk), then run `auto-merge.sh run --from-json <file>`.

2. **For each `state=eligible` PR, in the order listed.** Follow
   `peer-review/SKILL.md` for PR `<N>`: its invocation authority comes
   from this carve-out (`git-flow-rules.md` Rule 2). On the accept
   path, merge with the manifest's method and the head that CI passed
   on:

   ```bash
   gh pr merge <N> --<method> --delete-branch --match-head-commit <sha>
   ```

   Then log it:

   ```bash
   bash .claude/skills/auto-merge/auto-merge.sh log <N> merged "<method> <sha>"
   ```

   For a reject or a hold, log `rejected` or `held` with the first
   reason. Then move on to the next PR. One PR's failure never stops
   the pass.

3. **After each merge:**

   ```bash
   bash .claude/skills/auto-merge/auto-merge.sh after <N> --execute
   ```

   It resolves `on_merge`, runs a non-prod deploy from the trunk
   (fetch, fast-forward, then check that the merge commit is in), and
   comments the outcome on the PR. Exit 7 means the deploy failed. The
   merge stands: report it with the build, test or deploy record ids,
   and keep going. A queued action is reported for a person to take.

4. **For each `state=behind` PR:** merge the trunk into its branch.

   ```bash
   bash .claude/skills/land/land.sh sync-pr --branch <branch>
   ```

   It merges and pushes; it never rebases or force-pushes. Log it
   (`auto-merge.sh log <N> synced "<head>"`) and leave the PR for the
   next run, when CI has run on the synced head. Exit 5 is a conflict
   with the trunk: log `conflict` and report it for the author. Any
   other exit: report it, never retry blindly.

5. **Finish.**

   ```bash
   bash .claude/skills/auto-merge/auto-merge.sh finish
   ```

   Always run it, even when a step above failed. Leaving the lock held
   stops every run for two hours.

6. **Report.** Use the template below. An unattended run with nothing
   eligible, synced or merged reports one line.

## Output structure

```markdown
## 🔀 Auto-merge — <UTC time>

**Merged:** <n> · **Synced:** <n> · **Skipped:** <n> · **Queued for you:** <n>

| PR | Outcome | After merge |
|---|---|---|
| [#N](url) <title> | merged (squash) | deployed to staging · BLD-… |
| [#N](url) | rejected: <first blocking issue> | — |
| [#N](url) | behind: trunk merged in (head <sha>); next run, after CI | — |
| [#N](url) | behind: conflicts with the trunk, for the author | — |
| [#N](url) | skipped: <plan reason> | — |

**Queued for a person:** <#N: release v1.4.0, run /release> …
```

## What you must NOT do

- **Don't merge a PR the plan skipped.** The fix is the reason it names,
  not an override.
- **Don't add the label or set `merge: auto` for an author.** The opt-in
  is theirs. `/open-pr --merge auto` sets both at the author's request.
- **Don't deploy to production or run `/release`.** Queue it.
- **Don't merge without `/peer-review`.** "CI is green" is not a review.
- **Don't run two schedulers.** One `/loop` or one routine.
- **Don't leave the lock held.** Run `finish` on every path.

## When NOT to use this skill

- **Review and merge one PR now** → `/peer-review <N>`.
- **Open a PR** → `/open-pr` (tasks), `/push` (anything else).
- **Ship to production** → `/release`.

## What "done" looks like for an /auto-merge run

The lock is released. Every eligible PR is either merged through
`/peer-review`, with its `on_merge` carried out or queued and a comment
on the PR saying which, or rejected with the reason logged. Every
behind PR has the trunk merged into its branch, or its conflict
reported. Every skipped PR has the one reason the plan named. The
report names each item a person has to act on.
