# Environment Rules

How kit-bootstrapped projects declare and use **environments** — the
named contexts a project builds, runs, and deploys in (`local`,
`staging`, `prod`, …). The environment registry is the spine that ties
version stamping, `.env` selection, and deploy targeting together.

Pairs with `env-rules.md` (environment *variables* — the values),
`pipeline-rules.md` (deploys), `release-rules.md` (version tagging), and
the runtime / cloud stamps. Where those declare *what each needs*, the
environment registry declares *what environments exist* — and
everything else references it by name.

## Why a registry

"Environment" used to be implied independently in four places: the
pipeline's `build/pipeline-config.toml`, every runtime stamp's
`env.environments`, every cloud stamp's `environments`, every env-var
stamp's `environments`. Nothing reconciled them, and the names drifted
— `dev` in one file, `local` in another; `prod` here, `production`
there. A project couldn't answer "what environments do we have?" from
one place.

`.claude/environments.json` is the **single source of truth**. Every
environment name used anywhere in the project must be a key in it.

## The registry — `.claude/environments.json`

JSON, not a stamp — environments are machine-read config that the
current-env pointer switches between, so one parsable file beats N
markdown stamps. The kit ships it via `bin/init` (`skip-if-exists` —
the project owns it after bootstrap) seeded with `local / staging /
prod`.

```json
{
  "default": "local",
  "environments": {
    "local":   { "...": "..." },
    "staging": { "...": "..." },
    "prod":    { "...": "..." }
  }
}
```

Top-level:

| Field | Type | Description |
|---|---|---|
| `default` | string | Environment used when no current-env pointer is set. Must be a key in `environments`. |
| `environments` | object | Map of environment name → config. The keys are the canonical environment names. |

Each environment:

| Field | Type | Description |
|---|---|---|
| `description` | string | One line — what this environment is. |
| `env_file` | string | The dotenv profile this environment loads (`.env`, `.env.staging`, `.env.production`). Matches the runtime stamp `env.environments` convention. |
| `publish_to` | string \| null | Name of the cloud stamp build artifacts are published to (a registry — e.g. `azure-acr`), or `null`. |
| `deploy_to` | string \| null | Name of the cloud stamp the deploy targets (e.g. `azure-aks`, `firebase-hosting`), or `null`. |

`publish_to` / `deploy_to` reference `.claude/clouds/<name>.md` stamp
names. This is the link the kit was missing: an environment now
*declares where it ships* — registry and compute surface — instead of
that living only as freeform shell in `build/environments/<env>/`.
`build/deploy` reads them via `environment.sh get` and exports
`PUBLISH_TO` / `DEPLOY_TO`, so stage scripts route on the registry's
declared target instead of hard-coding it.

## The current working environment

The registry is declarative. *Which* environment is active right now —
for local development — is a separate, mutable pointer:

```
~/.claude/projects/<key>/current-env
```

- **Machine-local, never committed.** Which environment your machine is
  working in is personal state, not project state — it lives in
  user-global space, alongside `/save` snapshots and memory.
- **Shared across worktrees.** Keyed off the *main* repo root, so every
  worktree of one project reads the same pointer.
- **Absent ⇒ `default`.** A fresh clone has no pointer; `environment
  current` returns the registry's `default`. Nothing to set up.
- **`--env` always wins.** The pointer is a convenience default for
  local work. Any tool invoked with an explicit `--env` ignores it.

Set it with `environment use <env>`; read it with `environment
current`.

## The version string

One format, everywhere — running processes, build artifacts, `/health`
output, and git tags:

```
v<semver>-<shortsha>-<env>

  v1.4.2-9f3a1c7-prod
  v1.4.2-9f3a1c7-local
```

- **`<semver>`** — `MAJOR.MINOR.PATCH`. For a release, the version
  `/release` selects (from arg or heuristic — see
  `kit/skills/release/SKILL.md`). For any non-release build, the
  **nearest reachable release tag** (`git describe`), or `v0.0.0`
  before the first release.
- **`<shortsha>`** — `git rev-parse --short HEAD`: exactly the commit
  the build came from.
- **`<env>`** — the active environment's name (its registry key).

`environment.sh version` is the **single builder**. The deploy pipeline
and `/release` produce the version string by calling it, never by
reconstructing it — that is what keeps versioning from drifting across
code paths.

One caveat: the `-` after the semver makes everything after it a SemVer
pre-release identifier, so `v1.4.2-…-prod` sorts *below* `v1.4.2` under
strict semver ordering. Don't pick "latest" by tag sort — use `git
describe` or the deploy log.

## What references the registry

The registry exists so the rest of the project stops re-deciding
environment names. Each of these must use registry keys:

| System | Where the environment name appears |
|---|---|
| Runtime stamps (`.claude/runtimes/<name>.md`) | `env.environments` keys |
| Cloud stamps (`.claude/clouds/<name>.md`) | `environments` array |
| Env-var stamps (`env/stamps/<name>.md`) | `environments` array |
| Deploy pipeline (`build/pipeline-config.toml`) | `[environments] list` |
| Version strings | the `<env>` token = the environment's registry key |

An environment name appearing in any of these that is *not* a registry
key is drift. `environment.sh validate` catches it — it cross-checks
every runtime / cloud / env-var stamp and `build/pipeline-config.toml`
against the registry and exits non-zero on any mismatch. Run it before
a release, or wire it into CI.

## The `environment` skill

`bash .claude/skills/environment/environment.sh`:

- `list` — environments, with the current one marked
- `show <env>` — one environment's full config
- `get <env> <field>` — one field's raw value (for stage scripts)
- `current` — the current working environment
- `use <env>` — switch the current working environment
- `version [<env>] [--semver vX.Y.Z]` — build the version string
- `validate` — check every environment name against the registry

## See also

- `env-rules.md` — environment *variables* (declares values; this file
  declares environments).
- `pipeline-rules.md` — deploys and `build/environments/<env>/`.
- `release-rules.md` — version tagging and the release flow.
- `stamps.md` — runtime / cloud / env-var stamp models.
