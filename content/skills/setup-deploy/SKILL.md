---
name: setup-deploy
description: Walk a project through configuring its deploy pipeline and test suite — pipeline-config.toml, stages, environments, test stamps. Generates concrete bash scripts so future deploys are dumb shell calls. Triggered when the user wants to set up CI/CD — e.g. "/setup-deploy", "configure deployment", "I want to set up deploys for this project", "wire up the pipeline".
---

# /setup-deploy — Configure the deploy pipeline

Interactive setup that fills in the kit-shipped `build/` and `tests/` scaffolding with project-specific commands. Reads what's already there, detects project type, asks only what it can't infer, and writes concrete bash scripts that subsequent deploys can just invoke.

After this skill runs, `./build/deploy --env=<env>` should work end-to-end. AI agents don't need to reason about how to deploy at run time — the scripts are the contract.

Pairs with `pipeline-rules.md` (the vocabulary: stages, gates, args, environments) and `test-rules.md` (the test stamp model and suite-as-gate convention).

## Behavior contract

### Discover, don't assume

Read in this order to understand what's already configured:

1. `build/pipeline-config.toml` — project type, env list, suite names. The single source of truth for project-level config.
2. `CLAUDE.md` — "Deploy" / "Tech stack" sections. Existing context to draw from.
3. `build/stages/*.sh` — check whether each stage is still the TODO placeholder or has been filled in.
4. `build/environments/*/` — list which environments exist. The kit ships `example/`; real envs are project-created.
5. `tests/suites/pre-deploy.md` — current `tests:` array. Empty = nothing to gate yet.
6. Project-root indicators for **type detection** (when not already declared in `pipeline-config.toml`):
   - `Dockerfile` (root or `docker/`) → container
   - `*.xcodeproj` or `Package.swift` → ios
   - `package.json` → web (default) or library (if `"main"` + `"version"` and no app entry)
   - `pyproject.toml`, `setup.py`, `requirements.txt` → python (web / library / service — confirm)
   - `go.mod` → go service
   - `index.html` at root, no build tools → static-web
   - **Mixed indicators** → ask explicitly. Don't guess.

Surface what was detected before asking. "I see `Dockerfile` + `package.json` — looks like a containerized Node service. Confirm? [yes/no/other]"

### Ask one question at a time

The setup is a conversation, not a form. Walk the user through:

1. **Project identity** (only if `pipeline-config.toml` has placeholders)
   - Project name (default: directory name)
   - Project type (detected, with confirm)

2. **Environments** (only if not declared, or user asks to add one)
   - "What environments do you deploy to? (e.g. `dev staging prod`, or `prod only`, or your own names)"
   - For each env: "Does `<env>` require approval before deploy? [yes/no]"

3. **Build command** (`build/stages/20-build.sh`, if still TODO)
   - "How do you build this project?" Suggest based on project type:
     - container: `docker build -t "$IMAGE_NAME:$DEPLOY_TAG" .`
     - web: `npm ci && npm run build`
     - ios: `xcodebuild archive -scheme <scheme> -archivePath build/<scheme>.xcarchive`
     - python lib: `python -m build`
     - go: `go build -o build/<name> ./cmd/<name>`
   - Confirm or override.

4. **Test command source** (for populating `tests/suites/pre-deploy.md`)
   - "Do you already have tests in this project? Where do they live?"
   - If yes: "What command runs your full test suite?" → create a test stamp pointing at it
   - If no: leave `pre-deploy` empty; suggest user adds tests via `/test add` (future skill) or by writing scripts to `tests/scripts/`

5. **Publish command** (`build/stages/40-publish.sh`, if still TODO)
   - container: "Which registry? (e.g. `myacr.azurecr.io`, `ghcr.io/myorg`)" → generates `docker push` line
   - ios: usually no-op (export happens in build); confirm
   - web: usually no-op (deploy.sh does both); confirm
   - library: "npm publish or pip upload? Or skip?"

6. **Per-environment deploy** (one pass per env in the list)
   - "How does `<env>` deploy?" Suggest based on detected target hints:
     - Firebase Hosting: prompt for project ID → `firebase deploy --only hosting --project ...`
     - AKS / kubectl: prompt for cluster, resource group, namespace → kubectl/helm command
     - TestFlight: `xcrun altool --upload-app ...` (defer to `/ios-release` skill where applicable)
     - S3 / CloudFront: prompt for bucket, distribution ID
     - Custom: free-form command
   - For each env: generate `build/environments/<env>/env.sh` and `deploy.sh`.

