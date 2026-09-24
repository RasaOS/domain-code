# Code task rules — the engineering extension

`rasa.domain.code`'s addition to the task lifecycle. It extends
`.claude/task-rules.md` (the portable spine, vendored from
`rasa.module.tasks` v1.0.0) through the seam that file's §16 names:
`.claude/<domain>-task-rules.md`. It **adds**; it never overrides. Where the
two seem to disagree, the spine wins and this file has a bug.

Read in this order, before starting a task:

1. `.claude/task-rules.md` — how tasks move, what the frontmatter holds, the
   invariants `.claude/bin/check-tasks` enforces.
2. **this file** — what those stages mean when the work is software.
3. `.claude/done-gate.md` — what `review/` → `completed/` requires here.
4. `CLAUDE.md` — the project's actual build, test and run commands.

## 1. Where the other engineering rules live

| read | when |
|---|---|
| `ios-task-rules.md`, `web-task-rules.md`, `python-task-rules.md` | the work touches that platform. The prefix is a discovery hint, not a gate: every project pulls every file, each session reads the ones that apply, and cross-boundary work reads both. |
| `craft-rules.md` | before writing code — build it right, no copy-paste, no magic strings, no dead code, no premature abstraction |
| `script-craft.md` | before writing or changing a script a skill ships |
| `output-styles.md` + `output-rules.md` | when producing a structured report |
| `git-flow-rules.md` | any task touching branches, merges or deploys |
| `release-rules.md` | shipping a release or auditing dependencies |
| `batch-handoff.md` | wrapping a phase or a batch of tasks |
| `vocabulary.md` (+ `vocabulary-overrides.md`) | before assuming what a term means |
| `task-enforcement-rules.md` | how "every change is task-linked" is enforced (§6) |

## 2. What the stages mean in software

| stage | here | how it gets there |
|---|---|---|
| `triage/` | filed, not planned | `.claude/bin/task new --type T "<title>"` |
| `backlog/` | planned into a phase | `task graduate <id> --phase P` |
| `active/` | a branch is being worked (no PR, or a draft) | `task start <id>` |
| `review/` | **the PR is open and ready**; the done-gate has not passed | `task submit <id>` when the PR opens |
| `blocked/` | an external dependency stops it | `task block <id>`, with a `## Blocker` |
| `completed/` | the done-gate passed **and the PR merged** | `task pass <id> --by <who>` |
| `closed/` | ended without being done | `task close <id> --resolution R --by <who>` |

The old rule "an open-but-unmerged PR stays in `active/`" is retired: that is
precisely what `review/` is for. A PR sent back for changes is
`task reject <id> --note "<what the reviewer asked for>"`.

Never move a task file with `git mv` or a plain `mv`, and never write
`status:` — it is a hard error (I-10). The directory is the state and
`bin/task` is the only thing that changes it. A hand-move is caught by I-33.

Editing a task's **body** by hand is normal — ticking a criterion, writing
notes, the completion report. Afterwards run `.claude/bin/check-tasks --fix`:
the validator keeps a digest of every task, and a file that changed while
its `updated` did not is an error (I-34) until `--fix` bumps the date and
accepts the new content. Run it before `submit` and before `pass`; a gate
that fails on your own edit is still a failing gate.

## 3. Types, for software work

| type | in this domain | was (≤ v0.52) |
|---|---|---|
| `change` | a feature, a behavior change, a refactor with a visible outcome | `spec`, `stub` |
| `defect` | something is broken; the fix | `bug`, `hotfix` |
| `upkeep` | a dependency bump, a cleanup, a chore that changes no outcome | `chore` |
| `inquiry` | a spike, an audit, an investigation — the deliverable is an answer | `audit` |
| `record` | an ADR, a handoff, a runbook — the deliverable is a document | `docs`, `handoff` |

Depth is no longer a category. A task is a stub until its
`## Acceptance criteria` holds a real checkbox; `/task` expands it close to
execution (`.claude/skills/task/expanding-a-task.md`), not at filing.

## 4. Hotfixes

A hotfix is a `defect` with `priority: now`. There is no `HOTFIX-` id space
any more — it forced a reference-breaking rename every time the urgency
passed.

- File it straight into work: `task new --type defect --priority now
  --phase <P> "<what is broken>"`. `priority: now` routes it to `active/`
  (I-14); the phase is the one whose functionality is broken.
- Branch: `hotfix/TASK-NNN-slug` (`git-flow-rules.md` Rule 1).
- The body carries what is broken in production, the smallest fix, the
  rollback plan and the post-fix verification — the `defect` template has
  the sections.
