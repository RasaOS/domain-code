#!/usr/bin/env python3
"""
claude-kit dashboard — single-file server + state gatherer.

Usage
-----
    python3 dashboard.py start [--port 7531]
    python3 dashboard.py stop
    python3 dashboard.py status
    python3 dashboard.py refresh    # write state.json once, no server

Zero deps beyond Python 3 stdlib (3.9+). Designed to live at
.claude/dashboard/dashboard.py in a project, invoked from the
project root. Run via the /dashboard skill, or directly.
"""
from __future__ import annotations

import argparse
import datetime as dt
import http.server
import json
import os
import re
import signal
import socketserver
import subprocess
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


DEFAULT_PORT = 7531
SCRIPT_DIR = Path(__file__).resolve().parent
PID_FILE = SCRIPT_DIR / ".dashboard.pid"
STATE_FILE = SCRIPT_DIR / "state.json"


# ---------- project root detection -----------------------------------------

def find_project_root(start: Path | None = None) -> Path:
    """Walk up from CWD looking for the closest git work-tree boundary
    (`.git` file or dir), `CLAUDE.md`, or `.claude/`. The first match
    wins — `.git` first because it's the strongest signal and stops
    correctly at git worktree boundaries (where `.git` is a pointer
    file, not a directory). Falls back to CWD."""
    p = (start or Path.cwd()).resolve()
    for cur in [p, *p.parents]:
        if (cur / ".git").exists():
            return cur
        if (cur / "CLAUDE.md").exists():
            return cur
        if (cur / ".claude").is_dir():
            return cur
    return p


# ---------- shell helpers ---------------------------------------------------

def sh(cmd: list[str], cwd: Path, default: str = "") -> str:
    """Run a command, return stdout stripped, default on failure."""
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else default
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        return default


def sh_lines(cmd: list[str], cwd: Path) -> list[str]:
    out = sh(cmd, cwd)
    return [ln for ln in out.splitlines() if ln.strip()]


def has_cmd(cmd: str) -> bool:
    try:
        return subprocess.run(["which", cmd], capture_output=True).returncode == 0
    except OSError:
        return False


# ---------- environment detection ------------------------------------------

def detect_environment() -> dict[str, Any]:
    """Decide where we're running. Drives the start-time UX:

    - ``local`` — auto-open browser, just print URL
    - ``ssh`` — print the SSH tunnel command to run on the user's
      LOCAL machine (we know server IP + SSH port via $SSH_CONNECTION)
    - ``codespaces`` / ``gitpod`` / ``devcontainer`` — these have
      built-in port forwarding; tell the user to use it
    - ``unknown`` — fall back to "URL is X, you figure it out"
    """
    ssh_conn = os.environ.get("SSH_CONNECTION", "").split()
    if len(ssh_conn) >= 4:
        try:
            ssh_port = int(ssh_conn[3])
        except ValueError:
            ssh_port = 22
        return {
            "kind": "ssh",
            "ssh": {
                "host": ssh_conn[2],
                "port": ssh_port,
                "user": os.environ.get("USER") or os.environ.get("LOGNAME") or "user",
                "hostname": sh(["hostname"], Path.cwd()) or ssh_conn[2],
            },
            "open_browser": False,
        }
    if os.environ.get("CODESPACES") == "true" or os.environ.get("CODESPACE_NAME"):
        return {"kind": "codespaces", "open_browser": False}
    if os.environ.get("GITPOD_WORKSPACE_ID"):
        return {"kind": "gitpod", "open_browser": False}
    if os.environ.get("REMOTE_CONTAINERS") or os.environ.get("CODER_WORKSPACE_NAME"):
        return {"kind": "devcontainer", "open_browser": False}

    # Local-ish: only auto-open if a display is present.
    if sys.platform == "darwin":
        return {"kind": "local", "open_browser": True}
    if sys.platform.startswith("linux") and os.environ.get("DISPLAY"):
        return {"kind": "local", "open_browser": True}
    if sys.platform == "win32":
        return {"kind": "local", "open_browser": True}
    return {"kind": "local", "open_browser": False}


