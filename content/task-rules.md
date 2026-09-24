# Task rules — `rasa.module.tasks` v1.0.0

The law for every task under `tasks/`. The same law for a software project,
a law firm, a clinic and a novelist: nothing here assumes a version-control
store, a toolchain, or the vocabulary of any one trade.

Three seams carry everything that is *not* portable. This file names them
and never speaks for them:

| seam | owner | holds |
|---|---|---|
| `.claude/done-gate.md` | the project | what "done" requires here |
| `.claude/<domain>-task-rules.md` | the domain | extra discipline this domain needs |
| `tasks/tasks.config.yml` | the project | its actors, its targets, its id series |

Read this file first, the extension second. An extension *adds*; it never
overrides. A project with neither file is fully valid.

Two commands, installed at `.claude/bin/`:

- **`bin/task <verb> <id>`** — the only sanctioned way to move a task.
- **`bin/check-tasks [--fix]`** — the enforcement layer. Run it before you
  call anything finished. `--fix` repairs the mechanical subset; it never
  invents a date and never invents a person.

Every rule below is marked either **`I-nn`** — the invariant `bin/check-tasks`
enforces it under, and prints by that id — or **judgement**, meaning no
machine can settle it and a person must. There is no third kind. A rule with
no check and no admission that it needs a person is a rule that gets broken
quietly, and v0.1.x was full of them.

## 1. The directory is the state

```
tasks/intake.md → triage/ → backlog/ → active/ → review/ → completed/
                                ↕          ↕        ↕
                                └──── blocked/ ─────┘
                     (any state) ──────────────────→ closed/
```

| directory | meaning | `phase:` |
|---|---|---|
| `triage/` | filed, has an id, nothing promised yet | forbidden (I-19) |
| `backlog/` | phased, not started | required |
| `active/` | in flight | required |
| `review/` | work finished; **the done-gate has not passed yet** | required |
| `blocked/` | cannot proceed; enterable from backlog, active or review | required |
| `completed/` | terminal — the done-gate passed | required |
| `closed/` | terminal — ended **without** being done | iff it ever had one |

`closed/` is the only stage with a conditional in that column, and the
conditional is forced. `closed/` is reachable from every stage including
`triage/`, and a task in `triage/` has no phase *by rule* (I-19). Requiring
one on the way out would mean inventing a phase for work that was never
planned — filing "we are not taking this matter" under a phase of work, and
then listing it on the roadmap (I-22) as though somebody intended to do it.
So the phase is carried out of the stage the task was actually in, and a task
closed straight out of `triage/` carries none. The same holds for `target:`
(§5). Nothing else changes: the field is still forbidden in `triage/` and
still required everywhere a task is planned, worked, reviewed or finished.

**I-01** — a file is a task if and only if it is a `.md` file directly inside
one of those seven directories. Anything else under `tasks/` — your own
notes, a register, a sub-folder of source material — is left alone and
listed once as information. The ledger has exactly seven states and no
hidden eighth.

`review/` and `closed/` are new, and they are the two that make the model
honest. **`review/`** is where the done-gate runs; v0.1.x had nowhere to put
finished-but-unverified work, so it ordered that work to stay in `active/`
while also capping `active/` — two rules that cannot both be obeyed. It is
also the most domain-native state in the set: a partner's review, a clinical
sign-off and a manuscript cooling-off read are all literally this.
**`closed/`** keeps the terminal count honest, because `ls completed/ | wc -l`
is the number everyone reads and folding superseded, duplicated, obsolete and
abandoned work into it makes that number a lie. A task that actually got done
therefore carries no `resolution` field at all.

### Why `status:` no longer exists

v0.1.x recorded the state twice — the directory, and `status:` in the
frontmatter — and required them to agree. Measured across the installed base:
**`status:` disagreed with its directory in 301 of the 558 real task files,
and not one file was sitting in a directory nobody meant to put it in.**
(263 still disagree if you forgive the two spellings of the terminal state.
Either number is the same verdict.)

