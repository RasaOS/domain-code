# Pipeline Rules

CI/CD conventions for kit-bootstrapped projects. Platform-agnostic — the same structure works for Firebase Hosting, TestFlight, Azure Kubernetes, a bare VPS, or anywhere else you ship code.

The kit provides the **structure** and **vocabulary**. Projects fill in the actual deploy scripts. After setup, deploys are dumb shell calls — no agent reasoning required at run time.

## Vocabulary

Borrowed from Azure DevOps but platform-agnostic:

- **Stages** — ordered phases of the pipeline (preflight, build, test, publish, deploy). Each stage is a script. Stages run in order; any failure aborts.
- **Gates** — reusable check scripts (clean tree, tag matches version, user approval). Stages and environment deploys invoke gates as needed.
- **Args** — parameters passed at trigger time. `--env` and `--intent` are always required (`--intent` is derived with a deprecation warning until v0.45.0). Others: `--skip-tests`, `--skip-gates`, `--dry-run`, `--tag=<version>`, etc.
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
│   ├── 50-deploy.sh              # delegates to environments/<env>/deploy.sh
│   └── 60-verify.sh              # smoke-tests the environment after it lands
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
│   ├── approval.sh
│   ├── verified-build.sh         # deploy only what ./build/test passed (no bypass)
│   └── verify-lib.sh             # shared by build, test and the gate (sourced)
├── deploy-log.md                 # appended every run (timestamp, env, who, result)
├── build                         # BUILD phase: ./build/build → builds/records/BLD-*.md
├── test                          # TEST phase:  ./build/test  → tests/runs/TST-*.md
└── deploy                        # DEPLOY phase: ./build/deploy --env=staging --intent=deploy
```

## Entry point: `./build/deploy`

The canonical command. Always runs the same way:

```sh
./build/deploy --env=staging --intent=deploy
./build/deploy --env=prod --intent=release --tag=v1.2.0
./build/deploy --env=dev --intent=deploy --skip-tests --dry-run

