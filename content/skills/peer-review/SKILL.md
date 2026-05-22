---
name: peer-review
description: Peer-review a submitted PR end-to-end and act on the verdict — read the diff, check against the project's task/craft/test rules, decide accept or reject, then post the review and, if accepting, merge the PR. The skill takes action; the verdict is not just a written opinion. Triggered when the user wants a PR reviewed and resolved — e.g. "/peer-review #142", "review and merge PR 88 if it's good", "look at this PR and act on it", "/peer-review https://github.com/.../pull/N".
---

# /peer-review — review and act on a PR

Reads a submitted PR, judges it against the project's rules, and
**takes the action the verdict implies** — approve + merge if
accepting, request-changes with specific comments if rejecting.
This skill is one of the documented user-invoked carve-outs to
git-flow Rule 2 ("no skill auto-merges to `main`"): the user's
invocation of `/peer-review` is the static authorization for the
skill to merge an accepted PR. See `git-flow-rules.md` Rule 2.

Per CLAUDE.md ethos: calibrated honesty. The verdict is grounded
in the diff and the project's rules, with the reasoning visible.
"Looks good" is not a review. "I checked X, Y, Z; X passes, Y
passes, Z fails because <reason>" is.

## Behavior contract

- **Invocation is consent.** The user's `/peer-review` invocation
  is the merge authorization for an accepted PR. The skill does
  not ask "Should I merge?" — that's the question the user
  already answered by typing the skill name. See
  `git-flow-rules.md` Rule 2 carve-out.
- **The verdict is binary and concrete.** Every review ends in
  *accept* or *reject*. No "looks good with some concerns" — if
  there are concerns that don't block, name them in the approval;
  if they block, reject. Wishy-washy reviews train wishy-washy
  PRs.
- **Reject is the safer call when uncertain.** A wrong accept
  ships broken code. A wrong reject is a round trip. Bias toward
  reject when the diff fails a real check or when the project's
  rules are ambiguous.
- **Ground the verdict in the project's rules.** The review uses
  `task-rules.md`, `craft-rules.md`, `test-rules.md`, and
  `git-flow-rules.md` as the checklist. Plus the project's own
  `CLAUDE.md`. A review that disagrees with the kit's contract
  but doesn't cite which rule is being broken is not a review —
  it's an opinion.
- **Stop at hard gates.** Same gates as the autonomous skills
  (per `autonomy-rules.md`): a locked contract the PR touches, a
  gated file the PR modifies without authorization, a destructive
  change. Stop and surface; do not approve or reject. The PR
  needs human judgment for these.
- **Merge mechanism.** On accept: `gh pr review --approve` first,
  then `gh pr merge --squash --delete-branch`. Squash because a
  single PR == single logical change == single commit on `main`.
  If branch protection refuses the merge (required checks
  failing, required reviews short), leave the review approved
  and report — do not use `--admin` or force the merge.
- **Reject mechanism.** `gh pr review --request-changes` with a
  body that names each blocking issue, the file and line, the
  rule it violates (`task-rules.md` §X / `craft-rules.md` §Y /
  inline reason), and the smallest concrete fix. Reject comments
  that are vague ("seems off here") are worse than no review.

## What gets checked

The review is not exhaustive — it is *focused on the blocking
shape* of the diff. Run these in order, stop at the first
disqualifier:

1. **Scope sanity.** Does the PR title + body claim what the diff
   actually does? Scope creep ("added X" but diff also reworks
   Y) is a reject unless the body names Y.
2. **Gated files.** Does the diff touch any file the project
   marks as gated (per `task-rules.md` "Gated files" or
   `CLAUDE.md`)? If yes and the PR body doesn't acknowledge it,
   reject — gated files need explicit authorization.
3. **Tests.** Does the diff include tests for the new behavior?
   For non-trivial code changes, missing tests is a reject (per
   `test-rules.md`). For pure doc / config / spec PRs, tests are
   not required.
4. **Quality bars.** Per `craft-rules.md`: no dead code, no
   commented-out blocks, no debug prints, no obvious lints. Run
   the project's lint/build/test commands (from `CLAUDE.md`) and
   require green.
5. **Git hygiene.** Per `git-flow-rules.md`: branch named per
   convention, commits scoped, no force-push history rewrites,
   no merge-conflict markers, no `WIP` cruft in the final commit.
