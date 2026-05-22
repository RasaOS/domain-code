---
name: wrangle
description: Wrangle a chaotic or unfamiliar codebase into something clean, organized, and understood. Two phases — Phase 1 is a read-only deep audit (architecture, flows, data models, data/UI layers, infra, startup, auth) that writes durable `.md` reference docs under `docs/wrangle/` AND produces a tight Claude-targeted summary at `.claude/context/project-map.md` so future sessions land cold with project context already loaded. Phase 2 is a tailored plan of low-risk cleanups (dead code, commented-out blocks, obvious smells) plus offers for deeper reviews — nothing edited without explicit user consent. Triggered when the user wants to "wrangle", "tame", "make sense of", or "clean up" an existing codebase — e.g. "/wrangle", "wrangle this repo", "I just inherited this, help me understand it", "let's tame this codebase".
---

# /wrangle — Tame an existing codebase

Take a chaotic or unfamiliar repo and wrangle it into something the
user can actually reason about. Two phases, in order, with a hard
gate between them.

Per CLAUDE.md ethos: blunt resonant honesty, calibrated confidence,
no narratives. If something is unclear after reading, say so — don't
guess to fill the doc.

## The two phases

**Phase 1 — Read-only audit + context bundle.** Read everything
in scope. Produce two complementary artifacts:

1. **Deep human reference** — a set of durable `.md` files under
   `docs/wrangle/` (architecture, data model, startup, auth, etc.).
   Long-form, browsable, dated context.
2. **Claude-targeted context bundle** — a tight summary at
   `.claude/context/project-map.md` that future sessions read
   alongside `CLAUDE.md` to land cold with project context
   already loaded. Indexes into the deep docs.

If `CLAUDE.md` is missing or is the bootstrap stub, Phase 1 also
offers (with consent) to draft a populated `CLAUDE.md` from the
audit findings. No edits to source code, ever.

**Phase 2 — Tailored plan.** Based on what Phase 1 found, propose
a prioritized list of cleanups and follow-ups. The user picks what
to act on. **Nothing executes without explicit consent.**

The boundary between phases is hard. Phase 1 ends with "here's what
I found, written to `docs/wrangle/`." Phase 2 starts only when the
user has read (or skimmed) Phase 1 and says go.

## Behavior contract — overall

- **Read-only by default.** This skill is allowed to create files
  under `docs/wrangle/` and `.claude/context/` only — plus, with
  explicit user consent, a fresh `CLAUDE.md` if one doesn't already
  exist. It must not edit source code, config, or any other path
  during Phase 1. Phase 2 only proposes — it does not apply.
- **Write durable docs, not chat reports.** Phase 1 outputs are
  files on disk so the user (and future sessions) can refer back.
  The chat response after Phase 1 is a short index of what was
  written and a one-paragraph headline read.
- **Honest confidence.** Verified-by-reading claims are stated
  flat. Inferences are marked "I think" / "likely" / "couldn't
  verify". I-don't-know is a valid answer and goes in the docs.
- **Stay in scope.** If the user pointed at a repo, audit the repo.
  If they pointed at a subdirectory or feature, audit that. Don't
  unilaterally expand. Adjacent observations go in a footer, not
  the body.
- **No narratives, no soft no's, no soft yes's.** "This is mostly
  fine, but…" is banned. Either it's fine or it isn't.
- **Never auto-commit.** Created docs land in the working tree,
  uncommitted. The user reviews and commits when ready.

## Phase 1 — Read-only audit

### What to cover

For each area, read enough source to make a verified claim, then
write it down. Skip areas that genuinely don't apply (e.g. no auth
in a CLI tool) — note the absence rather than padding.

1. **Repo shape & entry points.** Top-level layout, package
   manifests, build/run scripts, where execution begins (main,
   server bootstrap, app entry, CLI command).
2. **Startup flow.** From process start to "ready to serve / render
   / accept input" — what loads, in what order, what it depends on.
