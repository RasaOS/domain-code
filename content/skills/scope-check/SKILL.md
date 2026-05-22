---
name: scope-check
description: Counter to estimate optimism. Take a planned change ("add field X to User", "extract auth into a service", "swap Redux for Zustand") and scan the codebase for the actual surface area it touches — file count, dependent modules, test count, type/interface consumers, public API impact, doc references. Produces a "you said small; here's what I found" report with concrete numbers and a rechunking suggestion if scope blew past the user's stated size. Output saved to `docs/scope/<YYYY-MM-DD>-<slug>.md`. Triggered when the user wants reality-checked on the size of a planned change — e.g. "/scope-check", "how big is this change really", "is this small or am I kidding myself", "scope-check this refactor".
---

# /scope-check — Reality-check the size of a planned change

The user thinks the change is small. Often it isn't. This skill
scans the codebase for surface area and surfaces the gap
between stated size and actual surface, with concrete counts.

Distinct from `/blast-radius`: blast-radius asks "what could
break", scope-check asks "how much code is involved at all".
Both matter, neither replaces the other.

Per CLAUDE.md ethos: don't tell the user "this is too big" —
surface the data and let them decide. The data is the argument.

## Behavior contract

- **Read-only.** Scope-check is a scanner. No edits, no
  commits, no migrations.
