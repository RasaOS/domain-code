---
name: land
description: Get a skill's outputs onto the trunk the way their class allows, always from the latest trunk. Doc outputs (audits, decisions, postmortems, retros, lessons, handoffs, exports, the task ledger) land by themselves through a short-lived land/ branch cut from the freshly fetched trunk, a PR, CI, and a merge pinned to the verified head, so a document is never lost in a working tree. Code, and anything agents load as instructions (CLAUDE.md and what it imports, .claude/, .github/), goes through a PR that the skill never merges. Also syncs branches with the trunk (fast-forward on the trunk, merge on a branch, never a rewrite) and installs the guard that keeps the trunk PR-only for Claude. Called at the end of other skills; triggered directly by "/land", "land this audit", "get these docs into main", "sync with main", "why didn't my audit land", "is the trunk protected".
---

# /land — nothing lost, nothing straight in

Two failures this skill exists to stop:

- **A document that never reaches the trunk.** An audit, a decision or a
  plan left uncommitted in one session's working tree is gone when the
  container is. Docs do not change behaviour, so there is no reason for
  them to wait on anyone: they land by themselves.
- **Code that reaches the trunk without a PR.** Code, CLAUDE.md, rules,
  hooks and workflows go through a pull request that the skill which
  wrote them never merges. The trunk only moves through a merged PR.

And one rule both share: **whatever merges or is proposed is built on
the latest trunk.** Every landing fetches first, cuts from
`origin/<trunk>`, and brings the trunk in again before it merges.

## The two classes

`land.py` decides, and nothing else does. Project config
(`.claude/landing.json`) can make docs wait for a person
(`"docs": "pr"`); it can never widen the class.

| Class | Paths | How it lands |
|---|---|---|
| **docs** | `docs/{audits,decisions,postmortems,retros,notes,handoff,blast-radius,scope,exports,regrets,mvp,wrangle}/**/*.md`, `docs/glossary.md`, `tasks/**/*.md`, `tasks/history.tsv` | `land.sh docs`: merges itself after CI |
| **code** | everything else, and always: any `CLAUDE.md` / `AGENTS.md`, anything CLAUDE.md `@`-imports (e.g. `docs/notes/INDEX.md`), `.claude/**`, `.github/**`, `tasks/tasks.config.yml`, `tasks/proto/**`, `docs/proto/**`, symlinks | `land.sh pr`: a PR the skill never merges |

`bash .claude/skills/land/land.sh classify <path>...` shows the class and
the reason for any path.

## Interface

```text
bash .claude/skills/land/land.sh docs --skill <name> --title "<what>" [--summary "<why>"] [--tasks "TASK-NNN ..."] -- <file>...
bash .claude/skills/land/land.sh pr   --skill <name> --title "<what>" [--tasks TASK-NNN] [--draft] [--summary "<why>"] [--verified "<commands + results>"] -- <file>...
bash .claude/skills/land/land.sh auto --skill <name> --title "<what>" [...] -- <file>...
bash .claude/skills/land/land.sh sync            # latest trunk into this checkout
bash .claude/skills/land/land.sh merge  --pr <N> --sha <sha> [--checks-json <file>]
bash .claude/skills/land/land.sh settle --pr <N>
bash .claude/skills/land/land.sh status
```

Name the files explicitly — the ones the skill wrote, and nothing else.
`auto` splits them: the docs land, the rest goes by PR.

Exit codes: `0` ok · `1` error · `2` usage · `3` refused (a code path
given to `docs`, a credential, an operation in progress) · `4` finish
with the session's GitHub tooling (no `gh`; follow `next=`) · `5`
conflict with the trunk (nothing pushed, files untouched) · `6` checks
failing or pending, or the merge was refused (the PR stays open) · `7`
the remote or the environment refused the push. Report the exit and its
message; never retry a `3`, `5` or `7` blindly.

## What `land.sh docs` does

1. **Fetch** the trunk with an explicit refspec.
2. **Classify** every file; any code-class file refuses the landing.
   A credential-shaped string refuses it too.
3. **Build the change without touching your checkout**: a commit made
   with plumbing from the files' current content, replayed onto the
   fresh trunk in a hook-less scratch worktree. Ledger files
   (`tasks/history.tsv`, `ROADMAP.md`, `AUDIT.md`) merge line by line;
   `history.tsv` is kept in date order. A conflict stops here (exit 5)
   with nothing pushed. A change that would add a `check-tasks` error
   to the trunk (a task id the trunk already used) stops here too.
4. **Push** `land/<skill>-<utc>-<hex>` and open a PR (manifest
   `kind: chore`, label `docs-land`).
5. **Verify the pushed commit by git alone**: the PR's head is exactly
   what was pushed, every file in it (both sides of any rename) is docs
   class, no symlinks, and it contains the latest trunk.
6. **Wait for CI.** Only a pass merges. "No checks reported" is never a
   pass while the trunk has a workflow that runs on pull requests.
   Failing, or still pending after `check_wait_secs`, leaves the PR open
   (exit 6); `land.sh merge` finishes it later.
