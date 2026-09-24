---
name: task
description: Drive the task lifecycle — file a task, triage it, give it a phase, start it, park it, block or unblock it, submit it for the done-gate, pass or reject it, close it without doing it, reopen it, declare a dependency between two tasks, expand an outline into a full task, declare a new phase, capture or promote an intake note, and check or repair the ledger. Writes; every state change runs through .claude/bin/task so the file, the log and the move happen as one act. Use for "/task", "file a task for X", "I am starting TASK-N", "I am blocked on TASK-N", "TASK-N is finished", "close TASK-N as superseded", "TASK-N depends on TASK-M", "which phase does this go in", "flesh out TASK-N". Not for rendering the ledger — use /backlog or /roadmap for that.
---

# /task — the lifecycle driver

You decide **what** should happen and then let `.claude/bin/task` make
it happen. The command is what moves a task: in one atomic act it
writes the conditional frontmatter, appends a line to
`tasks/history.tsv`, and moves the file. Splitting those three apart is
the exact failure this module exists to prevent, so **never do any of
them by hand.**

What is genuinely yours is the conversation: working out what the user
actually wants filed, which type it is, which phase it belongs to, what
"done" will mean for it, and turning a one-line idea into something a
worker can act on.

The authoritative lifecycle is `.claude/task-rules.md`. This skill
executes that contract; it does not redefine it. If they disagree,
`task-rules.md` wins.

## Two adapters, never inlined

This skill says nothing about what this project produces or how "done"
is checked. Where it needs a project-specific fact it reads:

- **`.claude/done-gate.md`** — what "done" requires here. Read it
  before any `pass`. Never invent a check that is not in it.
- **`.claude/<domain>-task-rules.md`** — the optional extension with
  this project's extra discipline. Read it when the work at hand
  touches its concerns.

## The command surface

Run everything from the project root.

```
.claude/bin/task <verb> [args]
.claude/bin/check-tasks [--fix]
```

Twelve verbs. Every directory is reachable and escapable:

| from | verb | to |
|---|---|---|
| — | `new --type T [--phase P] [--target …] [--priority …] [--series S] [--by WHO] "<title>"` | `triage/`, or `backlog/` with `--phase`, or `active/` with `--priority now` |
| `triage/` | `graduate --phase P [--target …]` | `backlog/` |
| `backlog/` | `demote` | `triage/` |
| `backlog/` | `start` | `active/` |
| `active/` | `park` | `backlog/` |
| `active/` `backlog/` `review/` | `block` | `blocked/` |
| `blocked/` | `unblock` | wherever it came from |
| `active/` | `submit` | `review/` |
| `review/` | `reject --note "<failing gate>"` | `active/` |
| `review/` | `pass --by WHO [--note "…"]` | `completed/` |
| any | `close --resolution R --by WHO [--ref ID]` | `closed/` |
| `completed/` `closed/` | `reopen --note "<reason>"` | `active/`, `backlog/` or `triage/` |

**If the installed command rejects a flag or exits non-zero, stop.**
Show the user the exact command and the exact error. Do not work around
it by editing files — a hand-edit is precisely the drift this module
exists to make impossible.

**One field has no flag on any verb: `needs:`.** Every other
person-written value — `--type`, `--phase`, `--target`, `--priority` —
is reachable above. A dependency is not, so it is the one thing this
skill writes into frontmatter by hand, followed by `check-tasks --fix`.
See **Declare a dependency** below; do not improvise it, and do not
pass `--needs`, which the command rejects.

## Routing