7. **Container-specific** (only if project type is `container` or `mixed-with-container`)
   - "What port does the container expose? (default 8080)"
   - "What's the health-check path? (default `/health`)"
   - "Any required log patterns to expect at startup? (e.g. 'Server listening on')"
   - "Any forbidden log patterns? (defaults: panic, FATAL, stack trace, uncaught)"
   - Edit `tests/container/run-local.sh` (`PORT`, `HEALTH_PATH`) and `tests/container/check-logs.sh` (`EXPECTED_PATTERNS`, `FORBIDDEN_PATTERNS`).
   - Add `container-greenlight` to `tests/suites/pre-deploy.md`'s `tests:` array.

8. **Hooks** (optional)
   - "Any post-deploy notifications? (e.g. Slack webhook, status-page update)" → wire into `pipeline-config.toml` `[hooks]`.

### Write incrementally, never auto-commit

After each user confirmation:

1. Write the relevant file(s). Stage them with `git add` so the diff is reviewable.
2. Tell the user what was written and where.
3. Continue to the next question.

**Never run `git commit`.** Same convention as every other kit skill: leave changes staged for the human to review and commit themselves.

### Verify at the end

Once all questions are answered:

1. Run `./build/deploy --env=<first-env> --dry-run` to validate the wiring (stages discover correctly, env folder exists, no syntax errors).
2. Surface the dry-run output to the user.
3. If anything errors, flag the specific file + line that needs attention. Don't try to fix silently.

### Resume gracefully

If the skill is invoked when partial setup already exists (e.g. `pipeline-config.toml` filled but no envs created), skip the answered questions and pick up at the next gap. Show the user a summary of what's already done before asking the next question.

### Surface unknowns, don't fabricate

If the user doesn't know an answer ("what's our registry hostname?"), don't make one up. Either:
- Leave the field as a `{{PLACEHOLDER}}` they can fill in later, with a clear comment
- Suggest where to find it ("check your Azure portal → Container Registries", "look in CI variables")
- Skip the section and note it as TODO in `pipeline-config.toml`'s notes

## Output structure

When the skill finishes, render a summary like this:

```markdown
## ✓ Deploy pipeline configured

**Project type:** container (Node + Docker)
**Environments:** dev, staging, prod
**Requires approval:** prod

### Generated files

- `build/pipeline-config.toml` — project metadata
- `build/stages/20-build.sh` — `docker build -t "$IMAGE_NAME:$DEPLOY_TAG" .`
- `build/stages/40-publish.sh` — `docker push "$REGISTRY/$IMAGE_NAME:$DEPLOY_TAG"`
- `build/environments/dev/{env.sh,deploy.sh}` — Firebase emulator deploy
- `build/environments/staging/{env.sh,deploy.sh}` — AKS staging namespace
- `build/environments/prod/{env.sh,deploy.sh}` — AKS prod namespace + approval gate
- `tests/container/run-local.sh` — port 3000, /healthz
- `tests/container/check-logs.sh` — expects "Server ready"
- `tests/suites/pre-deploy.md` — added `container-greenlight`

### Dry-run result

`./build/deploy --env=dev --dry-run` → ✓ all stages discovered

### Next steps

1. Review the diff: `git diff --staged`
2. Run a real dev deploy: `./build/deploy --env=dev`
3. Add project-specific tests under `tests/stamps/` and add their names to `tests/suites/pre-deploy.md`
4. Commit when satisfied: `git commit -m "feat: configure deploy pipeline"`
```

## What this skill does NOT do

- **Doesn't run actual deploys.** Run them after setup with `./build/deploy --env=<env>` or `/deploy --env=<env>`.
- **Doesn't decide approval policy for you.** Asks per-env; respects the answer.
- **Doesn't auto-commit.** Stages changes; the human commits.
- **Doesn't fetch secrets.** References them by env var name (`$ASC_KEY_ID`, etc.); user wires the source (CI variable group, 1Password, secret manager).
- **Doesn't replace `/ios-release`.** For iOS-specific TestFlight uploads, the env's `deploy.sh` can delegate: `exec ./bin/release-testflight.sh` or invoke the existing skill.

## When to invoke this skill

- New project, just bootstrapped with `bin/init`, ready to wire up deploys
- Adding a new environment to an existing setup (staging just got provisioned, need to add `build/environments/staging/`)
- Migrating an old pipeline (Azure DevOps YAML, GitHub Actions, etc.) onto the kit's structure
- Just curious about what's wired up — running with no changes is a fine way to audit current state

If `build/` is fully configured and the user just wants to *run* a deploy, use `/deploy` instead (future skill — a thin wrapper around `./build/deploy`).

---

**See also:** `pipeline-rules.md`, `test-rules.md`, `migration-rules.md`, the universal `task-rules.md` for the never-auto-commit convention.