The distribution is the lesson. Nobody mis-files a directory, because moving
the file *is* the act of changing state. The frontmatter line is a second
write carrying no new information, so it gets skipped — and once skipped it
is indistinguishable from a deliberate value. Enforcing the old rule harder
means a validator whose first run prints 301 errors, which is a validator
someone deletes in week one. So the field is deleted, not policed: the
violation is now unrepresentable rather than merely detectable. **I-10** —
the key `status` is a hard error anywhere in a task file.

The principle generalises: **one fact, one home.** A fact is stored twice only
when it is immutable *and* machine-written. Hence no `title:` key (the H1 is
the title), no `blocks:` key (the inverse of `needs`, derived), and no depth
or category key (depth is derived from whether the acceptance criteria hold a
real checkbox).

## 2. Every move goes through `bin/task`

| from | verb | to |
|---|---|---|
| — | `new` | `triage/`, or `backlog/` with `--phase`, or `active/` with `--priority now` |
| `triage/` | `graduate --phase P` | `backlog/` |
| `backlog/` | `demote` | `triage/` (drops the phase) |
| `backlog/` | `start` | `active/` |
| `active/` | `park` | `backlog/` |
| `active/` `backlog/` `review/` | `block` | `blocked/` |
| `blocked/` | `unblock` | back to wherever it came from |
| `active/` | `submit` | `review/` |
| `review/` | `reject` | `active/` |
| `review/` | `pass --by WHO` | `completed/` |
| any | `close --resolution R --by WHO [--ref ID]` | `closed/` (keeps the phase it had; **from `triage/` it has none and none is assigned**) |
| `completed/` `closed/` | `reopen` | `active/`, `backlog/` or `triage/` (**to `triage/` it drops the phase**, as `demote` does) |

One verb does three things **in one act**: writes the conditional
frontmatter, appends a line to `tasks/history.tsv`, moves the file. That is
the whole fix for the 301 stale statuses — the separate, easy-to-forget
second edit no longer exists as a step a person can skip.

"Writes the conditional frontmatter" includes **deleting** what the
destination forbids, which is the half that gets forgotten. `demote` and
`reopen --to triage` remove `phase`, because `triage/` forbids it. `reopen`
out of either terminal removes `completed_by`, `resolution` and
`resolution_ref`, because a reopened task is not finished and must not
still say it was. Any verb that leaves one of those behind produces a file
`bin/check-tasks` rejects under I-19 or I-30 — which is the point: the
invariants are what keep the verbs honest.

Moving a file by hand still leaves a valid tree, and is caught by **I-33**:
the directory must equal the `to` of the task's last history line. `--fix`
reconciles it with a line dated today, actor `unknown`, note `reconciled`. It
will not fabricate the date you actually did it on.

## 3. The frontmatter contract

A whole file, valid exactly as printed. The table under it says what each
field means, so nothing here has to be explained on the line it appears on —
and nothing here *may* be, because a `#` after a value is part of that value:

```yaml
---
# A comment is a whole line. This one is fine; the same words written after
# a value below would become part of the value. Every key here is a key.
# The task is in active/: it carries a phase (so not triage/) and
# `priority: now` (so not backlog/ either — see I-14).
id: TASK-LIT-042
type: change
created: 2026-09-14
created_by: para1
updated: 2026-09-20
phase: DISC
target: [smith-v-acme]
priority: now
needs: [TASK-LIT-038]
x-matter_number: 2:26-cv-01187
---

# TASK-LIT-042: Amend the protective order for third-party production

## Acceptance criteria
- [ ] The amended order is filed and the third party has been served.
```

| field | required | values | written by | checks |
|---|---|---|---|---|
| `id` | always | `TASK-[SERIES-]NNN[a]` | `bin/task new` | I-04 I-05 I-06 I-07 I-08 |
| `type` | always | `change` `defect` `upkeep` `inquiry` `record` | a person, at filing | I-12 |
| `created` | always | `YYYY-MM-DD`, not future | the allocator, once | I-15 I-35 |
| `created_by` | always | an actor handle, or `unknown` | the allocator, once | I-17 I-18 |
| `updated` | always | `created ≤ updated ≤ today` | every `bin/task` write | I-16 I-34 I-35 |
| `phase` | `backlog/`…`completed/`; never `triage/`; optional in `closed/` | a phase id declared in `tasks/ROADMAP.md` | a person, at graduation | I-19 I-20 I-22 |
| `target` | iff targets declared, and then everywhere a phase is required | members of `tasks.config.yml#targets` | a person | I-25 |
| `completed_by` | in `completed/`+`closed/` | an actor handle, or `unknown` | `bin/task pass` / `close` | I-29 I-30 |
| `resolution` | in `closed/` only | `superseded` `duplicate` `obsolete` `wont-do` | `bin/task close` | I-29 I-30 |
| `resolution_ref` | iff superseded/duplicate | an existing id, not this one | `bin/task close` | I-29 |
| `priority` | no | `now` `high` `normal` `low` (default `normal`) | a person | I-13 I-14 |
| `needs` | no | existing ids, acyclic | a person | I-26 I-27 I-28 |
| `x-*` | no | anything | you | exempt from I-11 |