| the user says | do this |
|---|---|
| `/task` bare, or an ambiguous ask | say what you can do in one line, ask which |
| "file / add / track / we need to …" | **File a task** |
| "which phase does this belong in?" | **Placement** |
| `/task phase`, "we need a new phase for …" | **Declare a phase** |
| `/task check` | **Check** |
| `/task repair` | **Check**, then **Repair** |
| "graduate TASK-N", "give TASK-N a phase" | `graduate` |
| "TASK-N is not ready / put it back in triage" | `demote` |
| "I am starting TASK-N", "picking up TASK-N" | `start` |
| "putting TASK-N down", "not working on it now" | `park` |
| "blocked on TASK-N", "TASK-N is stuck on …" | **Block** |
| "TASK-N is unblocked / that cleared" | `unblock` |
| "TASK-N cannot start until TASK-M is done", "TASK-N depends on TASK-M", "do TASK-M first" | **Declare a dependency** |
| "TASK-N no longer waits on TASK-M", "that dependency is not real" | **Declare a dependency** (the removal half) |
| "what is waiting on what?", "what does TASK-N depend on?" | read it: `.claude/bin/task show TASK-N` prints `needs:`; `/backlog` marks every waiting task |
| "TASK-N is finished / ready for the gate" | **Finish** (`submit`) |
| "the gate failed", "send TASK-N back" | `reject` |
| "TASK-N passed / it is done" | **Finish** (`pass`) |
| "we are not doing TASK-N", "superseded by", "duplicate of", "obsolete" | **Close** |
| "reopen TASK-N", "TASK-N came back" | `reopen` |
| "flesh out TASK-N", "expand TASK-N", "write the full task" | **Expand** |
| "note this down", "do not lose this thought" | **Intake capture** |
| "promote that intake note" | **Intake promote** |
| "drop that intake note" | **Intake drop** |
| "is the ledger OK?", an anomalies line from a view | **Check**, then **Repair** |

## Who is acting

Every verb that records a person needs one. Resolve in this order and
do not skip ahead:

1. an explicit `--by` the user gave you,
2. `$RASA_TASK_WHO`,
3. the first line of `tasks/.who`,
4. ask the user — and offer to write the answer to `tasks/.who` so
   they are asked once, not every time.

Never substitute `unknown` to avoid asking. On a project with a
`migrated_on` date, `unknown` on a new task is a hard validator error,
by design: the attribution debt is allowed to shrink and not to grow.

## The five things you must never do by hand

1. **Never move a task file.** `mv` writes the directory without
   writing the log. Use the verb.
2. **Never write `id`, `created`, `created_by`, `updated`,
   `completed_by`, `resolution` or `resolution_ref`.** The command owns
   them.
3. **Never write a `status:` key.** State is the directory in v1.0.0.
   The key is a hard validator error.
4. **Never invent a frontmatter key.** Unknown bare keys are a hard
   error. A project-specific fact goes under an `x-` prefix, which is
   preserved and never interpreted.
5. **Never edit a task file without bumping its date.** The digest
   ledger catches an edited file whose `updated` did not move, and
   reports it as an error. After any edit you made yourself — body or
   `needs:` — run `.claude/bin/check-tasks --fix`, which sets `updated`
   to today and accepts the new content. Tell the user you did.

You **may** freely write the body: the H1, `## Acceptance criteria`,
`## Blocker`, `## Notes`. That is what the templates at
`.claude/task-templates/` are for, and it is where all the real
authoring happens.

You **may** also write one frontmatter key by hand — `needs:`, and
only `needs:`, because it is the one person-written field with no flag
on any verb. **Declare a dependency** below is the whole procedure.
Nothing else in the frontmatter is yours: rules 1–4 stand unchanged.

---

## File a task

1. **Reflect it back in one line.** *"Filing: <restatement>. Right?"*
2. **Pick the type.** Ask if it is not obvious — one question, five
   options:
   - `change` — something becomes different than it was
   - `defect` — something is wrong and must be put right
   - `upkeep` — maintenance that keeps things working as they are
   - `inquiry` — find something out; the deliverable is an answer
   - `record` — capture, document, or file something

   There is no type for urgency. Urgency is `--priority now`, which
   composes with any type.
3. **Phase, or triage.** If the user names a phase, use `--phase`. If
   they do not, show the declared phase ids and names from
   `tasks/ROADMAP.md` and ask. If nothing fits, file to `triage/` —
   that is exactly what it is for. Never guess a phase, and never
   invent one silently; declaring a phase is its own operation below.
4. **Target, if this project declares one.** Read
   `tasks/tasks.config.yml`. If `targets:` is non-empty, a task outside
   `triage/` must carry `--target`, and the value must be one of the
   declared ones. If `targets:` is empty or absent, `--target` is
   forbidden — do not pass it.
5. **Priority.** Default is `normal`; pass nothing. `--priority now`
   files straight to `active/` and means work starts now — confirm that
   is what they mean before using it.
6. **Run it.**
   ```
   .claude/bin/task new --type change --phase 2 --by jmr "Amend the retention schedule"
   ```
