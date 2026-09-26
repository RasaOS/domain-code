# Reference stamp models

Canonical models for every kit-tracked **reference stamp**. New
entries follow the model; skills parse them; humans read them.

This file is the registry. Adding a new stamp model means adding
an entry here AND shipping a seed template that demonstrates
the model.

> **What's a reference stamp?** YAML frontmatter at the top of a
> kit-conventional markdown file — the machine-readable identity
> that skills parse. The body below is the qualitative context
> for humans and AI. See `vocabulary.md` for the term definition.

> **Where this file lives.** The kit ships this as `kit/stamps.md`.
> After `/sync`, it lands at `.claude/stamps.md` (file-replace each
> sync). Project-specific stamps live where their model declares
> (e.g. `.claude/runtimes/<name>.md`).

---

## Universal conventions

These apply to every stamp model unless an entry explicitly says otherwise.

### Field naming

- **snake_case** for multi-word fields (`pulls_from`, not `pullsFrom`).
- **Lowercase** always.
- **Booleans**: `is_<predicate>` (e.g. `is_breaking`).
- **Dates**: ISO `YYYY-MM-DD` or `YYYY-MM-DD HH:MM` strings (not epoch ints).
- **Cross-references**: by `name` string only. The orchestrating
  skill resolves names to filenames.

### Universal fields (every stamp)

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string (kebab-case) | Stable identity. Matches filename. |
| `kind` | yes | string (discriminator) | Sub-type within the stamp model. |
| `tags` | no | array of strings | Free-form classification. |

### Evolution rules

- **Adding a field** is additive. No version bump needed.
- **Removing a field** is breaking — CHANGELOG entry with
  "Structural change worth flagging" so `/sync`'s §25 alert fires.
- **Renaming a `kind`** is breaking. Same.
- **Changing a field's type** is breaking. Same.

### Validation

A future `kit/skills/stamp/stamp.sh validate <file>` will check a
stamp against its declared model in this file. Ground laid; not
shipped yet. The `kit/skills/runtime/runtime.sh check` script
already validates runtime stamps specifically.

---

## Stamp: cloud

**Where it lives:** `.claude/clouds/<name>.md`
**Purpose:** Describe a cloud / deployment surface (one file per surface).
**Shipped in:** v0.16.0

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string | Stamp identity. Matches filename. |
| `provider` | yes | enum | firebase / azure / aws / gcp / cloudflare / vercel / netlify / self-hosted / other |
| `kind` | yes | enum | hosting / database / compute / registry / storage / ml / queue / auth / cdn / monitoring / other |
| `environments` | yes | array | Env names supported (e.g. [dev, staging, prod]) |
| `pulls_from` | no | array | Names of other clouds this depends on (e.g. [azure-acr]) |

Cross-references resolve to sibling files: `pulls_from: [azure-acr]`
means `.claude/clouds/azure-acr.md` is a related surface.

---

## Stamp: runtime

**Where it lives:** `.claude/runtimes/<name>.md`
**Purpose:** Describe a runnable thing in the project.
**Shipped in:** v0.18.0; env profiles + preflight in v0.19.0

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string | Stamp identity |
| `kind` | yes | enum | dev-server / mobile-app / script / worker |
| `language` | yes | string | python / javascript / typescript / swift / kotlin / etc. |
| `framework` | no | string | fastapi-uvicorn / vite-react / swiftui / etc. |
| `commands` | yes | object | install / dev / build / test / lint |
| `ports` | depends on kind | object | Port per command (dev-server only) |
| `env.template` | no | string | Committed example env file (`.env-template`) |
| `env.file` | yes | string | Default local env file (`.env`) |
| `env.environments` | no | object | Named profiles → env file paths (`{local: ".env", test: ".env.test", production: ".env.production"}`) |
| `env.required` | yes | array | Required env var names |
| `env.optional` | no | object | Optional env vars with defaults |
| `depends_on` | no | array | Service dependencies — each item: `{name, check}` |
| `health_check` | depends on kind | object | `url`, `expect_status`, `timeout_seconds` (dev-server only) |
| `process.type` | yes | enum | long-running / build-and-run / one-shot |
| `simulator` | depends on kind | object | Default device + OS version (mobile-app only) |
| `queue` | depends on kind | object | name + broker config (worker only) |

