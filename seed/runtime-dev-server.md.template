---
name: <kebab-case-runtime-name>
kind: dev-server
language: <python | javascript | typescript | go | rust | ruby | java | other>
framework: <fastapi-uvicorn | vite-react | next-js | django | rails | express | other>

commands:
  install: "<deps install — e.g. pip install -r requirements.txt, npm ci>"
  dev: "<dev server command — e.g. uvicorn app.main:app --reload, npm run dev>"
  build: "<production build command, or 'n/a' if dev-only>"
  test: "<test command, or 'n/a'>"
  lint: "<lint command, or 'n/a'>"

ports:
  dev: 8000
  # add more as needed: { test: 8001, debug: 8002 }

env:
  template: ".env-template"           # committed example file (often gitignored deviates from this)
  file: ".env"                        # default local env file (loaded when --env not specified)
  environments:                       # named profiles → env file paths (keys = .claude/environments.json)
    local: ".env"
    staging: ".env.staging"
    prod: ".env.production"
  required: []                        # e.g. [DATABASE_URL, OPENAI_API_KEY]
  optional: {}                        # e.g. { LOG_LEVEL: "INFO", MAX_CONNECTIONS: "10" }

depends_on: []           # other runtimes / services this needs
  # - { name: postgres, check: "pg_isready -h localhost -p 5432" }
  # - { name: redis,    check: "redis-cli ping" }

health_check:
  url: "http://localhost:8000/health"
  expect_status: 200
  timeout_seconds: 10

process:
  type: long-running
  watch_globs: []        # e.g. ["app/**/*.py"] — files that trigger reload

tags: []                 # e.g. [api, backend, public]
---

# <Name> — local dev runtime

> Stamp at the top is the machine-readable identity (skills parse
> it). The body below is the qualitative context — humans read it,
> AI uses it for synthesis.

## What this is

<One paragraph: what kind of runtime this is, what it serves, who
talks to it. E.g. "FastAPI server providing the public REST API.
Web frontend at .claude/runtimes/web.md and iOS app both call this.">

## How to run

```sh
<dev command from the stamp>
```

Defaults to port `<port>`. Set `PORT` env var to override.

## First-time setup

1. Install deps: `<install command>`
2. Copy `<env.template>` → `.env` (or whichever profile from `env.environments`):
   ```sh
   cp .env-template .env
   ```
   Fill in `env.required` vars.
3. Start dependencies (postgres, redis, etc. — see `depends_on` in stamp)
4. **Preflight:** `bash .claude/skills/runtime/runtime.sh check <name>`
   Validates env vars are set + deps are reachable before you boot.
5. Run the dev command above

## Env profiles

Switch between environments via the `--env <profile>` flag on
`runtime.sh check`:

```sh
runtime.sh check <name> --env staging      # validate against .env.staging
runtime.sh check <name> --env prod         # validate against .env.production
```

`env.environments` in the stamp declares which profiles exist.

## Gotchas

<Sharp edges. Past incidents. Surprising defaults. Anything someone
running this for the first time would otherwise spend an hour
figuring out.>

- ...

## References

- <link to framework docs>
- <link to internal architecture doc, if any>

---

*Last verified working: <YYYY-MM-DD>. Update this date when you
re-confirm the dev command and deps still produce a running server.*
