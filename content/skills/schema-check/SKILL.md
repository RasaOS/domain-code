---
name: schema-check
description: Reconcile this project's local schema mirror against an externally-owned canonical schema (iOS Realm models, backend protobufs, OpenAPI specs, GraphQL schemas, partner API docs, etc.). Detects drift between what the canonical source says and what this codebase mirrors. Triggered when the user says — e.g. "/schema-check", "iOS just shipped a new field", "check our models against the API", "is our schema still in sync".
---

# /schema-check — Cross-platform schema reconciliation

When another team or platform owns the canonical data schema and
this codebase mirrors it, drift is the #1 silent-bug source. A
field renamed upstream becomes a quietly-missing field downstream,
and nothing fails loudly until production. This skill exists to
catch that drift.

Per CLAUDE.md: honest reporting. If a field is missing, say so. If
the source-of-truth wasn't reachable, say so plainly — don't
fabricate parity.

## What "schema mirror" means here

A schema mirror is any local representation of data shapes that
the project does **not** own — i.e., another system owns the
canonical definition and this project must stay byte-compatible.
Common shapes:

- **iOS / Android Realm or Core Data models** mirrored in JS/TS
  factory functions or types.
- **Backend protobuf / gRPC** mirrored as client types.
- **OpenAPI / Swagger** mirrored as a generated or hand-written
  client.
- **GraphQL schemas** mirrored as fragment / type definitions.
- **Partner API JSON contracts** mirrored as validators or DTOs.
- **Database column sets** when the database is owned by another
  team.

The pattern is the same: a canonical source exists somewhere else,
this project shadows it, and the only way to stay correct is
periodic reconciliation.

## Behavior contract

- **Identify the canonical source first.** Don't review the local
  mirror in isolation — that just tells you what we have, not
  whether it's right. The canonical source is one of:
  - A file the user pastes or links (Swift class, `.proto` file,
    `openapi.yaml`, schema dump).
  - A path in the repo or a sibling repo (e.g. `../ios-app/Sources/Models/`).
  - A URL or doc the user points to.
  - The user typing the new field(s) directly into chat.
  If you can't get to the canonical source, **stop and ask** —
  don't pretend you can reconcile against something you haven't
  seen.
- **Identify the local mirror second.** Read the project's
  conventions (typically `CLAUDE.md`) to find where mirrors live.
  Common patterns: `src/models/`, `src/types/`, `pkg/proto/`,
  `internal/api/`, `lib/schemas/`.
- **Diff field-by-field, not file-by-file.** A file can be 90%
  identical and still have one renamed field that breaks
  everything. Compare names, types, optionality, defaults, and
  any computed helpers (Swift class methods → JS helper functions,
  proto annotations → client validators).
- **Respect the schema-discipline rule.** Field names are
  byte-identical to the canonical source by contract. Don't
  "correct" upstream typos (a typo in a Realm property name has
  to be mirrored verbatim — fixing it on the mirror side breaks
  parity). Flag the typo as `Note` if it's worth surfacing, never
  as a recommended fix.
- **No fix work in this skill.** Report only. The user routes
  follow-ups through `/task` if remediation is needed.
- **Calibrate confidence.** If you're inferring a type ("looks
  like a string"), say so. If the canonical source is ambiguous
  (e.g. JSON example with no schema), say "couldn't verify type
  — only saw values".

## Process

### Step 1 — Establish the source-of-truth

Ask the user (or infer from `CLAUDE.md`) what canonical source to
reconcile against. Acceptable forms:

1. Pasted text (Swift class, proto, JSON, etc.).
2. Path inside this repo.
3. Path on disk outside this repo (sibling checkout).
4. URL.
5. Single-field input ("they added a field `lastSyncToken: String?`").

If none provided, ask which one before proceeding.

### Step 2 — Locate the local mirrors

Read `CLAUDE.md` for the project's "models" / "schema" /
"types" section. If the project has a registry file (e.g.
`src/firebase/paths.js`, `src/api/types.ts`, `pkg/api/types.go`),
read it too — registries often double as the source-of-truth for
"what we mirror".

Build a list of mirror files in scope.

### Step 3 — Diff

For every entity (class, message, type, schema):