7. **If the trunk moved**, merge it into the land branch (never a
   rewrite), push, and wait again (at most three rounds).
8. **Merge** `--squash --delete-branch --match-head-commit <sha>`. A
   branch-protection refusal leaves the PR open. Never `--admin`.
9. **Settle**: once the content is on the trunk, bring your checkout up
   to date (fast-forward on the trunk; merge the trunk in on a branch).
   Copies are saved first; a file you changed after landing is left
   alone and reported.

### Without `gh` (cloud sessions)

Every gate above except CI status is checked by git, so it still holds.
The hand-off is exact:

1. `land.sh docs …` → exit 4, `next=open-pr`, with `branch=`, `head=`,
   `title=`, `body_file=`. Open the PR with the session's GitHub tooling
   (base the trunk, head the branch, that title and body); add the
   `docs-land` label.
2. Read the PR's check runs (e.g. `pull_request_read` `get_check_runs`,
   and `get_status`) into files, then
   `land.sh merge --pr <N> --sha <head> --checks-json <file> [--checks-json <file>]`.
   Exit 6 → not green yet (or the branch was synced: read the checks
   again with the new `head`). Exit 4 with `next=merge` → merge the PR
   with the session's tooling, `merge_method: squash`, and
   `expectedHeadSha` exactly as printed.
3. `land.sh settle --pr <N>` — checks by git that the content is on the
   trunk, updates your checkout, deletes the land branch.

## What `land.sh pr` does

On the trunk it cuts a branch from the fresh trunk and carries your
uncommitted changes onto it (`task/<ID>-<slug>` with `--tasks`, else
`chore/<skill>-<slug>-<utc>`); on a branch it stays. It commits only the
named files, merges the latest trunk in (a merge, never a rebase or a
force), pushes, and opens a PR (`--draft` for autonomous skills) with a
merge manifest saying `merge: manual`. An open PR for the branch is
reused. **It never merges.** `/peer-review`, `/auto-merge` or a person
does. For task work, `/open-pr` owns the ready PR (§10 body) and marks a
draft ready.

## Sync

`land.sh sync` brings the latest trunk into the checkout: a fast-forward
on the trunk, a merge on a branch. Local trunk commits that are not on
origin are refused: they must land through a PR. A conflicting merge is
undone and reported (exit 5). `land.sh fresh --sha <sha>` answers "does
this commit contain the latest trunk?" for merge gates, and
`land.sh sync-pr --branch <b>` merges the trunk into a PR's branch
without touching the checkout.

## The guard — the trunk is PR-only for Claude

`bin/init` runs `land.sh hooks` on every install and `/sync`:

- **git pre-push** (armed again at every session start, so fresh cloud
  clones have it): refuses a push that would move the trunk on origin
  (matched by URL, so another remote name is caught) when `CLAUDECODE=1`.
  People pushing from their own terminal are not constrained here.
  The first push of the trunk to an empty remote is allowed.
- **PreToolUse Bash**: refuses what would switch that off or go around
  it — `--no-verify`, `commit -n`, `core.hooksPath`,
  `GIT_GUARD_ALLOW_MAIN`, writes under `.git/hooks`, `git push
  --all/--mirror`, repository writes through `gh api` — and the plain
  trunk pushes (`git push origin main`, a bare push on the trunk).
  Tags, branch pushes and PR merges pass.
- **PreToolUse GitHub tools**: `push_files`, `create_or_update_file`
  and `delete_file` on the trunk (or with no branch) are refused.

**The honest ceiling.** A hook sees what a tool call says, not what it
means; a determined enough command can get around it. The server is the
real guard: a ruleset on the trunk that requires a pull request.
`land.sh status` reports whether the trunk has one; to add it:

```bash
gh api -X POST repos/{owner}/{repo}/rulesets --input - <<'JSON'
{"name":"trunk: PRs only","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
 "rules":[{"type":"pull_request","parameters":{"required_approving_review_count":0,
   "dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,
   "require_last_push_approval":false,"required_review_thread_resolution":false}},
   {"type":"non_fast_forward"},{"type":"deletion"}]}
JSON
```

## Composed runs

When a skill runs as a step of `/mission`, `/self-heal` or
`/self-improve`, it does **not** land on its own: the orchestrator's
branch and PR carry its files. Land once, at the end, from the
outermost skill.

## What you must NOT do

- **Don't commit, push or merge to the trunk yourself.** Docs:
  `land.sh docs`. Code: `land.sh pr` or `/open-pr`.
- **Don't pass files the skill did not write.** Name each one.
- **Don't retry past a 5 or 7.** A conflict needs `land.sh sync` and a
  fresh look; an environment refusal needs the fallback it names.
- **Don't merge a land PR with other tooling before `land.sh merge`
  says `next=merge`**, and always with the `expectedHeadSha` it printed.
- **Don't edit `.claude/landing.json` to push code through `docs`.** It
  cannot widen the class, and trying is the wrong fix.

## What "done" looks like

Every file the skill wrote is either on the trunk (docs: merged PR,
checkout settled) or in an open PR that a reviewer will merge (code),
and the report says which, with the PR link, or names the exit code and
what is still open.