6. **Spec match.** If the PR references a `TASK-NNN`, does the
   diff satisfy the spec's acceptance criteria? Open the spec;
   confirm. If criteria aren't met, reject with the unmet items
   named.

A PR that passes all six → accept. A PR that fails any → reject
with the specific failure named. A PR the skill cannot judge (an
ambiguity in the rules, a domain call the kit can't make) → stop
at a hard gate and ask the user.

## Process

1. **Read the contracts.** `task-rules.md`, `craft-rules.md`,
   `test-rules.md`, `git-flow-rules.md`, `autonomy-rules.md` (for
   the hard-gate list), and the project's `CLAUDE.md`.
2. **Resolve the PR target.** Accept `#NNN`, `NNN`, a GitHub URL,
   or "the open PR on this branch" (use `gh pr view --json
   number`). Capture: number, title, body, base branch, head
   branch, author, status (mergeable, checks).
3. **Fetch the diff and metadata.** `gh pr diff <N>`,
   `gh pr view <N> --json files,title,body,headRefName,baseRefName,statusCheckRollup`.
   Read every changed file at the head ref via `gh pr diff` and
   spot-read the full files where the change interacts with
   broader context.
4. **Run the focused checks** (1–6 above) in order. On the first
   disqualifier, stop checking and prepare a reject. If all six
   pass, prepare an accept.
5. **Take the action.**
   - **Accept** → `gh pr review <N> --approve --body
     "<approval-message-with-checked-rules>"`, then
     `gh pr merge <N> --squash --delete-branch`. If the merge
     fails because of branch protection, leave the approval in
     place and report.
   - **Reject** → `gh pr review <N> --request-changes --body
     "<numbered-list-of-blocking-issues-with-file:line-and-rule>"`.
     Do not also leave inline comments unless the issue is
     specifically at one line — the body is the canonical record.
6. **Track the merge in `RELEASES.md`** (accept path only).
   After a successful merge, follow `release-add/SKILL.md` to
   append every TASK-NNN / HOTFIX-NNN landed by this PR to the
   "🚧 Next" entry of `tasks/RELEASES.md`. Idempotent — re-runs
   are no-ops. If `release-add`'s preconditions fail (file
   shape unexpected, no "🚧 Next" entry), surface as a
   non-blocking note in the review report; the merge already
   happened and is fine.
7. **Render the review report** — see template below.

## Output structure — the review report

One chat message at the end. Shape:

```markdown
# 🔍 Peer review — PR #<N>: <title>

> **Verdict.** <ACCEPT — merged | ACCEPT — approval posted, merge blocked by branch protection | REJECT — changes requested>
> **Decision.** <one sentence — the single most important reason>

## Checks

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Scope sanity | ✓ / ✗ | <one-line> |
| 2 | Gated files | ✓ / ✗ | <one-line> |
| 3 | Tests | ✓ / ✗ / N/A | <one-line> |
| 4 | Quality bars | ✓ / ✗ | <one-line — lint/build/test command + result> |
| 5 | Git hygiene | ✓ / ✗ | <one-line> |
| 6 | Spec match | ✓ / ✗ / N/A | <one-line — TASK-NNN match if applicable> |

## What I did

- Posted review: <accept | request-changes> with body covering <rules>.
- Merge: <squashed and deleted branch | blocked by <reason> | N/A — rejected>.

## Hard gates hit *(if any)*

<Each gate that stopped the run, what it needs from the user. Omit if none.>

- 🔒 <gate> — <what the user must do>
```

## When NOT to use this skill

- **You want a review without action** → run the checks manually,
  or ask Claude to comment without invoking `/peer-review`. This
  skill takes action; that's the contract.
- **The PR is yours and you want a self-check before pushing** →
  use `/code-review` or `/security-review`. Self-review is a
  different skill from peer-review-with-merge-authority.
- **The PR is a release-tagging or deploy action** → `/release`
  is the gate for that. `/peer-review` is for normal feature /
  fix / refactor PRs.
- **The branch protection requires multiple human approvals** →
  this skill posts *one* approval. If the project's rules require
  more, the PR will sit until the additional humans approve. The
  skill's report names this explicitly.

## What "done" looks like

Either: a merged PR, the branch deleted, and a green-verdict
review report in chat. Or: a PR with `request-changes` posted, a
numbered list of blocking issues, and a red-verdict report in
chat. Either way: one report, one action, no ambiguity.