The `depends_on[].check` is a shell command. `runtime.sh check`
runs each and reports pass/fail. Common patterns:

```yaml
depends_on:
  - { name: postgres, check: "pg_isready -h localhost -p 5432" }
  - { name: redis,    check: "redis-cli ping" }
  - { name: api,      check: "curl -s http://localhost:8000/health" }
```

The `env.environments` map enables named profiles:

```yaml
env:
  template: .env-template       # committed example
  file: .env                    # default for local runs
  environments:                 # keys = .claude/environments.json
    local: .env
    staging: .env.staging
    prod: .env.production
  required: [JWT_SECRET, POSTGRES_DB_HOST, OPENAI_API_KEYS]
```

Run with a specific profile: `runtime.sh check api --env staging`.

---

## Stamp: test

**Where it lives:** `.claude/tests/<name>.md`
**Purpose:** Declare an integration test scenario.
**Shipped in:** v0.18.0

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string | Stamp identity |
| `kind` | yes | enum | endpoint-test / flow / e2e / smoke / contract / regression / unit |
| `description` | yes | string | One-sentence purpose |
| `runtimes_required` | yes | array | Names of runtimes the test needs running |
| `verification.type` | yes | enum | script (only kind currently shipped) |
| `verification.script` | yes | string | Path to verification script |
| `verification.expected.exit_code` | no | int | Expected exit code (default: 0) |
| `verification.expected.stdout_contains` | no | string | Substring expected in stdout |
| `verification.expected.timeout_seconds` | no | int | Test timeout (default: 30) |
| `test_framework` | no | string | playwright / cypress / detox / xcuitest / etc. (e2e only) |
| `references` | no | array | Files this test references — each `{file, purpose}` |

The `references` field is what makes tests double as **executable
contracts**. Clients (iOS, web, etc.) wanting to call the same
endpoint can read the test's script as a reference implementation.

---

## Stamp: env-var

**Where it lives:** `env/stamps/<name>.md`
**Purpose:** Declare a single environment variable the project uses — what it is, who needs it, which profiles set it. Never the value.
**Shipped in:** v0.21.0

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string (kebab-case) | Stamp identity. Matches filename. |
| `kind` | yes | const `env-var` | Stamp discriminator. |
| `var_name` | yes | string (SCREAMING_SNAKE_CASE) | The actual env var name as it appears in `.env*` files. |
| `group` | yes | string (slash-path) | Hierarchical group for `ENV.md` rollup (`database/postgres`, `auth/jwt`, `feature-flags`, etc.). |
| `required` | yes | bool | `true` = system won't boot without it. `false` = enables/disables an optional feature. |
| `purpose` | yes | enum | connection / credential / feature-flag / config / secret / url / derived |
| `description` | yes | string (one line) | What this var represents. |
| `type` | yes | enum | string / int / bool / url / list / json |
| `default` | depends on `required` | scalar/null | Default value if `required: false`; `null` if required. |
| `used_by.runtimes` | yes | array | Names of runtime stamps that depend on this var. |
| `used_by.clouds` | yes | array | Names of cloud stamps that depend on this var. |
| `environments` | yes | array | Profile names this var should be set in — keys from `.claude/environments.json` (`[local, staging, prod]`), matching the runtime stamp `env.environments` keys. |
| `created` | yes | date (YYYY-MM-DD) | When the stamp was created. |
| `status` | yes | enum | active / deprecated / retired |
| `tags` | no | array | Free-form classification. |

The `purpose: secret` flag carries the strongest treatment (never logged, never echoed, aggressive rotation). The `credential` vs `secret` distinction is intentional — credentials are user-facing identifiers (often paired with passwords); secrets are the actual sensitive material.

Body of the stamp covers context: production source (which 1Password vault / Key Vault path), rotation policy, related vars, edge cases. See `env-rules.md` for the full convention.

The `var_name` ↔ runtime stamp `env.required` link is by name, not enforced. Drift surfaces via a future `env/env.sh validate` script.

---

## Stamp: contract