7. **Write the body.** Open the file the command reports and fill it
   from `.claude/task-templates/<type>.md`. A task filed to `triage/`
   or `backlog/` is an **outline** by default — title, one line of what
   it is, one line of why. Do not write a full task unless the user
   asked for one; **Expand** is the operation for that, later, when it
   is about to be worked.
8. **Dependencies, only if the user stated one.** If they said this
   cannot start until another task finishes, and named it, add
   `needs:` now — see **Declare a dependency**. If they did not say so,
   do not infer one: a dependency nobody asked for is a queue nobody
   agreed to, and the expansion step exists to surface real ones later.
9. **Show what landed** — the path, the id, the phase, and any
   `needs:` — and stop.

## Triage pass

Walk `tasks/triage/` with the user, oldest first. For each: graduate
it, close it, or leave it. A triage list nobody walks is the same as no
list.

- **Graduate** — it has a home:
  `.claude/bin/task graduate TASK-N --phase 3 --target filings`
- **Close** — it will not be done:
  `.claude/bin/task close TASK-N --resolution obsolete --by jmr`
- **Leave** — say why, in one line, in the task's `## Notes`, then run
  `check-tasks --fix` so its date is honest.

## Move it

Thin by design. Confirm the task and the intent, run the verb, report
the new directory.

- `start` / `park` — picking work up and putting it down.
- `block` — **write the `## Blocker` section first**, in the body, in
  the user's own words: what is blocking, and what would unblock it. A
  task in `blocked/` with an empty blocker is a validator error, and an
  unexplained blocker is a task nobody can clear. Then
  `.claude/bin/task block TASK-N`.
- `unblock` — the command returns the task to whichever state it came
  from, read from the log. Do not name a destination.

## Declare a dependency (`needs:`)

`needs:` is the only dependency field (`.claude/task-rules.md` §8): the
ids that must finish before this one can. Like `type`, `phase`,
`target` and `priority` it is **written by a person** — but unlike all
four of those it has **no flag on any verb**, and the command says so:

```
$ .claude/bin/task new --type change --needs TASK-LIT-038 "File the exhibit"
task: error: unrecognized arguments: --needs
```

So the sanctioned path is two steps, and the second is not optional.

1. **Write the key into the frontmatter by hand.** One line, a flow
   list, no indentation — the grammar in `.claude/task-rules.md` §3
   accepts nothing else. Put it where the contract's own example puts
   it, after `priority:` if there is one:

   ```yaml
   needs: [TASK-LIT-038]
   ```

   More than one: `needs: [TASK-LIT-038, TASK-LIT-041]`.

2. **Run `.claude/bin/check-tasks --fix`.** Until you do, the digest
   ledger reports the edit as a hard error:

   ```
   I-34  the file changed but 'updated' still reads 2026-09-14 [--fix]
        → --fix sets 'updated' to today and accepts the new content
   ```

   `--fix` prints exactly what it did, under `APPLIED`:
   `accepted the new content as current in the digest ledger`, plus
   `set 'updated: <today>'` when the date had actually fallen behind —
   edit and fix on the same day and you will see only the first. Show
   the user whichever lines appear. Never leave the error standing for
   someone else to find.

**This is not repairing around the tooling.** There is no verb here to
route around. `needs:` is person-written, the same way
`## Acceptance criteria` is person-written, and step 2 is what keeps
the date honest in place of the stamp a verb would have made. What
stays forbidden is unchanged: the directory, the log, and the seven
command-owned keys.

### What the validator will hold you to

All of it fires on the next `check-tasks`, so get it right while you
are looking at the file:

| what you wrote | what happens |
|---|---|
| an id that is not in this ledger | **I-26** error — `'needs: TASK-LIT-999' names a task that is not in this ledger` |
| this task's own id | **I-26** error — `a task cannot need itself` |
| the same id twice | **I-26** error — `'TASK-LIT-038' is listed twice in 'needs'` |
| anything but a one-line flow list of ids | **I-26** error — `'needs' must be a flow list of task ids` |
| a loop of any length | **I-27** error, and it prints the cycle: `TASK-LIT-001 -> TASK-LIT-002 -> TASK-LIT-001` |
| this task reaches `completed/` with a need that has not | **I-28** warning — `this task is completed but needs TASK-LIT-001, which is still in backlog/` |

I-26 and I-27 are errors `--fix` cannot touch — only a person knows
which of the ids was the wrong one. Walk them with the user one at a
time.