- It ships with a 🔥 `tasks/AUDIT.md` entry and a postmortem (§13).
- If the urgency passes before it ships, drop the priority to `high`. The id
  never changes.

## 5. Scope: one task, one PR

- One task is one PR. Do not bundle unrelated changes.
- Touch only the files in the task's expected-files list. To touch another,
  add it to the task file with a one-line reason **first**.
- No refactoring adjacent code "while you're in there", and no features,
  abstractions or configuration the acceptance criteria do not require.

## 6. Every change is task-linked

Every change to source code and to runtime or user-facing configuration is
linked to a task (task-rules.md §12) — the planned feature, the one-line fix,
the change made under pressure. Documentation, the task files themselves and
`.claude/` meta are exempt, except the paths
`.claude/task-enforcement.json#classify.audit_anyway` names.

How it is enforced here:

- **`/task-enforce`** (a `PreToolUse` hook) denies an unlinked code edit
  once, files a task with `.claude/bin/task new` into `triage/`, links it,
  and lets the retry through. Ships off in an existing project, on in a new
  one; see `task-enforcement-rules.md`.
- **`/task-guard`** (a git pre-commit hook) does the same at commit time,
  staging the new task and its `tasks/history.tsv` line into the commit.
- **The change ledger** — `tasks/changes/<day>-<task>.md`, indexed into
  `tasks/CHANGES.md` — records every path each task touched. It lives under
  `tasks/` but outside the seven stage directories, so the validator lists it
  as information (I-01) and leaves it alone.

An auto-filed task carries `x-origin: auto-fallback` or `x-origin:
auto-guard`, and a title derived from a filename rather than intent. Rewrite
the title and graduate it, or close it. Never bypass either hook with
`--no-verify` or its equivalent.

## 7. Frontmatter keys this domain adds

The spine allows any `x-` key and interprets none. This domain uses four:

| key | values | meaning |
|---|---|---|
| `x-origin` | `manual` `auto-fallback` `auto-guard` | who filed it; absent means `manual` |
| `x-owner` | a handle | the accountable person or team — not the per-run actor |
| `x-outcome` | `shipped` `reverted` | what happened after `completed/`; absent means not recorded |
| `x-severity` | `critical` `high` `medium` `low` | for a `defect`, how bad — urgency is `priority` |

Write them with `.claude/skills/task-enforce/task-enforce.sh stamp <id>
<key> <value>`, which also bumps `updated` and re-records the task's digest,
so the write never trips I-34. Never hand-edit a key the spine owns: `id`,
`created`, `created_by`, `updated`, `completed_by` and `resolution` are
written by `bin/task`, and `phase` by `graduate`.

`needs:` is the only dependency field (spine §8). The old `blocked_by:` is
gone — list the ids under `needs`, and use `blocked/` for an external stop.

## 8. Schema discipline

When the project mirrors a schema another team or platform owns — Realm
models, protobufs, an OpenAPI spec, a partner API — then:

- **The canonical source owns the schema.** Field names are byte-identical to
  its definition.
- **Never invent, rename or "correct" a field.** If a name is not in the
  project's mirror models or the task's source, stop and write a blocker.
- **Never modify the schema-registry file** `CLAUDE.md` names (a `paths.js`,
  `types.ts`, `schema.go` or similar) without a referenced source of truth.

`CLAUDE.md` says whether the project owns its schema or mirrors one. If it
owns it, this section is informational.

## 9. Files that need permission to change

Spine §13 makes touching a gated artifact a blocker, not autonomous work, and
leaves the list to the domain. In software it is, at minimum — `CLAUDE.md`
names the project's own additions:

- **Infrastructure and deploy config** — `firebase.json`, `*.tf`, CI
  workflows, `Dockerfile`, hosting config.
- **Security and secrets** — `.env`, `.env.example`, security rules, IAM.
- **Dependency manifests** — `package.json`, `Cargo.toml`, `go.mod`,
  `Gemfile`, `pyproject.toml`, `Package.swift` — adding, upgrading, removing.
- **Build and runtime config** — `vite.config.*`, `webpack.*`,
  `tsconfig*.json`, `babel.config.*`.
- **The process itself** — `CLAUDE.md`, `.claude/task-rules.md`, this file,
  `.claude/done-gate.md`, `.claude/task-templates/`, `.claude/bin/`,
  `.claude/skills/`, `.github/`, `.git/`.

If a task needs one of these, say so in its `## Blocker` and stop.

## 10. Branches, PRs and the completion report

- **Branch:** `task/TASK-NNN-short-slug`; `hotfix/TASK-NNN-slug` for a
  `priority: now` defect; `chore/<slug>` only for work that is genuinely not
  a task.
