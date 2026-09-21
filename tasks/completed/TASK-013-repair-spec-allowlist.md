---
id: TASK-013
category: bug
phase: P1
status: completed
---

# TASK-013: Repair the spec-file allowlist

**User story.** As a **reviewer**, I want **the spec-file allowlist to say
the same correct thing everywhere it appears** so that **the rule governing
autonomous merges to `main` is unambiguous and the skills obey it**.

## What's broken

v0.48.0 (`72f1149`, 2026-09-19) set out to add `tasks/RELEASES.md` to the
spec-file allowlist — the list of files an `/auto-task` or `/auto-phase` run
may auto-merge to `main` without per-invocation user authorization. The
change landed wrong in two different ways, and the result is that the
feature the CHANGELOG claims shipped does not work.

**Failure 1 — both rule files were corrupted by a duplicated line.** The
commit added exactly one line to each file (`+1` in the diffstat for both)
instead of extending the existing list:

`content/git-flow-rules.md:80-82` currently reads

```
  the spec-file allowlist (`tasks/**/*.md`, `tasks/PHASES.md`,
  `tasks/ROADMAP.md`) and the working tree is otherwise clean.
  `tasks/RELEASES.md`) and the working tree is otherwise clean.
```

`content/autonomy-rules.md:137-140` currently reads

```
  allowlist: `tasks/**/*.md`, `tasks/PHASES.md`,
  `tasks/ROADMAP.md`. Any file outside the allowlist disqualifies
  `tasks/RELEASES.md`. Any file outside the allowlist disqualifies
  the fast-path.
```

Both now have a sentence that terminates twice and a list entry stranded
outside its own parenthesis. Neither parses as a list.

**Failure 2 — the operative instructions were never updated at all.** The
allowlist is stated in four places. `72f1149` touched two of them. The other
two are the SKILL.md files the agents actually execute from, and they still
enumerate three entries:

- `content/skills/auto-task/SKILL.md:52` and `:78`
- `content/skills/auto-phase/SKILL.md:41`

So the live behavior today is: a PR containing only `tasks/RELEASES.md`
does **not** match the allowlist the skills read, falls back to "leave
uncommitted", and `/release-plan`'s output waits on a manual commit — the
exact friction v0.48.0 existed to remove.

## Why this matters

This is the rule that decides when an autonomous agent may merge to `main`
without asking. `git-flow-rules.md` says of the carve-out list: *"The list
is closed. Adding a new merge-bearing user-invoked skill requires adding it
here, in this rule, as a named carve-out — not silently in the SKILL.md."*
The rule is authoritative by its own declaration, so a rule that contradicts
itself and skills that contradict the rule is the worst available state.

Worth recording: `72f1149`'s own commit message notes that `bin/check-manifest`
caught a *different* botched edit in the same session (a `rasa.json` note edit
that merged two seed entries). The JSON had a gate and was caught. The prose
had no gate and shipped. That is `TASK-044`'s thesis, demonstrated — but
building that gate is **out of scope here**.

## Scope

**In scope:** make all four sites state the same four-entry allowlist —
`tasks/**/*.md`, `tasks/PHASES.md`, `tasks/ROADMAP.md`, `tasks/RELEASES.md`.

**Out of scope (explicit):**
- A lint/gate that would have caught this. That is `TASK-044`.
- Any change to *what* is on the allowlist. `tasks/RELEASES.md` belongs
  there because v0.48.0 decided it does; this task delivers that decision,
  it does not revisit it.
- The `tasks/**/*.md` glob already subsumes the three named files. Collapsing
  the list to one entry would be a behavior change to a governance rule and
  is not this task's call.

## Files expected to change

- `content/git-flow-rules.md` — repair the duplicated line at 80-82
- `content/autonomy-rules.md` — repair the duplicated line at 137-140
- `content/skills/auto-task/SKILL.md` — add `tasks/RELEASES.md` at 2 sites
- `content/skills/auto-phase/SKILL.md` — add `tasks/RELEASES.md` at 1 site

## Execution order

1. `content/git-flow-rules.md` — replace the two stranded lines with one
   correct list + sentence
2. `content/autonomy-rules.md` — same repair, matching that file's phrasing
3. `content/skills/auto-task/SKILL.md` — extend both allowlist enumerations
4. `content/skills/auto-phase/SKILL.md` — extend the one enumeration
5. Run the consistency assertion (below) — all four sites must agree
6. Run `bin/check-manifest`, `bin/check-invocations`, `bin/lint`

## Acceptance criteria

- [x] No duplicated sentence remains at either rule site
- [x] Every allowlist enumeration lists exactly: `tasks/**/*.md`,
      `tasks/PHASES.md`, `tasks/ROADMAP.md`, `tasks/RELEASES.md`
- [x] Five enumerations across the four files (`auto-task` states it twice);
      zero stale three-entry enumerations remain
- [x] `bin/check-manifest` exits 0
- [x] `bin/check-invocations` exits 0
- [x] `bin/check-bash32` exits 0
- [x] `bin/lint` does not regress — **corrected criterion.** The original
      criterion said "exits 0"; that was wrong to assert. `bin/lint` exits 1
      on pristine `main` (`0db5016`) with 14 findings, all pre-existing and
      none in the files this task touches. Verified 14 findings before and
      after, and zero findings in the four changed files. The pre-existing
      red lint is filed separately as `TASK-055` — this task does not fix it
      and must not be read as having done so.

## Test plan

No E2E applies — this is shipped prose, and the absence of any executable
test over shipped prose is precisely `TASK-044`. The verification is a
consistency assertion run against the tree:

```
grep -rn 'tasks/RELEASES.md' content/git-flow-rules.md content/autonomy-rules.md \
  content/skills/auto-task/SKILL.md content/skills/auto-phase/SKILL.md
```

Must return 4 matches — one per site — and each must sit inside the
allowlist enumeration rather than on a line of its own.

## Manual verification

1. Read `content/git-flow-rules.md:78-84` — the sentence terminates once.
2. Read `content/autonomy-rules.md:135-141` — same.
3. Confirm `git diff` touches only the four files above.

## Gotchas & learned lessons

- **Don't "fix" it by deleting the `tasks/RELEASES.md` line.** That reverts
  v0.48.0's intent. History (`git log -S`) confirms the line was an
  *addition* to the list, not a replacement for `tasks/ROADMAP.md`.
- **Don't collapse the list to `tasks/**/*.md`.** It would be correct as a
  glob and wrong as a governance edit — see "Out of scope".
- **The two rule files phrase the allowlist differently** (one parenthetical,
  one colon-led). Repair each in its own voice; do not homogenize them.

## Blocker notes

(none)

## Findings surfaced while working this task

Both are out of scope here and filed separately rather than folded in:

- **`bin/lint` exits 1 on pristine `main`.** 14 findings at `0db5016`, all
  pre-existing. `CLAUDE.md` names `bin/lint` as a release gate ("run before
  tagging"), so the gate is currently red and releases are either skipping
  it or ignoring it. Filed as `TASK-055`.
- **A background agent wrote into the repo.** During recon for `TASK-012`, a
  subagent created and staged `content/tests/suites/prod-gate.md` (a
  `tests: []` stub) in the working tree despite being instructed to work only
  in temp dirs. Unstaged and discarded here; the real `prod-gate.md` is
  `TASK-012`'s to design, and an empty one would be vacuous anyway.

---

**Definition of done:**
- All acceptance criteria checked
- `bin/check-manifest`, `bin/check-invocations`, `bin/lint` all clean
- Committed on `task/TASK-013-repair-spec-allowlist`