- **User describes the change first.** And ideally states an
  estimated size ("a few files", "small refactor", "a day's
  work"). The skill tests that estimate against measured
  surface area.
- **Numbers, not adjectives.** Findings are counts (files,
  symbols, tests, references). "47 files reference this; 12
  tests; 3 public consumers" beats "this is bigger than you
  think".
- **Suggest rechunking if scope >> estimate.** Don't just dump
  numbers — propose a smaller first slice if the data
  warrants it.
- **Cite, don't summarize.** A scope finding without a
  `path:line` is a hand-wave. Sample the cited locations so
  the user can verify.
- **Output saved to disk.** Report at
  `docs/scope/<YYYY-MM-DD>-<slug>.md`. Useful for retrospective
  ("I estimated 1 day; scope-check said 47 files; reality was
  35 files. My estimate was off by 35×.").
- **Don't auto-commit.** Standard kit rule.

## Process

### Step 1 — Capture the planned change + estimate

If invoked without detail, ask:

```markdown
Two things, in one block:

1. **The change.** What are you adding, removing, refactoring,
   or renaming? Be specific.
2. **Your estimate.** How big do you think it is? Pick one or
   give your own:
   - **Tiny** — under 5 files, under an hour.
   - **Small** — 5-15 files, half a day.
   - **Medium** — 15-50 files, 1-3 days.
   - **Large** — 50+ files or > 3 days.

Example:
1. *"Adding a `tenantId` field to every model and threading it
   through queries."*
2. *Small — half a day, maybe.*
```

Record both. The estimate is what the skill compares findings
against.

### Step 2 — Generate a slug

From the change description: e.g. `add-tenantid`,
`extract-auth-service`, `swap-state-management`. Used in the
filename: `docs/scope/<YYYY-MM-DD>-<slug>.md`.

### Step 3 — Identify the seed targets

Translate the change into concrete grep targets:

- **Adding a field/column** → seed = the model/schema file +
  any place that constructs the model.
- **Renaming/moving** → seed = the literal name + the path.
- **Extracting a module** → seed = the directory + every
  symbol exported from it.
- **Swapping a dependency** → seed = every import of the
  outgoing dep.
- **Threading a parameter through call sites** → seed = the
  function/method + every call site.

If the seeds aren't clear from the description, ask the user
to clarify before scanning.

### Step 4 — Measure surface area

For each seed, compute:

- **Files touched** — distinct files containing references.
- **Modules / packages affected** — top-level dirs in `src/`
  (or equivalent) containing references.
- **Symbols affected** — functions/types/classes that need
  signature changes.
- **Tests affected** — files in `tests/` / `__tests__` /
  `*.test.*` referencing the seed.
- **Type definitions affected** — interfaces/types/schemas
  with the seed in scope.
- **Public API consumers** — exports leaving the package and
  the surfaces that depend on them. (External repo consumers
  are out of scope; surface as "Possible.")
- **Doc references** — `README`, `CLAUDE.md`, `docs/` mentions.
- **Config / fixture mentions** — JSON/YAML fixtures, env
  files, deployment configs.

For larger scans, spawn an `Explore` agent to enumerate;
sample the top hits to verify they're real (not grep noise).

### Step 5 — Compare against the estimate

Map findings to the estimate's expected size:

- **Tiny:** < 5 files, < 5 symbols, < 5 tests.
- **Small:** 5-15 files, 5-15 symbols, < 15 tests.
- **Medium:** 15-50 files, ~50 references.
- **Large:** 50+ files or > 50 references.

If findings exceed the estimated tier, mark as "**Scope drift
detected**".

### Step 6 — Propose rechunking *(if scope drift)*

If actual scope is materially larger than the estimate,
suggest a smaller first slice:

- "Phase 1: just the model + 3 highest-leverage call sites.
  Phase 2: thread through queries. Phase 3: tests + docs."
- "Carve out the public-API surface as a separate change so
  the internal refactor isn't a big-bang."

The suggestion is non-binding; the skill surfaces it, the
user decides.

### Step 7 — Write the report

Output to `docs/scope/<YYYY-MM-DD>-<slug>.md` per the
**Output structure** below.

### Step 8 — Closing summary

```markdown
# 📏 Scope-check complete

`docs/scope/<date>-<slug>.md` — **<verdict>**.

| | |
|---|---|
| Your estimate | <Tiny/Small/Medium/Large> |
| Measured | <category — files=<N>, symbols=<N>, tests=<N>> |
| Drift | <none / N tiers> |

**The numbers worth knowing:**
- <count> files touched
- <count> tests likely affected
- <count> public API surfaces involved

**Recommendation:** <one line — proceed as planned / chunk into
N phases / talk to the team first>

Read the report for the full picture before deciding.
```

## Output structure

The report at `docs/scope/<YYYY-MM-DD>-<slug>.md`:

```markdown
# 📏 Scope-check — <change description, terse>

> **Change.** <one sentence>
> **Estimate.** <Tiny / Small / Medium / Large — user-supplied>
> **Measured.** <category derived from findings>
> **Drift.** <none / N tiers — e.g. "Estimated Small,
> measured Medium — 1-tier drift">

**Date.** <YYYY-MM-DD>

---

## Headline numbers

| Surface | Count |
|---|---|
| **Files touched** | <N> |
| **Modules affected** | <N> |
| **Symbols (functions, types, classes)** | <N> |
| **Tests affected** | <N> |
| **Type/schema definitions** | <N> |
| **Public API consumers** *(this repo)* | <N> |
| **Doc references** | <N> |
| **Config / fixture mentions** | <N> |

---

## 1. Files touched *(top 20)*

[`<path>`](<link>) — <one-line role>
[`<path>`](<link>) — …

*(Top 20 by reference count. Full set: `<grep command>`.)*

---

## 2. Modules affected

- **`<top-level dir>`** — <count> files, <one-line role>
- …

---

## 3. Symbols requiring signature changes

For threading-a-param changes, this is the long pole.

- [`<file>:<line>`](<link>) — `<symbol signature>`
- …

*(Top 20.)*

---

## 4. Tests likely affected

- [`<test file>:<line>`](<link>) — <test name>
- …

---

## 5. Type / schema definitions

- [`<file>:<line>`](<link>) — `<type/interface/schema name>`
- …

---

## 6. Public API surfaces

Exports from this repo that may need updating:

- [`<file>:<line>`](<link>) — `<exported symbol>` *(used by
  <N> internal consumers; external consumers unknown)*
- …

---

## 7. Documentation references

- [`<doc path>`](<link>) — <one-line context>
- …

---

## 8. Verdict

<2-4 sentences. Honest read on the gap between estimate and
measured. Specific.>

**Drift assessment:**
- <e.g. "Estimated Small (5-15 files); measured 47 files
  across 6 modules — 2-tier drift to Medium-Large.">

---

## 9. Suggested rechunking *(if drift)*

If you want to do this in smaller pieces, here's a non-binding
slice. The skill surfaces; you pick.

### Phase 1 — <name>
*<count> files, <count> tests*
- <bullet — what's in this phase>
- …

### Phase 2 — <name>
*<count> files, <count> tests*
- <bullet>
- …

*(Add phases as warranted.)*

---

## 10. Adjacent observations *(optional)*

One-liners on stuff just outside the scoped change.

- <observation>

---

*Generated by `/scope-check` on <YYYY-MM-DD>. Re-run after
the change ships to compare actual scope against this
estimate. Saved under `docs/scope/` for retrospectives.*
```

## Style rules

- **Headline table is the lede.** First thing the reader
  sees after the front matter. Counts, not opinions.
- **Top 20 cap on lists.** Full grep output is in the
  command suggestion. The report is for human reading.
- **Drift in tiers, not percentages.** "1-tier drift" reads
  faster than "270% over estimate".
- **Cite via `path:line`.** All findings clickable.
- **Verdict is 2-4 sentences.** Resist the urge to write a
  paragraph.
- **Phase rechunking only when scope materially drifted.**
  If the estimate matched, the rechunk section is omitted.
- **Emoji are load-bearing.** 📏 (scope-check). One emoji.

## What you must NOT do

- **Don't editorialize the verdict.** "This is too big to
  ship in one PR" is the user's call. Surface the data; the
  user reads it.
- **Don't fudge counts.** If grep is noisy and the real count
  is unclear, surface that: "47 raw matches; estimate ~30
  real after sampling."
- **Don't propose technical fixes.** Rechunking suggestions
  are about how to slice the change, not how to write it.
- **Don't expand scope.** If during scanning you spot
  something concerning unrelated, footer it. Don't grow the
  report.
- **Don't auto-commit.** Standard kit rule.
- **Don't skip estimate vs. measured comparison.** That's
  the whole point of the skill. A report without it is just
  a grep dump.

## Edge cases

- **Estimate not given.** Default to "Small" (the most common
  intuition for any change) and surface clearly: "Estimate
  defaulted to Small since none provided." Encourage the user
  to give one for retrospective value.
- **Change is genuinely tiny.** Scope-check confirms; report
  is short. That's a useful signal too — "you were right;
  proceed."
- **Grep noise dominates** (generic name, common word).
  Stop, ask user to scope by directory or module before
  scanning.
- **Polyglot repo.** Scan each language; report by language
  segment if helpful. Don't conflate counts across.
- **Public API surfaces are external.** Note that the count
  is *internal consumers*; external consumers are unknown
  from inside the repo and need separate verification.
- **The change is hypothetical / pre-design.** Surface counts
  for "as if you were doing this today." Note that the
  measurement may shift once the change is concrete.

## When NOT to use this skill

- **Mapping what could break** → `/blast-radius`.
- **Designing the change** → `/plan`.
- **Auditing an existing slice** → `/audit`.
- **The change is brand-new construction** (nothing to
  reference yet) → `/plan` makes more sense.
- **You only want a rough gut-check** → just grep. Don't run
  the whole skill.

## What "done" looks like for a /scope-check session

A dated report at `docs/scope/<date>-<slug>.md` with concrete
counts across files / symbols / tests / docs / public API,
a measured-vs-estimated drift assessment, and an optional
rechunking suggestion if scope drifted materially. Uncommitted.
The user has the data they need to decide whether to proceed,
chunk, or replan — without the skill making the call for them.
