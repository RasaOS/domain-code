---
name: deploy
description: Deploy the project to a LOWER environment — dev or staging. Structurally cannot reach production: the pipeline's class-guard refuses it, and there is no bypass flag. Routes to `./build/deploy --intent=deploy`. Use for "/deploy", "/deploy staging", "push this to staging", "get it on dev", "deploy it so I can test". If the user wants production, that is `/release` — say so and stop rather than trying.
---

# /deploy — Ship to a lower environment

`/deploy` goes DOWN the stack. `/release` goes to production. Same
pipeline underneath; the direction is the whole difference.

**This skill cannot deploy to production.** Not "should not" — the
`class-guard.sh` gate refuses the pairing before any stage runs, and
unlike the clean-tree and approval gates it has no `FORCE_*` escape. If
the user asks you to `/deploy` to prod, tell them the sanctioned route is
`/release` and stop. Do not reach around the gate by calling
`environments/<env>/deploy.sh` directly, editing a class, or renaming an
environment.

## What direction means here

| | `/deploy` | `/release` |
|---|---|---|
| Target class | `dev`, `staging` | `prod` |
| Tags? | No | Yes, always |
| Approval gate | No | Yes (production class) |
| If the user says... | "deploy", "push to staging", "get it on dev" | "release", "ship it", "cut a release", "go to prod" |

If the user says "deploy to production", they mean release. Say that,
then run `/release` if they confirm — do not silently translate.

## Steps

### 1 — Resolve the target environment

Read the registry, which is the source of truth for what exists and what
class each environment is:

```bash
.claude/skills/environment/environment.sh classes
```

Each row is `<name>  <class>  <why>`. Pick from the `dev` and `staging`
rows.

- **Argument given** (`/deploy staging`) — use it.
- **No argument** — use the session's current environment if it is not
  production: `.claude/skills/environment/environment.sh current`.
  Otherwise present the non-prod environments and ask which.
- **Registry missing** — fall back to the directory listing under
  `build/environments/`, and say the project has no environment registry
  so classes are being guessed from names.

Never pick an environment for the user when more than one non-prod
environment exists and they did not name one.

### 2 — Check the class before spending their time

```bash
.claude/skills/environment/environment.sh class <env>
```

`prod` → stop here. Tell them `/deploy` cannot target production and
that `/release` is the route. Do not run the pipeline to let the gate
produce the error; say it yourself, immediately.

`unclassified` → proceed, and tell them once that the environment has no
declared class, so it is unguarded. Point at `environment.sh classes`.

### 3 — Make sure this commit was built and tested

At `staging` class the pipeline refuses a deploy unless `/test` passed
a `/build` of HEAD whose artifacts are unchanged (`gates/verified-build.sh`,
no bypass). Check before spending the user's time:

```bash
ls tests/runs/TST-*.md 2>/dev/null | tail -1   # then read its sha: and status:
```

No passing run for HEAD → run `/build` then `/test` first (or ask, if
the user only asked to deploy). At `dev` class the gate only warns, and
when no verified build of this source exists, the pipeline rebuilds in
place as it always has (with one, it ships that build like staging does).

### 3b — Run the pipeline

What it refuses, and the fix — say it plainly, never reach around it:

| Refusal | Fix |
|---|---|
| bad environment name / not in the registry / registry cannot be read | use the registry's name exactly; fix `.claude/environments.json` |
| `verified-build` — no passing test, the newest run failed, artifacts changed, declared no artifacts | `/build` then `/test` (declare outputs in `20-build.sh`) |
| another run holds the lock | wait for it; a lock from a dead run on this host is taken over automatically |
| `artifacts changed during stage …` | a stage rewrote the tested outputs — fix that stage; nothing was shipped past it |

```bash
./build/deploy --env=<env> --intent=deploy
```

`--intent=deploy` is required; without it the pipeline exits 2.

Useful flags, pass through only when the user asked for them:

| Flag | Effect |
|---|---|
| `--dry-run` | Skips every stage. Runs the class guard, tests-required, verified-build and promoted-build gates, but **not** the stage-level gates — `10-preflight` is a stage, so clean-tree and the production approval do not run. It still prints `✓ … complete` and closes its ship-log record `success` with note `dry-run`. A dry-run exit 0 is not a verification. |
| `--skip-tests` | Skips stages whose name contains `test`, below `prod` class. **Refused at `prod` class** (exit 2). |
| `--skip-gates` | Skips the OPTIONAL gates (clean tree, tag match) on non-prod only. Never skips the class guard. |
| `--tag=<tag>` | Overrides the computed `v<semver>-<sha>-<env>` tag. |

With a verified build the pipeline prints `▷ 20-build (reusing BLD-…,
tested by TST-…)` — it ships the tested artifacts rather than
rebuilding — and stage `60-verify` runs `tests/suites/smoke.md` against
the environment after it lands. A `60-verify` failure fails the deploy
**with the new build live**: say that plainly and point at the
environment's rollback.

### 4 — Stream and report

Show the output as it runs. Do not summarize away a stage failure.

On success, report: environment, class, tag, duration. On failure,
report the stage that failed and the actual error — the pipeline prints
`✗ Stage failed: <name>` and exits 1.

## What this skill does not do

- **It does not decide how to deploy.** The mechanics live in
  `build/environments/<env>/deploy.sh`, which the project owns. If that
  file is missing, say so and point at `/setup-deploy`.
- **It does not tag.** Tagging is a release act. A deploy is repeatable
  and disposable; that is why it is safe to do often.
- **It does not touch production.** See above, twice.

## Related

- `/build` → `/test` → `/deploy` — the three phases; each writes the
  record the next one checks.
- `/release` — production, tagged. The other direction.
- `/environment` — declare environments and their classes; set the
  session's current environment.
- `/setup-deploy` — scaffold `build/` for a project that has no pipeline.
- `.claude/pipeline-rules.md` — the stage and gate contract.
- `.claude/environment-rules.md` — the registry and the class model.
