---
name: build
description: The BUILD phase — build this commit once and record it. Runs the project's one build definition (`build/stages/20-build.sh`, the same stage `./build/deploy` runs) from a clean tree through `./build/build`, which writes `builds/records/BLD-*.md` with the commit and the fingerprint of every artifact; `/test` tests that record and `/deploy` / `/release` ship it instead of rebuilding. When the project has no pipeline yet, falls back to a toolchain-detected compile / type-check and says plainly that it is not a recorded build. Triggered when the user wants the project built — e.g. "/build", "build it", "does it build", "build for staging", "compile this".
---

# /build — Build this commit, once, on the record

The first of three phases: **`/build` → `/test` → `/deploy`**
(or `/release`). Each writes a record the next one checks, so a
deploy can only ship what was built from a commit and then tested.

**Why it exists.** A deploy used to rebuild the app from scratch, so
what reached production was a *different* build from the one that was
tested. `/build` builds **once** and writes down exactly what it made:
the source it built (a fingerprint of the committed tree), a unique
`BUILD_TAG`, and a checksum of every output. `/test` tests that build,
and `/deploy` ships that same build — never a new one.

Per CLAUDE.md: honest reporting. Surface the actual output, not a
paraphrase. Don't claim "build clean" if there are warnings.

## Two modes — say which one ran

| Mode | When | What it proves |
|---|---|---|
| **Pipeline build** | `build/build` exists and `build/stages/20-build.sh` is configured | This commit was built by the project's real build, and the artifacts are fingerprinted. `/test` and `/deploy` accept it. |
| **Compile check** | No pipeline, or `20-build.sh` is still the `TODO: configure` stub | The code compiles / type-checks. **Nothing downstream accepts it** — no record is written. |

Detect: `20-build.sh` containing `TODO: configure 20-build.sh` is
the unconfigured stub. Never report a compile check as "built".

## Pipeline build

### Step 1 — Run it

```bash
./build/build                 # environment-neutral (the default)
./build/build --env=<env>     # a build that bakes in one environment's config
```

It refuses (exit 3) a repository with no commits, **any** uncommitted
change in the repository — in a monorepo that includes shared folders
outside this project, and edits hidden with `--skip-worktree` — and a
second build while one is running (`builds/.lock`). Commit or stash
first; never work around it.

Before running `20-build.sh` it removes the outputs the previous build
declared (only git-ignored paths inside the project), so a stale file
left in `dist/` cannot be fingerprinted into this build.

Use `--env` only when the build really is environment-specific (e.g. a
web bundle with the API URL compiled in): it loads that environment's
`env.sh`, exactly as a deploy would, the record says `built_for: <env>`,
and the deploy gate refuses to ship it anywhere else. An
environment-neutral build (the default) must not depend on `env.sh`
variables.

### Step 2 — Check what it declared

`20-build.sh` declares its outputs by appending to
`$BUILD_ARTIFACTS` — `echo dist >> "$BUILD_ARTIFACTS"` for a file or
directory, `image=<id>` for a container. Tag images with `$BUILD_TAG`
(unique per build); `40-publish` pushes the same tag.

- **Declared nothing** → staging and production refuse the build: nothing
  would prove what ships is what was tested. Offer the one-line fix. A
  deploy that genuinely builds from source itself declares that on
  purpose: `echo source=commit >> "$BUILD_ARTIFACTS"`.
- **A symlink inside an output** must point inside that same output
  (where its target is fingerprinted); one pointing anywhere else fails
  the build. So does anything that is not a file, directory or symlink.
- **A path containing `=`** is a path; only `label=value` shapes like
  `image=sha256:…` are labels.

A build that writes files git does not ignore **fails**: the
source it was built from changed. The fix is `.gitignore`, not
deleting the files.

### Step 3 — Report

Build id, commit, `BUILD_TAG`, duration, artifacts and fingerprint,
and the next step: `/test`.

## Compile check (no pipeline)

Run this only when the pipeline build is unavailable, and lead
the report with **"Compile check — not a recorded build. Run
/setup-deploy to give this project a pipeline build that /test and
/deploy accept."**

### Detection rules

- **Detect first.** Don't assume. Read `CLAUDE.md` for the
  project's tech stack and build command. Then look for manifest
  files to confirm:

  | Manifest present | Likely toolchain | Conventional build command |
  |---|---|---|
  | `package.json` with `build` script | Node / web | `npm run build` (or `pnpm` / `yarn` per lockfile) |
  | `*.xcodeproj` / `*.xcworkspace` / `Package.swift` | Xcode / iOS / macOS / SwiftPM | `xcodebuild build -scheme <…>` or `swift build` |
  | `build.gradle(.kts)` | Gradle / Android / JVM | `./gradlew build` (or `assembleDebug`) |
  | `pom.xml` | Maven | `mvn compile` or `mvn package` |
  | `go.mod` | Go | `go build ./...` |
  | `Cargo.toml` | Rust | `cargo build` |
  | `pyproject.toml` / `setup.py` | Python | no compile step — see below |
  | `Gemfile` | Ruby | no compile step — see below |
  | `mix.exs` | Elixir | `mix compile` |
  | `*.csproj` / `*.sln` | .NET | `dotnet build` |
  | `Makefile` with a `build` target | generic | `make build` |
  | `Dockerfile` (and user asks) | container | `docker build .` |

  If multiple are present (e.g. monorepo), ask which to build.