Filing costs a person **one typed value (`type`) and a title.** Everything
else is stamped, or typed once later at graduation.

- **I-02 / I-03** — the grammar is a deliberately small subset: one key per
  line, plain scalars or flow lists, no indentation, no block scalars, no
  anchors, no `null`, no duplicate keys. It parses without a third-party
  library, because a gate that needs one is a gate that does not run.
- **A value is the rest of the line, and `#` is a literal character in it.**
  A comment is a line that *begins* with `#` (leading whitespace is itself
  illegal, so it begins in column one). There is no trailing-comment syntax:
  `type: change    # the usual one` sets `type` to
  `change    # the usual one`, which then fails I-12 — and the same trap is
  waiting on `id`, on both dates, on `created_by`, on `phase` and on
  `priority`. Put the explanation on its own line above the field. The rule
  is the same in `tasks.config.yml`, which the same parser reads.
- **I-11** — an unrecognized bare key is an error; prefix it `x-` and it is
  legal, preserved, never interpreted. That is the only extension seam, and
  it is deliberately visible.
- **I-07 / I-08** — the filename is `<id>-<slug>.md` and the body's single H1
  is `# <id>: <title>`. The id appears three times; all three are
  machine-written, which is the one case where duplication is allowed.

## 4. `phase:` — and the rule it reverses

**This reverses a v0.1.x rule. Read it even if you knew the old ones.**
v0.1.x said: *ROADMAP.md is the sole registry; never record the phase in the
task file, because a second copy drifts.* **Replaced.** The installed base
ignored it — 522 of 558 real files carry a `phase:` key the old rules forbade
— because the phase is the first thing a reader of a task file wants and the
old design made them open a second document to get it. v1.0.0 keeps both
copies and proves they agree instead of forbidding one:

- **I-19** — `phase` is absent in `triage/`, present in `backlog/`,
  `active/`, `review/`, `blocked/` and `completed/`, and optional in
  `closed/` — present there iff the task had one before it was closed. Those
  are the three cases, and `closed/` is the only one that is not a flat
  yes-or-no, for the reason given in §1.
- **I-20** — the value equals, case-sensitively, a phase id declared by a
  `## Phase <id> — <name>` heading in `tasks/ROADMAP.md`.
- **I-22** — ROADMAP lists that task exactly once, under exactly that phase.
  The roadmap follows the **phase**, not the stage: a task with a phase is
  listed under it wherever it sits, and a task with no phase — anything in
  `triage/`, and anything closed straight out of it — is not listed at all.
  `--fix` inserts a missing line and removes a misplaced one, preserving the
  existing order: the order is the one you intend to work in, and is never
  resorted for you.
- **I-23 (warn)** — a ROADMAP line whose title text has drifted from the
  task's own H1.
- **I-24** — no dangling entries. Never auto-fixed; a line naming a missing
  file is either a lost task or a stale promise, and only you know which.
- **I-21 (warn)** — every phase heading has a scope paragraph. A phase with
  no scope is a label, not a plan.

A phase is a name, a scope paragraph saying what is in and what is out, and
an ordered list of tasks. Whether a task *fits* that scope is **judgement** —
the only part of the phase system no machine can check for you.

## 5. `target:` — what the work is for

The axis your project works along, declared by you in
`tasks/tasks.config.yml#targets`, never by this Element:

```yaml
targets: [intake, litigation, appeals]     # a firm, by practice
targets: [manuscript, screenplay]          # a novelist, by work
targets: []                                # a project with one surface
```

