---
id: TASK-058
category: bug
phase: P3
status: completed
owner: unassigned
blocked_by:
outcome: shipped
filed: 2026-09-21 05:00 UTC
origin: manual
---

# TASK-058: the spec fast-path's allowlist is never actually checked

**User story.** As an **operator**, I want **the spec-only merge carve-out
enforced by a program** so that **the one autonomous path to `main` does not
depend on a model correctly applying a glob list from prose**.

## What is and is not wrong here

Exception 2 lets `/auto-task` and `/auto-phase` merge spec-only PRs to `main`
with no reviewer. TASK-022 flagged this as "ungraded by anyone". Read properly,
**the carve-out's reasoning is sound and is not the defect**:

> Spec content is the team's plan, not the team's runtime. It is reversible
> (`git revert`) and visible (PR record). Lifting the gate for code would change
> behavior on `main`; lifting it for specs only changes what plans are visible.

That holds. Spec files do not execute. The merge is reversible and leaves a PR.
Adding a mandatory subagent review to every spec filing would be the "expensive
mandatory step that cries wolf" TASK-022 argued against.

**The defect is that the carve-out's own precondition is unenforced.**
Exception 2 says: *"The moment any non-allowlist file is in the change set, the
fast-path is off — no exceptions."* Nothing checks that.

- `ls content/skills/auto-task/ content/skills/auto-phase/` → `SKILL.md` only.
  **No script behind either skill.**
- `grep -rn 'git diff --name-only\|git status --porcelain'` across both skills
  and `autonomy-rules.md` → **zero hits.**

So the allowlist is prose, applied by the same model that authored the change,
immediately before it merges to `main` unattended. Every other gate in this
Element is a program — `class-guard.sh`, `tests-required.sh`, `approval.sh`,
`git-clean.sh`, and `task-enforce.sh`'s PreToolUse deny. This one is a
paragraph.

Corroborating: the allowlist text was **silently corrupted from v0.48.0 until
TASK-013 repaired it** — a duplicated line that left it not parsing as a list.
Nothing caught it for exactly this reason. A prose allowlist can be wrong for
months and still "pass".

## The fix

A real gate, following the `class-guard.sh` precedent: **no bypass variable.**

`task-enforce.sh spec-gate` — the task-governance engine already installed in
every consumer, already holding `repo_root` and the frontmatter reader.

Two modes, and the second is the load-bearing one:

- **local** (pre-push) — checks the dirty tree.
- **`--pr <N>`** (pre-merge) — checks the **pushed artifact** via
  `gh pr view <N> --json files`. This is TASK-022's lesson applied here: verify
  what is actually in the PR, not what the session believes it staged. Local
  state at check time is not necessarily what got pushed.

The allowlist becomes **data in one place** in the script, so prose and
enforcement cannot drift apart again.

## Honest ceiling

A script cannot stop a model from typing `gh pr merge` anyway. What this
delivers is: a mechanical answer that fails closed, a prose contract requiring
it, and a record that shows afterwards whether it ran. Same ceiling as
TASK-022, stated the same way — a hardened convention with an artifact trail,
not an enforced one. Real enforcement needs branch protection on the remote,
which is the consumer's repo setting and outside this Element.

## Acceptance criteria

- [x] `spec-gate` accepts an all-spec change set and rejects any set containing
      a non-allowlist path
- [x] `--pr <N>` reads the pushed file list, not local state
- [x] Exits non-zero and names every offending path
- [x] No bypass environment variable
- [x] An unreadable PR or missing `gh` is an error, never a pass
- [x] The allowlist is defined once, in the script
- [x] Both skills require it before merging; Exception 2 says it is mechanical
- [x] All four gates green
