---
name: dashboard
description: Start, stop, refresh, or check the live HTML dashboard for this project — a single-page browser view of production, git state, activity timeline, open PRs, in-flight tasks, inbox, backlog, recent commits, and warnings. Reads project files (no DB, no daemon). Triggered when the user wants the visual companion to the kit — e.g. "/dashboard", "/dashboard start", "open the dashboard", "start the dashboard server", "stop the dashboard", "show me the kit dashboard", "is the dashboard running".
---

# /dashboard — live kit dashboard

Manage the lifecycle of `.claude/dashboard/` — a self-contained
HTML+Python dashboard that visualizes the kit's runtime state in
one place. Opt-in: nothing happens until the user installs it.

Per CLAUDE.md ethos: **calibrate honestly.** If the dashboard
isn't installed, say so and point at the install step. If a port
is in use, say so. If `gh` isn't available and PRs don't load,
say so.

## Behavior contract

- **Read-only orchestrator.** This skill starts/stops a Python
  server. It does not edit project files, does not commit, does
  not push.
- **Opt-in by design.** The dashboard files (`dashboard.py`,
  `index.html`, `README.md`) live at `kit/dashboard/` in the
  claude-kit repo and are **not** synced by `/sync` or installed
  by `bin/init`. Users opt in by copying them into their
  `.claude/dashboard/`.
- **Detect installation first.** Before any command, check whether
  `.claude/dashboard/dashboard.py` exists in the project root. If
  not, surface the install step — don't try to start a server
  that isn't there.
- **Detect Python.** Need `python3` 3.9+. If it's missing, surface
  it with the actual `python3 --version` output.
- **Background server.** `start` spawns the Python script via
  `nohup ... &` so it survives the current shell. It writes a PID
  file (`.claude/dashboard/.dashboard.pid`) used by `stop` and
  `status`.
- **Localhost only.** The server binds to `127.0.0.1` — never
  expose to LAN. Don't override this.
- **Don't auto-stop other processes.** If port 7531 is taken by
  something else (not our PID file), report it and suggest
  `--port` rather than killing whatever's there.

## Output structure

**Catalogue entry.** §25 Alert variants for status messages
(INFO when running cleanly, WARNING when something's odd, ERROR
on failure). Optional §28 Stats card grid for the steady-state
"running" report (URL, port, PID, uptime).

This skill is a thin orchestration layer — its primary outputs
are short status alerts, not a long deliverable.

## Process

### Step 1 — Detect installation

Check `.claude/dashboard/dashboard.py`. If missing, render an
`INFO` alert with the install command:

````markdown
```
┌─ ⓘ  INFO ───────────────────────────────────────────────────┐
│  dashboard not installed                                    │
│                                                             │
│  Opt-in:                                                    │
│  cp -r /path/to/claude-kit/kit/dashboard ./.claude/         │
│                                                             │
│  See .claude/dashboard/README.md after install.             │
└─────────────────────────────────────────────────────────────┘
```
````

Stop. Don't try to start anything.

### Step 2 — Route on subcommand

The user's invocation determines the operation:

| Invocation | Operation |
|---|---|
| `/dashboard` (bare) | `status` — show running state, render summary if alive, suggest `start` if not |
| `/dashboard start [--port N]` | `start` |
| `/dashboard stop` | `stop` |
| `/dashboard status` | `status` |
| `/dashboard refresh` | `refresh` — write state.json once, no server |
| `/dashboard restart` | `stop` then `start` |

If the invocation is ambiguous ("turn on the dashboard"), default
to `start`.

### Step 3 — Operation: status

Run `python3 .claude/dashboard/dashboard.py status`. Returns
running PID or "not running".

If running: render a short summary using §28 Stats card grid:

````markdown
```
┌──────────────────┬──────────────────┬──────────────────┐
│      RUNNING     │      :7531       │      PID 12345   │
│       state      │       port       │       process    │
└──────────────────┴──────────────────┴──────────────────┘
```

→  http://localhost:7531
````

If not running: render an INFO alert suggesting `/dashboard start`.

### Step 4 — Operation: start

The python script handles environment detection itself — local
auto-opens the browser, SSH prints a ready-to-paste tunnel
command, Codespaces / Gitpod / dev containers get platform-
specific guidance. Your job is the lifecycle (pre-flight, run,
verify, report) — not the env decision.

Pre-flight:

