---
id: TASK-018
category: spec
phase: P2
status: active
---

# TASK-018: Define the task and run record shape

**User story.** As an **operator**, I want **every task to carry who is
accountable and how the work ended up, and every agent run to leave its own
record** so that **the system produces evidence about itself**.

## The stub's hypothesis was wrong

The stub said: adopt the proposed task-stamp fields and "extend them with
`actor`, `actor_kind`, `run_id`, `outcome`, `attempts`." Recon killed that on
**arity** — run and task are many-to-many, verified in shipped files:

- **One run spans N tasks.** `mission/SKILL.md:151-158` loops over every
  decomposed TASK-NNN and `:209-215` renders exactly ONE report. A mission that
  stops at a gate on task 7 of 9 would fan one `outcome` across 9 task files,
  false for 8 of them.
- **One task spans N runs.** `task-rules.md:297` is an explicit cycle:
  `active/ ⇄ blocked/`. A single-valued `run_id` on the task is overwritten by
  attempt 2, destroying attempt 1 — precisely the history this program exists
  to compute from.

Two facts close it:

- **A field written at the end of a run records nothing when the run is what
  died** — and silently-dead runs *are* the escape rate. `deploys.sh:119-164`
  opens a record `status: in-flight` *before* the work and seals it after; its
  header documents the measured bug that forced record-as-reservation (8
  back-to-back deploys left 2 records while `check` reported "consistent").
- **The Element already decided this once, against the task file.**
  `task-enforce.sh:231-247` writes activity to `tasks/changes/$day-$task.md`,
  keyed per (day, task), because "a single append-only file conflicts on every
  PR."

## The split

- **Task frontmatter** — durable, single-valued properties of the *task*:
  `id`, `category`, `status`, `phase`, `owner`, `blocked_by`, `outcome`,
  `filed`, `origin`, `severity`.
- **Per-run record** at `tasks/runs/<RUN-id>.md` — `actor`, `actor_kind`,
  `run_id`, `kind`, `started`/`finished`, `status`, `outcome`, `gate`, `sha`,
  `branch`, `task_refs`, `duration_s`.

`tasks/runs/`, **not** a top-level `runs/` — two blockers verified.
`task-enforcement.json` exempts `tasks/**` but `classify_path` defaults to
`code`, so a top-level `runs/` would have every run-record write **denied** in
every consumer — and that config is `skip-if-exists`, so a fix would never
reach the ~9 existing installs. Separately `git-clean.sh:72-73` excludes only
`deploys/`, `build/deploy-log.md` and `tasks/`, so a top-level `runs/` would
fail `/mission`'s own preview deploy on the record it just wrote. Under
`tasks/runs/` both are zero-change. Not `deploys/records/` either —
`deploys.sh:226,260` glob `???-*.md` and would swallow `RUN-` files into the
ship-log table.

**`attempts` is not stored.** It is `count(run records whose task_refs contains
TASK-NNN)` — derived, race-free, and correct for runs that never closed. A
stored counter needs a read-modify-write per run, the race both `deploys.sh:26-29`
and `task-enforce.sh:144-172` document being bitten by in this repo.

**`outcome` exists at both levels deliberately.** Task-level answers "how did
this work end up" (`unrecorded`/`shipped`/`reverted`/`superseded`); run-level
answers "how did this episode end"
(`completed`/`stopped-at-gate`/`failed`/`abandoned`).

## Scope corrections to the proposed set

- **Drop `name`** — the filename is identity; `task-enforce.sh:162-168` parses
  the id from the basename and a disagreeing `id:` is ignored.
- **Drop `priority`** — collides head-on with the existing "priority signal
  rule" (`task-rules.md:668,685`), which means spec *depth*, not rank.
  Ordering already lives in ROADMAP list order.
- **Keep `blocked_by`** — a task-graph edge, distinct from the mandatory
  `## Blocker` prose section, which names an *external* dependency.
- **Rename `assignee` → `owner`**, reserving `actor` for the run layer so
  TASK-019's `RASA_ACTOR` cannot collide.
- **Add `category`** — the proposed block predates it. Adopting the proposed
  set literally would have been a data-loss bug.

## Why this cannot be documentation only

`contract.sh:151-163 fm_set` is the Element's only frontmatter writer and it
has **no insert branch**. Verified by running it: `fm_set <task> outcome
shipped` returned **exit 0 with the file byte-identical** (md5 unchanged), and
on a file with no `---` block it also returned 0 and wrote nothing. Defining
`outcome` on top of that reproduces exactly the rendered-not-written failure
the audit named. So this task ships one mechanical writer:
`task-enforce.sh stamp <id> <key> <value>`, a real upsert that fails loudly on
a file with no frontmatter.

## Four incompatible task shapes ship today

| Writer | Emits | Lands in |
|---|---|---|
| `task-enforce.sh:188-196` | real frontmatter (incl. undocumented `filed`, `origin`) | `tasks/backlog/` |
| `task-guard.sh:162-188` | **no frontmatter** — `**Status.** STUB` body lines | `tasks/active/` |
| `/mvp` `SKILL.md:244-252` | **no frontmatter** — `**STATUS**: STUB` | `tasks/backlog/` |
| `/prototype` `SKILL.md:234-242` | **no frontmatter** — `**Status**: STUB` | `tasks/proto/<slug>/` |

`/mvp` is the first skill a greenfield repo runs, so *untracked-by-construction
is the default starting state of every new repo in the fleet.* A stamp adopted
only in the frontmatter block would be a lie for half the auto-minted corpus.

## Execution order

1. **Prerequisite** — anchor the three task-title parsers below frontmatter
   (`status.sh:344`, `dashboard.py:361`, `release.sh:574`). Until then, a
   frontmatter comment line starting `#` is read as the task title.
2. The shape — `stamps.md` (task + run models), `task-rules.md`, 4 templates
3. The writer — `task-enforce.sh`: `mint_stub`, the `origin` counter, `stamp`
4. The other minters — `task-guard.sh`, `/mvp`, `/prototype`
5. Prose — `release-add`, `mission`, `task`, `spec-phase`
6. 0.50.0 + install smoke test

## Acceptance criteria

- [ ] All three title parsers ignore frontmatter; verified against a fixture
      whose frontmatter contains a standalone `#` line
- [ ] `stamps.md` carries adopted `## Stamp: task` and `## Stamp: run`; the
      `### task (proposed…)` block is gone
- [ ] All four templates carry the adopted keys, readable by `deploys.sh`'s
      `field()` helper
- [ ] `task-enforce.sh stamp` inserts a missing key (md5 changes), rewrites an
      existing one, refuses an unknown key, and **exits non-zero** on a file
      with no frontmatter
- [ ] `task-guard.sh` emits real frontmatter with `origin: auto-guard`, and
      `release.sh`'s `_title_for` returns non-empty for it (returns empty today)
- [ ] `/mvp` and `/prototype` stubs carry frontmatter
- [ ] Every new field is **optional** with a declared absence-default
      (MINOR per `CHANGELOG.md:5-9`; required fields would be MAJOR)
- [ ] `check-manifest` 184 unchanged, `check-bash32` 0, `check-invocations` 0,
      `bin/lint` **0** — the baseline is green as of TASK-055 and must stay so

## Out of scope

`runs.sh` and any run-record writer (TASK-020). `RASA_ACTOR` threading
(TASK-019). The telemetry Element (TASK-021). This task defines the shape and
makes the *task* half real.