**Where it lives:** `contracts/stamps/<name>.md`
**Purpose:** Declare a system contract — a schema, API endpoint, or system doc that other code (and other repos) depend on being stable.
**Shipped in:** v0.26.0

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string (kebab-case) | Stamp identity. Matches filename. |
| `kind` | yes | enum | `schema` / `endpoint` / `doc` — the contract discriminator. |
| `version` | yes | string (`MAJOR.MINOR.PATCH`) | Contract version. Bumped deliberately via `/contract bump`. |
| `status` | yes | enum | `draft` / `active` / `deprecated` |
| `is_locked` | yes | bool | `true` = frozen; only an explicit `false` is unlocked. Absent, any other value, a duplicated key, or unreadable frontmatter is treated as locked. A locked contract cannot change until `/contract unlock`. |
| `created` | yes | date (YYYY-MM-DD) | When the contract was created. |
| `last_updated` | yes | date (YYYY-MM-DD) | When the body or version last changed. |
| `owner` | no | string | The repo or team that owns this contract. Forward-looking for cross-repo linking. |
| `consumers` | no | array | Repos or teams that depend on this contract. Forward-looking for cross-repo linking. |
| `references` | no | array | Paths or URLs to related material — mockups, source files, external docs. |
| `tags` | no | array | Free-form classification. |

The `is_locked` flag is the load-bearing field: when `true`,
`contract.sh update`/`bump` refuse the change (exit 3) and the
`PreToolUse` guard hook denies hand-edits. See `contract-rules.md`.

Body of the stamp is the contract itself — the schema DDL, the
endpoint request/response shape, the system doc. Every change is
recorded in `contracts/LEDGER.md`. Managed exclusively by the
`/contract` skill; never hand-edited.

The `owner` / `consumers` fields are populated but unused in the
single-repo model — they exist so a future cross-repo linking
feature can resolve who publishes and who depends on each contract.

---

## Stamp: task

**Where it lives:** `tasks/<stage>/<id>-<slug>.md`, where `<stage>` is one of `triage/`, `backlog/`, `active/`, `review/`, `blocked/`, `completed/`, `closed/`. The directory **is** the state — there is no `status` field.
**Purpose:** Declare a unit of tracked work — what it is, where it sits in the lifecycle, who is accountable, and how it ended up.
**Shipped in:** v0.50.0; reshaped to the `rasa.module.tasks` v1.0.0 frontmatter after v0.52.

**Authoritative schema:** `.claude/task-rules.md` §3 (every key but the `x-` ones, and the invariants `.claude/bin/check-tasks` enforces). This domain's `x-` keys: `.claude/code-task-rules.md` §7. The table summarizes both; where it disagrees with them, they win.

