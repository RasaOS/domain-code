# Environment Variables

Human-readable grouping of every env var this project uses. The
machine-readable source of truth is `env/stamps/` (one stamp per var,
YAML frontmatter). This file is the rollup — read it to understand
the env surface at a glance.

**See `.claude/env-rules.md` for conventions and stamp model.**

---

## Profiles

This project uses the following `.env*` profiles. Each is gitignored
except `.env-template`.

| File | Profile | Purpose |
|---|---|---|
| `.env-template` | (reference) | Committed example with every required var and placeholder values |
| `.env` | local | Developer's local machine |
| `.env.test` | test | Test runs (CI and local) |
| `.env.staging` | staging | Staging mirror (rarely populated locally) |
| `.env.production` | production | Production mirror (almost never local) |

Adjust to the project's actual profiles. Profile names should match
the `env.environments` keys in your runtime stamps.

---

## Database connections

### {{POSTGRES / MYSQL / MONGO — delete what's not used}}

- `POSTGRES_HOST` — required — server hostname
- `POSTGRES_PORT` — required — server port
- `POSTGRES_DB` — required — database name
- `POSTGRES_USER` — required — connection user
- `POSTGRES_PASSWORD` — **required** (secret) — connection password

### {{CHROMADB / REDIS / OTHER VECTOR-OR-CACHE — delete what's not used}}

- `CHROMA_HOST` — required — Chroma server host
- `CHROMA_PORT` — required — Chroma server port

---

## Auth

### {{JWT / OAUTH / SESSION — delete what's not used}}

- `JWT_SECRET` — **required** (secret) — signing key for JWTs

---

## External APIs

- `{{OPENAI_API_KEY}}` — **required** (secret) — {{auth for OpenAI calls}}
- `{{STRIPE_SECRET_KEY}}` — **required** (secret) — {{Stripe server-side ops}}

Delete what doesn't apply; add what does.

---

## Cloud credentials

Per-cloud deploy credentials live in `.claude/clouds/<name>.md`.
Reference them here for cross-reading. Examples:

- `AZURE_CLIENT_ID` — required — service principal client ID (cloud: `azure-aks-prod`)
- `AZURE_CLIENT_SECRET` — **required** (secret) — service principal secret
- `AZURE_TENANT_ID` — required — Azure tenant
- `AZURE_SUBSCRIPTION_ID` — required — Azure subscription

---

## Feature flags

- `FEATURE_{{NAME}}` — optional — {{what this enables}} (default `false`)

Feature flags are `required: false` in their stamps. The system boots
without them; they just toggle code paths.

---

## Logging & observability

- `LOG_LEVEL` — optional — `debug / info / warn / error` (default `info`)
- `SENTRY_DSN` — optional — Sentry endpoint if enabled

---

## Conventions in this project

- All required vars must appear in `.env-template` with placeholder values
- Secrets never appear in committed files (only `.env-template` reference value)
- Profile names match runtime stamp `env.environments` keys
- New vars: run `/import-env` after editing the `.env*` file, or add the stamp by hand

---

## Glyph key

- **required** — system won't boot without it
- **optional** — enable/disable a feature
- **(secret)** — sensitive value, special handling required (never logged, rotate aggressively)
- **deprecated** — still used, on the way out
- **retired** — no longer in use (stamp preserved for history)
