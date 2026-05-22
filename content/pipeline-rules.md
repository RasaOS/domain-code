# Pipeline Rules

CI/CD conventions for kit-bootstrapped projects. Platform-agnostic — the same structure works for Firebase Hosting, TestFlight, Azure Kubernetes, a bare VPS, or anywhere else you ship code.

The kit provides the **structure** and **vocabulary**. Projects fill in the actual deploy scripts. After setup, deploys are dumb shell calls — no agent reasoning required at run time.

## Vocabulary

Borrowed from Azure DevOps but platform-agnostic:

- **Stages** — ordered phases of the pipeline (preflight, build, test, publish, deploy). Each stage is a script. Stages run in order; any failure aborts.
- **Gates** — reusable check scripts (clean tree, tag matches version, user approval). Stages and environment deploys invoke gates as needed.
- **Args** — parameters passed at trigger time. `--env` is always required. Others: `--skip-tests`, `--skip-gates`, `--dry-run`, `--tag=<version>`, etc.
- **Environment** — named deploy target with its own config and deploy command. Lives in `environments/<name>/`. The name must be a key in `.claude/environments.json` (the environment registry — see `environment-rules.md`). **Always required** — there is no default environment.

## Folder structure

Every kit-enabled project gets:

```
build/
├── pipeline-config.toml          # project config (name, env list, project type)
├── stages/                       # ordered scripts; run in numeric order
│   ├── 10-preflight.sh
│   ├── 20-build.sh
│   ├── 30-test.sh
│   ├── 40-publish.sh
│   └── 50-deploy.sh              # delegates to environments/<env>/deploy.sh
├── environments/                 # one folder per environment (names = environments.json)
│   ├── local/
│   │   ├── env.sh                # exports env vars for this environment
│   │   └── deploy.sh             # the actual deploy command
│   ├── staging/
│   │   ├── env.sh
│   │   └── deploy.sh
│   └── prod/
│       ├── env.sh
│       └── deploy.sh
├── gates/                        # reusable check scripts (project picks which)
│   ├── git-clean.sh
│   ├── tag-matches.sh
│   └── approval.sh
├── deploy-log.md                 # appended every run (timestamp, env, who, result)
└── deploy                        # entry point: ./build/deploy --env=staging
```

## Entry point: `./build/deploy`

The canonical command. Always runs the same way:

```sh
./build/deploy --env=staging
./build/deploy --env=prod --tag=v1.2.0
./build/deploy --env=dev --skip-tests --dry-run
```

**`--env` is mandatory.** If omitted, the script lists available environments and exits non-zero. The `/deploy` Claude skill (if installed) prompts for env when missing; the bash script itself does not — it refuses.

### Run order

1. Validate `--env=<name>` and that `environments/<name>/` exists
2. Source `environments/<name>/env.sh` (exports env vars)
3. Run `stages/*.sh` in numeric order, passing the env name as `$1`
4. The final `stages/50-deploy.sh` execs `environments/<name>/deploy.sh`
5. Append a row to `deploy-log.md` (timestamp, env, user, result)

Any non-zero exit aborts the pipeline.

### Pipeline-wide variables

`build/deploy` exports these for every stage and `environments/<env>/deploy.sh`:

- `ENVIRONMENT` — the `--env` name.
- `DEPLOY_TAG` — the `v<semver>-<sha>-<env>` version string.
- `PUBLISH_TO` / `DEPLOY_TO` — the registry's `publish_to` / `deploy_to`
  cloud-stamp names for this environment (empty when unset). Stages and
  `deploy.sh` route on these instead of hard-coding the target. See
  `environment-rules.md`.
- `DEPLOY_USER`, `DEPLOY_TIMESTAMP`.

## Stages

The kit ships skeleton scripts. Each stage receives the environment name as `$1`. Each stage either does its job and exits 0, does nothing and exits 0, or fails and exits non-zero.

### `10-preflight.sh` — checks before doing anything

Typical content: invoke gates. Example wiring:

```sh
./build/gates/git-clean.sh
./build/gates/tag-matches.sh "$1"
```

For prod deploys, also invoke `gates/approval.sh`.

### `20-build.sh` — produce the artifact

Project-specific. Examples:

- Web: `npm ci && npm run build`
- iOS: `xcodebuild archive -scheme MyApp ...`
- Container: `docker build -t $IMAGE_NAME .`
- Python service: `python -m build`

If the project type has no build step, leave it as `exit 0`.

### `30-test.sh` — run the test suite

Reads `tests/suites/pre-deploy.md` (or another suite based on env), iterates the listed tests, runs each. See `test-rules.md` for the test stamp model.

```sh
./build/run-suite tests/suites/pre-deploy.md "$1"
```