- **Commits:** match the repository's style — usually a one-line summary, a
  blank line, a body saying *why*, and a `Co-Authored-By` trailer. Check
  `git log` first.
- **PR title:** `TASK-NNN: <task title>`.
- **PR body:** the task path; the acceptance criteria with ☑/☐; the files
  changed against the expected list, deviations called out; "How I verified"
  with the commands and their output.
- **When the PR opens,** `task submit <id>`. The task is now in `review/`.

The completion report (spine §11) goes into the task file before `pass`. In
this domain its table carries four more rows:

```markdown
| **Branch** | `task/TASK-NNN-slug` |
| **PR** | [#N](url) |
| **Tests** | full headless gate: <count> green · <time> — focused run: ✅/❌ |
| **Build** | clean / <new warnings> |
```

Test results are real numbers from the run, never "tests pass". A chore PR
uses the same shape; "What changed" may be one line.

**Two moments, one table.** When the PR opens (`submit`), post the table in
chat as the hand-off — Branch, PR, Tests, Build, what changed, what the
reviewer should do next — so the reviewer reads it in five seconds and
decides whether to dig in. The task is in `review/`; nothing is *done* yet,
so there is no Outcome row. The completion report proper — with its Outcome
of done / blocked / failed and the done-gate results — goes into the task
file when the gate is run, before `pass`.

**Iteration versus gate.** While working, run only this task's test in the
project's focused mode. Before `submit`, run the unfiltered headless command
once. If a gate fails and cannot be fixed in scope, block the task — do not
disable tests and do not bypass hooks.

## 11. Filing: stub first

When someone says "add a task" with no stated urgency, file it
(`task new --type T`) and stop. Do not promote it ahead of other work, draft
a full spec, reshuffle the roadmap, or split it into siblings.

A full spec is written at filing time only on an explicit signal —
"emergency", "urgent", "do it now", "needs to ship before X", "this is next
up", "top priority". "Needs to ship before X" places it ahead of X on the
roadmap; "for a future phase" or no qualifier places it at the back. When
unsure: *"backlog only, or should this jump the queue?"*

## 12. The audit log

`tasks/AUDIT.md` is the curated, append-only record of meaningful actions.
Git log is the ground truth; this is the readable layer on top. Newest first
within `## YYYY-MM-DD` sections; one to a few lines per entry, receipts last
(PR, tag, SHA); never backdate — log late with `(retroactive)`.

| log | emoji |
|---|---|
| every tagged production release — version, tag SHA, integration PR | 🚀 |
| every task that reaches `completed/` | 📦 |
| a change to the task rules, this file or the done-gate | 📜 |
| major scaffolding — a new convention or tool that affects everyone | 🏗 |
| every hotfix release, linked to its postmortem | 🔥 |
| incidents and honest trade-off calls | ⚠️ |

Not every commit, not behavior-free refactors, not drafts that never ship.
Every batch's closing report is the prompt to update it.

## 13. Postmortems

The spine (§16) requires an incident write-up and leaves its home to the
domain. Here:

- **When:** any production outage or rollback; every hotfix; any data loss,
  corruption or mis-stamp; any regression found in production rather than
  before deploy; a near-miss that exposed a real gap. A bug caught in review
  or by the test gate needs none — that is the system working.
- **Where:** `docs/postmortems/YYYY-MM-DD-short-slug.md`, drafted with
  `/postmortem`.
- **Linkage:** a ⚠️ entry in `tasks/AUDIT.md` linking the file; a hotfix
  postmortem also links its 🔥 entry.
- **Action items become tasks,** filed immediately with `task new`. A
  postmortem with no action items is a story.

## 14. Orchestrator notices

If the project is one repo of several (`CLAUDE.md` "Macro architecture"), an
orchestrator may drop read-only coordination files into `.claude/` —
`.claude/active-*.md`, e.g. `active-migrations.md`.

- Read every `active-*.md` at session start and surface open entries; re-read
  at task start.
- Treat them as authoritative. If this repo's part has shipped, update the
  orchestrator, not the file here.
- Never hand-edit, delete, or copy their state into this project's files.

`/migration`, which writes them, is an orchestrator skill this Element does
not ship, so `bin/check-invocations` lists it as dangling; that is expected.
With no orchestrator (`n/a — solo project`), any `active-*.md` is stale —
flag it, do not act on it.

## 15. The parade

When a reviewer is ready to test a stack of tasks by hand, they run the full
verification suite in its watched / headed mode, unfiltered, so every test
plays in sequence. Do not redirect them to "just the new test" — the whole
parade is how regressions across tasks get caught. The focused mode is for the
inner loop, not final review.