1. `python3 .claude/dashboard/dashboard.py status` — if already
   running, report and exit (don't double-start).
2. Check the requested port is free (`lsof -i :PORT` or
   `nc -z 127.0.0.1 PORT`). If taken by a non-dashboard process,
   render a WARNING alert and suggest `--port`.

Start in the background:

```sh
cd <project root>
nohup python3 .claude/dashboard/dashboard.py start --port <port> \
  > .claude/dashboard/.dashboard.log 2>&1 &
```

The script's stdout (now in the log file) contains the env-aware
guidance — read the first ~20 lines after starting; that's what
the user needs to see. For SSH sessions, this includes the
ready-to-paste `ssh -L ...` tunnel command. Quote it back to the
user verbatim — don't reformat.

Wait briefly (~1s), then verify the server is up by polling
`http://localhost:PORT/state.json`. If it responds with HTTP 200,
the server's alive.

Render a SUCCESS alert with the URL plus, if the log shows a
remote env, the SSH tunnel line:

````markdown
```
┌─ ✓  SUCCESS ────────────────────────────────────────────────┐
│  dashboard running                                          │
│  →  http://localhost:7531                                   │
│  PID 12345 · log .claude/dashboard/.dashboard.log           │
│                                                             │
│  REMOTE (SSH) detected — on your local machine:             │
│    ssh -L 7531:localhost:7531 chazz@1.2.3.4                 │
│  then open  http://localhost:7531                           │
└─────────────────────────────────────────────────────────────┘
```
````

(The "REMOTE" block only renders if the script's output
contained "REMOTE (SSH)" — local mode just shows URL + PID.)

If the verify poll fails, render an ERROR alert with the tail of
the log file (`.claude/dashboard/.dashboard.log`). Don't leave a
zombie running.

### Step 5 — Operation: stop

`python3 .claude/dashboard/dashboard.py stop`. Render an INFO
alert with what stopped.

If `stop` reports "not running", that's not an error — render an
INFO alert.

### Step 6 — Operation: refresh

`python3 .claude/dashboard/dashboard.py refresh`. Writes
`.claude/dashboard/state.json` once and exits — useful for debug
or for a one-shot snapshot without running the server.

Render the size of state.json + a summary count:

```
state.json written (4.2 KB)
  · 10 commits  · 0 open PRs  · 8 audit entries  · 2 worktrees
```

### Step 7 — Operation: restart

`stop` → wait for PID file to clear → `start`. Same alerts as the
two operations on their own.

## Style rules

- **Render structured deliverables per `output-rules.md`.** §25
  Alert variants for state messages (INFO/WARNING/ERROR/SUCCESS).
  §28 Stats card grid only for the running-state status report.
- **Don't narrate the lifecycle.** If `start` succeeds, the
  output is the SUCCESS alert with the URL — not a paragraph
  about what happened.
- **Surface the URL prominently.** Every successful start should
  end with the clickable `http://localhost:PORT` line.
- **Cite log file on failure.** `.claude/dashboard/.dashboard.log`
  is the truth — show its tail when the server fails to start.
- **Calibrate honestly.** If you couldn't verify the server is up
  (e.g., poll timed out), say so. Don't claim success on hope.

## What you must NOT do

- **Don't auto-install the dashboard.** Detection-only. The opt-in
  is a deliberate user action.
- **Don't kill processes on the requested port** that aren't the
  dashboard's own PID. That's destructive — suggest `--port`
  instead.
- **Don't expose the server beyond `127.0.0.1`.** No `0.0.0.0`,
  no `--bind`, no LAN hostname binding.
- **Don't poll the dashboard's `/state.json` repeatedly from this
  skill.** The browser already does that on its 3s timer.
- **Don't auto-commit the runtime files** (`state.json`,
  `.dashboard.pid`, `.dashboard.log`). They're in the dashboard's
  `.gitignore` already.

## Edge cases

- **Dashboard not installed.** Render install instructions; stop.
- **Port in use by another process.** Render WARNING, suggest
  `--port` argument.
- **Server starts but `/state.json` poll fails.** Stop the
  process (it's a zombie), render ERROR with log tail.
- **Stale PID file** (process died but file remains). Detect via
  `kill -0 <pid>` failing; remove the stale file and restart.
- **`gh` not installed.** That's not a hard failure — the PRs
  panel renders an empty state with "install gh to enable." The
  dashboard works fine without it.
- **No git history yet** (fresh repo, no commits). All git-derived
  panels render empty states. Not an error.
- **No `tasks/` directory** (project doesn't use the kit's task
  layout). Backlog / In flight panels render empty. Activity
  panel falls back to `CHANGELOG.md` if present.

## When NOT to use this skill

- **Reading the dashboard's content programmatically** → just
  read `.claude/dashboard/state.json` directly after a `refresh`.
- **Modifying what the dashboard shows** → edit `dashboard.py`'s
  gather functions. The skill doesn't change the dashboard's
  schema.
- **Customizing the dashboard's design** → edit `index.html`.
  Same — out of scope for this skill.
- **Setting up a 24/7 dashboard service** → write a `launchd`
  plist or `systemd` unit yourself; this skill is for
  Claude-session-companion lifecycles only.

## What "done" looks like for a /dashboard session

The user's intent is satisfied:

- `start` → server running, URL surfaced, page reachable.
- `stop` → server stopped, PID file cleaned up.
- `status` → accurate report of running/not-running.
- `refresh` → fresh `state.json` on disk.

If a step fails, the failure is reported with concrete next-steps
(install, change port, check log) — never silent.
