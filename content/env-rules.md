# Env Var Rules

Conventions for environment variables in kit-bootstrapped projects. Every env var the project uses gets a stamp under `env/stamps/`. Stamps record **what** the var is, **why** it exists, and **where** it's required — never the value.

Pairs with `runtime-rules` (per-runtime env requirements), `cloud-rules` (per-cloud deploy credentials), and `pipeline-rules` (per-deploy-env exports). Those existing systems declare *which* env vars they need; the env-var stamps in this system declare *what each var is* — the canonical registry.

`secrets-rules.md` is the companion: this file is the registry (what each var *is*), `secrets-rules.md` governs the *values* (how a secret value gets entered, and how it is kept out of the AI's context). The `/secrets` skill provisions values; `/import-env` and `/export-env` move keys between `.env` files and stamps.

## Why a separate system

Runtime stamps already say "this runtime requires `POSTGRES_HOST`." Cloud stamps say "this cloud needs `AZURE_CLIENT_ID`." Build env scripts export per-deploy-target vars. What's missing:

- **A single registry** of every env var the project uses, regardless of who needs it
- **A clear required-vs-optional split** at the var level (required = system won't boot; optional = enable/disable features)
- **Group-level grouping** so a project can see "all Postgres vars" or "all feature flags" at a glance
- **Audit trail** — when was this var added, by whom, why

The env-var stamp solves all four without duplicating the per-resource declarations.

## Folder structure

```
env/
├── ENV.md                          # narrative grouping (postgres / chroma / feature flags / …)
└── stamps/                         # one yaml-frontmatter stamp per env var
    ├── postgres-host.md
    ├── postgres-password.md
    ├── chromadb-host.md
    ├── openai-api-key.md
    ├── feature-new-checkout.md
    └── …

# Profile files at project root (dotenv convention):
.env-template                       # committed reference (every required var, placeholder values)
.env                                # gitignored — default local (matches kit runtime convention)
.env.test                           # gitignored — test profile
.env.staging                        # gitignored — staging profile
.env.production                     # gitignored — production profile
```

**Profile naming** follows the kit's runtime stamp convention:
- `.env-template` (hyphen) — the committed example with all vars and placeholder values
- `.env` — default local (no suffix)
- `.env.<profile>` (dot) — named profiles like `.env.test`, `.env.staging`, `.env.production`

Profile names should match the `env.environments` map in your runtime stamps. The env-var stamp's `environments:` field references those same names.

## The `env-var` stamp model

```yaml
---
name: postgres-host
kind: env-var
var_name: POSTGRES_HOST
group: database/postgres
required: true
purpose: connection
description: Hostname of the PostgreSQL server
type: string
default: null
used_by:
  runtimes: [api, worker]
  clouds: []
environments: [local, staging, prod]
created: 2026-05-13
status: active
tags: [database, critical]
---

# Env var: POSTGRES_HOST

The Postgres connection target. Required because no runtime boots
without a database.

**Production source:** Azure Database for PostgreSQL Flexible Server
(reference cloud stamp `azure-postgres-prod`). Set via deploy
pipeline.

**Rotation:** N/A — host is stable. Connection password rotates
separately, see `postgres-password.md`.
```

### Fields

| Field | Required | Type | Description |
|---|---|---|---|
| `name` | yes | string (kebab-case) | Stamp identity. Matches filename. |
| `kind` | yes | const `env-var` | Stamp discriminator. |
| `var_name` | yes | string (SCREAMING_SNAKE_CASE) | The actual env var name as it appears in `.env*` files. |
| `group` | yes | string (path) | Hierarchical group for `ENV.md` rollup. Slash-separated (`database/postgres`, `auth/jwt`, `feature-flags`, `external-apis`). |
| `required` | yes | bool | `true` = system won't boot without it. `false` = enables/disables an optional feature. |
| `purpose` | yes | enum | `connection` / `credential` / `feature-flag` / `config` / `secret` / `url` / `derived` |
| `description` | yes | string (one line) | What this var represents. |
| `type` | yes | enum | `string` / `int` / `bool` / `url` / `list` / `json` |
| `default` | depends | scalar/null | Default value if `required: false`. `null` if `required: true` (no default — must be set). |
| `used_by` | yes | object | `{runtimes: [...], clouds: [...]}` — names of runtime/cloud stamps that depend on this var |
| `environments` | yes | array | Profile names this var should be set in — keys from `.claude/environments.json` (`[local, staging, prod]`) |
| `created` | yes | date (YYYY-MM-DD) | When the stamp was created. |
| `status` | yes | enum | `active` / `deprecated` / `retired` |
| `tags` | no | array | Free-form classification. |

### `purpose` values

- **`connection`** — host / port / endpoint to reach a service (POSTGRES_HOST, REDIS_PORT)
- **`credential`** — username / password / token used for auth (POSTGRES_USER, DB_PASSWORD)
- **`feature-flag`** — boolean toggle (FEATURE_NEW_CHECKOUT)
- **`config`** — non-secret behavior tuning (LOG_LEVEL, BATCH_SIZE)
- **`secret`** — sensitive value not safe in plaintext anywhere (JWT_SECRET, ENCRYPTION_KEY)
- **`url`** — full URL endpoint (WEBHOOK_URL, FRONTEND_URL)
- **`derived`** — computed at runtime from other vars (rare; document derivation)

The `credential` / `secret` distinction is intentional: credentials are user-facing identifiers (often paired with passwords); secrets are the actual sensitive material. Both need source-of-truth discipline but `secret` purpose flags the strongest treatment (never in logs, never echoed, rotate aggressively).

### Cross-references

`used_by.runtimes` and `used_by.clouds` reference stamp `name` fields, not filenames. The orchestrating tooling resolves names to files. A var used by no runtime or cloud (e.g. a project-global setting consumed only by scripts) has empty arrays.

When a runtime stamp's `env.required` array contains a var name, the var should have a corresponding env-var stamp listing that runtime in `used_by.runtimes`. The two systems are linked by var name, not enforced.

## Group taxonomy

Suggested top-level groups for `ENV.md` rollup. Projects extend as needed:

- **`database/<system>`** — Postgres, MySQL, Mongo, Redis, Chroma, etc.
- **`auth/<scheme>`** — JWT, OAuth, session, API keys for the project's own auth
- **`external-apis/<provider>`** — OpenAI, Stripe, Twilio, etc.
- **`cloud/<provider>`** — AWS, Azure, GCP credentials and config
- **`feature-flags`** — boolean toggles
- **`logging`** — log level, log targets, observability config
- **`infra`** — internal ports, service discovery, container names
- **`secrets`** — high-sensitivity values that don't fit elsewhere
- **`runtime/<runtime-name>`** — vars specific to one runtime that don't fit a domain group

Use slash-separated paths for sub-grouping. `ENV.md` reads the `group:` field across all stamps and rolls them up by section.

## `ENV.md` — narrative grouping

The kit ships a template; projects fill it in. Structure:

```markdown
# Environment Variables

This project's env vars, grouped by concern. The authoritative list is
in `env/stamps/` (one stamp per var).

## Database connections

### PostgreSQL
- `POSTGRES_HOST` — required — server hostname
- `POSTGRES_PORT` — required — server port (default 5432)
- `POSTGRES_DB` — required — database name
- `POSTGRES_USER` — required — connection user
- `POSTGRES_PASSWORD` — **required** (secret) — connection password

### ChromaDB
- `CHROMA_HOST` — required — Chroma server host
- `CHROMA_PORT` — required — Chroma server port

## External APIs
- `OPENAI_API_KEY` — **required** (secret) — auth for OpenAI calls

## Feature flags
- `FEATURE_NEW_CHECKOUT` — optional — enables new checkout flow (default `false`)
```

The format is conventional, not enforced. The point is human scanability — agents and humans should be able to read `ENV.md` and understand the project's env surface at a glance.

## Profile files

Profile files at the project root follow the dotenv convention:

| File | Purpose | Committed? |
|---|---|---|
| `.env-template` | Reference with every required var and placeholder values | Yes — committed |
| `.env` | Default local profile | No — gitignored |
| `.env.test` | Test profile (CI, local test runs) | No — gitignored |
| `.env.staging` | Staging mirror values (rarely on local machines) | No — gitignored |
| `.env.production` | Production mirror values (almost never on local machines) | No — gitignored |

**Always gitignore the populated profiles.** The kit's `.gitignore` should include `.env` and `.env.*` (except `-template`). The committed `.env-template` is the only file with var names; everything with values stays out of git.

**The kit does not ship a `.env-template`.** It's project-specific — generate it from your stamps via `/import-env` (or hand-write it). The kit ships the convention; the values are yours.

## Secret discipline

The env-var stamps record metadata, not values. Where actual secret values come from is the project's call — common patterns:

- **1Password / Bitwarden / LastPass** — pull at runtime via CLI (`op read`, `bw get`, etc.)
- **AWS Secrets Manager / Azure Key Vault / GCP Secret Manager** — pull at deploy time via cloud CLI
- **CI variable groups** — Azure DevOps, GitHub Actions, GitLab — secrets injected at runtime
- **Hardware tokens / hardware-backed keystores** — for the strictest

Document the source in each `purpose: secret` stamp's body. Don't commit retrieval scripts that hard-code paths — parameterize them.

**Never:**
- Commit a populated `.env` file
- Echo a secret to stdout in CI logs (mask with `***` or `$$$REDACTED$$$`)
- Store a secret in `rasa.json`, CLAUDE.md, or any markdown body
- Email or Slack a secret value (use the secret manager's share feature)

## Validation

Three checks projects should run:

### `env/stamps/` coverage

Every var in `.env-template` should have a stamp. Every required stamp should appear in `.env-template`. A future kit-shipped `env/env.sh validate` script will check both directions.

### Profile completeness

For each profile listed in a stamp's `environments:`, the corresponding `.env.<profile>` file should set the var (or the stamp's `default` for optional vars). Missing required vars = system can't boot in that profile.

### Runtime cross-ref

For each runtime stamp's `env.required` entry, an env-var stamp should exist with that runtime in `used_by.runtimes`. Drift here means a runtime needs a var that isn't registered.

## Adding a new env var

1. Add a stamp under `env/stamps/<name>.md` (or run `/import-env` to bulk-add from an existing `.env` file).
2. Add a line to `env/ENV.md` under the appropriate group.
3. Add to `.env-template` with a placeholder value (e.g. `POSTGRES_HOST=__SET_ME__`).
4. Add to the appropriate `.env*` profile files (uncommitted).
5. If a runtime/cloud uses it, update that stamp's `env.required` array.

For secrets, also: record the source in the stamp body and ensure the runtime can pull it from that source.

## Retiring an env var

Don't delete the stamp. Flip `status: active` → `status: deprecated` (still in use, on its way out) or `status: retired` (no code depends on it). Preserves the audit trail.

When `retired`, the var can be removed from `.env-template` and profile files. Leave the stamp for history.

## Importing from existing `.env`

The `/import-env` skill parses an existing `.env*` file line by line. For each `KEY=value` it encounters:

- If a stamp for `KEY` already exists, increment its `environments:` if this profile isn't listed yet.
- If no stamp exists, draft one and ask the user for `required`/`group`/`purpose`/`description` — never auto-decides these.

The skill writes stamps to `env/stamps/` and updates `ENV.md` grouping. It never reads values into stamps.

## Glyphs (for `ENV.md` and reports)

- **required** — var without which the system won't boot
- **optional** — feature toggle or tunable
- **secret** — sensitive (in `**bold**` and noted)
- **deprecated** — still used but on the way out
- **retired** — no longer in use; stamp preserved for history

---

**See also:** `stamps.md` (universal stamp model conventions), `pipeline-rules.md` (per-deploy-env exports), `test-rules.md` (test stamp model — env-var stamps follow the same shape).