**I-25** — if that list is non-empty, every task that is required to carry a
`phase` carries a non-empty `target` drawn from it. That is `backlog/`
through `completed/`; in `triage/` a target is allowed but not demanded, and
in `closed/` it is carried iff the task had one. The axis is answered when
the work is taken on, and a matter you are declining is exactly the one that
is not on your declared list. If the list is empty or absent, `target` must
be absent everywhere: a value against an undeclared axis is an error, not a
shrug. Always a list, even with one member.

## 6. `type:` — what kind of work this is

| type | the deliverable | e.g. |
|---|---|---|
| `change` | something the project produces is different afterwards | draft a new clause; add a capability; rewrite a chapter |
| `defect` | something is wrong and must be corrected | a wrong citation; a miscalculated figure; a continuity error |
| `upkeep` | maintenance that changes no outcome | re-file old records; renew a subscription; tidy a naming scheme |
| `inquiry` | the deliverable is an answer, not an alteration | can we do this at all?; why did that take three weeks?; what does the statute require? |
| `record` | the deliverable is a document | a decision record; meeting notes; a procedure write-up |

**I-12** — required, one of the five, no unset and no legacy value. Every file
in the installed base mapped to a real one; the mapping is in
`tasks/MIGRATION-REVIEW.md`, written by `bin/migrate-tasks`.

**There is no urgent *type*.** Urgency is `priority: now`, which composes with
all five — an urgent `record` (a filing due in four hours) is now expressible,
which no category system here could say before. v0.1.x gave urgent work its
own id space; that forced a reference-breaking rename every time the urgency
passed, and it was never once used.

## 7. `priority:` — and `now` as a route

**`now` is a route, not a mood.** **I-14** — a task with `priority: now` may
not sit in `triage/` or `backlog/`. If it is genuinely now, it is being
worked, waiting on a gate, blocked, or finished. Anything else is a `high`.

Work filed without any stated urgency is `normal` and goes to the back: do
not re-order the phase list to make room, do not expand it into a full spec,
do not split it into siblings. Expand a spec close to execution, not at
filing. If you cannot tell whether something jumps the queue, ask — one round
trip beats a wrong placement. **Judgement.**

## 8. `needs:` — the only dependency field

Ids that must reach `completed/` before this one can. **I-26** they exist, are
well-formed, exclude this task, and do not repeat; **I-27** the graph is
acyclic and the error prints the cycle; **I-28 (warn)** a task in `completed/`
whose `needs` are not themselves finished.

No `blocks:` key — it is the inverse of `needs`, and derived. No "related"
key either: a link with no semantics is prose, so put it under `## Notes`.

## 9. The done-gate

A task is done when **both** are true:

1. **Its acceptance criteria are met** — every checkbox satisfied and
   *actually verified*, not assumed.
2. **The project's done-gate passes** — the contract in `.claude/done-gate.md`.

The done-gate is the one part of "done" that varies by domain, so it is the
one part this file refuses to state. Portable is only its shape and its
*position*:

- It runs on the `review/` → `completed/` transition. Nowhere else.
- Each gate is **objectively checkable** — something that either produced a
  result or did not, a named person who approved, a document that exists —
  never a feeling.
- If a gate cannot pass and you cannot make it pass in scope, the task is
  **not** done: block it (§10) or report it honestly (§12).
- **Never bypass the gate.** Whatever the mechanism, the equivalent of "skip
  the verification to finish faster" is forbidden.

If `.claude/done-gate.md` is absent the default gate is the minimum honest
bar — *every acceptance criterion is checked and a second person has
approved* — and running on the default is a smell, not a destination.
**Judgement**: no validator can read your gate for you. The checks nearest it
are I-29 (`completed_by` was recorded) and I-37 (a task reaching `review/` or
`completed/` with no real acceptance criteria is flagged).

## 10. `blocked/`

Blocked means an **external** dependency stops progress: a decision owed by
someone else, a person or party unavailable, access only someone else can
grant, an upstream task unfinished. Not blocked: "I don't know how" (recon),
"this is hard" (the work), "I lost the thread" (park it to `backlog/`).

