---
id: TASK-014
type: defect
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P1
completed_by: chazzcoin
---
# TASK-014: Fix dead pointers shipped into every seeded repo

**User story.** As a **developer onboarding a repo**, I want **the links in my
seeded CLAUDE.md to point at things that exist** so that **I am not sent to an
archived repo or a renamed folder on day one**.

## What the stub claimed, and what was actually true

The stub named four defects. **Two of them were wrong**, and verifying before
editing is the only reason they were not "fixed" into breakage.

| Claim | Verdict |
|---|---|
| Archived `claude-orchestrator` link | **True.** One site, shipped to every seeded repo. |
| `/ultrareview` referenced 4× and never built | **False as stated.** It is a Claude Code *harness* command — `bin/check-invocations:66` allowlists it in `BUILTINS`, which is why it never appeared as a dangling ref. It is, however, a **deprecated alias** for `/code-review ultra`. |
| `/migration` exists in no RasaOS Element | **False.** It exists in `rasa.module.cto` (`/Volumes/256GB/vsi-orchestration/content/skills/migration`). Deleting the reference would have been the bug. |
| `bootstrap/` legacy term survives | **True**, and worse than filed — it had also reached `vocabulary.md`, the file that *defines* the vocabulary lock. |

## What changed

- `seed/CLAUDE.md.template` — the archived `ChazzCoin/claude-orchestrator` link
  now points at `rasa.orchestrator.core` and its `SHAPE.md` Pattern 3, where
  that pattern was preserved when the repo was archived.
- `/ultrareview` → `/code-review ultra` at 4 sites (`blast-radius`, `review`,
  `status`, `wrangle`). Not a dead reference — a deprecated one.
- Forbidden legacy vocabulary, per the lock in `vocabulary.md` and the
  workspace contract: `bootstrap/` → `seed/`, `MANIFEST`/`MANIFEST.json` →
  `rasa.json`, across `stamps.md`, `vocabulary.md`, `lint-kit`, `wrangle`,
  `env-rules.md`.
- `task-rules.md` gains a note that `/migration`'s dangling advisory is
  **correct and expected**, so the next session does not delete a working
  cross-Element reference — the trap this task nearly fell into.

## Deliberately NOT changed

- **`content/skills/sync/SKILL.md`** still contains 4 `bootstrap/` references
  and its `MANIFEST.json` / `foundation.json` machinery. `/sync` is dead — it
  gates on files that have not existed since the vocabulary lock — and
  `TASK-041` replaces it wholesale with a port of `domain-core`'s `/sync` +
  `/promote`. Fixing vocabulary in a file scheduled for deletion is waste.
- **`content/skills/contribute/SKILL.md`** — same reason; `TASK-041` retires it.
- **`audit.sh`'s `MANIFEST_PARSERS`** — that variable parses *other* projects'
  dependency manifests (`package.json`, `Cargo.toml`, `go.mod`). Legitimate
  usage of the English word, not the forbidden Element term.
- **"kit-bootstrapped" / "bootstrap mode"** as adjective and verb. The lock
  forbids the `bootstrap/` **folder**, not the English word.

## Acceptance criteria

- [x] No `ChazzCoin/claude-orchestrator` reference in `content/` or `seed/`
- [x] No `/ultrareview` reference remains; all 4 point at `/code-review ultra`
- [x] No `bootstrap/` folder reference outside `skills/sync/`
- [x] No stray `MANIFEST` reference outside `skills/sync/`, `skills/contribute/`
      and `audit.sh`'s parser table
- [x] `/migration` reference retained, with its advisory documented as correct
- [x] `check-manifest` 182, `check-invocations` exit 0, `check-bash32` green
- [x] `bin/lint` 14 findings — identical to baseline, no regression (TASK-055)