Failures abort the pipeline. Skipping is possible via `--skip-tests` (don't use for prod).

### `40-publish.sh` — push the artifact to its target

Project-specific. Examples:

- Container: `docker push $REGISTRY/$IMAGE_NAME:$TAG`
- iOS: export `.ipa` (if not done in build)
- Web: prepare `dist/` for deploy (often a no-op)
- Library: `npm publish` / `pip upload`

Leave as no-op if your project's deploy step does both publish + deploy in one shot.

### `50-deploy.sh` — invoke the env-specific deploy command

By default just `exec` into the environment's `deploy.sh`. Keep this generic; per-env logic lives in `environments/<env>/deploy.sh`.

## Environments

One folder per environment under `environments/`. Each contains:

### `env.sh`

Exports environment variables consumed by the stages and deploy command. Example:

```sh
#!/usr/bin/env bash
export ENVIRONMENT=staging
export FIREBASE_PROJECT=mysite-staging
export DEPLOY_TARGET=https://staging.mysite.com
export REQUIRES_APPROVAL=false
```

Keep secrets out of `env.sh` — reference them via env vars set by the CI runner, 1Password, or a similar source. `env.sh` is committed; secrets are not.

### `deploy.sh`

The actual deploy command(s). Example for Firebase Hosting staging:

```sh
#!/usr/bin/env bash
set -euo pipefail
firebase deploy --only hosting --project "$FIREBASE_PROJECT"
```

Example for AKS prod (with approval gate):

```sh
#!/usr/bin/env bash
set -euo pipefail
./build/gates/approval.sh "Deploy $IMAGE_NAME:$TAG to production?"
kubectl set image deployment/myapp myapp="$REGISTRY/$IMAGE_NAME:$TAG" -n prod
kubectl rollout status deployment/myapp -n prod
```

## Gates

Reusable check scripts. The kit ships a few; projects add more as needed.

### `gates/git-clean.sh`

Exits 0 if working tree is clean, non-zero otherwise.

### `gates/tag-matches.sh`

Exits 0 if HEAD is on an annotated tag matching the project's version source (e.g. `package.json`, `Info.plist`).

### `gates/approval.sh`

Prompts the user (or the orchestrating Claude skill) for `yes` before proceeding. Used in prod deploys.

```sh
./build/gates/approval.sh "Deploy to production?"
# Prints prompt, reads from stdin, exits 0 only on exact "yes"
```

Other useful gates a project might add: `db-backed-up.sh`, `tests-passing.sh`, `staging-healthy.sh`, `change-window-open.sh`.

## `pipeline-config.toml`

Project-level configuration. Read by the setup skill, the `/deploy` Claude skill, and potentially by stages that want declarative config rather than env vars.

```toml
[project]
name = "mysite"
type = "web"                       # web / ios / container / library / mixed

[environments]
list = ["local", "staging", "prod"]
requires_approval = ["prod"]

[tests]
default_suite = "pre-deploy"
prod_suite = "prod-gate"

[hooks]
post_deploy = "scripts/notify-slack.sh"   # optional
```

Not all fields are required. The setup skill walks through filling it in.

## Logging

Every run appends to `deploy-log.md`:

```markdown
| Timestamp | Env | User | Tag | Result | Duration | Notes |
|---|---|---|---|---|---|---|
| 2026-05-13 14:32 UTC | staging | chazz | v1.2.0 | ✓ | 47s | |
| 2026-05-13 18:00 UTC | prod | chazz | v1.2.0 | ✓ | 1m12s | Approved by chazz |
```

Optional — projects can disable by removing the log append from the entry script.

## Integration with `/deploy` skill

The `/deploy` Claude skill is a thin orchestrator:

1. If `--env=<name>` not provided, prompt the user (multiple choice from `pipeline-config.toml`'s env list)
2. If env requires approval (per config), confirm with explicit "yes"
3. Invoke `./build/deploy --env=<name> [args]`
4. Stream output back to the user
5. Report success/failure with relevant context

The skill does **not** reason about how to deploy. It just routes args to the script.

## Setup

A new project runs `/setup-deploy` (skill, ships in kit) which:

1. Asks the project's type (web / ios / container / library / mixed)
2. Asks for environment list (dev / staging / prod / others)
3. Asks for the build, test, publish, and deploy commands per project type
4. Generates `pipeline-config.toml`, fills in `stages/*.sh`, scaffolds `environments/<env>/` per env
5. Wires gates into preflight and prod deploy
6. Generates `tests/suites/pre-deploy.md` (default empty suite)
7. Stages everything for git review (never auto-commits — kit convention)

After `/setup-deploy`, deploys are just `./build/deploy --env=<env>` from then on.

---

**See also:** `test-rules.md` for the test stamp model and suite gating. `stamps.md` for the universal stamp pattern.
