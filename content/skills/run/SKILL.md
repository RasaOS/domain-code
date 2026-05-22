---
name: run
description: Run / launch / serve the project locally. Detects project language/toolchain and uses the conventional run command — `npm run dev`, `python main.py`, `cargo run`, `xcodebuild + simulator`, `go run`, etc. For ecosystems with a compile step, builds first if needed. Triggered when the user wants to start the app — e.g. "/run", "run the project", "spin up the dev server", "launch in the simulator".
---

# /run — Run the project

Start the project locally. Detect the toolchain, activate any
version pin, run the conventional dev / run command, and surface
the result (URL, simulator window, log tail).

This skill **does** start a process. Unlike `/build` (which only
verifies compilation), `/run` actually launches the app.

Per CLAUDE.md: honest reporting. If the run fails, surface the
real error. If the app starts but the URL doesn't respond yet,
say "started, awaiting readiness" rather than "running".

## Behavior contract

- **Detect first.** Same logic as `/build` — read `CLAUDE.md`,
  glob for manifests:

  | Manifest / context | Conventional run command |
  |---|---|
  | `package.json` with `dev` / `start` script | `npm run dev` (or the documented dev script) |
  | `package.json` API / server only | `npm start` or documented |
  | `*.xcodeproj` + iOS scheme | `xcodebuild -scheme … -destination 'platform=iOS Simulator,name=…' build` then `xcrun simctl launch` |
  | `Package.swift` | `swift run` |
  | `build.gradle(.kts)` Android | `./gradlew installDebug` + `adb shell am start …` |
  | `pom.xml` Spring Boot etc. | `mvn spring-boot:run` or documented |
  | `go.mod` | `go run ./cmd/<bin>` or `go run .` |
  | `Cargo.toml` | `cargo run` (with `--bin <name>` if multi-bin) |
  | `pyproject.toml` / `setup.py` + entrypoint | `python -m <module>` or documented |
  | `Gemfile` Rails | `bin/rails server` |
  | `mix.exs` Phoenix | `mix phx.server` |
  | `*.csproj` | `dotnet run` |
  | `Makefile` with `run` / `dev` target | `make dev` |
  | `Dockerfile` / `compose.yaml` | `docker compose up` (if user asks) |

- **Project's `CLAUDE.md` overrides defaults.** If the project
  documents a specific run command, that's the source of truth.

- **Honor toolchain pins** the same way `/build` does (`.nvmrc`,
  `.tool-versions`, `.python-version`, etc.).

- **Pre-flight: handle stale processes.** Many dev servers fail to
  start because a previous instance is still bound to the port.
  Before starting:
  - Web: identify the dev port (Vite 5173, CRA 3000, Next 3000,
    Rails 3000, Django 8000, etc. — check `vite.config.*`,
    `package.json`, env, or `CLAUDE.md`).
  - If a process holds it, kill it first (`lsof -ti:<port> | xargs
    -r kill -9`) — or, if the project ships a `predev` /
    equivalent that does this, just trust it and run.
  - For native / mobile: kill stale simulators / emulators only
    if the user asked.

- **Run in the background, then verify readiness.** Most run
  commands don't terminate. Start the process backgrounded,
  briefly wait for the readiness signal (HTTP 200 on the dev URL,
  "compiled successfully" line, simulator boot complete), then
  report.

- **Don't auto-deploy, don't auto-test.** This skill runs the app
  for the human. Tests are a separate command. Deploy is
  `/release`.

- **Don't bypass install steps silently.** If dependencies aren't
  installed (`node_modules/` missing, no virtualenv, no
  `cargo build` artifact), say so and ask before installing.

## Process

### Step 1 — Detect

Read `CLAUDE.md`. Glob for manifests. Decide the run command and
the readiness signal (URL + port for servers; window/process for
GUI/native).

State detection in one line before running.

### Step 2 — Activate toolchain

If a version pin exists, activate it. For Node + nvm in
non-interactive shells, use:

```sh
export NVM_DIR="$HOME/.nvm" && \. "$NVM_DIR/nvm.sh" && nvm use >/dev/null
```

### Step 3 — Pre-flight

- Kill stale process on the dev port if relevant.
- For native: ensure simulator/emulator is available (or asked
  before booting one).
- For containers: ensure runtime is up.

### Step 4 — Launch

Start the run command **in the background** so the chat can
continue. Capture stdout/stderr to a tail-able buffer.

For build-then-run toolchains (Xcode, Gradle Android), the build
phase runs in foreground; only the launch is backgrounded.

### Step 5 — Verify readiness

- **Web**: poll the dev URL until it returns or until a
  readiness line appears in stdout (typical: "Local: http://…",
  "ready in", "compiled successfully"). Cap the wait at ~30s.
- **Native**: wait for the simulator/emulator process and the
  app launch.
- **CLI**: just confirm the process is running and not crashing
  on startup.

### Step 6 — Report

Render the output structure. Open the URL / surface the
simulator only if the user is local and the host can do so —
otherwise just print the URL.

## Output structure

```markdown
# ▶️ Running — <project name or scope>

> **Status.** ✅ ready | ⏳ starting | ❌ failed to start

**Detected toolchain.** <e.g. "Node 20 + Vite">
**Command.** `<exact command>` *(running in background)*
**URL / target.** <http://localhost:5173 | iOS Simulator: iPhone 15 Pro | …>
**Process.** <pid or background-id>

---

## Startup output

```
<last ~20 lines of stdout/stderr — enough to show readiness or
the error, not the whole log>
```

---

## What now

- **To stop:** <how — kill pid, ctrl-c if foreground, etc.>
- **To watch logs:** <how — tail file, attach to process>
- **To run tests:** <project's test command from CLAUDE.md / package.json>

*(Skip rows that don't apply.)*

---

## Bottom line

<one or two sentences. On ✅: "Hit <URL>." On ⏳: "Server starting,
typically ready in N seconds — refresh the URL." On ❌: name the
root cause and the suggested fix.>
```

## Style rules

- **Print the URL even if you can't open it.** The user needs to
  see it.
- **Don't dump the whole log.** ~20 lines max in the report. The
  user can tail if they want more.
- **Surface real errors verbatim.** Same rule as `/build`.
- **Don't editorialize unrelated issues** found in the log.

## What you must NOT do

- **Don't deploy.** That's `/release`.
- **Don't run tests as a side-effect.** The user can ask
  separately.
- **Don't kill processes the user didn't ask about.** Stale dev
  ports, yes (it's prerequisite). Other random processes, no.
- **Don't auto-rerun on failure.** Report the failure and stop.
  Loop-on-fail hides root cause.

## When NOT to use this skill

- **Just verify it builds** → `/build`.
- **Deploy to production** → `/release`.
- **Debug a runtime issue** → `/stuck` or hands-on debugging.
- **Production hosting** → use your deploy / hosting tooling, not
  this skill. This is for local dev.

## What "done" looks like for a /run session

A running process and a clear "where to find it" pointer (URL,
simulator window, attached pid). The user can interact with the
app. The skill doesn't loiter — once the process is up and the
report is rendered, the turn ends.
