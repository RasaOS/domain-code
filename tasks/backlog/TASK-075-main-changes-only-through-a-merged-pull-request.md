---
id: TASK-075
type: change
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P4
---
# TASK-075: main changes only through a merged pull request

**User story.** As **the owner of every repository this Element runs**, I want **all work done on a feature branch and `main` changed only by merging a pull request** so that **nothing reaches `main` — or production — without a reviewable, CI-checked record of what changed**.

**Why.** Today nothing enforces it. `main` accepts direct pushes (no ruleset, no branch protection), `git-guard`'s trunk hooks are opt-in and per-machine, and `/release` itself merges into `main` locally and pushes it (its Steps 3, 6 and 7) — the one flow that bypasses a PR by design. Once `main` accepts only PRs server-side, that release flow is rejected, so it is redesigned together with the deploy and release records.

## Acceptance criteria

- [ ] Server side (the owner applies it; this Element never edits repository settings): a ruleset on the default branch requiring a pull request, the CI checks, and blocking force-pushes and deletion, with no bypass. The Element ships the ruleset and the one command that applies it, for any repository it is installed in.
- [ ] `/release` never merges into or pushes `main`: the release's changes (version, notes, CHANGELOG, RELEASES) arrive through a release PR; the tag goes on the merge commit; post-merge facts go to the deploy ledger, not a commit on `main`.
- [ ] `git-flow-rules.md` states the rule without the `/release` carve-out: `main` changes only through a merged PR; server rules enforce it, `git-guard`'s hooks catch it locally.
- [ ] `git-guard`'s trunk guards (pre-commit, pre-push) are on by default for a new install, as task enforcement is; an existing install turns them on deliberately.
- [ ] Every flow that merges does so with `gh pr merge` against a PR whose required checks pass; none pushes `main`.

## Notes

- Requested by the owner 2026-09-24, during the 0.54.0 work. Scheduled with the deploy and release redesign (0.55.0), since `/release` is the flow it changes.
