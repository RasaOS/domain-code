---
name: blast-radius
description: Pre-mortem for a proposed destructive or risky change — schema migration, large refactor, dependency major-version bump, service rename, file/path move, deprecation. Takes a description of the change, scans the codebase for direct references, indirect references, tests, docs, deployments, and external surfaces that touch it, then produces a structured "what could break" report with confidence-tagged findings. Output saved to `docs/blast-radius/<YYYY-MM-DD>-<slug>.md`. The pre-mortem you actually do, not the one you mean to. Triggered when the user is about to do something risky and wants the surface mapped first — e.g. "/blast-radius", "what breaks if I drop this column", "blast radius of renaming X", "pre-mortem this refactor".
---

# /blast-radius — Map what could break before you break it

Before a destructive change — schema migration, big refactor,
dependency bump, service rename, file move, public API
deprecation — enumerate everything that might break. Confidence-
tagged. The report is the thing that gets read in 3 weeks when
a regression surfaces; document accordingly.

Per CLAUDE.md ethos: distinguish verified-by-reading from
inferred-from-pattern. A pre-mortem that hedges everything is
useless; one that overstates confidence is dangerous.

## Behavior contract

- **Read-only by default.** This skill produces a report. No
  edits, no migrations, no commits. Action follows the report,
  not from the skill.
- **User describes the change first.** The skill needs to know
  what's being changed before it can scan for what depends on
  it. Ask if the user invokes without a description.
- **Verified vs. inferred is mandatory.** Every finding is
  tagged as one of:
  - **Verified** — confirmed by reading the code/doc/config.
  - **Likely** — strong inference from a pattern; not
    confirmed by reading.
  - **Possible** — pattern match only; needs human review.
- **Cite everything.** Each finding has a `path:line` or named
  resource. Unsourced claims are forbidden.
- **Don't expand the change.** If the user says "drop column
  X", the skill maps blast radius for X — not "while we're at
  it, also drop Y." Adjacent observations go in a footer.
- **Output saved to disk.** The report lives at
  `docs/blast-radius/<YYYY-MM-DD>-<slug>.md` so it's preserved
  for post-action verification ("did we miss anything?").
- **Don't auto-commit.** Standard kit rule.

## Process

### Step 1 — Capture the change

If the user invoked without detail, ask:

```markdown
Describe the change. Be specific:

- **What** — the file/column/symbol/service/dependency
  changing.
- **How** — drop, rename, move, refactor, version-bump,
  deprecate.
- **Why now** — one line, optional but useful.

Example: "Renaming the `inspections` table column
`inspectionFormId` → `formId`. Why: clean up legacy naming
ahead of v3."
```

### Step 2 — Generate a slug for the report file

From the change description: `<verb>-<target>` →
`drop-inspectionformid`, `rename-auth-service`, `bump-react-19`.
Used in the filename: `docs/blast-radius/<date>-<slug>.md`.

### Step 3 — Scan for direct references

For each kind of change, the direct scan differs:

- **Code symbol** (function, class, type, variable) →
  `grep` / `Grep` for the literal name across `src/`, `lib/`,
  `tests/`, etc.
- **File or directory move** → grep for the path string + any
  `import` / `require` / `include` referencing it.
- **Schema column / field** → grep for the column name in
  models, migrations, queries, ORM definitions, and JSON/YAML
  fixtures.
- **Service/API endpoint** → grep for the route path,
  client-side fetch calls, integration test fixtures, OpenAPI
  schemas.
- **Dependency (major bump)** → read changelogs/breaking-change
  notes for the target version; cross-reference with the
  project's actual usage.
- **Environment variable / config key** → grep for the key in
  code, config files, deployment manifests, CI/CD, secrets.

For larger scans, spawn an `Explore` agent to enumerate
candidate files; read the highest-leverage matches yourself to
confirm.

### Step 4 — Scan for indirect references

Indirect = touched through an abstraction, not literally named.

- **Wrappers** — utilities that take the symbol as input.
- **Reflection / dynamic dispatch** — `Object.keys()`, JSON
  serialization, ORM auto-generation, code-gen targets.