### Two things that are easy to get wrong

- **`needs:` moves nothing.** It is a declaration, not a transition. A
  task waiting on another is *not* thereby in `blocked/`, and adding
  the key will not put it there. The two are complementary and both are
  fine to use at once: `needs:` names **which task**, the `## Blocker`
  section and `.claude/bin/task block` say **what is in the way and
  why**. Use `blocked/` when the user wants the task out of the working
  view; use `needs:` when they want the order recorded.
- **To drop a dependency, delete the line** — by hand, then
  `check-tasks --fix`, exactly as above. Do not leave `needs: []`
  behind: the validator accepts an empty list without complaint, which
  is precisely why it is the wrong way to say "none" — it reads as a
  declaration and checks as nothing. Remove the key.

### The gap, stated plainly

Every other person-written field is reachable through a flag, so the
file, the log and the date move as one act. `needs:` is not, which is
why this one field costs a hand-edit and a `--fix`. If the installed
`.claude/bin/task` has grown a `--needs` flag — check with
`.claude/bin/task new --help` — **use the flag and ignore the two steps
above.** It is strictly better: it stamps `updated` itself and leaves
no window in which the ledger is red.

## Finish it

This is where the done-gate finally has a position, and it is the one
place this skill is worth more than the command alone.

1. **`submit`.** Work is finished but unverified:
   `.claude/bin/task submit TASK-N`. It lands in `review/`. It is not
   done yet, and the ledger no longer pretends otherwise.
2. **Read `.claude/done-gate.md`.** That file, and only that file, says
   what must hold. If it is missing or still holds its seeded
   placeholder text, say so plainly and stop — an ungated `pass` is a
   claim nobody checked.
3. **Walk the gate with the user, item by item.** Against the task's
   own `## Acceptance criteria`, not against your impression of the
   work. Do not mark an item satisfied on the user's say-so without
   asking what satisfied it.
4. **Then one of two things:**
   - Everything holds →
     `.claude/bin/task pass TASK-N --by jmr --note "gate: <what was checked, and when>"`
   - Something does not →
     `.claude/bin/task reject TASK-N --note "<the item that failed>"`.
     It returns to `active/`. The note names the failing item so the
     next attempt knows what to aim at.

Never run `pass` in the same breath as `submit`. If the gate is
genuinely instantaneous, that is still two commands and two log lines,
and the log is the record.

## Close it

For work that ends **without** being done. Never use `pass` for this —
that is what makes the completed count a number people can trust.

Pick the resolution with the user:

| resolution | means | needs |
|---|---|---|
| `superseded` | another task took this over | `--ref <id>` |
| `duplicate` | this was already filed | `--ref <id>` |
| `obsolete` | the reason for it went away | — |
| `wont-do` | a decision was taken not to | — |

```
.claude/bin/task close TASK-N --resolution superseded --ref TASK-M --by jmr
```

Then write the *why* into `## Notes` and run `check-tasks --fix`. The
resolution says what happened; the note says why, and it is the only
part a future reader cannot reconstruct.

## Reopen

`.claude/bin/task reopen TASK-N --note "<why it came back>"`. Ask for
the destination: `active/` if work restarts now, `backlog/` if it is
queued, `triage/` if it needs rethinking. The old terminal lines stay
in the log — a reopened task's history is the point of reopening it.

## Expand an outline into a full task

The operation that turns one line into something a worker can act on
without asking. It involves real reading and takes real time.

**Read `expanding-a-task.md`, in this skill's own directory, and follow
it.** It is a separate file because it is long, because it is only
needed for this one operation, and because inlining it here made the
rest of the lifecycle unreadable. Do not attempt the expansion from
memory of what a good task looks like.

The short version, so you know what you are agreeing to: read the
outline, consider whether it is one task or several, gather what this
project already has that bears on it, read the current authority the
work turns on rather than recalling it, show the user a context report,
drill the acceptance criteria until each one is independently
checkable, map each to `.claude/done-gate.md`, ask the questions only
the user can answer, then write the file. Eleven steps, and step 11 is
the one that writes.

## Placement — "which phase does this go in?"

1. Ask one or two questions about the outcome the user wants.
2. Read the scope paragraphs under the phase headings in
   `tasks/ROADMAP.md`. Propose one or two that fit, and say why for
   each.
