---
name: glossary
description: Generate (or update) `docs/glossary.md` — a single durable reference for every internal term, domain entity, acronym, and project-specific name new contributors and future Claude sessions waste time guessing at. Sources from `README.md`, `CLAUDE.md`, schema/model files, prevalent identifiers in the code, and existing docs. On re-run, syncs additions and surfaces removed/ambiguous terms; never silently overwrites curated entries. Triggered when the user wants a glossary built or refreshed — e.g. "/glossary", "build a glossary", "what does X mean here", "sync the glossary".
---

# /glossary — Build or sync a project glossary

Every codebase grows internal language. New people (and new
Claude sessions) burn hours reverse-engineering what
`InspectionFormField` means or whether `wo` is "work order" or
"week of". This skill produces and maintains a single
`docs/glossary.md` so the answer is one click away.

Per CLAUDE.md ethos: a glossary entry that hedges ("could refer
to either…") is more useful than a confident wrong one. When
terms have ambiguous use, surface that.

## Behavior contract

- **One file: `docs/glossary.md`.** Don't sprawl into multiple
  glossary files. Sections inside the doc are the organization.
- **Two modes: bootstrap and sync.** If the file doesn't exist,
  generate from scratch. If it does, propose additions/updates
  without overwriting curated entries.
- **Source from real signal, not guesses.** Pull terms from
  files on disk: README, CLAUDE.md, schema/model definitions,
  identifiers that appear ≥5× in the code, doc folder.
- **Cite each entry's origin.** Every term has a "first seen
  at" or "primary location" `path:line` so the reader can verify.
- **Categorize honestly.** Domain term, technical term,
  acronym, person/team, vendor — these don't all read the same.
  Group them.
- **Surface ambiguity, don't bury it.** If a term has
  conflicting uses across the codebase, the glossary entry
  flags it explicitly. Don't pick one definition silently.
- **Don't auto-commit.** Same rule as every kit-write skill.
- **Don't edit anything but `docs/glossary.md`.**

## Process

### Step 1 — Detect mode

- `docs/glossary.md` missing → **bootstrap mode**.
- `docs/glossary.md` exists → **sync mode**.

### Step 2 (bootstrap) — Gather candidate terms

Read, in priority order:
1. **`README.md`** — proper nouns, capitalized phrases, terms
   in headings.
2. **`CLAUDE.md`** — names called out as conventions or domain
   entities.
3. **Schema/model files** — class names, enum values, field
   names that are domain language (not generic types).
4. **`docs/decisions/`, `docs/postmortems/`** — terms appearing
   in decision titles or summaries.
5. **Code identifiers** with high frequency — top symbols by
   occurrence count, filtered for project-specific (skip
   stdlib, framework, generic helpers).
6. **Acronyms** — uppercase 2-5 letter sequences appearing in
   docs or comments.

For each candidate term, capture:
- The literal string.
- A "first seen" or "primary location" `path:line`.
- Surrounding context (one sentence) for the inference.

### Step 3 (bootstrap) — Categorize and define

Group candidates into:

- **🏷 Domain entities** — things the business cares about
  (Order, Inspection, WorkOrder, etc.).
- **🛠 Technical terms** — internal abstractions (a service,
  a layer, a custom type).
- **🔤 Acronyms** — expanded forms (PR = Pull Request? or
  Purchase Request? Be specific.).
- **🤝 People / teams / vendors** — named entities the project
  references.
- **🚧 Ambiguous** — terms with conflicting uses; entry calls
  out the conflict.

For each, draft a definition. Two-sentence max:
1. What it is.
2. Where it lives or how it's used.

If a definition can't be inferred from the code/docs with
confidence, mark `<!-- TODO: confirm -->` and surface to the
user at the end.

### Step 4 (sync) — Diff against existing glossary

Read the current `docs/glossary.md`. Parse its terms.

Compute three sets:
- **Still valid** — term in code AND in glossary. Citation
  may need updating; definition stays.
- **New** — term in code, not in glossary. Candidate to add.
- **Stale** — term in glossary, not found in code anymore.
  Candidate to mark deprecated or remove.

Don't touch entries the user has marked `<!-- curated -->` or
similar — treat any in-line comment in the entry as a "hands
off" signal.

### Step 5 — Render the glossary

For both modes, write `docs/glossary.md`:

```markdown
# 📖 <Project> glossary

> Internal terminology, domain entities, acronyms, and
> project-specific names. One source of truth — update via
> `/glossary` or by hand.

**Last updated.** <YYYY-MM-DD>
**Terms:** <count>

> *Conventions:*
> - Each entry shows where the term is primarily used (`path:line`).
> - Entries with `⚠️` have ambiguous or conflicting uses; the
>   note explains.
> - Entries with `<!-- curated -->` after the term are
>   hand-edited; `/glossary` won't overwrite them.

---

## 🏷 Domain entities

### **<Term>**
<Definition — 1-2 sentences. What it is.>

Primary location: [`<path>:<line>`](<relative-link>)
*(Optional: alternative names, related terms.)*

### **<Term>** ⚠️
<Definition.>

**Ambiguous use:** <one-line — where the conflict lives.>

Primary location: [`<path>:<line>`](<relative-link>)

---

## 🛠 Technical terms

*(same structure)*

---

## 🔤 Acronyms

| Acronym | Expansion | Notes |
|---------|-----------|-------|
| `<XYZ>` | <expansion> | <one-line context if needed> |
| ... | ... | ... |

*(Acronyms are the one place a table reads better than a list.)*

---

## 🤝 People / teams / vendors

### **<Name>**
<One-line — who they are, why they're in the codebase.>

---

## 🚧 Ambiguous or contested terms

Terms used inconsistently across the code/docs. Listed for
awareness; the team should pick one usage and clean up.

### **<Term>**

- Used as <meaning A> in [`<path>:<line>`](<link>)
- Used as <meaning B> in [`<path>:<line>`](<link>)

**Recommendation:** <one-line — pick A or B, or rename one.>

---

## ⏳ Possibly stale

*(Sync mode only.)* Terms previously in the glossary but no
longer found in the code/docs. Confirm before removing.

- **<Term>** — last seen at <pinned location, may now be gone>.
  Remove?

---

*Generated by `/glossary` on <YYYY-MM-DD>. Re-run anytime; this
file is regenerable but curated entries are preserved.*
```

### Step 6 — Surface uncertain entries

After writing the file, render in chat:

```markdown
# 📖 Glossary written

`docs/glossary.md` — <count> terms across <category count>
categories.

**Confirmed entries:** <count>
**Need your eyes:** <count>

The following entries had `<!-- TODO: confirm -->` markers — I
couldn't pin down the definition with confidence:

- **<term>** — <one-line — what I'm uncertain about>
- …

Reply with definitions and I'll update. Otherwise, `git diff
docs/glossary.md` to review and commit when ready.
```

If sync mode also surfaced removals:

```markdown
**Possibly stale terms** *(also in the glossary):*

- **<term>** — last citation no longer found in code.
  - (D)elete — remove from glossary
  - (K)eep — historical reference, leave it
  - (A)rchive — move to a "former terms" section
```

## Style rules

- **Bold the term, not the definition.** Reader scans for terms
  first.
- **Two-sentence definitions, max.** A glossary entry that
  needs three sentences belongs in `docs/decisions/` or a
  proper architecture doc.
- **Cite primary location, not all locations.** A term used in
  47 files only needs one canonical pointer.
- **Categorize, don't alphabetize globally.** Categories are
  the navigation. Within a category, alphabetical.
- **Acronyms get a table, terms get a list.** Information
  density per shape.
- **Curated entries are sacred.** If the user added a comment
  inline in the entry (e.g. `<!-- curated -->`), this skill
  never touches it.

## What you must NOT do

- **Don't fabricate a definition.** If you can't tell what a
  term means from the code, mark it `<!-- TODO: confirm -->`
  and ask the user. Don't fill in a plausible-sounding guess.
- **Don't include stdlib or framework names.** `useState`,
  `String`, `Promise` aren't project terminology.
- **Don't auto-resolve ambiguous terms.** If a term has two
  uses, the entry shows both. Picking one is a project decision,
  not a glossary skill's call.
- **Don't auto-commit.** Same rule as every kit-write skill.
- **Don't sprawl into multiple glossary files.** One file.
  Categorize internally.
- **Don't overwrite curated entries.** Read first; preserve
  any entry containing a `<!--` comment.
- **Don't include secrets, internal URLs, or credentials**
  even if they appear as named constants in the code. Glossary
  is for terminology, not configuration.

## Edge cases

- **Repo has no docs/, README is empty.** Glossary still works
  — sources from code identifiers + schema. Note in the doc
  header that it's code-derived only.
- **Term collides with a stdlib/framework name** (e.g. project
  defines a class called `Map` for geographic maps). Disambiguate
  in the entry: "Project-defined Map class — not JS Map."
- **Code uses extremely generic identifiers.** `data`, `item`,
  `value` aren't glossary-worthy. Skip even if frequent.
- **Massive codebase.** Spawn an `Explore` agent to enumerate
  high-frequency identifiers; cap candidate set at ~200 before
  filtering.
- **Glossary already exists but was hand-rolled.** Sync mode
  preserves all entries; only adds new candidates and surfaces
  possibly-stale ones. The user merges manually.
- **User wants per-feature glossaries.** That's not this skill.
  Suggest naming a feature-scoped doc (e.g.
  `docs/glossary-billing.md`) and managing it manually.

## When NOT to use this skill

- **One specific term explanation** ("what does X mean?") →
  ask directly; don't run the whole skill.
- **Architectural deep-dive** → `/audit` for a slice or
  `/wrangle` for the whole repo.
- **Onboarding doc** → `/onboard` or `/export-project`. The
  glossary supports onboarding but isn't onboarding.
- **Project has < ~20 internal terms** → not worth the file.
  Just put the few terms in CLAUDE.md.

## What "done" looks like for a /glossary session

A single `docs/glossary.md` with categorized terms, each citing
its primary location. Bootstrap mode: file freshly generated.
Sync mode: existing entries preserved, new candidates added,
possibly-stale entries surfaced for the user's call. Uncommitted.
The user knows what's confirmed and what needs their definition
to fill in.