- **Project's `CLAUDE.md` overrides defaults.** If the project
  documents a specific build command (e.g. `npm run build:prod`,
  `make ci`, `bazel build //...`), use that — it's the source of
  truth, not the table above.

- **Honor toolchain pins.** If the repo has `.nvmrc`,
  `.tool-versions`, `.python-version`, `.ruby-version`, `rust-toolchain.toml`,
  `Gemfile.lock`, or similar — activate the pinned version before
  building. Common patterns:
  - Node: `nvm use` (note: `nvm` is a shell function — use the
    `export NVM_DIR=… && \. "$NVM_DIR/nvm.sh" && nvm use` form
    in non-interactive shells)
  - Python: `pyenv shell <version>`
  - Ruby: `rbenv shell <version>`

- **Don't run / serve / deploy / install dependencies as a
  side-effect.** If `node_modules/` or `vendor/` is missing, say
  so and ask before installing. Same for `pip install -r
  requirements.txt`. Installing is a separate decision.

- **Surface warnings, don't bury them.** Many ecosystems treat
  warnings as warnings, but warnings are how broken things ship.
  Quote them in the report.

### Languages without a build step

For ecosystems where there's no compile/build (interpreted, no
type system or bytecode artifact):

- **Python, Ruby, Lua, plain JS, shell** — there's no "build."
  Run the closest equivalent and say so:
  - **Type check** if the project has one configured (`mypy`,
    `pyright`, `sorbet`, `tsc --noEmit` for JS-with-JSDoc,
    `flow`).
  - **Lint** as a sanity gate (`ruff`, `flake8`, `rubocop`,
    `eslint`, `shellcheck`).
  - **Syntax check** as a last resort (`python -m compileall .`,
    `ruby -c`).

  In the report, lead with **"This project doesn't have a build
  step — ran <X> as the closest equivalent."** so the user knows
  what they actually got.

### Check process

#### Step 1 — Detect

Read `CLAUDE.md`. Glob for manifest files. Decide the toolchain
and build command. **State your detection** before running, in
one line: `Detected: Node / Vite — running \`npm run build\``.

If detection is ambiguous, ask once.

#### Step 2 — Activate toolchain

If a version manager pin exists, activate it.

#### Step 3 — Run the build

Run the build command in the foreground. Capture stdout + stderr.
For very long builds (Xcode, Gradle), consider running in the
background and tailing — but only if the user asked for that or
the build is clearly going to be slow (>2 min).

#### Step 4 — Report

Render the output structure below. **Don't run anything else.**
Don't auto-launch the app on success.

## Output structure

```markdown
# 🔨 Build report — <project name or scope>

> **Mode.** Pipeline build `BLD-…` | Compile check (not recorded)
> **Result.** ✅ clean | ⚠️ warnings | ❌ failed

**Record.** `builds/records/BLD-….md` — commit `<sha>`, <n> artifact(s), fingerprint `<first 16>` *(pipeline build only)*
**Detected toolchain.** <e.g. "Node 20 + Vite 6">
**Command run.** `<exact command>`
**Duration.** <Xs / Xm Ys>

---

## What happened

<one paragraph — succeeded with no warnings / succeeded with N
warnings / failed at step Y>

### Warnings *(if any)*

```
<verbatim warning lines, deduped if repetitive>
```

### Errors *(if failed)*

```
<verbatim error block — keep the first failure, summarize repeats>
```

---

## Notable output

*(only if useful — bundle size, output paths, generated artifacts.
Skip the section if there's nothing notable.)*

- Output: `dist/` (X files, Y MB)
- …

---

## Bottom line

<one or two sentences. What does this build state mean for what
the user is trying to do? On clean: "next: /test."
On warnings: name them. On failure: name the root cause and the
suggested next step.>
```

## Style rules

- **Verbatim error/warning text.** Don't paraphrase compiler
  output. Reviewers need the literal lines for grep / search.
- **Quote, don't summarize, the failure.** If the build crashed
  at a specific file:line, show that line.
- **Don't editorialize unrelated codebase issues** discovered in
  the output. This is a build report, not a review.
- **No emoji beyond the section's three result markers** (✅ ⚠️ ❌).

## When NOT to use this skill

- **Run / launch / serve the project** → `/run`.
- **Test the build** → `/test`, the next phase.
- **Deploy** → `/deploy` (dev / staging) or `/release` (prod).
- **Code review** → `/review` or `/audit`.

## What "done" looks like for a /build session

A single build report that says which mode ran. For a pipeline
build: a `BLD-…` record for this commit with its artifacts
fingerprinted, and `/test` named as the next step. For a compile
check: the result, and the plain statement that nothing downstream
accepts it. No app launched, no server started, no deploy.