| Check | What you're looking for |
|---|---|
| **Missing fields** | In canonical, not in mirror |
| **Extra fields** | In mirror, not in canonical (sometimes intentional — flag, don't assume bug) |
| **Renamed fields** | Same semantic, different name on each side |
| **Type drift** | Same name, different types (`Int` vs string, optional vs required) |
| **Default drift** | Different defaults / initial values |
| **Helper drift** | Computed methods on canonical that have no mirror helper |
| **Path drift** | If the project has a path/route registry, are new routes mirrored? |

For each finding, record:
- Entity name (class / message / type)
- Field name
- Canonical state vs mirror state
- Severity (see rubric)
- Proposed change (concrete — name + type + default), but **do not apply**

## Severity rubric

- **🔴 Breaking drift** — the mirror will read or write the wrong
  data today. e.g., field exists upstream and our writes don't
  include it; field renamed upstream and our reads point at the
  old name.
- **🟡 Latent drift** — won't break correctness today but will
  bite when the field starts being used. e.g., a new optional
  field added upstream that our writes don't populate yet.
- **🟢 Cosmetic / metadata** — helper functions missing, comments
  out of date, ordering differences. Worth a sweep, not urgent.
- **⚪ Note** — observations the user should know but that aren't
  drift (e.g., "upstream has an obvious typo `enableUnderBusection`
  — per schema discipline, mirror it verbatim, do not fix").

## Output structure

```markdown
# 🔁 Schema check — <entity or scope>

> **Headline.** <one-sentence read. e.g. "Two new fields on
> upstream `WorkOrder` not yet mirrored; one rename detected.">

**Canonical source.** <path / URL / pasted-by-user>
**Local mirror(s).** <comma list of file paths>
**Last reconciled.** <date if known, else "—">

---

## 🔴 Breaking drift

### `<EntityName>.<fieldName>`

**Canonical.** `<type>` (optional? default?) — `path:line` if known
**Mirror.** missing | `<wrong type>` | wrong name (`<our name>`)
**Impact.** <one sentence on what breaks today>

**Proposed change to mirror:**
```diff
  // path/to/mirror/file.ext:line
- <existing line, if any>
+ <proposed line>
```

---

## 🟡 Latent drift

*(same shape)*

---

## 🟢 Cosmetic / metadata

- `<EntityName>.<fieldName>` — <one-line description>
- …

---

## ⚪ Notes

- <observations, including upstream typos to mirror verbatim>
- …

---

## ✅ Verified in sync

Entities (or fields, when checking a specific slice) confirmed
identical between canonical and mirror.

- `<EntityName>` — N fields match
- …

---

## Bottom line

<2–4 sentences. What's the recommended action? "File a TASK to
update the three breaking-drift mirrors before next deploy" or
"Cosmetic only, can defer to next sweep". If remediation is
non-trivial, recommend opening a `/task` for it — name the phase
you'd put it in.>
```

## Style rules

- **Cite `path:line` whenever possible** — both for canonical (if
  it's a file) and mirror.
- **Diff blocks for proposed changes.** Same shape as
  `/update-docs`.
- **Don't recommend "fix the upstream typo".** Schema discipline
  is firm: the mirror matches the canonical, including warts.
- **Don't propose new architecture.** This is reconciliation, not
  redesign. If the drift suggests a structural problem ("we have
  18 fields drifting because no one's reconciled in 6 months"),
  flag it in the bottom line, don't try to solve it inside the
  skill.

## What you must NOT do

- **Don't apply edits.** Report only. Remediation is a separate
  task per the project's normal task flow.
- **Don't invent canonical content.** If the user only pasted
  three fields, you only know about three fields. Don't extrapolate.
- **Don't auto-extend the schema.** "I think they probably also
  added a `dateCreated` field" — no. Only what's in the source.
- **Don't normalize naming.** camelCase vs snake_case mismatches
  are real drift if the canonical uses one and the mirror uses
  the other. Don't silently translate.

## When NOT to use this skill

- **Designing a new schema** that this project owns → just design
  it; this skill is for mirrors.
- **General code review** → `/review` or `/audit`.
- **Filing a remediation task** → `/task` (this skill produces
  the report; `/task` files the work).
- **Doc reconciliation generally** → `/update-docs`.

## What "done" looks like for a /schema-check session

A single rendered report. The user knows precisely what's in sync,
what's drifted, and what severity. Remediation routes through
`/task`. No file edits in this skill.
