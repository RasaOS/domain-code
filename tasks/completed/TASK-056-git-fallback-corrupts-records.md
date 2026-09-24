---
id: TASK-056
type: defect
created: 2026-09-21
created_by: chazzcoin
updated: 2026-09-21
phase: P1
completed_by: chazzcoin
x-origin: manual
x-outcome: shipped
x-owner: unassigned
---
# TASK-056: `$(cmd || echo unknown)` corrupts two ledgers

**User story.** As an **auditor**, I want **every ledger record to be
well-formed** so that **the audit trail is parseable and not silently malformed**.

## The bug

`git rev-parse --abbrev-ref HEAD` on a repo with **no commits** prints `HEAD`
to stdout *and then* exits 128. So the idiom `$(cmd || echo unknown)` **appends**
the fallback rather than replacing the value, and the record gets a stray bare
`unknown` line inside its frontmatter:

```
sha: unknown
branch: HEAD
unknown          <- not a key. Malformed YAML, inside an audit trail.
user: T
```

Reproduced through the real `deploys.sh`: 1 malformed frontmatter line.

Precise scope, which matters for the fix: `--short HEAD` fails **cleanly** —
it prints nothing to stdout — so `sha:` was always fine. Only `--abbrev-ref`
prints before failing. Both are written defensively anyway, since the next
person to copy the idiom will not know the difference.

## Sites

- `content/skills/deploys/deploys.sh:143-144`
- `content/skills/env-sync/env-sync.sh:191-192`

`runs.sh` had the same idiom — copied from `deploys.sh` — and was fixed in
TASK-020 when a fresh-repo test caught it. These two were left, and the fix is
the same shape: assign first, test the exit status second.

## Bookkeeping note

TASK-020's commit message says this was "filed separately rather than folded
in". **It was not filed** — I wrote that and did not do it, and the claim shipped
in a released commit (`d3a055a`, tag `v0.50.0`). This task is that filing,
after the fact. The lesson is narrow and worth keeping: a commit message that
promises follow-up is a claim like any other, and it is only true once the file
exists.

## Verified

| | |
|---|---|
| no-commit repo, before | 1 malformed frontmatter line |
| no-commit repo, after | **0**, `sha: unknown` / `branch: unknown` |
| after a real commit | `sha: 3f96e98` / `branch: master` |

## Acceptance criteria

- [x] Both sites assign-then-test instead of `\|\| echo unknown`
- [x] 0 malformed frontmatter lines on a repo with no commits
- [x] Correct sha/branch once the repo has a commit
- [x] `check-bash32` 0, all four gates green