3. **Architecture & module boundaries.** The layers that exist
   (e.g. routing, services, data, UI, infra), how they call each
   other, where the seams are (and aren't).
4. **Data model.** Domain entities, their shapes, where they're
   defined, where they're persisted, where they're transformed.
   Include a small ER-style sketch if it helps.
5. **Data layer.** How the app reads/writes — ORM, raw SQL, REST,
   GraphQL, RPC, file IO, queues. Caching, pagination, retries.
6. **UI layer (if any).** Component tree shape, state management,
   styling approach, routing, where business logic leaks into
   views.
7. **Database / cloud infrastructure.** What backs the app — DBs,
   buckets, queues, caches, third-party services. How config /
   secrets are wired.
8. **Auth (if any).** Identity provider, session model, where
   credentials live, where authorization decisions are made,
   public vs. authed surfaces.
9. **External integrations.** Third-party APIs, webhooks, cron /
   scheduled jobs, background workers.
10. **Tests & verification.** What kinds of tests exist, what's
    covered, how they run, what's missing.
11. **Build, deploy, environments.** How a change becomes
    production. CI/CD, environments, feature flags, release
    discipline.
12. **Smells & risks.** Verified concerns from reading the code —
    not vibes. Each item cites `file_path:line_number`.
13. **Dependency inventory.** Every external library, SDK,
    package, and third-party service the project uses, with
    versions, purposes, and official doc URLs. Parsed from
    every manifest file in the repo (`package.json`,
    `Package.swift`, `Podfile.lock`, `requirements.txt`,
    `pyproject.toml`, `build.gradle*`, `Gemfile.lock`,
    `go.mod`, `Cargo.lock`, etc.). This file becomes the
    **starting reference for future task work's external
    reconnaissance** (per `/task` Operation 3, which fetches
    current docs from these sources before drafting specs).

### Where to write

Under `docs/wrangle/` at the repo root. Create the directory if
missing. One file per area, plus an index:

```
docs/wrangle/
  README.md                   # index + headline read
  01-repo-shape.md
  02-startup-flow.md
  03-architecture.md
  04-data-model.md
  05-data-layer.md
  06-ui-layer.md              # omit if no UI
  07-infrastructure.md
  08-auth.md                  # omit if no auth — note in README
  09-integrations.md
  10-tests.md
  11-build-deploy.md
  12-smells-and-risks.md
  13-dependencies.md          # external libs / SDKs / services + doc URLs
  questions.md                # things you couldn't verify
```

Number the files so they sort in reading order. Omit any area that
genuinely doesn't apply — and say so in `README.md` rather than
writing a stub.

### How to write each doc

Each area doc follows the same shape:

```markdown
# <Area name>

> **Read.** <one-sentence verified claim about this area. Not
> "looks fine" — something specific.>

## What's actually here

<2–6 paragraphs or a tight bulleted list. Cite files as
`path:line`. Include code snippets only when they make a point —
≤15 lines each, with a one-line "why this matters" after.>

## How it fits

<2–4 sentences on how this area connects to the rest of the
system. If the boundary is fuzzy, say so.>

## Open questions

<Bulleted list of things you couldn't verify from reading the
code. Each item ≤1 line. If empty, omit the section.>
```

### `docs/wrangle/13-dependencies.md` shape

This file uses a different shape — tabular, optimized for
future task work to look up doc URLs quickly. Build it by
parsing every manifest in the repo and capturing each
external dependency.

```markdown
# Dependencies & external services

> **For future task work.** When `/task` does external
> reconnaissance (per `/task` Operation 3, Step 3.3), this file
> is the starting list of doc URLs to fetch. Keep it current —
> re-run `/wrangle` after major dep changes.

**Audited at.** `<short SHA>` on <YYYY-MM-DD>
**Manifest sources read.** <list paths: `package.json`,
`Package.swift`, etc.>

## Libraries & frameworks (vendored code we link)

Pulled from the project's package manifests. Skip stdlib /
trivial helpers — focus on load-bearing deps.

| Library | Version | Used for | Docs |
|---|---|---|---|
| `<name>` | `<version>` | <one-line purpose in this project> | <full doc URL> |
| `<name>` | `<version>` | <purpose> | <URL> |

*(Examples per stack — adapt to what the project actually uses:*
- *iOS — SwiftUI, Combine, AVKit, Realm, Kingfisher, Alamofire*
- *Android — Jetpack Compose, Room, Hilt, Coroutines, Coil*
- *Web — React, Next.js, Vue, axios, Tailwind, shadcn*
- *Python — Flask, FastAPI, Django, SQLAlchemy, Pydantic*
- *Cross-cutting SDKs — Firebase, Stripe, OpenAI, Anthropic SDK)*

## Third-party services & APIs (runtime integrations)

Services the running app calls — usually paired with an SDK
above (Firebase has both an SDK and a service surface; OpenAI
has both). List the service-side facts: what we call, what
endpoints, what we depend on.

| Service | Used for | Docs |
|---|---|---|
| <name> | <purpose — auth / storage / analytics / etc.> | <URL> |
| <name> | <purpose> | <URL> |

## Dev / build / CI dependencies

Tools that don't ship with the app but matter for development.
Test runners, build tools, linters, CI utilities, formatters.

| Tool | Version | Purpose | Docs |
|---|---|---|---|
| <name> | <version> | <purpose> | <URL> |

## Notes

<2–4 bullets — anything worth flagging:*
- *deprecated deps*
- *deps with known security advisories*
- *deps locked to old versions for compat reasons*
- *missing doc URLs for in-house libs (link the source)*
```

### `docs/wrangle/README.md` shape

```markdown
# Wrangle — <repo or scope name>

> **Headline.** <one sentence on the overall read. Specific.>

**Audited at.** `<short SHA>` on <YYYY-MM-DD>
**Scope.** <directories or features actually read>
**Approx. lines read.** <count>

## Index

1. [Repo shape & entry points](01-repo-shape.md)
2. [Startup flow](02-startup-flow.md)
3. [Architecture & module boundaries](03-architecture.md)
4. [Data model](04-data-model.md)
5. [Data layer](05-data-layer.md)
6. [UI layer](06-ui-layer.md) *(omit line if N/A)*
7. [Infrastructure](07-infrastructure.md)
8. [Auth](08-auth.md) *(omit line if N/A — note absence below)*
9. [External integrations](09-integrations.md)
10. [Tests & verification](10-tests.md)
11. [Build, deploy, environments](11-build-deploy.md)
12. [Smells & risks](12-smells-and-risks.md)
13. [Dependency inventory](13-dependencies.md)
14. [Open questions](questions.md)

## What I couldn't audit

<List anything skipped + why. e.g. "No auth — this is a public
read-only CLI." or "Skipped iOS subproject — out of scope.">
```

### Claude-targeted context bundle

The deep `docs/wrangle/` files are for human reading. Future
Claude sessions need a *tighter* artifact they can load on
session start without having to read 13 files. Phase 1 also
writes `.claude/context/project-map.md`:

```markdown
# Project map — <repo name>

> **For Claude sessions.** Tight context map. The deep reference
> docs live under `docs/wrangle/`; this file is the index Claude
> reads on session start to land cold with project context.

**Audited at.** `<short SHA>` on <YYYY-MM-DD>

---

## What this project is

<2-3 sentences. Verified-by-reading. From `docs/wrangle/01-repo-shape.md`
+ `03-architecture.md`. No marketing voice.>

## Tech stack

- **<Language + runtime>** — [docs](URL)
- **<Framework(s)>** — [docs](URL)
- **<DB / persistence>** — [docs](URL)
- **<Other load-bearing deps>** — [docs](URL)

*(Full inventory with versions: [`docs/wrangle/13-dependencies.md`](../../docs/wrangle/13-dependencies.md))*

## Where execution starts

<2-3 sentences naming the entry point and what it does at boot.
Cite `path:line`. From `docs/wrangle/02-startup-flow.md`.>

## Key boundaries

<3-5 bullets — the layer seams that matter. Each one-line, with
the directory or file that anchors it.>

- **<layer>** at `<path>` — <one-line role>
- …

## Data model in 5 lines

<5 bullets max — the entities a contributor needs to know
exist. From `docs/wrangle/04-data-model.md`.>

- **<Entity>** — <one-line role>
- …

## Auth

<One sentence + cite. Or "No auth — this is a public/CLI tool."
From `docs/wrangle/08-auth.md`.>

## Sharp edges

<3-5 bullets — the gotchas a fresh contributor will hurt
themselves on. From `docs/wrangle/12-smells-and-risks.md` (only
the ones tagged dangerous, not all smells).>

- **<gotcha>** — <one-line warning + cite>
- …

## Where to dig

| Need | File |
|---|---|
| Architecture deep-dive | [`docs/wrangle/03-architecture.md`](../../docs/wrangle/03-architecture.md) |
| Data model | [`docs/wrangle/04-data-model.md`](../../docs/wrangle/04-data-model.md) |
| Startup flow | [`docs/wrangle/02-startup-flow.md`](../../docs/wrangle/02-startup-flow.md) |
| Auth | [`docs/wrangle/08-auth.md`](../../docs/wrangle/08-auth.md) |
| Tests | [`docs/wrangle/10-tests.md`](../../docs/wrangle/10-tests.md) |
| Build & deploy | [`docs/wrangle/11-build-deploy.md`](../../docs/wrangle/11-build-deploy.md) |
| Open questions | [`docs/wrangle/questions.md`](../../docs/wrangle/questions.md) |

*(Omit rows for any wrangle file that wasn't created.)*

## Past audits & decisions

- Recent audits: see `docs/audits/`
- Architectural decisions: see `docs/decisions/`
- Postmortems: see `docs/postmortems/`
- Regrets: see `docs/regrets/`

---

*Generated by `/wrangle` on <YYYY-MM-DD>. Re-run wrangle when
the project shape shifts; this file is regenerable. Past
versions live in git history.*
```

This file is **deliberately concise**. Aim for under 200 lines.
The deep docs do the heavy lifting; this is the index.

### Drafting CLAUDE.md *(if absent or stub)*

Read `CLAUDE.md` at the repo root.

- **No `CLAUDE.md`** → offer to draft one from the audit
  findings. Ask explicitly:

  ```markdown
  No `CLAUDE.md` at the repo root. The kit's working contract
  lives there — and Claude sessions read it on start.

  Want me to draft a `CLAUDE.md` from the audit findings?
  Tech stack, conventions, the gotchas surfaced, the
  rules-of-thumb implied by the code. You'll review and edit
  before it's the working contract; I won't commit.
  ```

  On approval: write a CLAUDE.md grounded in `docs/wrangle/`.
  Use the kit's `bootstrap/CLAUDE.md.template` as the shape
  (read from the kit if available).

- **`CLAUDE.md` exists and looks like the bootstrap stub**
  (mostly placeholder, very short, has `<TODO>` markers) →
  same offer: "Looks like CLAUDE.md is mostly stub. Want me to
  populate it from the audit?" Same consent path.

- **`CLAUDE.md` exists and has substance** → leave it alone.
  This skill never overwrites a populated CLAUDE.md. Surface
  in the closing summary that CLAUDE.md was preserved as-is.

### Phase 1 chat response

After writing the files, the chat response is **short**:

```markdown
# 🪢 Wrangle — Phase 1 complete

> **Headline.** <same one-sentence read as the README.>

**Wrote:**
- <N> deep reference docs under [`docs/wrangle/`](docs/wrangle/)
- [`.claude/context/project-map.md`](.claude/context/project-map.md)
  — tight Claude-targeted context map
- *(if applicable)* [`CLAUDE.md`](CLAUDE.md) — drafted from audit
  findings, awaiting your edits

**The three things most worth knowing right now:**
1. <terse, specific>
2. <terse, specific>
3. <terse, specific>

Future Claude sessions can read `.claude/context/project-map.md`
on start for fast context. The deep docs are linked from there.

Phase 2 (cleanup plan) is ready when you are. Say "go" to see it,
or read the docs first and come back.
```

That's the whole Phase 1 chat response. No retelling of every doc.
The docs are the artifact.

## Phase 2 — Tailored plan (consent-gated)

Only run Phase 2 after the user explicitly asks for it.

### What goes in the plan

Tailor the plan to what Phase 1 actually found. Don't generate a
generic checklist. Group items by tier:

- **Tier 1 — Quick wins, low risk.** Mechanical or near-mechanical
  cleanups the user can approve in one read. Examples:
  - Remove commented-out code (with file:line citations).
  - Remove obvious dead code (verified unreachable, not "I think
    unused").
  - Delete stale TODO/FIXME comments that have been resolved.
  - Fix trivially broken imports / unused imports.
  - Normalize obvious formatting drift (only if a formatter is
    already configured — don't introduce one).

- **Tier 2 — Targeted reviews worth doing.** Non-trivial but
  bounded. Each is a candidate for a follow-up `/audit` or `/plan`
  session. Examples:
  - "The auth flow has three branches that diverge at
    `auth.ts:142` — worth a focused audit."
  - "Data layer mixes ORM and raw SQL — worth deciding on one."

- **Tier 3 — Bigger questions for the user.** Things that need
  human judgment before any plan can form. Examples:
  - "Is the legacy `/v1` API still used? If not, we can carve it
    out."
  - "There's no test layer above unit — do you want one?"

- **Open offers.** A short list of "do you want me to dig into X?"
  prompts based on what Phase 1 surfaced. Plus an explicit:
  "Anything you're worried about, confused by, or want to
  understand better? Tell me and I'll take a look."

### Plan output shape

Render in chat (this is a plan, not a doc — it changes as the user
responds):

```markdown
# 🪢 Wrangle — Phase 2 plan

Tailored to what Phase 1 found. Nothing here runs without your
explicit go-ahead, item by item.

## Tier 1 — Quick wins

- [ ] **<short claim>** — <one-line why, with file:line>. Effort:
  <S/M>. Risk: <low/none>.
- …

## Tier 2 — Targeted reviews

- [ ] **<short claim>** — <one-line why>. Suggest: `/audit <target>`
  or `/plan <topic>`.
- …

## Tier 3 — Questions for you

- **<question>** — <why it matters; what changes based on the
  answer>
- …

## What else can I look at?

I can dig deeper into any of these if you want:

- <area from Phase 1, one line>
- <area from Phase 1, one line>
- <area from Phase 1, one line>

Or — anything you're worried about, confused by, or want to
understand? Name it and I'll take a look.

---

**To act on Tier 1**: tell me which items (e.g. "all of them",
"items 1, 3, 5", "skip the import cleanup"). I'll apply them to
the working tree, uncommitted, so you can review with `git diff`
and commit when ready.

**To go deeper on Tier 2**: name the item and I'll route it
through `/audit` or `/plan`.
```

### Applying Tier 1 items

When (and only when) the user picks specific Tier 1 items:

- Apply them to the working tree.
- **Do not commit.** The user reviews `git diff` and commits.
- After applying, render a short summary: what was changed, what
  was skipped, suggested commit message (one line).
- If a "quick win" turns out to be non-trivial once you start
  reading more closely, **stop and surface it** — don't expand
  scope silently. Move it to Tier 2 in the plan.

## Style rules

- **Imperative, specific, cited.** "Remove the commented block at
  `src/foo.ts:42-58`." not "consider cleaning up old code".
- **Code snippets ≤15 lines, always cited as `path:line`.**
- **Emoji are load-bearing.** 🪢 marks wrangle output. Don't
  sprinkle others.
- **Bold the claim, then dash, then the reason.** `- **Claim** —
  reason.`
- **No tables in the plan.** Lists scan faster for actionable
  items.
- **No "let me know if you have questions" sign-offs.** End on the
  last actionable section.

## What you must NOT do

- **Don't edit source code in Phase 1.** Read-only means
  read-only. The only writes allowed are files under
  `docs/wrangle/`, `.claude/context/project-map.md`, and —
  with explicit user consent — a fresh `CLAUDE.md` if none
  exists.
- **Don't overwrite a populated `CLAUDE.md`.** If a substantive
  CLAUDE.md already exists, leave it. The drafted CLAUDE.md
  path is for projects that are missing one or have only the
  kit bootstrap stub.
- **Don't auto-run Phase 2.** Wait for the user to ask. They may
  want to read the docs first, or may want to stop after Phase 1.
- **Don't apply Tier 1 items en masse without the user picking
  them.** "Apply all" is fine if the user says it; assuming it
  is not.
- **Don't auto-commit.** Same rule as every other skill that
  modifies files.
- **Don't pad docs.** A section with nothing real to say gets
  omitted, not stubbed. The reader's time matters.
- **Don't extrapolate.** If the code doesn't show it, you don't
  know it. "Couldn't verify" is a valid answer and goes in
  `questions.md`.
- **Don't expand scope unilaterally.** If you find something
  important outside the audited scope, mention it as an adjacent
  observation in the README — don't silently audit it too.
- **Don't replace `/audit` or `/plan`.** Wrangle covers the whole
  repo at a coarse grain and produces durable docs. For a focused
  read on one slice, route to `/audit`. For designing new work,
  route to `/plan`.

## Edge cases

- **Repo is huge.** Spawn an `Explore` agent for the initial
  enumeration (file tree + entry points + manifests), then read
  the highest-leverage files yourself. Document what you read vs.
  what you skipped at the top of `docs/wrangle/README.md`.
- **`docs/wrangle/` already exists with prior output.** Don't
  silently overwrite. Surface it: "There's a previous wrangle
  from `<date>`. Update in place, archive it to
  `docs/wrangle/archive/<date>/`, or stop?" Same rule for
  `.claude/context/project-map.md`.
- **Working tree is dirty.** Warn before writing — the user might
  lose track of which files came from where. Offer to abort.
- **No source docs at all (no README, no CLAUDE.md).** Wrangle
  still works — you just won't be able to cite project intent.
  Note that explicitly in the README headline.
- **Mid-Phase-1, you find something dangerous** (hardcoded
  secret, trivially exploitable code path). Stop the audit, tell
  the user immediately, then resume after they decide what to do.

## When NOT to use this skill

- **You already understand the codebase** → use `/audit` for a
  focused slice or `/onboard` for a guided walkthrough of
  documented projects.
- **You want a focused review of one feature or directory** →
  `/audit`.
- **You're designing new work** → `/plan`.
- **You're reconciling docs that already exist** → `/update-docs`.
- **You're reviewing a PR** → `/review` or `/ultrareview`.
- **You want to actually fix things without a plan stage** →
  describe what to fix directly; don't run wrangle just to skip
  to edits.

## What "done" looks like for a /wrangle session

- **After Phase 1:** `docs/wrangle/` exists with an index README
  and one file per audited area; `.claude/context/project-map.md`
  exists as the tight Claude-targeted index; if CLAUDE.md was
  missing/stub, a drafted CLAUDE.md exists (with consent),
  uncommitted, awaiting user edits. Chat response is a short
  headline + the three things most worth knowing + an offer to
  run Phase 2. Future Claude sessions in this project land cold
  with project context already loaded.
- **After Phase 2 (if run):** A tailored plan rendered in chat,
  with Tier 1/2/3 items and open offers. Any approved Tier 1
  items applied to the working tree, uncommitted. The user knows
  exactly what changed and what to do next (`git diff` + commit).