| Field | Required | Type | Description |
|---|---|---|---|
| `id` | yes | string | `TASK-[SERIES-]NNN[a]`. Written once by `.claude/bin/task new`. Equals the filename prefix and the H1 prefix (`# <id>: <title>`) — `bin/check-tasks` errors on any disagreement (I-07, I-08). |
| `type` | yes | enum | `change` / `defect` / `upkeep` / `inquiry` / `record`. The one value a person types at filing. This model's discriminator, in place of the universal `kind` — see the exception note. |
| `created` | yes | date (`YYYY-MM-DD`) | Written once by the allocator; never in the future. |
| `created_by` | yes | string | Actor handle, or `unknown`. Written once by the allocator. |
| `updated` | yes | date (`YYYY-MM-DD`) | Bumped by every `bin/task` write; after a hand edit to the body, `bin/check-tasks --fix` bumps it (I-34). |
| `phase` | conditional | string | A phase id declared as `## Phase <id> — <name>` in `tasks/ROADMAP.md`. Required in `backlog/` `active/` `review/` `blocked/` `completed/`; **forbidden** in `triage/`; in `closed/` iff the task had one (I-19, I-20, I-22). Written by `bin/task graduate` (or `new --phase`). |
| `target` | conditional | array (one-line flow list) | Required iff `tasks/tasks.config.yml#targets` is non-empty, and then wherever `phase` is; forbidden otherwise (I-25). |
| `completed_by` | conditional | string | Actor handle. In `completed/` and `closed/` only. Written by `bin/task pass` / `close`. |
| `resolution` | conditional | enum | `superseded` / `duplicate` / `obsolete` / `wont-do`. In `closed/` only. Written by `bin/task close`. A task that got done carries none. |
| `resolution_ref` | conditional | string | The id that replaced this one, iff `resolution` is `superseded` or `duplicate`. Written by `bin/task close --ref`. |
| `priority` | no | enum | `now` / `high` / `normal` / `low`. Absent = `normal`. `now` is a route, never in `triage/` or `backlog/` (I-14). |
| `needs` | no | array (one-line flow list) | Ids that must reach `completed/` before this one can, e.g. `[TASK-012, TASK-014]`. Acyclic (I-26 – I-28). The only dependency field — distinct from the *external* stop a `## Blocker` section names in `blocked/`. |
| `x-origin` | no | enum | How the file came to exist: `manual` / `auto-fallback` (minted by the `task-enforce` PreToolUse guard) / `auto-guard` (minted by the `task-guard` pre-commit hook). Absent = `manual`. |
| `x-owner` | no | string | The accountable human, team or agent identity. Durable and single-valued; never guessed. **Not** the per-run actor — see `Stamp: run`. |
| `x-outcome` | no | enum | What happened after `completed/`: `shipped` / `reverted`. Absent = not recorded. **Never inferred** from residence in `completed/`. Does not move the file. |
| `x-severity` | no | enum | `critical` / `high` / `medium` / `low` — for a `defect`, how bad. Urgency is `priority`, not this. |

Who writes what: `bin/task` stamps `id`, `created`, `created_by`, `updated`, `completed_by`, `resolution` and `resolution_ref`. A person chooses `type`, `phase`, `target` and `priority` and passes them as flags (`bin/task new`, `graduate`). The four `x-` keys, and `priority` later on, are written with `.claude/skills/task-enforce/task-enforce.sh stamp <id> <key> <value>`. `needs` is written by hand, followed by `bin/check-tasks --fix`. Any other bare key is an error (I-11), and `status` is an error anywhere (I-10).

> **Universal-field exception.** This model ships neither `name` nor
> `kind`. Identity is the **filename** plus `id` plus the H1 — three
> copies, all machine-written and checked against each other (I-07,
> I-08). The discriminator is `type`, fixed by the `rasa.module.tasks`
> spine; renaming it to `kind` would be breaking under "Evolution rules"
> and is not this Element's call.

> **No absence defaults.** A task in `triage/` carries the five required
> keys like any other — `bin/task new` writes four, the filer supplies
> `type` — and must **not** carry `phase` (I-19). The ≤ v0.52 fields map
> one way: `category` → `type`, `status` → the directory, `owner` /
> `outcome` / `origin` / `severity` → their `x-` forms, `blocked_by` →
> `needs`, `filed` → `created`. `HOTFIX-NNN` ids are retired: a hotfix is
> a `defect` with `priority: now` (`code-task-rules.md` §4).

**Run identity is deliberately absent from this model.** `actor`, `run_id`
and `attempts` describe an *episode of work*, not the work itself, and the
two are many-to-many: one `/mission` run spans several tasks and renders one
report, while one task is re-attempted across many runs via the
`active ⇄ blocked` cycle. A single-valued `run_id` here would be overwritten
by the second attempt, destroying the history it exists to record. Those
fields live on `Stamp: run`.

## Stamp: run

**Where it lives:** `tasks/runs/<RUN-id>.md`
**Purpose:** Record one episode of agent or human work — who ran it, what it touched, and how it ended.
**Shipped in:** v0.50.0 (model only — the writer lands with the autonomy-report work)