- **Test fixtures and seed data** — files that bake in the
  current shape.
- **Documentation** — `README`, `CLAUDE.md`, `docs/`,
  comments referencing the symbol.
- **External configs** — environment files, deploy manifests,
  cron jobs, CI pipelines.

Mark these as "**Likely**" or "**Possible**" — not Verified —
unless reading the code confirms the dependency.

### Step 5 — Scan tests

Separately enumerate tests that mention the target. Tests are
where the regression lives if the blast radius is wrong.

- Unit tests referencing the symbol/column/file.
- Integration tests hitting the endpoint/service.
- E2E tests with fixtures that bake in the schema.
- Snapshot tests that may capture output dependent on the
  target.

### Step 6 — Scan external surfaces

Things outside the repo that depend on the target.

- **Public API consumers** — if applicable (other repos, third
  parties).
- **Webhooks / outbound integrations** — fields the project
  emits.
- **Database migrations** — the actual SQL/DDL that's run vs.
  the model definition.
- **Cached / stored data** — backups, replicas, caches that
  hold the old shape.
- **Documentation outside the repo** — wiki, customer docs.

These are usually **Possible** — the skill flags them so the
user verifies. The skill can't see outside the repo.

### Step 7 — Compose the report

Write to `docs/blast-radius/<YYYY-MM-DD>-<slug>.md` using the
**Output structure** below.

### Step 8 — Closing summary

```markdown
# 💥 Blast radius mapped

`docs/blast-radius/<date>-<slug>.md` — <count> findings:

- **Verified:** <count> *(confirmed by reading the code)*
- **Likely:** <count> *(strong inference)*
- **Possible:** <count> *(needs human review)*

**Highest-leverage worries:**
1. <terse — the finding most likely to cause trouble>
2. <terse>
3. <terse>

**Recommended next moves:**
- <one-line — e.g. "Resolve the 4 'Likely' tests before
  merging.">
- <one-line — e.g. "Verify the OpenAPI consumer in
  `acme-api-client` still works.">

Review the full report, then proceed with the change. Re-run
this skill after the change to verify the blast radius was
correctly mapped.
```

## Output structure

The report file at `docs/blast-radius/<YYYY-MM-DD>-<slug>.md`:

```markdown
# 💥 Blast radius — <change description, terse>

> **Change.** <one sentence describing what's changing>
> **Why.** <one sentence — optional but valuable>
> **Date.** <YYYY-MM-DD>
> **Author session.** <user / agent / both>

**Confidence legend:**
- ✅ **Verified** — confirmed by reading the code/config.
- ⚠️ **Likely** — strong inference, not confirmed.
- ❓ **Possible** — pattern match only, needs review.

---

## 1. Direct references

Files, symbols, configs that reference the target literally.

### ✅ Verified

- [`<path>:<line>`](<link>) — <one-line: what this file does
  with the target>
- …

### ⚠️ Likely

- …

### ❓ Possible

- …

---

## 2. Indirect references

Touched via abstractions, reflection, dynamic dispatch.

*(same Verified / Likely / Possible structure)*

---

## 3. Tests

Tests that depend on the target's current shape.

### ✅ Verified

- [`<test path>:<line>`](<link>) — <test name; what it asserts>
- …

### ⚠️ Likely

- …

### ❓ Possible

- …

---

## 4. Documentation

Doc files that reference the target.

- [`<doc path>`](<link>) — <one-line context>
- …

*(No confidence breakdown — docs are simpler.)*

---

## 5. External surfaces

Things outside the repo that may depend on the target.

- ❓ **<surface>** — <one-line. e.g. "OpenAPI clients consuming
  `/v1/inspections` — verify with downstream repos.">
- …

*(Almost always Possible; the skill can't verify externals.)*

---

## 6. Risk summary

A tight read on the overall blast radius.

**Total findings:** <count> *(<verified> verified, <likely>
likely, <possible> possible)*

**Hot spots:**
- <area with the most findings or the most fragile findings>
- …

**The two questions worth asking before you proceed:**
1. <verifiable question — "Does test X actually depend on the
   old shape, or is it incidental?">
2. <verifiable question>

---

## 7. Suggested order of operations

If you're going to do this change, here's a non-binding
suggestion of order. The user picks; this is just the surface.

1. **<step>** — <why first>
2. **<step>** — <why second>
3. **<step>** — <why later>

---

## 8. Adjacent observations *(optional)*

Things outside the audited blast radius that the reader
should know about. One-liners only — don't expand the
report scope.

- <observation>

---

*Generated by `/blast-radius` on <YYYY-MM-DD>. Re-run after the
change ships to verify the radius was mapped correctly. Saved
under `docs/blast-radius/` for future reference.*
```

