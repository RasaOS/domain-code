# CLAUDE.md — `rasa.domain.code`

Per-repo working contract for Claude sessions opened inside this
folder (the **Element repo itself**, not a project that has the
Element installed). Extends `~/.claude/CLAUDE.md` and the workspace
`~/rAI/rasa-os/CLAUDE.md`; does not override them.

## What this is

You are working on **`rasa.domain.code`** — the canonical RasaOS
engineering toolkit. Portable, language-agnostic, repo-agnostic
foundation that ships skills, rules, agents, build infrastructure,
and templates Claude Code sessions use across any engineering project.

Originally `claude-kit` (pre-RasaOS); locked to RasaOS canon v1.0.0
vocabulary 2026-05-21 at commit `63cdd56`; declares conformance to
Element Contract v1.3.0 as of v0.42.0 (2026-05-24).

## The two-level distinction

- **This folder = the kit repository.** Edits here change what
  every project that installs `rasa.domain.code` will eventually
  get via `/sync`. High blast radius. Treat as a published library.
- **A project that has `bin/init` installed = an install target.**
  Different concern. The project's own work happens there, gated by
  the toolkit's skills + rules. That work is NOT this repo's
  concern.

## Source of truth

- **`~/rAI/rasa-os/canon/`** — authoritative for everything architectural.
  Current LOCKED is v1.2.0; current WORKING is v1.3.0 IN PROGRESS.
  Spec §6 defines the `domain` kind; ELEMENT_CONTRACT.md §4 defines
  required files; §7 defines install policies.
- **`~/rAI/rasa-os/elements/domain-core/` v1.0.0** — the unified
  domain template `rasa.domain.code` conforms to. The shape locked
  there is the minimum every domain Element follows. This Element
  exceeds the minimum substantially (full toolkit), but the shape
  is conformant.
- **`~/rAI/rasa-os/CLAUDE.md`** — workspace orientation (the
  `rasa.tenant.rasaos` tenant's contract); role-split is locked
  there.
- **This folder's `README.md`** — full description.
- **This folder's `rasa.json`** — formal Connection Contract
  declaration with 39 element.files[] + 28 seed.files[] entries.

## Shape pattern

`rasa.domain.code` follows the **toolkit shape pattern** (per
`elements/domain-core/content/SHAPE.md` Pattern 1):

- `content/skills/` — 78 skill folders (one per skill capability)
- `content/agents/` — 4 Claude subagent definitions
- `content/modes/` — operating modes (drive prose)
- `content/build/` — pipeline scaffolding
- `content/tests/` — test infrastructure
- 27 root-level rule files in `content/` (task-rules.md,
  craft-rules.md, git-flow-rules.md, etc.)
- `seed/` — 28 templates (CLAUDE.md, AUDIT, PHASES, ROADMAP,
  RELEASES, MIGRATIONS, ENV, TESTS, runtime + test templates, etc.)

This is the most-developed canonical implementation of the toolkit
pattern.

## rasa.json discipline (manifest-driven)

`bin/init` (install) and `/sync` (update) both read `rasa.json` —
neither has a hardcoded file list. Consequences:

- **Adding a kit file is a one-line `rasa.json` edit.** Put the file
  under `content/` or `seed/`, register it, and both `bin/init` and
  `/sync` pick it up.
- A file committed under `content/` or `seed/` but **not** registered
  silently never ships. Nothing else catches this — `bin/check-manifest`
  does.
- A file added under a directory already covered by a
  `directory-mirror` entry needs no manifest change.

## Verify before you finish

- **`bin/check-manifest`** — verifies `rasa.json` is a complete,
  accurate inventory of `content/` + `seed/`. Run after adding or
  removing any kit file, and before tagging a release. **It must
  pass.**
- Scripts (`bin/`, the shipped hooks) — syntax-check and exercise
  them. Standard smoke test: `bin/init` into a temporary directory.
- **`bin/lint`** — domain-code-specific markdown linting for shipped
  skill files. Run before tagging.

## Vocabulary lock

Per workspace `CLAUDE.md` + canon `02_brand_kit.html` §XI +
ELEMENT_CONTRACT §8 + §8a:

**Forbidden legacy terms** (do not introduce; fix on touch):
- `kit` → `Element`
- `MANIFEST.json` → `rasa.json`
- `bootstrap/` → `seed/`
- `foundation.json` → `rasa.lock.json`
- `manifest contract` → `Connection Contract`

**Install vs Pull** (canon v1.2.0 + v1.3.0):
- `install` = `bin/init` copies content INTO a consumer's `.claude/`
  (Pattern 1, what `rasa.domain.code`'s `bin/init` does)
- `pull (Element)` = kernel ingests Element at `/rasa/modules/<name>/`
  (Pattern 2)
- `pull (Tenant)` = kernel mounts tenant repo at `/rasa/app/`
  (Pattern 3, new in v1.3 SA-018)

## Don'ts

- **Don't bulk-edit `content/`** — each file ships to every install
  target. Surgical edits per skill, one file at a time, tested before
  the next change.
- **Don't author MANIFEST.json or any legacy-shape files.** Vocabulary
  is locked.
- **Don't add unregistered files** under `content/` or `seed/`. They
  silently never ship; `bin/check-manifest` catches but it's better
  to register inline as you add.
- **Don't install `bin/init` into this Element's own folder.** Per
  workspace `CLAUDE.md`: Element repos do not get `bin/init`'d into
  themselves; `content/` is the source.
- **Don't shape decisions casually.** Anything that changes the
  toolkit shape (new top-level content/<subdir>/, new seed template
  category) should be considered for promotion into
  `rasa.domain.core` (the unified template) — flag to user before
  committing.

## How a version bump works

- **Patch (0.41.x → 0.41.y)** — bug fix to existing skill/rule/agent;
  doc improvement; no new files.
- **Minor (0.41.x → 0.42.0)** — new skill, new rule, new agent, new
  seed template, capability category. Existing projects can pull via
  `/sync` without breakage.
- **Major (0.x → 1.0)** — first stable lock-down OR breaking change
  requiring projects to re-init.

Each bump: edit `VERSION`, update `rasa.json#version`, write a
CHANGELOG.md entry. Commit + tag + push. Update
`~/rAI/rasa-os/elements/REGISTRY.md` + `~/rAI/rasa-os/elements/CHANGELOG.md`
(workspace orchestrator's seat) with the new SHA + version.

## What success looks like

- A new project that installs `rasa.domain.code` via `bin/init`
  gets a fully-equipped Claude Code engineering environment with
  zero per-project configuration.
- Updates to the kit propagate cleanly via `/sync`; per-project
  customization sits at `.claude/<file>-overrides.md` (skills
  resolve overrides first, fall back to kit defaults).
- The kit stays platform-agnostic — iOS / web / Python / Go all
  work through the same skill set (with platform-prefix files as
  hints, never gates).
- `bin/check-manifest` passes on every commit; `bin/lint` passes on
  every release.