**I-31** — a task in `blocked/` has a `## Blocker` section with at least one
real line under it. Say what is blocking, who or what would unblock it, and
when to check back. Without that section it is not blocked, it is abandoned,
which is a different problem and a worse one.

**I-36 (warn)** — a task sitting in `review/` more than 30 days. A state whose
exit depends on someone else is the state that becomes a graveyard; this is
the only ageing check there is.

## 11. The completion report

When a task passes the gate, the closer writes the report **into the task
file, as a `## Completion report` section, before `bin/task pass` moves it.**
v0.1.x mandated the report and never said where it went, so it went nowhere.
It lives with the task and travels with it.

```markdown
## Completion report

| | |
|---|---|
| **Outcome** | done / blocked / failed |
| **Type** | change / defect / upkeep / inquiry / record |

**Done-gate** (per `.claude/done-gate.md`)
- <gate>: pass/fail · <evidence — what was produced, who approved>

**What changed** — the actual deltas, one line each
**What to do next** (in order) — concrete actions
**Things I noticed** — not blockers; may be empty
```

- **Outcome is one of three words.** Never "almost", never "mostly". If the
  criteria are not met the outcome is blocked or failed, and the report says why.
- **Gate results are evidence, not adjectives.** Name the output, the
  approver, the document — not the word "verified".
- **Do not tick a box you did not check.**
- **"What to do next" is not optional.** It is why a reader opens the report.

**Judgement** — the validator checks `completed_by` (I-29) and warns on
missing acceptance criteria (I-37). It cannot tell whether your report is true.

## 12. Scope, honesty, and the task-linked rule

**Scope.** One task is one unit of finishable work; do not bundle unrelated
work. Touch only the artifacts the task names — to touch anything else, add
it to the task file with a one-line justification *first*. Do not improve
adjacent work while you are in there, and do not add scope the acceptance
criteria do not require. ("Artifacts" is deliberately neutral: source
documents, contract clauses, care pathways, manuscript chapters — whatever
this project produces.)

Keep `active/` small. v0.1.x said "at most one per worker"; v1.0.0 has no
owner field, so nothing can tell whether four active tasks are four people
working or one person thrashing. That makes it advice, and it is labelled as
advice instead of posing as a rule.

**Honesty.** If the acceptance criteria cannot all be met, the task is **not**
done: leave the boxes unticked, write the blocker, say so. If you find the
task's premise is wrong, stop and write a blocker — do not silently redesign
the work. Never mark verified what you did not verify; "verified" means you
ran the gate and watched it pass, not that it looks like it would.

**Every change is task-linked.** Every change to an artifact this project
produces, and to its operative configuration, is linked to a task — not the
planned work only, also the one-line urgent correction, also the change made
under pressure. The task is the audit trail; a change with no task is a hole
in the record nobody can review later. It does not apply to internal notes,
to the task files themselves, or to `.claude/`. A stub is acceptable, nothing
is not: the bar is "a task exists", not "a task is fully specified".

All three are **judgement**, the last one deliberately — how it is *enforced*
depends on how your project records changes, so the mechanism belongs in
`.claude/done-gate.md` or the domain extension. The rule holds whether or not
anything automated is wired up. v0.1.x mandated a `tasks/CHANGES.md` ledger
here and no layer ever created one; `tasks/history.tsv` (§15) now carries the
part that can be recorded mechanically.

## 13. Artifacts that need permission to change

Touching one of these is a blocker, not autonomous work: **this task system's
own files** (`.claude/task-rules.md`, `.claude/done-gate.md`,
`.claude/task-templates/`, any `.claude/<domain>-task-rules.md`, the project's
`CLAUDE.md`), and **whatever this project marks canonical or
high-blast-radius** — whatever it treats as its source of truth, its operative
configuration, anything under a compliance control. The done-gate or the
project's `CLAUDE.md` names them; this Element cannot know them. If a task
requires changing one, say so in its `## Blocker` and stop. **Judgement.**

## 14. Intake and triage

**`tasks/intake.md`** is the pre-triage capture layer: one file, dated H2
sections, one bullet per thought. No id, no file, no obligation beyond "I
wrote it down". Triage costs a real thing — an id is spent and never reissued
— so intake exists to cost nothing. When an entry matures, file it with
`bin/task new` and delete the bullet; an entry that will not become work is
just deleted, with no ceremony at all. That is the point of the layer.