# Refused — deploy may not target a production-class environment:
./build/deploy --env=prod --intent=deploy
```

### Direction — `--intent`

`--intent=deploy` targets `dev` and `staging` and **can never reach a
production-class environment**. `--intent=release` targets production and
tags. `build/gates/class-guard.sh` enforces the pairing before any stage
runs, keyed on the environment's declared `class`, never on its name.

The guard has **no bypass**. `--skip-gates` does not reach it, and there
is no `FORCE_*` variable. The sanctioned route to production is
`/release`.

An absent `--intent` is derived from the class and prints a deprecation
warning; it becomes required in v0.45.0.

`--skip-gates` skips the **optional** gates only — clean tree, tag match —
and only on non-production classes. It never skips the class guard or the
production approval. (Before v0.44.0 it skipped nothing at all: it was
parsed, printed as `Gates: SKIPPED`, and never read, so an operator was
told gates were skipped and then failed on the gate they asked to skip.)

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

## The chain: build → test → deploy

Three phases, three entry points, each writing a record the next one
checks — so what reaches staging or production is exactly what was built
from a commit and then tested.

| Phase | Entry point | Skill | Writes | Refuses when |
|---|---|---|---|---|
| **Build** | `./build/build [--env=<e>]` | `/build` | `builds/records/BLD-<utc>.md` (+ `.artifacts`, `.log`) | no commits; the tree differs from HEAD; the build wrote files git does not ignore; a declared artifact is missing |
| **Test** | `./build/test [--build=<id>]` | `/test` | `tests/runs/TST-<utc>.md` (+ logs) | no successful build of HEAD; the tree differs from HEAD; the build's artifacts changed since it was built |
| **Deploy** | `./build/deploy --env --intent` | `/deploy`, `/release` | `deploys/records/DEP-….md` | at staging and prod: no passing test run of HEAD whose build's artifacts are unchanged (`gates/verified-build.sh`); at prod also no `tests/suites/smoke.md` |

- **Build once.** `20-build.sh` is the one build definition. `./build/build`
  runs it and fingerprints what it declares; with a verified build,
  `./build/deploy` skips `20-build` and ships those artifacts.
- **Test the build.** `./build/test` runs the gate suite strict, then
  `tests/suites/e2e.md` with its runtimes started, health-checked and
  always stopped (`test-rules.md` → "End-to-end").
- **Verify after deploy.** `60-verify.sh` runs `tests/suites/smoke.md`
  against the environment that was just deployed.
- **Calibration.** `verified-build` refuses at `staging` and `prod`, warns
  at `dev` and `unclassified`, and has no bypass variable. `--dry-run`,
  `--skip-gates`, `--skip-tests` and `env.sh` all still reach it.
- **The records are files.** They make a skipped or stale step impossible
  to ship by accident; they do not stop someone forging one on purpose —
  the approval gate and branch protection do that. `git-clean.sh` never
  counts `builds/` or `tests/runs/` as dirt.

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

**Declare the artifacts.** Append one line per output to
`$BUILD_ARTIFACTS` — a path relative to the project (a file or a
directory), or `label=value` for something that is not a file:

```sh
echo "dist" >> "$BUILD_ARTIFACTS"
echo "image=$(docker image inspect -f '{{.Id}}' "$IMAGE_NAME:$DEPLOY_TAG")" >> "$BUILD_ARTIFACTS"
```

`./build/build` fingerprints them; the deploy gate refuses a build whose
artifacts changed after it was tested. The variable is always set, in
`./build/build` and in `./build/deploy` alike. Build outputs must be in
`.gitignore` — a build that dirties the tree fails.

### `30-test.sh` — run the test suite

Reads `tests/suites/pre-deploy.md` (or another suite based on env), iterates the listed tests, runs each. See `test-rules.md` for the test stamp model.

Two inputs from the phase scripts, both of which can only narrow or
tighten it: `TEST_SUITE=<name>` runs `tests/suites/<name>.md` (missing is
an error, never a fall-back) and `TEST_STRICT=1` applies the prod rule —
a suite that runs nothing fails — at any class. `./build/test` sets both.

Failures abort the pipeline. `--skip-tests` skips the stage below `prod` class and is **REFUSED at `prod` class** (exit 2) — the parenthetical "don't use for prod" was a comment, and a comment is not a gate. A suite that would run no tests also refuses at `prod` class, via `build/gates/tests-required.sh`, which has no bypass variable.

### `40-publish.sh` — push the artifact to its target

Project-specific. Examples:

- Container: `docker push $REGISTRY/$IMAGE_NAME:$TAG`
- iOS: export `.ipa` (if not done in build)
- Web: prepare `dist/` for deploy (often a no-op)
- Library: `npm publish` / `pip upload`

Leave as no-op if your project's deploy step does both publish + deploy in one shot.

### `50-deploy.sh` — invoke the env-specific deploy command

By default just `exec` into the environment's `deploy.sh`. Keep this generic; per-env logic lives in `environments/<env>/deploy.sh`.

### `60-verify.sh` — prove the deployed environment works

Runs `tests/suites/smoke.md` through `30-test.sh` against the environment
just deployed (`ENVIRONMENT`, `DEPLOY_TO`, `DEPLOY_TAG` are exported). At
prod class the suite is required and must run at least one test; below
prod, a missing `smoke.md` warns. A failure fails the deploy and the ship
log records `failed at 60-verify` — **with the new build live.** Roll it
back.

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

### `gates/verified-build.sh`

Run by `./build/deploy` right after `tests-required.sh`, before any stage,
where no flag reaches it. Passes when `tests/runs/` holds a passed run of
HEAD whose build (`builds/records/`) succeeded, built HEAD, was built for
this environment or for any, and whose artifacts still match their
fingerprint. Refuses at `staging` and `prod`; warns below. No bypass
variable. Shared logic lives in `gates/verify-lib.sh`.

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
3. Invoke `./build/deploy --env=<name> --intent=<deploy|release> [args]`
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

After `/setup-deploy`, deploys are just `./build/deploy --env=<env> --intent=deploy` from then on.

---

**See also:** `test-rules.md` for the test stamp model and suite gating. `stamps.md` for the universal stamp pattern.