## Style rules

- **Confidence is heading-level, not parenthetical.** Group
  Verified / Likely / Possible as subheadings under each
  category. The visual separation matters.
- **Emoji are load-bearing.** 💥 (blast radius), ✅ ⚠️ ❓
  (confidence). One emoji per role.
- **Cite via `path:line` clickable links.** No bare paths.
- **Keep findings to one line.** If a finding needs explanation,
  it's the wrong granularity — split it.
- **No tables for findings.** Lists scan faster.
- **"Two questions worth asking" beats "Conclusions".** Forces
  the reader to verify the highest-leverage uncertainties.

## What you must NOT do

- **Don't tag everything as "Likely" to feel safe.** Calibrated
  confidence matters. Verified = read it. Possible = pattern
  match. Don't blur.
- **Don't propose the fix.** This skill maps blast radius;
  fixing follows separately. If the change is so risky it
  needs replanning, surface that — but don't write the new
  plan inside this report.
- **Don't run the actual change.** Read-only. The report
  exists so the user can decide whether to proceed.
- **Don't expand scope.** Adjacent observations footer is
  one-liners; don't grow into a second blast radius.
- **Don't auto-commit.** Standard kit rule.
- **Don't fall back to "no findings" for hard targets.** If a
  scan can't run (e.g. binary asset rename), say so explicitly:
  "Couldn't verify references to binary assets via grep —
  recommend manual asset audit."

## Edge cases

- **Empty repo or no matches at all.** The change has no
  visible blast radius. Surface that explicitly: "No
  references found. Either the target isn't used, or the
  references are dynamic/string-based and grep missed them.
  Verify manually before proceeding."
- **Target name is too generic** (e.g. renaming a function
  called `get`). Grep noise is too high. Stop, ask the user
  to scope by file or module.
- **Polyglot codebase.** Scan each language separately;
  separate findings sections per language if helpful. Don't
  assume one grep covers all.
- **Massive change** (renaming all of `src/auth/`). Spawn
  `Explore` for enumeration; cap report findings at top
  ~30 per category and link to the full grep output.
- **Change spans multiple repos** (microservices). This skill
  scans the current repo only. Surface explicitly: "External
  surfaces — likely to break in <other repo>. Run
  `/blast-radius` separately there."
- **User asks about a change to a file that doesn't exist
  yet.** That's `/plan`, not `/blast-radius`.

## When NOT to use this skill

- **Estimating effort, not risk** → `/scope-check` is the
  surface-area scanner. `/blast-radius` is the
  what-could-break scanner.
- **Designing a new feature** → `/plan`.
- **Reviewing an in-flight PR** → `/review` or `/ultrareview`.
- **Auditing existing code** → `/audit` for a slice,
  `/wrangle` for the whole repo.
- **The change is genuinely small and well-contained** —
  don't bother. Save the skill for when it earns its keep.

## What "done" looks like for a /blast-radius session

A dated markdown report at `docs/blast-radius/<date>-<slug>.md`
with confidence-tagged findings across direct references,
indirect references, tests, docs, and external surfaces.
Uncommitted. The user knows the highest-leverage worries and
the two questions worth verifying before proceeding. After the
change ships, the report is the artifact that lets the team
verify the radius was mapped correctly.
