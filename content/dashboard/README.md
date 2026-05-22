# claude-kit dashboard

A live, browser-rendered status panel for a claude-kit project.
Single static HTML page + a tiny Python server. **Zero runtime
dependencies** beyond Python 3 (already on every macOS/Linux box).

> **Opt-in.** Not installed by `bin/init` and not synced by
> `/sync`. You add it to a project explicitly. Keeps the kit's
> default footprint untouched for projects that don't want a
> running web service.

---

## What it shows

A single "kit" dashboard with all the kit-relevant state in one
view:

- **Production** — latest tag, when it shipped, recent versions,
  30-day deploy frequency strip
- **Git state** — branch, dirty/clean, ahead/behind, all worktrees
- **Activity** — timeline of releases / task ships / scaffolding
  events (from `tasks/AUDIT.md`, falls back to `CHANGELOG.md`)
- **Open PRs** — via `gh pr list` (gracefully degrades if `gh`
  isn't installed)
- **In flight** — files in `tasks/active/`
- **Inbox** — messages in `.claude/inbox/`
- **Backlog** — phases and tasks from `tasks/ROADMAP.md`
- **Recent commits** — last 10 from `main`
- **Anything off** — surfaced warnings (stale PRs, dirty `main`,
  etc.)
- **Mode** — from `.claude/mode` (when `feat/modes` lands)

The page polls `/state.json` every 3 seconds. State is recomputed
on each request — no caching, no background process, no DB.

---

## Installation (opt-in)

From a project that already has the kit installed:

```sh
# Copy the dashboard files into the project's .claude/
cp -r /path/to/claude-kit/kit/dashboard /path/to/your/project/.claude/

# Verify
ls .claude/dashboard
# dashboard.py  index.html  README.md
```

That's it. No `pip install`, no `npm install`. The dashboard runs
with whatever `python3` is on your PATH (3.9+).

---

## Usage

### Via the `/dashboard` skill

The kit ships a `/dashboard` skill that wraps the lifecycle:

```
/dashboard start          # starts the server, opens the page
/dashboard stop           # stops the server
/dashboard status         # shows running state
/dashboard refresh        # writes state.json once, no server (debug)
```

### Or directly

```sh
# from the project root
python3 .claude/dashboard/dashboard.py start
# → auto-detects env: local opens the browser, SSH prints the tunnel command

python3 .claude/dashboard/dashboard.py stop
python3 .claude/dashboard/dashboard.py status
python3 .claude/dashboard/dashboard.py refresh
```

Flags:

```sh
python3 .claude/dashboard/dashboard.py start --port 8080
python3 .claude/dashboard/dashboard.py start --no-open  # don't auto-open browser
```

---

## Environments — auto-detected

`start` checks the environment and tailors its output. You don't
configure anything; it just does the right thing.

### Local (macOS, Linux with `$DISPLAY`, Windows)

Auto-opens the URL in your default browser. Output:

```
claude-kit dashboard
  project : claude-kit
  port    : 7531
  url     : http://localhost:7531

  opening http://localhost:7531 in your default browser…

  Ctrl-C to stop.
```

Override with `--no-open` if you want quiet startup.

### SSH (any remote you SSH into)

Detected via `$SSH_CONNECTION`. The script extracts the remote
host IP, SSH port, and your username, and prints the exact tunnel
command to copy-paste on your **local** machine:

```
claude-kit dashboard
  project : my-project
  port    : 7531
  url     : http://localhost:7531

  REMOTE (SSH) — run this on your LOCAL machine to view:

    ssh -L 7531:localhost:7531 chazz@10.0.0.50

  then open  http://localhost:7531  in your local browser.

  Ctrl-C to stop.
```

If you SSH'd in on a non-default port (e.g. `-p 2222`), it's
included automatically: `ssh -p 2222 -L ...`. The dashboard server
still binds to `127.0.0.1` only — the SSH tunnel is the only way
in. **No LAN exposure.**

### Cloud editors

| Env | Detection | Behavior |
|---|---|---|
| GitHub Codespaces | `$CODESPACES`, `$CODESPACE_NAME` | Tells you to use the VS Code "Ports" panel to forward 7531 |
| Gitpod | `$GITPOD_WORKSPACE_ID` | Reminds you Gitpod auto-forwards; click the toast |
| Dev container | `$REMOTE_CONTAINERS`, `$CODER_WORKSPACE_NAME` | Points at the editor's port-forwarding UI |

These platforms have their own port-forwarding mechanisms; the
dashboard just surfaces a hint pointing at them.

### Unknown

If none of the above match (e.g. an unusual remote shell),
prints just the URL with a note that you'll need to arrange
access yourself.

---

## Architecture

```
.claude/dashboard/
├── dashboard.py    # ~330 LOC — server + state gatherer (stdlib only)
├── index.html      # ~700 LOC — page (vanilla JS, inline CSS, no build)
├── README.md       # this file
├── .gitignore      # ignores runtime artifacts
├── state.json      # (runtime) regenerated on every request
└── .dashboard.pid  # (runtime) PID for stop command
```

**Single-file server.** `dashboard.py` is the entire backend. Two
endpoints:

- `GET /` → serves `index.html`
- `GET /state.json` → recomputes state from project files + git +
  optional `gh`, returns JSON

**Single-file page.** `index.html` is everything: HTML structure,
CSS design tokens, vanilla JS for fetch/render. No bundler, no
node_modules, no transpilation.

**State sources** are the same files Claude already maintains:

| Panel | Source |
|---|---|
| Production | `git describe --tags`, `git log` |
| Git state | `git status`, `git rev-list`, `git worktree list` |
| Activity | `tasks/AUDIT.md` (or `CHANGELOG.md` fallback) |
| Open PRs | `gh pr list` (optional) |
| In flight | `tasks/active/*.md` |
| Inbox | `.claude/inbox/*` |
| Backlog | `tasks/ROADMAP.md` (parsed for phases) |
| Commits | `git log -10 origin/main` |
| Mode | `.claude/mode` |

If a source is missing, the panel renders an empty state — never
fabricates.

---

## Design language

The dashboard mirrors the kit's catalogue (`output-styles.md`)
in HTML/CSS form:

- §2 Live status dashboard → the production hero + git state cards
- §17 Branch overview → worktree list
- §23 Activity timeline → activity card
- §3 Roadmap timeline → backlog card
- §28 Stats card grid → header chip rendering
- §25 Alert variants → warnings card
- §16 Git log → commits card

Same glyph vocabulary (`● ◐ ○ ✓ ✗ ▲`), same semantic colors
(green = healthy, yellow = active, red = failed, purple = accent).

---

## Lifecycle

The dashboard is a **Claude-session companion**, not a 24/7
service. Behavior:

- Starts when you run `/dashboard start` (or `dashboard.py start`).
- Lives as long as the controlling terminal lives.
- Closing the terminal kills the server. Reopen and start again.
- Bind is `127.0.0.1` only — never exposed to LAN.

If you want a 24/7 dashboard, wrap it in a `launchd` plist (macOS)
or `systemd` unit (Linux). Out of scope for this README.

---

## Limitations

- **Single dashboard variant ("kit")** — the only view. More
  variants ("project", "team", etc.) could ship later but aren't
  here.
- **Read-only.** Claude updates the page (via state recomputation
  on each poll); the page does not push commands back.
- **Polls every 3s** — not real-time. WebSockets / SSE would be a
  bigger addition; polling stays stdlib.
- **Single user.** No auth. Bound to localhost only.

---

## Updating

The dashboard files are not synced by `/sync` (intentional). To
update after pulling a newer claude-kit:

```sh
cp -r /path/to/claude-kit/kit/dashboard/* .claude/dashboard/
# preserve your runtime state by not deleting state.json / .dashboard.pid
# (but they're regenerated anyway — safe to clobber)
```

---

## Removing

```sh
python3 .claude/dashboard/dashboard.py stop
rm -rf .claude/dashboard
```

The `/dashboard` skill stays installed (it's a kit-managed file)
but its first invocation will tell you the dashboard isn't
installed and how to opt back in.