def open_browser(url: str) -> bool:
    """Best-effort browser launch. Returns True if launched."""
    if sys.platform == "darwin":
        opener = ["open", url]
    elif sys.platform == "win32":
        opener = ["cmd", "/c", "start", url]
    else:
        opener = ["xdg-open", url]
    try:
        subprocess.Popen(
            opener,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True
    except (OSError, FileNotFoundError):
        return False


def render_env_guidance(env: dict[str, Any], port: int) -> None:
    """Print environment-specific guidance after the server header."""
    kind = env["kind"]
    if kind == "ssh":
        s = env["ssh"]
        port_flag = "" if s["port"] == 22 else f" -p {s['port']}"
        print("  REMOTE (SSH) — run this on your LOCAL machine to view:")
        print()
        print(f"    ssh{port_flag} -L {port}:localhost:{port} {s['user']}@{s['host']}")
        print()
        print(f"  then open  http://localhost:{port}  in your local browser.")
        print()
        return
    if kind == "codespaces":
        print("  CODESPACES detected — open the 'Ports' panel in VS Code")
        print(f"  to forward port {port} and click the resulting URL.")
        print()
        return
    if kind == "gitpod":
        print(f"  GITPOD detected — Gitpod auto-forwards port {port}.")
        print("  Click the toast / 'Ports' panel in your editor.")
        print()
        return
    if kind == "devcontainer":
        print(f"  DEV CONTAINER detected — your editor should forward port {port}")
        print("  automatically; check the 'Ports' panel.")
        print()
        return
    # local
    if env.get("open_browser"):
        if open_browser(f"http://localhost:{port}"):
            print(f"  opening http://localhost:{port} in your default browser…")
            print()
            return
    print(f"  open  http://localhost:{port}  in your browser.")
    print()


# ---------- time helpers ----------------------------------------------------

def parse_iso(s: str) -> dt.datetime | None:
    try:
        return dt.datetime.fromisoformat(s)
    except (ValueError, TypeError):
        return None


def humanize_ago(when: dt.datetime | None, now: dt.datetime | None = None) -> str:
    if not when:
        return "—"
    if when.tzinfo and now is None:
        now = dt.datetime.now(when.tzinfo)
    elif now is None:
        now = dt.datetime.now()
    delta = now - when
    seconds = int(delta.total_seconds())
    if seconds < 60:
        return f"{max(seconds, 0)}s ago"
    if seconds < 3600:
        return f"{seconds // 60}m ago"
    if seconds < 86400:
        return f"{seconds // 3600}h ago"
    days = seconds // 86400
    if days < 30:
        return f"{days}d ago"
    months = days // 30
    if months < 12:
        return f"{months}mo ago"
    return f"{days // 365}y ago"


# ---------- state gatherers -------------------------------------------------

def gather_project(root: Path) -> dict[str, Any]:
    """Project name = main-repo dirname, even when invoked from a worktree.
    `git rev-parse --git-common-dir` returns the main repo's `.git` path,
    so its parent is the canonical project root."""
    name = root.name
    common = sh(["git", "rev-parse", "--git-common-dir"], root)
    if common:
        common_path = Path(common)
        if not common_path.is_absolute():
            common_path = root / common_path
        try:
            name = common_path.resolve().parent.name
        except OSError:
            pass
    return {"name": name, "root": str(root)}


def gather_production(root: Path) -> dict[str, Any]:
    tag = sh(["git", "describe", "--tags", "--abbrev=0"], root)
    if not tag:
        return {"tag": None, "sha": None, "shipped_at": None, "shipped_ago": None,
                "deploys_30d": []}
    sha = sh(["git", "rev-list", "-n", "1", "--abbrev-commit", tag], root)
    iso = sh(["git", "log", "-1", "--format=%aI", tag], root)
    when = parse_iso(iso) if iso else None
    # Deploy frequency over last 90 days — pull every tag with date
    raw = sh(["git", "for-each-ref", "--sort=-creatordate", "--format=%(refname:short)|%(creatordate:iso8601)",
              "refs/tags"], root)
    deploys = []
    for line in raw.splitlines():
        parts = line.split("|", 1)
        if len(parts) != 2:
            continue
        deploys.append({"tag": parts[0], "iso": parts[1]})
    return {
        "tag": tag,
        "sha": sha,
        "shipped_at": iso,
        "shipped_ago": humanize_ago(when),
        "deploys_30d": deploys[:20],
    }


def gather_branch(root: Path) -> dict[str, Any]:
    name = sh(["git", "rev-parse", "--abbrev-ref", "HEAD"], root)
    porcelain = sh_lines(["git", "status", "--porcelain"], root)
    ahead = sh(["git", "rev-list", "--count", "@{u}..HEAD"], root, default="0")
    behind = sh(["git", "rev-list", "--count", "HEAD..@{u}"], root, default="0")
    return {
        "name": name or "—",
        "dirty": len(porcelain) > 0,
        "changes_count": len(porcelain),
        "ahead": int(ahead) if ahead.isdigit() else 0,
        "behind": int(behind) if behind.isdigit() else 0,
    }


def gather_worktrees(root: Path) -> list[dict[str, Any]]:
    raw = sh(["git", "worktree", "list", "--porcelain"], root)
    if not raw:
        return []
    out: list[dict[str, Any]] = []
    cur: dict[str, Any] = {}
    for line in raw.splitlines():
        if line.startswith("worktree "):
            if cur:
                out.append(cur)
            cur = {"path": line.split(" ", 1)[1]}
        elif line.startswith("branch "):
            cur["branch"] = line.split(" ", 1)[1].replace("refs/heads/", "")
        elif line.startswith("HEAD "):
            cur["sha"] = line.split(" ", 1)[1][:7]
        elif line.strip() == "detached":
            cur["branch"] = "(detached)"
    if cur:
        out.append(cur)
    cwd_str = str(root)
    for wt in out:
        path = wt.get("path", "")
        wt["is_current"] = cwd_str.startswith(path) or path.startswith(cwd_str)
    return out


def gather_commits(root: Path, n: int = 10) -> list[dict[str, Any]]:
    fmt = "%H%x09%h%x09%an%x09%aI%x09%s"
    out = sh(["git", "log", f"-{n}", f"--format={fmt}", "origin/main"], root) or \
          sh(["git", "log", f"-{n}", f"--format={fmt}"], root)
    commits = []
    for line in out.splitlines():
        parts = line.split("\t", 4)
        if len(parts) != 5:
            continue
        full, short, author, iso, subject = parts
        when = parse_iso(iso)
        commits.append({
            "sha": short,
            "full_sha": full,
            "author": author,
            "iso": iso,
            "ago": humanize_ago(when),
            "subject": subject,
        })
    return commits


def gather_open_prs(root: Path) -> list[dict[str, Any]] | None:
    if not has_cmd("gh"):
        return None
    raw = sh(["gh", "pr", "list", "--state", "open",
              "--json", "number,title,author,headRefName,createdAt,isDraft"], root)
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    out = []
    for pr in data:
        when = parse_iso(pr.get("createdAt", ""))
        author = pr.get("author") or {}
        out.append({
            "number": pr["number"],
            "title": pr["title"],
            "author": author.get("login", "—"),
            "branch": pr.get("headRefName", "—"),
            "age": humanize_ago(when),
            "draft": pr.get("isDraft", False),
        })
    return out


def gather_active_tasks(root: Path) -> list[dict[str, str]]:
    active_dir = root / "tasks" / "active"
    if not active_dir.is_dir():
        return []
    out = []
    for path in sorted(active_dir.iterdir()):
        if path.suffix not in (".md", ".markdown") or path.name.startswith("."):
            continue
        title = path.stem
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
            m = re.search(r"^#\s+(.+)$", text, re.M)
            if m:
                title = m.group(1).strip()
        except OSError:
            pass
        out.append({"file": path.name, "title": title})
    return out


def gather_phases(root: Path) -> list[dict[str, Any]]:
    rm = root / "tasks" / "ROADMAP.md"
    if not rm.exists():
        return []
    text = rm.read_text(encoding="utf-8", errors="replace")
    phases: list[dict[str, Any]] = []
    cur: dict[str, Any] | None = None
    for line in text.splitlines():
        m = re.match(r"^##\s+(Phase\s+[\dA-Z].*)$", line.strip())
        if m:
            if cur:
                phases.append(cur)
            cur = {"name": m.group(1), "items": []}
            continue
        if cur is not None:
            mb = re.match(r"^[-*]\s+(TASK[-A-Z]*-\d+.*)$", line.strip())
            if mb:
                cur["items"].append(mb.group(1))
    if cur:
        phases.append(cur)
    return phases


def gather_audit(root: Path, n: int = 10) -> list[dict[str, str]]:
    audit_md = root / "tasks" / "AUDIT.md"
    fallback = False
    if not audit_md.exists():
        audit_md = root / "CHANGELOG.md"
        fallback = True
    if not audit_md.exists():
        return []
    text = audit_md.read_text(encoding="utf-8", errors="replace")
    out: list[dict[str, str]] = []
    cur_date: str | None = None
    for line in text.splitlines():
        s = line.strip()
        m_date = re.match(r"^##\s+(.+?)(?:\s+—.*)?$", s)
        if m_date and (re.match(r"^(\d{4}-\d{2}-\d{2}|v\d+\.\d+\.\d+|Unreleased)", m_date.group(1))):
            cur_date = m_date.group(1)
            continue
        m_b = re.match(r"^[-*]\s+(.+)$", s)
        if m_b and cur_date and len(out) < n:
            text_b = m_b.group(1)
            icon = "◆"
            if "🚀" in text_b or "Released" in text_b:
                icon = "▲"
            elif "🔥" in text_b or "Hotfix" in text_b:
                icon = "⚠"
            text_b = re.sub(r"[🚀🔥📦📜🏗⚠️📊🌿🛠🗺]\s*", "", text_b)
            text_b = text_b.replace("**", "")
            out.append({"date": cur_date, "icon": icon, "text": text_b[:140]})
    return out


def gather_inbox(root: Path) -> list[dict[str, str]]:
    inbox_dir = root / ".claude" / "inbox"
    if not inbox_dir.is_dir():
        return []
    out = []
    items = sorted(
        [p for p in inbox_dir.iterdir() if p.is_file() and not p.name.startswith(".")],
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    for path in items[:10]:
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
            preview = next((ln.strip() for ln in text.splitlines() if ln.strip()), "(empty)")[:80]
            mtime = dt.datetime.fromtimestamp(path.stat().st_mtime)
            out.append({"file": path.name, "preview": preview, "ago": humanize_ago(mtime, dt.datetime.now())})
        except OSError:
            continue
    return out


def gather_mode(root: Path) -> str:
    mode_file = root / ".claude" / "mode"
    if mode_file.exists():
        try:
            return mode_file.read_text(encoding="utf-8").strip() or "—"
        except OSError:
            pass
    return "—"


def gather_warnings(state: dict[str, Any]) -> list[dict[str, str]]:
    warns: list[dict[str, str]] = []
    for pr in (state.get("open_prs") or []):
        ago = pr.get("age", "")
        m = re.match(r"^(\d+)d ago$", ago)
        if m and int(m.group(1)) > 7:
            warns.append({
                "severity": "warn",
                "title": f"PR #{pr['number']} open {ago}",
                "body": f"{pr['title']} — needs reviewer attention",
            })
    branch = state.get("branch", {})
    if branch.get("name") in ("main", "master") and branch.get("dirty"):
        warns.append({
            "severity": "warn",
            "title": f"Dirty working tree on {branch.get('name')}",
            "body": f"{branch.get('changes_count', 0)} uncommitted changes",
        })
    return warns


def build_state(root: Path) -> dict[str, Any]:
    state: dict[str, Any] = {
        "updated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "project": gather_project(root),
        "production": gather_production(root),
        "branch": gather_branch(root),
        "worktrees": gather_worktrees(root),
        "commits": gather_commits(root),
        "open_prs": gather_open_prs(root),
        "active_tasks": gather_active_tasks(root),
        "phases": gather_phases(root),
        "audit": gather_audit(root),
        "inbox": gather_inbox(root),
        "mode": gather_mode(root),
    }
    state["warnings"] = gather_warnings(state)
    return state


# ---------- HTTP handler ----------------------------------------------------

class Handler(http.server.SimpleHTTPRequestHandler):
    project_root: Path = Path.cwd()

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(SCRIPT_DIR), **kw)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/state.json":
            try:
                state = build_state(self.project_root)
                payload = json.dumps(state).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            except Exception as e:
                self.send_error(500, f"state error: {e}")
            return
        if url.path in ("/", "/index.html"):
            self.path = "/index.html"
        return super().do_GET()

    def log_message(self, fmt, *args):
        sys.stderr.write(f"[dashboard] {self.address_string()} {fmt % args}\n")


# ---------- commands --------------------------------------------------------

def cmd_start(port: int, no_open: bool = False) -> int:
    if PID_FILE.exists():
        try:
            pid = int(PID_FILE.read_text().strip())
            os.kill(pid, 0)
            print(f"[dashboard] already running at PID {pid}", file=sys.stderr)
            return 1
        except (OSError, ValueError):
            PID_FILE.unlink(missing_ok=True)

    project_root = find_project_root()
    Handler.project_root = project_root
    project_name = gather_project(project_root)["name"]

    print("claude-kit dashboard")
    print(f"  project : {project_name}")
    print(f"  root    : {project_root}")
    print(f"  port    : {port}")
    print(f"  url     : http://localhost:{port}")
    print()

    env = detect_environment()
    if no_open:
        env["open_browser"] = False
    render_env_guidance(env, port)

    print("  Ctrl-C to stop.")
    print()
    sys.stdout.flush()  # flush before serve_forever blocks — matters when stdout is piped to a log

    PID_FILE.write_text(str(os.getpid()))
    try:
        socketserver.TCPServer.allow_reuse_address = True
        with socketserver.TCPServer(("127.0.0.1", port), Handler) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[dashboard] stopping.")
    except OSError as e:
        print(f"[dashboard] failed to bind port {port}: {e}", file=sys.stderr)
        PID_FILE.unlink(missing_ok=True)
        return 1
    finally:
        PID_FILE.unlink(missing_ok=True)
    return 0


def cmd_stop() -> int:
    if not PID_FILE.exists():
        print("[dashboard] not running")
        return 0
    try:
        pid = int(PID_FILE.read_text().strip())
        os.kill(pid, signal.SIGTERM)
        PID_FILE.unlink(missing_ok=True)
        print(f"[dashboard] stopped PID {pid}")
    except (OSError, ValueError) as e:
        PID_FILE.unlink(missing_ok=True)
        print(f"[dashboard] failed to stop: {e}", file=sys.stderr)
        return 1
    return 0


def cmd_status() -> int:
    if PID_FILE.exists():
        try:
            pid = int(PID_FILE.read_text().strip())
            os.kill(pid, 0)
            print(f"[dashboard] running at PID {pid}")
            return 0
        except (OSError, ValueError):
            PID_FILE.unlink(missing_ok=True)
            print("[dashboard] stale pid file removed; not running")
            return 1
    print("[dashboard] not running")
    return 1


def cmd_refresh() -> int:
    project_root = find_project_root()
    state = build_state(project_root)
    STATE_FILE.write_text(json.dumps(state, indent=2))
    print(f"[dashboard] wrote {STATE_FILE} ({len(json.dumps(state))} bytes)")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="dashboard.py", description="claude-kit dashboard")
    sub = p.add_subparsers(dest="cmd", required=True)
    s_start = sub.add_parser("start", help="start the server")
    s_start.add_argument("--port", type=int, default=DEFAULT_PORT)
    s_start.add_argument("--no-open", action="store_true",
                         help="don't auto-open browser even when local")
    sub.add_parser("stop", help="stop a running server")
    sub.add_parser("status", help="show running status")
    sub.add_parser("refresh", help="rewrite state.json once, no server")
    args = p.parse_args()

    if args.cmd == "start":
        return cmd_start(args.port, no_open=args.no_open)
    if args.cmd == "stop":
        return cmd_stop()
    if args.cmd == "status":
        return cmd_status()
    if args.cmd == "refresh":
        return cmd_refresh()
    return 1


if __name__ == "__main__":
    sys.exit(main())
