---
name: build
description: Build the project — compile, type-check, package — without running it. Detects project language/toolchain (Node, iOS/Xcode, Android/Gradle, Go, Rust, Python, etc.) and uses the project's conventional build command. For ecosystems without a build step (Python, Ruby, etc.), runs the closest equivalent (lint + type-check) and says so honestly. Triggered when the user wants to verify the project compiles — e.g. "/build", "does it build", "build and check for errors", "compile this".
---

# /build — Build the project

Run the project's build to verify it compiles / type-checks /
packages cleanly. **Do not run / launch / serve the result.** That's
`/run`.

Per CLAUDE.md: honest reporting. If a step warns or fails, surface
the actual output, not a paraphrase. Don't claim "build clean" if
there are warnings.

## Behavior contract

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

## Languages without a build step

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

## Process

### Step 1 — Detect

Read `CLAUDE.md`. Glob for manifest files. Decide the toolchain
and build command. **State your detection** before running, in
one line: `Detected: Node / Vite — running \`npm run build\``.

If detection is ambiguous, ask once.

### Step 2 — Activate toolchain

If a version manager pin exists, activate it.

### Step 3 — Run the build

Run the build command in the foreground. Capture stdout + stderr.
For very long builds (Xcode, Gradle), consider running in the
background and tailing — but only if the user asked for that or
the build is clearly going to be slow (>2 min).

### Step 4 — Report

Render the output structure below. **Don't run anything else.**
Don't auto-launch the app on success.

## Output structure

```markdown
# 🔨 Build report — <project name or scope>

> **Result.** ✅ clean | ⚠️ warnings | ❌ failed

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
the user is trying to do? On clean: "ready to /run or open a PR."
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
- **Test the project** — running tests is closer to `/run` than
  build. Use the project's test command directly, or extend the
  build skill only if the project's contract bundles them.
- **Deploy** → `/release`.
- **Code review** → `/review` or `/audit`.

## What "done" looks like for a /build session

A single build report. No app launched, no server started, no
deploy. The user reads the report and decides what's next.