| Field | Required | Type | Description |
|---|---|---|---|
| `run_id` | yes | string | `RUN-YYYYMMDD-HHMMSS-<short>`. Matches the filename. |
| `kind` | yes | enum | `mission` / `auto-task` / `auto-develop` / `auto-test` / `auto-phase` / `auto-bug` / `auto-hotfix` / `manual`. The invoked entry point. |
| `actor` | yes | string | Who or what ran it. Resolved in one fixed order: `RASA_ACTOR`, then the clone's git identity, then the OS user (`rasa_actor`, in the shared library). `RASA_ACTOR` is the knob a runner, CI job or agent harness sets to identify itself. An identity carrying a control character is refused before the record is opened. |
| `actor_kind` | yes | enum | `human` / `agent`. Distinct from the task's `x-origin`, which records how a *file* came to exist. |
| `status` | yes | enum | `in-flight` / `completed` / `stopped` / `failed`. Opened `in-flight` **before** the work and sealed after. |
| `outcome` | no | enum | `completed` / `stopped-at-gate` / `failed` / `abandoned`. Absent while `in-flight`. |
| `gate` | no | string | The hard gate that stopped the run, when `outcome` is `stopped-at-gate`. |
| `task_refs` | no | array (one line, comma-separated) | Task ids this run touched. The join key: a task's attempt count is `count(runs whose task_refs contains it)`. |
| `started` | yes | date (`YYYY-MM-DD HH:MM UTC`) | When the record was opened. |
| `finished` | no | date (`YYYY-MM-DD HH:MM UTC`) | When it was sealed. Absent = the run never closed. |
| `duration_s` | no | int | Seconds. Absent = never closed. |
| `sha` | no | string | Commit the run started from. |
| `branch` | no | string | Branch the run worked on. |

**One file per run, opened before the work.** Both properties are load-bearing
and both are borrowed from `deploys/records/`, which learned them the hard way
— its header records 8 back-to-back deploys leaving 2 records while `check`
reported "consistent". A record written only at the *end* of a run cannot
represent a run that died, and silently-dead runs are exactly the escape rate
this model exists to measure. A single append-only log would conflict on every
PR the moment two long-lived branches exist, which is why
`tasks/changes/<date>-<task>.md` is already per-file.

**Why `tasks/runs/` and not a top-level `runs/`.** `task-enforcement.json`
exempts `tasks/**` but `classify_path` defaults to `code`, so a top-level
`runs/` would have every run-record write **denied** in every consumer — and
that config is `skip-if-exists`, so the fix would never reach an existing
install. `build/gates/git-clean.sh` likewise excludes only the records it
knows (`deploys/`, `builds/`, `tests/runs/`, `build/deploy-log.md`, and
`tasks/` below prod), so a top-level `runs/` would fail
`/mission`'s own preview deploy on the record the mission just wrote. Under
`tasks/runs/` both are zero-change. Not `deploys/records/` either — that
directory is globbed `???-*.md` and would pull `RUN-` files into the ship-log
table.

**`attempts` is derived, never stored.** It is
`count(run records whose task_refs contains the task id)`. A stored counter
needs a read-modify-write per run — the race both `deploys.sh` and
`task-enforce.sh` document being bitten by in this repo — and would be wrong
for runs that never closed.

## Stamp: save

**Where it lives:** `~/.claude/projects/<key>/saves/SAVED.md` (current) and `<YYYY-MM-DD-HHMM>.md` (archived)
**Purpose:** Snapshot of a thread of work.
**Status:** **MODEL — adoption pending.** Current `save.sh` emits blockquote-style metadata (`> **When.** > **Thread.** > **Branch.**`). Migration to YAML frontmatter is targeted for v0.20.0+.

| Field | Required | Type | Description |
|---|---|---|---|
| `kind` | yes | enum | `full` (fresh save) / `merge` (auto-save merged update) |
| `when` | yes | string | YYYY-MM-DD HH:MM timestamp |
| `thread` | yes | string | One-sentence thread name |
| `branch` | yes | string | Branch name or "None" |
| `merge_source` | no | string | If `kind: merge`, the prior save's timestamp |
| `merge_count` | no | int | If `kind: merge`, sequential count within this thread (1, 2, 3...) |
| `archived` | no | bool | True for archive entries; absent/false for current SAVED.md |
| `tags` | no | array | Optional classification |

The `kind: full | merge` field distinguishes:
- **`full`** — explicit `/save` invocation; fresh content written.
- **`merge`** — auto-save merged the prior SAVED.md with new session
  activity. Captures provenance.