**`tasks/triage/`** holds tasks that are tracked but not yet taken on: they have an id,
have no phase, and by **I-19** they must not have one. They are deliberately
absent from `tasks/ROADMAP.md`. Graduate with `bin/task graduate --phase P`,
which writes the phase and moves the file in one act; the ROADMAP line is
part of the same graduation, and if you leave it out I-22 says so and
`--fix` inserts it.
Work that will not be done goes `bin/task close --resolution wont-do --by WHO`
— `closed/` with the reason recorded, where v0.1.x sent it to a
`.claude/wont-do.md` that nothing ever created. **No `--phase` is asked for
and none is written**: the task never had one, `closed/` does not require
one, and the roadmap is left alone. That is the whole point of the
`closed/` exception in §1 — the ordinary triage answer has to be one
command with nothing invented, or the sweep does not happen. Sweep whenever
triage grows past what you can read in one sitting: graduate, or close.
Letting it grow is the failure mode; **judgement** on which is which.

## 15. The record

**`tasks/history.tsv`** — append-only, six tab-separated columns:

```
date	id	from	to	actor	note
2026-09-14	TASK-LIT-042	-	triage	para1	filed
2026-09-20	TASK-LIT-042	active	review	jmr
2026-09-23	TASK-LIT-042	review	completed	jmr	gate: partner sign-off 2026-09-22
```

Four things at once: the transition log; the audit trail a project with no
version-control store has never had; the corroboration for `created`,
`created_by` and `completed_by` (**I-35**); and the id-retirement ledger — an
id that appears here is never issued again, even if its file was deleted, so
an old reference can never silently resolve to unrelated work. **It is never
hand-edited.** **I-32** checks its shape, **I-06** that every task on disk
appears in it, **I-33** that every task's directory matches its last line.

**`tasks/.state/digests.tsv`** is a machine cache — regenerable, not yours to
edit. It exists to make one field honest: **I-34** records each task's
SHA-256, so a file that changed while its `updated` did not is a hard error.
No modification times are consulted (177 of the 558 real files share one
single modification date, so they carry almost no signal) and no version
history is read. That is what
makes `updated` a fact rather than a hope.

## 16. Domain extensions

Everything above is what is true of task management in *any* domain. A domain
that needs more adds `.claude/<domain>-task-rules.md` and points at it from
`CLAUDE.md`. What belongs there and not here: an engineering project's
verification commands and change-review conventions; a firm's matter-number
conventions, conflict checks, privilege handling and statutory deadlines as
gate items; a clinic's clinical-rule validation, protected-information
handling and sign-off; a writing project's continuity checks, reader pass and
rights clearance.

Incident write-ups are a seam too. This file requires one for: any operative
failure or harm event in this domain's terms; any correction that skipped the
normal route; any loss or corruption of records; any problem found *after*
the work was accepted rather than at the gate. Something caught *at* the gate
needs no write-up — that is the system working. Where the write-up lives and
what it must contain is for the done-gate or the extension to say; this
Element creates no directory outside `tasks/` and `.claude/`, and will not
invent one for you. A write-up with no action items is a story; real ones end
with tasks, filed immediately. **Judgement.**

## What no machine will catch

Every invariant is cited inline at the rule it enforces: I-01 §1 · I-02 I-03
I-11 §3 · I-04–I-08 §3 · I-09 files are UTF-8 and newline-terminated · I-10
§1 · I-12 §6 · I-13 I-14 §7 · I-15–I-18 §3 · I-19–I-24 §4 · I-25 §5
· I-26–I-28 §8 · I-29 I-30 §3 · I-31 I-36 §10 · I-32–I-35 §15 · I-37 §9 ·
I-38 the digest ledger re-seeded itself this run.

These are the ones nobody checks but you:

- whether a task genuinely fits its phase's scope (§4)
- whether the done-gate actually passed (§9)
- whether the completion report is true (§11)
- whether the work stayed in scope, and whether `active/` is honest (§12)
- whether the criteria you ticked were verified (§12)
- whether every change really is task-linked (§12)
- whether a gated artifact was touched without permission (§13)
- whether triage and intake are being swept (§14)