3. **Leave the decision with the user.** If nothing fits, the honest
   answers are triage or a new phase — offer both.

## Declare a phase (`/task phase`)

A project with no phases cannot graduate anything out of triage, so
this has to be possible. It is the one write this skill makes to
`tasks/ROADMAP.md` that is not a task line.

1. **Confirm it is really a new phase** and not an existing one under
   another name. Two tasks that share a theme are not a phase; a
   coherent block of work with a boundary is.
2. **Get an id and a name.** The id is short and stable
   (`^[A-Za-z0-9][A-Za-z0-9._-]{0,23}$`) — it goes in every task's
   frontmatter, so renaming it later is expensive. The name is a short
   noun phrase.
3. **Get a scope paragraph** from the user: two to four sentences on
   what is in, what is out, and what finishing it looks like. This is
   the phase's contract. **Do not write it for them** — a placeholder
   scope is a validator warning precisely so it does not become
   permanent.
4. **Write the heading** into `tasks/ROADMAP.md` at the position the
   user chooses, in the form the grammar accepts:

   ```markdown
   ## Phase 4: Handover

   Scope paragraph, two to four sentences.
   ```

   Both `## Phase 4: Handover` and `## Phase 4 — Handover` are legal
   and mean the same thing. Match whichever form the file already uses;
   do not mix them within one file.
5. **Phase order is working order.** Ask where it goes; do not append
   by reflex.

## Intake

`tasks/intake.md` is pre-task prose: no ids, no phases, no ceremony. It
exists so a thought does not have to become a task to be kept.

- **Capture** — append under today's `## YYYY-MM-DD` heading (add the
  heading if it is not there): `- **<short title>** — <a sentence or
  two of context>`. No id is assigned. This is the cheapest thing in
  the whole module; keep it cheap.
- **Promote** — file it as a task to `triage/` (the **File a task**
  operation), carry the note's context into the body's `## Notes`, then
  **remove the line from `intake.md`**. A promoted note that stays in
  intake gets promoted twice.
- **Drop** — remove the line. If the user wants the reasoning kept,
  that is not an intake concern: file it and close it with
  `--resolution wont-do` and the reasoning in `## Notes`, so the
  decision is in the ledger where someone will find it.

## Check, then repair (`/task check`, `/task repair`)

- **Check** — `.claude/bin/check-tasks`. Show the user its output
  **verbatim**. Do not summarize a validator; the exact message is the
  whole value. Exit `0` is clean, `1` is errors, `2` means it could not
  run at all.
- **Repair** — `.claude/bin/check-tasks --fix` only ever repairs what
  can be repaired mechanically: it deletes a `status:` key, reconciles
  a hand-moved file by appending a log line dated today with actor
  `unknown`, sets a stale `updated` to today, accepts as current the
  content of a file that was edited in place (the I-34 digest error —
  the step **Declare a dependency** ends here), and inserts a missing
  ROADMAP line. **Say which of those apply before running it**, and get
  a yes. It never invents a past date and never resolves a dangling
  ROADMAP line — a line naming a file that does not exist is either a
  lost task or a stale promise, and only the user knows which.

Everything `--fix` cannot touch is yours to walk through with the user
one at a time. Do not batch them into a single confident sweep.

## What you must not do

- **Do not write a full task when the user asked to file one.** The
  default is an outline. **Expand** is a separate, later, explicit act.
- **Do not split one task into several unasked.** Filing one task means
  filing one task. Propose a split in **Expand**; do not perform one.
- **Do not hardcode what "done" means.** Every verification routes
  through `.claude/done-gate.md`. Never write a check or a command into
  a task's body.
- **Do not do the work.** A task is a description of work. Executing it
  is a different session with a different purpose.
- **Do not invent a convention.** If this project already shapes this
  kind of work a certain way, match it. Being the first to do it
  differently is how a ledger stops being readable.
- **Do not repair around the tooling.** If a verb fails, report the
  failure. A hand-edit that makes the validator quiet has hidden a real
  problem, not solved one. The one sanctioned hand-write is `needs:`,
  which has no verb to fail around — and it ends by running the
  validator, not by silencing it.

## When NOT to use this skill

- Rendering what is in flight → `/backlog`.
- Rendering progress by phase, or history → `/roadmap`.
- Reading one task → read the file.
- Doing the work a task describes → just do it.