Migration of `save.sh` to emit this format is a separate piece of
work — when it lands, the canonical model is right here.

---

## Stamp: skill (existing)

**Where it lives:** `kit/skills/<name>/SKILL.md` (synced to `.claude/skills/<name>/SKILL.md`)
**Purpose:** Declare a skill.
**Status:** Already in use across all kit skills.

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string | Skill identity. Matches `/<name>` invocation. |
| `description` | yes | string | Long-form trigger description used for routing. |

---

## Stamp: agent (existing)

**Where it lives:** `kit/agents/<name>.md` (synced to `.claude/agents/<name>.md`)
**Purpose:** Declare a subagent.
**Status:** Already in use (auditor, doc-scanner, spec-expander).

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string | Agent identity |
| `description` | yes | string | When to use this agent |
| `tools` | yes | string or list | Comma-separated tool names |
| `model` | no | enum | opus / sonnet / haiku |

---

## Stamp: mode (existing)

**Where it lives:** `kit/modes/<name>.md` (synced to `.claude/modes/<name>.md`)
**Purpose:** Declare a work mode (drive prose that primes appetite).
**Status:** Already in use.

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string | Mode identity |
| `description` | yes | string | What this mode is for |

---

## Models — proposed but not yet adopted

Concepts the kit tracks today that don't yet use stamps. Adopting
each is its own piece of work — template change + migration steps +
optional skill refactor. Listed here so the canonical model is
visible *now*, before adoption drifts.

### decision (proposed for `docs/decisions/<name>.md`)

| Field | Type | Description |
|---|---|---|
| `name` | string | Slug (matches filename — e.g. `0042-token-refresh`) |
| `id` | int | Sequential ADR number |
| `status` | enum | proposed / accepted / superseded / deprecated |
| `deciders` | array | Names / handles of people who agreed |
| `supersedes` | array | Names of decisions this replaces |
| `date` | string | YYYY-MM-DD |

### postmortem (proposed for `docs/postmortems/<name>.md`)

| Field | Type | Description |
|---|---|---|
| `name` | string | Slug |
| `date` | string | Incident date |
| `severity` | enum | critical / high / medium / low |
| `services_affected` | array | Service / runtime names |
| `root_cause_category` | enum | code-bug / config / infra / process / external / unknown |
| `duration_minutes` | int | Incident duration |
| `was_hotfix` | bool | Triggered the hotfix path? |

### handoff (proposed for `docs/handoff/<name>.md`)

| Field | Type | Description |
|---|---|---|
| `name` | string | Date-slug |
| `date` | string | YYYY-MM-DD |
| `author` | string | Handle |
| `departure_type` | enum | end-of-day / weekend / leave / project-handover |
| `expected_return` | string | YYYY-MM-DD or "unknown" |
| `project_state` | enum | clean / mid-feature / mid-refactor / blocked |

### audit (proposed for `docs/audits/<name>.md`)

Already extracted by `audit.sh` as semi-structured metadata. Adopting
as a formal stamp is straightforward.

| Field | Type | Description |
|---|---|---|
| `name` | string | Date-slug |
| `target` | string | Path / module audited |
| `lens` | enum | code / docs / config / architecture / security / mixed |
| `confidence` | enum | high / mixed / low |
| `findings` | object | `{critical: N, high: N, medium: N, low: N}` (auto-computed) |
| `verdict` | enum | ship / fix-first / needs-discussion |

---

## Adding a new stamp model

The process:

1. **Design the fields** — start with what skills will need to parse.
   Use the universal fields (`name`, `kind`, `tags`) as the base.
2. **Add an entry to this file** under the appropriate section
   (existing / proposed). Document field types, required-ness,
   semantics.
3. **Ship a seed template** at `seed/<thing>.md.template`
   that demonstrates the model with placeholder values.
4. **Add `rasa.json` entries** — `seed.files[]` mapping (skip-if-exists)
   and scaffold directory if applicable.
5. **CHANGELOG entry** documenting the new stamp model.
6. **(Optional) Skill integration** — a skill that reads the stamps
   and does something with them (validation, listing, querying).

The first 3 steps are the doctrine; (4-5) ship it; (6) makes it
useful.
