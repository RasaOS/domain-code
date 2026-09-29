#!/usr/bin/env python3
"""land.py — the program behind land.sh: get a skill's outputs onto the trunk
the way their class allows, always from the latest trunk.

Two classes, decided here and nowhere else:

  docs  the dated outputs of doc skills and the task ledger. They land by
        themselves: a short-lived land/ branch cut from the freshly fetched
        trunk, a PR, CI, a merge pinned to the verified head.
  code  everything else. It lands only through a PR that the skill never
        merges. land.sh pr opens it; /peer-review, /auto-merge or a person
        merges it.

The class is data in this file. Project config can only narrow it (docs that
open a PR but do not merge); nothing widens it and there is no bypass. Every
check runs on the pushed commit with git itself, so it holds in sessions that
have no gh and drive GitHub through other tooling.

land.sh is the entry point and owns the argument contract; see its header.
Portable: python3 (3.6+), git >= 2.20, gh optional.
"""
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

OK, ERR, USAGE, REFUSED, NOGH, CONFLICT, CHECKS, ENVREFUSED = 0, 1, 2, 3, 4, 5, 6, 7

HERE = os.path.dirname(os.path.abspath(__file__))


class Stop(Exception):
    def __init__(self, code, msg):
        Exception.__init__(self, msg)
        self.code = code
        self.msg = msg


def say(*lines):
    for line in lines:
        print(line)
    sys.stdout.flush()


def warn(msg):
    print("land: " + msg, file=sys.stderr)


# ── the docs class ────────────────────────────────────────────────────────
#
# Only these land by themselves. Every entry is a place a doc skill writes a
# dated or append-only record that no program executes and no agent loads as
# instructions. Anything else, including anything unrecognised, is code.

DOCS_DIRS = (
    "docs/audits/", "docs/decisions/", "docs/postmortems/", "docs/retros/",
    "docs/notes/", "docs/handoff/", "docs/blast-radius/", "docs/scope/",
    "docs/exports/", "docs/regrets/", "docs/mvp/", "docs/wrangle/",
    "docs/refinement/",
)
DOCS_FILES = ("docs/glossary.md", "tasks/history.tsv")
# Loaded into every session as instructions, wherever they sit.
INSTRUCTION_NAMES = ("claude.md", "claude.local.md", "agents.md")
# Named explicitly as code even though a docs rule would match them:
# tasks.config.yml declares the ledger's actors and targets (a decision, not
# a record); docs/notes/INDEX.md is @-imported by the seeded CLAUDE.md.
ALWAYS_CODE = ("tasks/tasks.config.yml", "docs/notes/INDEX.md")
# Prototype scope never reaches the trunk except through /prototype graduate.
CODE_PREFIXES = ("tasks/proto/", "docs/proto/")
# Folders an agent or a CI runner loads from at ANY depth (Claude Code finds
# nested .claude/skills when it works in a subdirectory).
CODE_DIRS_ANY_DEPTH = (".claude", ".github")


def classify(path, imports=(), mode=None):
    """Return (class, reason) for an install-relative path."""
    p = path
    if not p or p.startswith("/") or "\\" in p:
        return "code", "not a relative path inside the install"
    parts = p.split("/")
    if any(part in ("", ".", "..") for part in parts):
        return "code", "path has an empty, '.' or '..' component"
    if mode in ("120000", "160000"):
        return "code", "a symlink or submodule is never a doc"
    if mode is not None and mode not in ("100644", "000000"):
        return "code", "file mode %s (executable): a doc is never run" % mode
    if parts[-1].lower() in INSTRUCTION_NAMES:
        return "code", "agent instructions (%s)" % parts[-1]
    if p in imports:
        return "code", "imported by CLAUDE.md, so every session loads it"
    if p in ALWAYS_CODE:
        return "code", "named as code (a decision or an imported file)"
    for part in parts[:-1]:
        if part.lower() in CODE_DIRS_ANY_DEPTH:
            return "code", "under %s/ (agent or CI configuration)" % part
    for pre in CODE_PREFIXES:
        if p.startswith(pre):
            return "code", "under %s" % pre
    if p in DOCS_FILES:
        return "docs", "ledger / doc record"
    if p.startswith("tasks/") and p.endswith(".md"):
        return "docs", "task ledger"
    if p.endswith(".md"):
        for d in DOCS_DIRS:
            if p.startswith(d):
                return "docs", "doc output (%s)" % d.rstrip("/")
    return "code", "not a doc-output path"


IMPORT_RE = re.compile(r"(?<![\w`@])@([A-Za-z0-9_.~/-]*[A-Za-z0-9_~/-])")


IMPORT_ROOT_NAMES = ("claude.md", "claude.local.md")


def claude_imports(read, roots):
    """Every repository-relative path @-imported by the instruction files in
    `roots` (every CLAUDE.md / CLAUDE.local.md in the repository, at any
    depth: Claude Code loads nested ones when it works in their folder and
    parent ones above a monorepo install), transitively (depth 4). An import
    can sit anywhere in the prose ("See @docs/x.md"); fenced code and `code`
    spans are skipped. `read(path)` returns the text or None. Relative
    imports resolve against the importing file's folder."""
    seen, found = set(), set()
    queue = [(r, 0) for r in roots]
    while queue:
        f, depth = queue.pop()
        if f in seen:
            continue
        seen.add(f)
        text = read(f)
        if text is None:
            continue
        text = re.sub(r"(?ms)^\s*(```|~~~).*?^\s*\1", "", text)
        text = re.sub(r"`[^`\n]*`", "", text)
        base = os.path.dirname(f)
        for m in IMPORT_RE.finditer(text):
            target = m.group(1)
            if target.startswith("~") or target.startswith("/"):
                continue
            norm = os.path.normpath(os.path.join(base, target)).replace("\\", "/")
            if norm.startswith("../") or norm == "." or norm == "..":
                continue
            found.add(norm)
            if depth < 4 and norm.endswith(".md"):
                queue.append((norm, depth + 1))
    return found


def instruction_roots(names):
    """The files among `names` (repository-relative) that Claude Code loads
    as instructions and follows imports from."""
    return sorted(n for n in names if n.rsplit("/", 1)[-1].lower() in IMPORT_ROOT_NAMES)


# High-confidence credential shapes only: a doc that talks about secrets is
# fine, a doc that contains one is not.
SECRET_RES = [
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{50,}\b"),
    re.compile(r"\bxox[abpors]-[A-Za-z0-9-]{10,}\b"),
    re.compile(r"\bsk_live_[A-Za-z0-9]{20,}\b"),
    re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
]


def secret_hit(text):
    for rx in SECRET_RES:
        m = rx.search(text)
        if m:
            return m.group(0)[:12] + "…"
    return None


# ── git plumbing ──────────────────────────────────────────────────────────

def run(args, cwd=None, env=None, check=True, input_text=None, timeout=None):
    # UTF-8 whatever the locale (Python 3.6 in a C locale would decode as
    # ASCII), and bytes that are not UTF-8 survive the round trip.
    p = subprocess.run(args, cwd=cwd, env=env, input=input_text,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       encoding="utf-8", errors="surrogateescape", timeout=timeout)
    if check and p.returncode != 0:
        raise Stop(ERR, "%s failed: %s" % (" ".join(args[:4]), (p.stderr or p.stdout).strip()[:600]))
    return p


def have(cmd):
    return shutil.which(cmd) is not None


class Repo(object):
    """The install and the git repository around it."""

    def __init__(self, root):
        self.root = os.path.realpath(root)
        top = run(["git", "-C", self.root, "rev-parse", "--show-toplevel"], check=False)
        if top.returncode != 0:
            raise Stop(REFUSED, "not inside a git repository (%s)" % self.root)
        self.top = os.path.realpath(top.stdout.strip())
        rel = os.path.relpath(self.root, self.top)
        self.prefix = "" if rel == "." else rel.replace("\\", "/") + "/"
        gd = run(["git", "-C", self.top, "rev-parse", "--git-dir"]).stdout.strip()
        self.git_dir = os.path.realpath(os.path.join(self.top, gd))
        cd = run(["git", "-C", self.top, "rev-parse", "--git-common-dir"]).stdout.strip()
        self.common = os.path.realpath(os.path.join(self.top, cd))
        self.state = os.path.join(self.common, "land")
        self._trunk = None
        self._imports = None
        self._ident = None

    # git in the user's repository
    def git(self, *args, **kw):
        return run(["git", "-C", self.top] + list(args), **kw)

    def top_path(self, p):
        return self.prefix + p

    def rel(self, top_rel):
        """install-relative form of a top-relative path, or None if outside."""
        if self.prefix and not top_rel.startswith(self.prefix):
            return None
        return top_rel[len(self.prefix):]

    def has_origin(self):
        return self.git("remote", "get-url", "origin", check=False).returncode == 0

    @property
    def trunk(self):
        if self._trunk:
            return self._trunk
        cache = os.path.join(self.state, "trunk")
        t = ""
        r = self.git("symbolic-ref", "--short", "-q", "refs/remotes/origin/HEAD", check=False)
        if r.returncode == 0 and r.stdout.strip().startswith("origin/"):
            t = r.stdout.strip()[len("origin/"):]
        if not t and os.path.exists(cache):
            t = open(cache, encoding="utf-8", errors="replace").read().strip()
        if not t and self.has_origin():
            r = self.git("ls-remote", "--symref", "origin", "HEAD", check=False)
            m = re.search(r"ref:\s+refs/heads/(\S+)\s+HEAD", r.stdout or "")
            if m:
                t = m.group(1)
        if not t:
            for cand in ("main", "master"):
                if self.git("show-ref", "--verify", "-q", "refs/heads/" + cand, check=False).returncode == 0 or \
                   self.git("show-ref", "--verify", "-q", "refs/remotes/origin/" + cand, check=False).returncode == 0:
                    t = cand
                    break
        t = t or "main"
        try:
            os.makedirs(self.state, exist_ok=True)
            with open(cache, "w", encoding="utf-8") as fh:
                fh.write(t + "\n")
        except OSError:
            pass
        self._trunk = t
        return t

    def fetch_trunk(self):
        """Fetch the trunk with an explicit refspec and return its SHA."""
        if not self.has_origin():
            raise Stop(REFUSED, "no remote 'origin': nothing to land onto. Push the repository first.")
        spec = "+refs/heads/%s:refs/remotes/origin/%s" % (self.trunk, self.trunk)
        last = None
        for attempt in range(3):
            r = self.git("fetch", "-q", "origin", spec, check=False)
            if r.returncode == 0:
                break
            last = (r.stderr or "").strip()
            if "couldn't find remote ref" in last or "could not find remote ref" in last:
                raise Stop(REFUSED, "the remote has no '%s' yet: make and push the first commit, then land" % self.trunk)
            time.sleep(1 + attempt)
        else:
            raise Stop(ERR, "could not fetch %s: %s" % (self.trunk, last))
        return self.git("rev-parse", "refs/remotes/origin/" + self.trunk).stdout.strip()

    def head(self):
        r = self.git("rev-parse", "-q", "--verify", "HEAD", check=False)
        return r.stdout.strip() if r.returncode == 0 else None

    def branch(self):
        r = self.git("symbolic-ref", "--short", "-q", "HEAD", check=False)
        return r.stdout.strip() if r.returncode == 0 else ""

    def op_in_progress(self):
        for name in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "BISECT_LOG",
                     "rebase-merge", "rebase-apply"):
            if os.path.exists(os.path.join(self.git_dir, name)):
                return name
        return None

    def blob_at(self, rev, top_rel):
        r = self.git("rev-parse", "-q", "--verify", "%s:%s" % (rev, top_rel), check=False)
        return r.stdout.strip() if r.returncode == 0 else None

    def wt_blob(self, top_rel):
        full = os.path.join(self.top, top_rel)
        if not os.path.lexists(full):
            return None
        return self.git("hash-object", "--", top_rel).stdout.strip()

    def is_ancestor(self, a, b):
        return self.git("merge-base", "--is-ancestor", a, b, check=False).returncode == 0

    def imports(self):
        """Install-relative paths @-imported by any CLAUDE.md in the
        repository, read from the working tree and from the fetched trunk (a
        stale checkout must not miss an import the trunk already has)."""
        if self._imports is not None:
            return self._imports
        found = set()

        def from_wt(p):
            try:
                return open(os.path.join(self.top, p), encoding="utf-8", errors="replace").read()
            except OSError:
                return None

        ref = "refs/remotes/origin/%s" % self.trunk

        def from_trunk(p):
            r = self.git("show", "%s:%s" % (ref, p), check=False)
            return r.stdout if r.returncode == 0 else None

        wt_names = self.git("ls-files", "-co", "--exclude-standard", "-z", check=False).stdout.split("\0")
        tr = self.git("ls-tree", "-r", "--name-only", "-z", ref, check=False)
        tr_names = tr.stdout.split("\0") if tr.returncode == 0 else []
        found |= claude_imports(from_wt, instruction_roots(n for n in wt_names if n))
        found |= claude_imports(from_trunk, instruction_roots(n for n in tr_names if n))
        self._imports = set(x for x in (self.rel(p) for p in found) if x)
        return self._imports

    def identity_env(self, scratch=False):
        """An environment whose author/committer is the user's, or a named
        stand-in when the repository has none configured. In a scratch
        worktree LFS smudging is skipped; never in the user's checkout."""
        env = dict(os.environ)
        name = self.git("config", "user.name", check=False).stdout.strip()
        email = self.git("config", "user.email", check=False).stdout.strip()
        if not name:
            env.setdefault("GIT_AUTHOR_NAME", "rasa land")
            env.setdefault("GIT_COMMITTER_NAME", "rasa land")
        if not email:
            env.setdefault("GIT_AUTHOR_EMAIL", "land@localhost")
            env.setdefault("GIT_COMMITTER_EMAIL", "land@localhost")
        if scratch:
            env["GIT_LFS_SKIP_SMUDGE"] = "1"
        return env


# ── state: lock, log ──────────────────────────────────────────────────────

class Lock(object):
    """One landing step at a time per repository (all worktrees): planning,
    pushing, syncing and merging. Never held through a CI wait. A mkdir lock
    whose owner is gone is taken over; the owner is recorded with its
    process start time, so a pid the system has since reused does not count
    as alive."""

    WAIT = 180

    def __init__(self, repo):
        self.path = os.path.join(repo.state, "lock")
        os.makedirs(repo.state, exist_ok=True)

    @staticmethod
    def _started(pid):
        """When the process started, as the system tells it: /proc on Linux,
        ps elsewhere; '' when neither can say."""
        try:
            with open("/proc/%d/stat" % pid, encoding="utf-8", errors="replace") as fh:
                return "proc:" + fh.read().rsplit(")", 1)[1].split()[19]
        except (OSError, IndexError):
            pass
        try:
            r = run(["ps", "-o", "lstart=", "-p", str(pid)], check=False)
        except OSError:
            return ""
        return " ".join(r.stdout.split()) if r.returncode == 0 else ""

    def __enter__(self):
        me = os.getpid()
        self.token = "%d %d %s %s" % (me, int(time.time()), self._started(me) or "-", os.urandom(4).hex())
        waited, told = 0, False
        while True:
            try:
                os.mkdir(self.path)
            except FileExistsError:
                if self._stale() and self._take_over():
                    continue
            else:
                try:
                    with open(os.path.join(self.path, "owner"), "w", encoding="utf-8") as fh:
                        fh.write(self.token + "\n")
                    return self
                except OSError:
                    continue  # removed under us by a takeover that judged it stale: try again
            if waited >= self.WAIT:
                raise Stop(REFUSED, "another landing step (%s) has held %s for over %ds; it is still running, so run this again once it ends"
                           % (self._owner() or "?", self.path, self.WAIT))
            if not told:
                say("waiting=another landing step is running (%s)" % (self._owner() or "?"))
                told = True
            time.sleep(1)
            waited += 1

    def _take_over(self):
        """Remove a stale lock, one waiter at a time: only the holder of the
        takeover guard may remove it, and only after judging it stale again
        under the guard, so a fresh lock another waiter just made is never
        removed. A guard left by a crash is cleared after 30 s."""
        guard = self.path + ".takeover"
        try:
            os.mkdir(guard)
        except FileExistsError:
            try:
                if time.time() - os.path.getmtime(guard) > 30:
                    os.rmdir(guard)
            except OSError:
                pass
            time.sleep(0.2)
            return False
        try:
            if self._stale():
                shutil.rmtree(self.path, ignore_errors=True)
                return True
            return False
        finally:
            try:
                os.rmdir(guard)
            except OSError:
                pass

    def _owner(self):
        try:
            return open(os.path.join(self.path, "owner"), encoding="utf-8").read().strip()
        except OSError:
            return ""

    def _stale(self):
        parts = self._owner().split()
        try:
            pid, since = int(parts[0]), int(parts[1])
        except (IndexError, ValueError):
            # Being written right now, or garbage: stale only once it is old.
            try:
                return time.time() - os.path.getmtime(self.path) > 30
            except OSError:
                return True
        started = " ".join(parts[2:-1]) if len(parts) > 3 else (parts[2] if len(parts) > 2 else "-")
        if time.time() - since > 3600:
            return True
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return True
        except PermissionError:
            pass
        if started != "-":
            now = self._started(pid)
            if now and now != started:
                return True  # the pid now belongs to another process
        return False

    def __exit__(self, *exc):
        if self._owner() == getattr(self, "token", None):
            shutil.rmtree(self.path, ignore_errors=True)
        return False


def log_row(repo, event, **fields):
    os.makedirs(repo.state, exist_ok=True)
    row = dict(fields)
    row["event"] = event
    row["at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with open(os.path.join(repo.state, "log.jsonl"), "a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, sort_keys=True) + "\n")


def log_rows(repo):
    f = os.path.join(repo.state, "log.jsonl")
    rows = []
    if os.path.exists(f):
        for line in open(f, encoding="utf-8", errors="replace"):
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
    return rows


def inflight(repo):
    """Landings pushed but not settled, newest state per branch."""
    last = {}
    for r in log_rows(repo):
        if r.get("branch"):
            last[r["branch"]] = r
    return [r for r in last.values() if r.get("event") in ("pushed", "pr-open", "merge-ready")]


# ── config: may only narrow ───────────────────────────────────────────────

def _read_config(text, where):
    cfg = {}
    try:
        user = json.loads(text) if text is not None else {}
    except ValueError:
        warn("%s: not valid JSON; ignored" % where)
        return cfg
    if not isinstance(user, dict):
        return cfg
    if user.get("docs") in ("auto", "pr"):
        cfg["docs"] = user["docs"]
    if isinstance(user.get("skills"), dict):
        cfg["skills"] = {k: v for k, v in user["skills"].items() if v in ("auto", "pr")}
    if "check_wait_secs" in user:
        try:
            cfg["check_wait_secs"] = max(0, min(3600, int(user.get("check_wait_secs"))))
        except (TypeError, ValueError):
            pass
    for k in user:
        if k not in ("docs", "skills", "check_wait_secs") and not k.startswith("_"):
            warn("%s: unknown key '%s' ignored (the docs class is fixed in land.py)" % (where, k))
    return cfg


def load_config(repo):
    """.claude/landing.json from the checkout AND from the fetched trunk: a
    hold either one declares applies, so a stale checkout (or a local edit)
    cannot drop a hold the project has committed."""
    cfg = {"docs": "auto", "skills": {}, "check_wait_secs": 180}
    local, trunk = None, None
    try:
        local = open(os.path.join(repo.root, ".claude", "landing.json"), encoding="utf-8", errors="replace").read()
    except OSError:
        pass
    r = repo.git("show", "refs/remotes/origin/%s:%s" % (repo.trunk, repo.top_path(".claude/landing.json")), check=False)
    if r.returncode == 0:
        trunk = r.stdout
    for text, where in ((trunk, "origin/%s:.claude/landing.json" % repo.trunk), (local, ".claude/landing.json")):
        c = _read_config(text, where)
        if c.get("docs") == "pr":
            cfg["docs"] = "pr"
        for k, v in c.get("skills", {}).items():
            if v == "pr":
                cfg["skills"][k] = "pr"
        if "check_wait_secs" in c:
            cfg["check_wait_secs"] = c["check_wait_secs"]  # the checkout's value wins: it only sets a wait
    return cfg


def docs_mode(cfg, skill):
    """'auto' only if both the project and the skill allow it. A landing whose
    skill cannot be told is held whenever any per-skill hold exists."""
    if cfg["docs"] == "pr" or cfg["skills"].get(skill) == "pr":
        return "pr"
    if not skill and any(v == "pr" for v in cfg["skills"].values()):
        return "pr"
    return "auto"


LAND_BRANCH_RE = re.compile(r"^land/([a-z0-9][a-z0-9-]*?)-\d{8}-\d{6}-[0-9a-f]{4}$")
DOCS_TITLE_RE = re.compile(r"^docs\(([a-z0-9][a-z0-9-]*)\):")


def skill_of(branch, title=""):
    """The skill a docs landing came from, told by its own branch or title."""
    m = LAND_BRANCH_RE.match(branch or "")
    if m:
        return m.group(1)
    m = DOCS_TITLE_RE.match(title or "")
    return m.group(1) if m else ""


# ── the temporary worktree ────────────────────────────────────────────────

class Scratch(object):
    """A hook-less, LFS-less detached worktree at `rev`, always removed."""

    def __init__(self, repo, rev):
        self.repo = repo
        self.rev = rev
        base = os.path.join(repo.state, "wt")
        os.makedirs(base, exist_ok=True)
        self._prune(base)
        self.path = tempfile.mkdtemp(prefix="%d-" % os.getpid(), dir=base)
        os.rmdir(self.path)
        self.env = repo.identity_env(scratch=True)

    def _prune(self, base):
        for name in os.listdir(base):
            pid = name.split("-", 1)[0]
            try:
                os.kill(int(pid), 0)
                continue
            except (ValueError, ProcessLookupError):
                pass
            except PermissionError:
                continue
            self.repo.git("worktree", "remove", "--force", os.path.join(base, name), check=False)
            shutil.rmtree(os.path.join(base, name), ignore_errors=True)
        self.repo.git("worktree", "prune", check=False)

    def __enter__(self):
        run(["git", "-C", self.repo.top, "-c", "core.hooksPath=/dev/null", "worktree", "add", "-q",
             "--detach", self.path, self.rev], env=self.env)
        return self

    def git(self, *args, **kw):
        kw.setdefault("env", self.env)
        return run(["git", "-C", self.path, "-c", "core.hooksPath=/dev/null",
                    "-c", "core.attributesFile=%s" % self.attributes()] + list(args), **kw)

    def attributes(self):
        """Union merges for the append-only ledgers, for git commands run in
        this worktree only. The consumer's own .gitattributes still wins."""
        f = os.path.join(self.repo.state, "attributes")
        p = self.repo.prefix
        want = "".join("%s%s merge=union\n" % (p, x) for x in
                       ("tasks/history.tsv", "tasks/ROADMAP.md", "tasks/AUDIT.md"))
        try:
            if not os.path.exists(f) or open(f, encoding="utf-8").read() != want:
                with open(f, "w", encoding="utf-8") as fh:
                    fh.write(want)
        except OSError:
            pass
        return f

    def __exit__(self, *exc):
        run(["git", "-C", self.repo.top, "worktree", "remove", "--force", self.path], check=False)
        shutil.rmtree(self.path, ignore_errors=True)
        run(["git", "-C", self.repo.top, "worktree", "prune"], check=False)
        return False


def sort_history(path):
    """Stable sort of tasks/history.tsv by its date column. A union merge
    concatenates; bin/task and check-tasks require dates never to run
    backwards."""
    try:
        lines = open(path, encoding="utf-8", errors="surrogateescape", newline="").read().splitlines()
    except OSError:
        return False
    if not lines:
        return False
    head, body = lines[:1], lines[1:]
    if not head[0].startswith("date\t"):
        head, body = [], lines
    keyed = sorted(enumerate(body), key=lambda t: (t[1].split("\t", 1)[0], t[0]))
    new = head + [l for _, l in keyed]
    if new == lines:
        return False
    with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as fh:
        fh.write("\n".join(new) + "\n")
    return True


def check_tasks_errors(tree_root):
    """New-error gate: the ERROR findings of check-tasks on a tree, as a set."""
    ct = None
    for cand in (os.path.join(HERE, "..", "..", "bin", "check-tasks"),):
        if os.path.exists(cand):
            ct = cand
    if not ct or not os.path.isdir(os.path.join(tree_root, "tasks")):
        return None
    # Only the ledger's shape is gated. The digest ledger (I-34/I-38) tracks
    # edits between runs in one checkout; a scratch tree has no history, and
    # the baseline run would seed it and then flag every same-day edit.
    digests = os.path.join(tree_root, "tasks", ".state", "digests.tsv")
    if os.path.exists(digests):
        os.unlink(digests)
    r = run([sys.executable, ct, "--json", tree_root], check=False)
    if os.path.exists(digests):
        os.unlink(digests)
    try:
        d = json.loads(r.stdout)
    except ValueError:
        return {("unreadable", "", (r.stderr or r.stdout)[:200])}
    return {(f.get("invariant"), f.get("file"), f.get("message"))
            for f in d.get("findings", [])
            if f.get("severity") == "ERROR" and f.get("invariant") not in ("I-34", "I-38")}


def gate_tree(sc, repo, touched, baseline):
    """Refuse a landing that adds a ledger error the trunk did not have."""
    root = os.path.join(sc.path, repo.prefix) if repo.prefix else sc.path
    if any(p.startswith("tasks/") for p in touched) and baseline is not None:
        after = check_tasks_errors(root)
        new = sorted((after or set()) - baseline)
        if new:
            detail = "; ".join("%s %s: %s" % (i or "?", f or "", (m or "")[:120]) for i, f, m in new[:5])
            raise Stop(CONFLICT, "the ledger would break on the trunk (%s). Re-file or re-run the writer after `land.sh sync`." % detail)


# ── building the landing commit ───────────────────────────────────────────

def wt_mode(full):
    """The git mode a working-tree file would be committed with."""
    if os.path.islink(full):
        return "120000"
    if os.path.isfile(full) and os.access(full, os.X_OK):
        return "100755"
    return "100644"


def git_bytes(repo, *args, **kw):
    """git with raw bytes in and out (blob contents are not text)."""
    p = subprocess.run(["git", "-C", repo.top] + list(args), input=kw.get("input_bytes"),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=kw.get("env"))
    if kw.get("check", True) and p.returncode != 0:
        raise Stop(ERR, "git %s failed: %s" % (" ".join(args[:3]), p.stderr.decode("utf-8", "replace").strip()[:300]))
    return p


def wt_entry(repo, tp):
    """(mode, blob) for the working-tree file at top-relative `tp`, its blob
    written to the object store the way `git add` would; None if absent."""
    full = os.path.join(repo.top, tp)
    if not os.path.lexists(full):
        return None
    mode = wt_mode(full)
    if mode == "120000":
        target = os.readlink(full).encode("utf-8", "surrogateescape")
        return mode, git_bytes(repo, "hash-object", "-w", "--stdin", input_bytes=target).stdout.decode().strip()
    return mode, repo.git("hash-object", "-w", "--", tp).stdout.strip()


def plan_paths(repo, paths, base):
    """Sort each requested doc into land / skip. Returns (land, skip,
    parent): the change is taken from `parent`, the point where this checkout
    left the trunk, so a doc committed on a branch (a wip/ autosave, a task
    branch) or on a local trunk that has gone its own way lands as what it
    adds to the trunk, never as a false conflict."""
    head = repo.head()
    parent = base
    if head:
        r = repo.git("merge-base", head, base, check=False)
        if r.returncode == 0 and r.stdout.strip():
            parent = r.stdout.strip()
    imports = repo.imports()
    cur = repo.branch()
    work_branch = bool(cur) and cur != repo.trunk and not cur.startswith("wip/")
    land, skip = [], []
    for p in paths:
        tp = repo.top_path(p)
        full = os.path.join(repo.top, tp)
        if os.path.isdir(full):
            raise Stop(USAGE, "%s is a directory; name the files" % p)
        if work_branch and p.startswith("tasks/") and head and repo.blob_at(head, tp) != repo.blob_at(parent, tp):
            # A task branch's own transitions (start, submit) ride its PR; landed
            # from here they would reach the trunk ahead of the files they move.
            raise Stop(REFUSED, "%s has changes committed on %s, which ride that branch's PR. Land planning changes from a checkout "
                       "of %s instead: a planning worktree (land/SKILL.md, \"Planning from a work branch\"). Undo what you filed "
                       "here first (it is not on the trunk)." % (p, cur, repo.trunk))
        klass, why = classify(p, imports, wt_mode(full) if os.path.lexists(full) else None)
        if klass != "docs":
            raise Stop(REFUSED, "%s is %s class (%s). Docs land by themselves; this goes through `land.sh pr`." % (p, klass, why))
        if repo.git("check-ignore", "-q", "--", tp, check=False).returncode == 0:
            skip.append((p, "ignored by .gitignore; not landed"))
            continue
        wt = repo.wt_blob(tp)
        tb = repo.blob_at(base, tp)
        if wt == tb:
            skip.append((p, "already on the trunk"))
            continue
        if wt is not None:
            try:
                hit = secret_hit(open(full, encoding="utf-8", errors="replace").read())
            except OSError:
                hit = None
            if hit:
                raise Stop(REFUSED, "%s looks like it holds a credential (%s). Remove it; nothing was landed." % (p, hit))
        if wt == repo.blob_at(parent, tp):
            skip.append((p, "unchanged here since this checkout left %s, and %s has changed it since: nothing of yours to land"
                         % (repo.trunk, repo.trunk)))
            continue
        land.append((p, "delta", wt))
    return land, skip, parent


def build_commit(repo, land, base, message, parent=None):
    """C = parent + the landed contents, built with plumbing in a private
    index: no checkout, no hooks. Replayed onto the trunk, it carries exactly
    what the checkout changed since `parent`."""
    head = parent or base
    env = repo.identity_env(scratch=True)
    idx = tempfile.NamedTemporaryFile(prefix="land-idx-", dir=repo.state, delete=False)
    idx.close()
    env["GIT_INDEX_FILE"] = idx.name
    try:
        g = lambda *a, **k: run(["git", "-C", repo.top] + list(a), env=env, **k)
        g("read-tree", head)
        for p, _kind, wt in land:
            tp = repo.top_path(p)
            if wt is None:
                g("update-index", "--force-remove", "--", tp)
            else:
                blob = g("hash-object", "-w", "--", tp).stdout.strip()
                g("update-index", "--add", "--cacheinfo", "100644,%s,%s" % (blob, tp))
        tree = g("write-tree").stdout.strip()
        return g("commit-tree", tree, "-p", head, "-m", message).stdout.strip()
    finally:
        os.unlink(idx.name)


def pick_onto(repo, commit, base, touched, message):
    """Replay `commit` onto the fresh trunk in a scratch worktree. Returns the
    landing commit, or None when the trunk already has all of it."""
    with Scratch(repo, base) as sc:
        root = os.path.join(sc.path, repo.prefix) if repo.prefix else sc.path
        baseline = check_tasks_errors(root) if any(p.startswith("tasks/") for p in touched) else None
        r = sc.git("cherry-pick", "--no-commit", commit, check=False)
        if r.returncode != 0:
            conflicted = sc.git("diff", "--name-only", "--diff-filter=U", check=False).stdout.split()
            sc.git("cherry-pick", "--abort", check=False)
            sc.git("reset", "-q", "--hard", check=False)
            if conflicted:
                raise Stop(CONFLICT, "the trunk changed the same lines in: %s. Nothing was pushed and your files are untouched. Run `land.sh sync`, then land again."
                           % ", ".join(conflicted))
            raise Stop(ERR, "cherry-pick failed: %s" % (r.stderr or r.stdout).strip()[:400])
        hist = repo.top_path("tasks/history.tsv")
        if "tasks/history.tsv" in touched and sort_history(os.path.join(sc.path, hist)):
            sc.git("add", "--", hist)
        if sc.git("diff", "--cached", "--quiet", check=False).returncode == 0:
            return None
        gate_tree(sc, repo, touched, baseline)
        sc.git("commit", "-q", "-m", message)
        return sc.git("rev-parse", "HEAD").stdout.strip()


def merge_trunk_into(repo, tip, base, touched):
    """Bring the trunk into a pushed landing branch: a merge, never a rewrite.
    The ledger gate runs here too: the trunk may have filed the same id."""
    if repo.is_ancestor(base, tip):
        return tip
    with Scratch(repo, tip) as sc:
        root = os.path.join(sc.path, repo.prefix) if repo.prefix else sc.path
        baseline = None
        if any(p.startswith("tasks/") for p in touched):
            with Scratch(repo, base) as sb:
                baseline = check_tasks_errors(os.path.join(sb.path, repo.prefix) if repo.prefix else sb.path)
        r = sc.git("merge", "--no-edit", "-q", base, check=False)
        if r.returncode != 0:
            conflicted = sc.git("diff", "--name-only", "--diff-filter=U", check=False).stdout.split()
            left = [f for f in conflicted if not resolve_appends(repo, sc, f)]
            if left or not conflicted:
                sc.git("merge", "--abort", check=False)
                raise Stop(CONFLICT, "the trunk now conflicts with this landing in: %s" % (", ".join(left or conflicted) or "?"))
            sc.git("commit", "-q", "--no-edit")
        hist = repo.top_path("tasks/history.tsv")
        if "tasks/history.tsv" in touched and sort_history(os.path.join(sc.path, hist)):
            sc.git("add", "--", hist)
            sc.git("commit", "-q", "-m", "land: keep the transition log in date order")
        gate_tree(sc, repo, touched, baseline)
        return sc.git("rev-parse", "HEAD").stdout.strip()


# ── push, PR, checks ──────────────────────────────────────────────────────

ENV_REFUSAL = re.compile(r"HTTP 403|403 Forbidden|not allowed|permission denied|denied by|protected branch|pre-receive hook declined", re.I)


def push_ref(repo, sha, branch, force_new=True):
    r = repo.git("push", "-q", "origin", "%s:refs/heads/%s" % (sha, branch), check=False)
    if r.returncode == 0:
        return
    err = (r.stderr or r.stdout).strip()
    if ENV_REFUSAL.search(err):
        raise Stop(ENVREFUSED, "the remote or this environment refused the push to %s: %s" % (branch, err[:300]))
    raise Stop(ERR, "push of %s failed: %s" % (branch, err[:300]))


def stamp():
    return time.strftime("%Y%m%d-%H%M%S", time.gmtime())


def slugify(text, n=40):
    s = re.sub(r"[^a-z0-9]+", "-", (text or "").lower()).strip("-")
    return (s[:n].rstrip("-")) or "change"


def manifest_block(kind, tasks, merge, method):
    here_manifest = os.path.join(HERE, "..", "auto-merge", "pr-manifest.sh")
    args = ["bash", here_manifest, "block", "--kind", kind, "--merge", merge, "--method", method,
            "--on-merge", "hold"]
    if tasks:
        args += ["--tasks", " ".join(tasks)]
    r = run(args, check=False)
    if r.returncode == 0:
        return r.stdout.strip()
    # Fallback that pr-manifest.sh check accepts, if the helper is absent.
    return "\n".join([
        "```yaml merge-manifest", "kind: %s" % kind, "tasks: [%s]" % ", ".join(tasks), "phase: none",
        "release: none", "merge: %s" % merge, "method: %s" % method, "after: []", "on_merge: hold",
        "migrations: none", "rollback: revert", "```"])


def pr_body(klass, skill, title, summary, tasks, files, base, verified, risk):
    kind = "task" if (klass == "code" and tasks) else "chore"
    block = manifest_block(kind, tasks, "manual", "squash")
    lines = [
        "**Merge manifest.** It is read by `/auto-merge` and the `pr-manifest` check, so keep the fence and every key.",
        "", block, "",
        "**Landing:** `%s` · opened by `/%s` through `land.sh`." % (klass, skill), "",
        "## What & why", "", summary or ("Output of /%s: %s." % (skill, title)), "",
        "## Part of", "",
        "- **Skill:** `/%s`" % skill,
        "- **Tasks:** %s" % (", ".join("`%s`" % t for t in tasks) if tasks else "none"),
        "- **Files:** " + ", ".join("`%s`" % f for f in files), "",
        "## How I verified", "",
        verified or ("`land.sh` classified every file as %s class and replayed the change onto `%s`, the trunk tip it was cut from." % (klass, base[:12])), "",
        "## Risk & rollback", "",
        risk or ("Documentation and ledger records only; nothing executes them. Roll back with a revert." if klass == "docs"
                 else "Code-class change: review the diff before merging. Roll back with a revert."), "",
        "## After merge", "",
        "- **Hold.** Nothing runs on merge." if klass == "docs" else
        "- **Hold.** Merged by `/peer-review`, `/auto-merge` or a person, never by the skill that opened it.",
    ]
    return "\n".join(lines) + "\n"


def write_body(repo, text):
    f = tempfile.NamedTemporaryFile("w", prefix="land-body-", suffix=".md", dir=repo.state, delete=False, encoding="utf-8")
    f.write(text)
    f.close()
    return f.name


_GH = {}


def gh_ok():
    """gh is on PATH and signed in (cached per run). A gh that cannot reach
    GitHub takes the same hand-off as no gh at all."""
    if "ok" not in _GH:
        _GH["ok"] = have("gh") and run(["gh", "auth", "status"], check=False).returncode == 0
    return _GH["ok"]


def gh_pr_for_branch(repo, branch):
    r = run(["gh", "pr", "view", branch, "--json", "number,url,state,isDraft,headRefOid"], cwd=repo.top, check=False)
    if r.returncode != 0:
        return None
    try:
        d = json.loads(r.stdout)
    except ValueError:
        return None
    return d if d.get("state") == "OPEN" else None


def gh_create_pr(repo, branch, title, body_file, draft=False, label=None):
    if label:
        run(["gh", "label", "create", label, "--color", "C5DEF5",
             "--description", "Opened by land.sh"], cwd=repo.top, check=False)
    args = ["gh", "pr", "create", "--base", repo.trunk, "--head", branch, "--title", title, "--body-file", body_file]
    if draft:
        args.append("--draft")
    r = run(args + (["--label", label] if label else []), cwd=repo.top, check=False)
    if r.returncode != 0 and label:
        r = run(args, cwd=repo.top, check=False)
    if r.returncode != 0:
        raise Stop(ERR, "gh pr create failed: %s" % (r.stderr or r.stdout).strip()[:400])
    url = r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ""
    m = re.search(r"/pull/(\d+)", url)
    return (int(m.group(1)) if m else None), url


def _patterns(block, key):
    """Branch patterns under `key:` in a workflow trigger block (list form or
    inline [a, b]); None when the key is absent."""
    m = re.search(r"(?m)^([ \t]*)%s:[ \t]*(.*)$" % re.escape(key), block)
    if not m:
        return None
    inline = m.group(2).strip()
    if inline:
        return [x.strip().strip("'\"") for x in inline.strip("[]").split(",") if x.strip()]
    out, indent = [], len(m.group(1))
    for line in block[m.end():].splitlines()[1:]:
        if not line.strip():
            continue
        if len(line) - len(line.lstrip()) <= indent and not line.lstrip().startswith("-"):
            break
        item = re.match(r"^[ \t]*-[ \t]*(.+?)[ \t]*$", line)
        if item:
            out.append(item.group(1).strip("'\""))
        elif len(line) - len(line.lstrip()) <= indent:
            break
    return out


def _branch_match(patterns, branch):
    import fnmatch
    return any(fnmatch.fnmatchcase(branch, pat.replace("**", "*")) for pat in patterns)


def workflow_runs_for(text, branch):
    """Would this workflow report on a PR from `branch` (pull_request,
    pull_request_target, or a push to the branch)? Read loosely: when in
    doubt, yes, so an empty read waits rather than passes."""
    if re.search(r"\bpull_request(_target)?\b", text):
        return True
    if re.search(r"(?m)^[ \t]*['\"]?on['\"]?[ \t]*:[ \t]*\[?[^\n]*\bpush\b", text):
        return True  # on: push / on: [push, ...]: no branch filter possible there
    m = re.search(r"(?m)^([ \t]*)push[ \t]*:[ \t]*$", text)
    if not m:
        return False
    indent = len(m.group(1))
    lines = []
    for line in text[m.end():].splitlines()[1:]:
        if line.strip() and len(line) - len(line.lstrip()) <= indent:
            break
        lines.append(line)
    block = "\n".join(lines)
    only = _patterns(block, "branches")
    ignore = _patterns(block, "branches-ignore")
    if only is not None:
        return _branch_match(only, branch)
    if ignore is not None:
        return not _branch_match(ignore, branch)
    if _patterns(block, "tags") is not None:
        return False  # tags only
    return True


def trunk_requires_checks(repo, base, branch="land/x"):
    """True when a workflow on the trunk will report on this PR, so an empty
    read means 'not started yet', never 'nothing to run'. Only the top-level
    .github/workflows counts: GitHub runs no other."""
    wf = repo.git("ls-tree", "-r", "--name-only", base, "--", ".github/workflows", check=False).stdout.split()
    for f in wf:
        if f.endswith((".yml", ".yaml")) and workflow_runs_for(repo.git("show", "%s:%s" % (base, f), check=False).stdout, branch):
            return True
    return False


def classify_rollup(rollup):
    """(state, failing, pending) through peer-review.sh classify — one
    classifier for every merge gate in the Element."""
    pr = os.path.join(HERE, "..", "peer-review", "peer-review.sh")
    r = run(["bash", pr, "classify"], input_text=json.dumps({"statusCheckRollup": rollup}), check=False)
    out = dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)
    return out.get("checks_state", "fail"), out.get("failing_checks", ""), out.get("pending_checks", "")


def rollup_from_json(files, sha):
    """Normalise GitHub reads made with other tooling: REST check-runs
    ({check_runs: [...]}, each with head_sha), REST combined status
    ({sha, statuses: [...]}) and a gh read ({headRefOid, statusCheckRollup}).
    Only entries tied to `sha` count; a read with no commit id says nothing
    about this head and is set aside. Returns (rollup, check_runs): the
    check runs are counted apart, since a status alone cannot stand for the
    trunk's own workflows."""
    rollup, runs, understood = [], 0, False
    for f in files:
        try:
            d = json.load(open(f, encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise Stop(USAGE, "could not read checks JSON %s: %s" % (f, exc))
        if isinstance(d, dict) and isinstance(d.get("statusCheckRollup"), list):
            understood = True
            if d.get("headRefOid") != sha:
                say("ignored=%s (its statusCheckRollup is not tied to %s: read it with headRefOid)" % (f, sha[:12]))
            else:
                rollup += d["statusCheckRollup"]
                runs += sum(1 for c in d["statusCheckRollup"] if isinstance(c, dict) and c.get("__typename") == "CheckRun")
        if isinstance(d, dict) and isinstance(d.get("check_runs"), list):
            understood = True
            for c in d["check_runs"]:
                if c.get("head_sha") != sha:
                    continue  # another commit's result, or one that does not say
                runs += 1
                rollup.append({"__typename": "CheckRun", "name": c.get("name") or "?",
                               "status": str(c.get("status") or "").upper(),
                               "conclusion": str(c.get("conclusion") or "").upper()})
        if isinstance(d, dict) and isinstance(d.get("statuses"), list):
            understood = True
            if d.get("sha") != sha:
                say("ignored=%s (its statuses are for %s, not %s)" % (f, str(d.get("sha") or "no commit")[:12], sha[:12]))
            else:
                for st in d["statuses"]:
                    rollup.append({"__typename": "StatusContext", "context": st.get("context") or "?",
                                   "state": str(st.get("state") or "").upper()})
        if isinstance(d, list):
            understood = True
            say("ignored=%s (a bare list is not tied to any commit)" % f)
    if not understood:
        raise Stop(REFUSED, "the checks JSON is in no shape land.sh knows (REST check_runs, REST combined status, gh headRefOid+statusCheckRollup)")
    return rollup, runs


NONE_GRACE_SECS = int(os.environ.get("LAND_NONE_GRACE", "90"))


def wait_checks(repo, pr, base, secs, checks_json=None, sha=None, branch="land/x"):
    """'pass' or a Stop. When a trunk workflow will report on this PR, a pass
    needs its check runs; with none, 'no checks' passes only once the head is
    old enough for CI to have registered (external CI included)."""
    need = trunk_requires_checks(repo, base, branch)
    ct = repo.git("show", "-s", "--format=%ct", sha, check=False).stdout.strip()
    pushed_at = int(ct) if ct.isdigit() else 0

    def settled():
        return time.time() - pushed_at >= NONE_GRACE_SECS

    if checks_json:
        rollup, runs = rollup_from_json(checks_json, sha)
        state, failing, pending = classify_rollup(rollup)
        if need and runs == 0 and state != "fail":
            state = "pending" if state == "pending" else "none"
        return _judge(state, failing, pending, need, final=True, grace_left=not settled())
    deadline = time.time() + secs
    poll = max(1, int(os.environ.get("LAND_POLL", "15")))
    while True:
        r = run(["gh", "pr", "view", str(pr), "--json", "statusCheckRollup,headRefOid"], cwd=repo.top, check=False)
        if r.returncode != 0:
            raise Stop(ERR, "could not read PR #%s checks: %s" % (pr, (r.stderr or "").strip()[:200]))
        d = json.loads(r.stdout or "{}") or {}
        if d.get("headRefOid") and d.get("headRefOid") != sha:
            raise Stop(REFUSED, "PR #%s head is now %s, not %s: something was pushed after the check" % (pr, d["headRefOid"][:12], sha[:12]))
        rollup = d.get("statusCheckRollup") or []
        state, failing, pending = classify_rollup(rollup)
        runs = sum(1 for c in rollup if isinstance(c, dict) and c.get("__typename") == "CheckRun")
        if need and runs == 0 and state != "fail":
            state = "pending" if state == "pending" else "none"
        final = time.time() >= deadline
        verdict = _judge(state, failing, pending, need, final=final, grace_left=not settled())
        if verdict == "pass":
            return "pass"
        time.sleep(poll)


def _judge(state, failing, pending, need, final, grace_left=False):
    if state == "fail":
        raise Stop(CHECKS, "checks failing: %s. The PR stays open." % (failing or "?"))
    if state == "pass":
        return "pass"
    if state == "none" and not need and not grace_left:
        return "pass"  # nothing runs on this PR here, and CI has had time to register
    if final:
        what = "still running: %s" % pending if state == "pending" else "none reported yet"
        raise Stop(CHECKS, "checks %s. The PR stays open; run `land.sh merge` again later." % what)
    return "wait"


# ── verify: the pushed-artifact gate (git only) ───────────────────────────

def verify(repo, pr, sha, want="docs"):
    """The PR's head must be `sha`, carry only `want`-class files, and
    contain the fetched trunk. Checked by git alone."""
    r = repo.git("ls-remote", "origin", "refs/pull/%s/head" % pr, check=False)
    remote_head = (r.stdout.split() or [""])[0]
    if not remote_head:
        raise Stop(REFUSED, "the remote has no refs/pull/%s/head (no such PR, or not visible yet)" % pr)
    if remote_head != sha:
        raise Stop(REFUSED, "PR #%s head is %s, not %s: something was pushed after the check" % (pr, remote_head[:12], sha[:12]))
    repo.git("fetch", "-q", "origin", "+refs/pull/%s/head:refs/land/pr-%s" % (pr, pr))
    base = repo.fetch_trunk()
    mb = repo.git("merge-base", base, sha).stdout.strip()
    raw = repo.git("diff", "--raw", "--no-renames", "-z", mb, sha).stdout
    bad = []
    fields = raw.split("\0")
    i = 0
    files = []
    imports = repo.imports()
    while i < len(fields) - 1:
        meta = fields[i]
        if not meta.startswith(":"):
            i += 1
            continue
        path = fields[i + 1]
        i += 2
        parts = meta[1:].split()
        mode_new = parts[1] if len(parts) > 1 else None
        mode_old = parts[0]
        rel = repo.rel(path)
        files.append(path)
        mode = mode_new if mode_new != "000000" else mode_old
        if rel is None:
            bad.append((path, "outside the install"))
            continue
        klass, why = classify(rel, imports, mode)
        if want == "docs" and klass != "docs":
            bad.append((rel, why))
    if not files:
        raise Stop(REFUSED, "PR #%s changes nothing against %s" % (pr, repo.trunk))
    if bad:
        raise Stop(REFUSED, "PR #%s is not docs-only: %s" % (pr, "; ".join("%s (%s)" % b for b in bad[:6])))
    fresh = repo.is_ancestor(base, sha)
    return base, fresh, [repo.rel(f) or f for f in files]


# ── settle: bring the user's checkout in line after a merge ───────────────

def landed_on(repo, base, p, blob, before_rev=None):
    """Is this landing's content on the trunk? A whole file for new or
    rewritten docs; for ledgers merged line by line (history.tsv, ROADMAP.md,
    AUDIT.md) every line the landing added — against the point it was built
    from — must be there."""
    tp = repo.top_path(p)
    tb = repo.blob_at(base, tp)
    if tb == blob:
        return True
    if blob is None or tb is None:
        return False
    mine = repo.git("cat-file", "blob", blob).stdout.splitlines()
    theirs = set(repo.git("cat-file", "blob", tb).stdout.splitlines())
    head = before_rev or repo.head()
    hb = repo.blob_at(head, tp) if head else None
    before = set(repo.git("cat-file", "blob", hb).stdout.splitlines()) if hb else set()
    added = [l for l in mine if l not in before and l.strip()]
    return bool(added) and all(l in theirs for l in added)


def settle(repo, branch, landed, merged=True):
    """landed: list of [path, blob|None]. Runs only once this landing's
    content is on the fetched trunk. Never loses a byte: copies are saved
    first, restores go through git (index and file, byte for byte), and the
    result is checked before success is reported."""
    base = repo.fetch_trunk()
    parent = None
    for r in log_rows(repo):
        if branch and r.get("branch") == branch and r.get("parent"):
            parent = r["parent"]
    for p, blob in landed:
        if not landed_on(repo, base, p, blob, parent):
            raise Stop(CHECKS, "not on %s yet: %s. Settle again after the merge." % (repo.trunk, p))
    if repo.op_in_progress():
        return ["checkout left as is: an operation is in progress"]
    head, cur = repo.head(), repo.branch()
    if not cur and not (head and repo.is_ancestor(head, base)):
        return ["detached HEAD with commits of its own: landed files kept in the checkout"]
    if cur == repo.trunk and head and not repo.is_ancestor(head, base):
        return ["local %s has commits that are not on origin: landed files kept. `land.sh sync` moves those commits onto a rescue branch (to propose by PR) and brings the checkout up to date" % cur]
    if os.path.exists(os.path.join(repo.git_dir, "index.lock")):
        return ["index.lock present: landed files kept"]
    report, touched = [], []
    stash = os.path.join(repo.state, "stash", stamp())
    for p, blob in landed:
        tp = repo.top_path(p)
        full = os.path.join(repo.top, tp)
        if repo.wt_blob(tp) != blob:
            report.append("%s changed since it landed; kept as is" % p)
            continue
        existed = os.path.lexists(full)
        if existed:
            os.makedirs(os.path.dirname(os.path.join(stash, tp)), exist_ok=True)
            shutil.copy2(full, os.path.join(stash, tp))
        touched.append((p, tp, full, existed))
    if not touched:
        return report or ["nothing to settle"]
    env = repo.identity_env()

    def restore_copies():
        for _p, tp, full, existed in touched:
            src = os.path.join(stash, tp)
            if existed and os.path.exists(src):
                os.makedirs(os.path.dirname(full), exist_ok=True)
                shutil.copy2(src, full)
            elif not existed and os.path.lexists(full):
                os.unlink(full)

    try:
        for _p, tp, full, _e in touched:
            if head and repo.blob_at(head, tp):
                repo.git("checkout", "-q", head, "--", tp)
            else:
                repo.git("rm", "-q", "--cached", "--ignore-unmatch", "--", tp, check=False)
                if os.path.lexists(full):
                    os.unlink(full)
        if not cur:
            r = repo.git("checkout", "-q", "--detach", base, check=False, env=env)
        elif cur == repo.trunk:
            r = repo.git("merge", "-q", "--ff-only", base, check=False, env=env)
        else:
            r = repo.git("merge", "-q", "--no-edit", base, check=False, env=env)
            if r.returncode != 0 and os.path.exists(os.path.join(repo.git_dir, "MERGE_HEAD")):
                repo.git("merge", "--abort", check=False)
        if r.returncode != 0:
            restore_copies()
            return report + ["could not bring %s into %s (%s); landed files kept as they were" %
                             (repo.trunk, cur, (r.stderr or r.stdout).strip()[:160])]
        off = [p for p, tp, _f, _e in touched if repo.wt_blob(tp) != repo.blob_at("HEAD", tp)]
        if off:
            restore_copies()
            return report + ["%s merged, but %s did not match it afterwards; your copies were put back" %
                             (repo.trunk, ", ".join(off))]
    except Stop as exc:
        restore_copies()
        return report + ["settle stopped (%s); your copies were put back" % exc.msg]
    return report + ["%s now carries the landed files from %s" % (cur or "the detached checkout", repo.trunk)]


# ── verbs ─────────────────────────────────────────────────────────────────

def cmd_classify(repo, paths):
    imports = repo.imports() if repo else set()
    worst = OK
    for p in paths:
        full = os.path.join(repo.root if repo else os.getcwd(), p)
        klass, why = classify(p, imports, wt_mode(full) if os.path.lexists(full) else None)
        say("%s\t%s\t%s" % (klass, p, why))
        if klass != "docs":
            worst = REFUSED
    say("class=%s" % ("docs" if worst == OK else "code"))
    return worst


def land_docs(repo, a, cfg):
    """The docs landing, end to end. The lock covers building, pushing and
    opening the PR; the CI wait runs without it."""
    op = repo.op_in_progress()
    if op:
        raise Stop(REFUSED, "a git operation is in progress (%s); finish it first" % op)
    with Lock(repo):
        base = repo.fetch_trunk()
        cfg = load_config(repo)  # again, now that the trunk's copy is fresh
        land, skip, parent = plan_paths(repo, a.paths, base)
        for p, why in skip:
            say("skipped=%s (%s)" % (p, why))
        if not land:
            say("landed=nothing", "result=nothing to land")
            return OK
        touched = [p for p, _, _ in land]
        msg = "docs(%s): %s" % (a.skill, a.title)
        c = build_commit(repo, land, base, msg, parent=parent)
        tip = pick_onto(repo, c, base, touched, msg)
        if tip is None:
            say("landed=already", "result=the trunk already has all of it")
            try:
                for line in settle(repo, "", [(p, wt) for p, _, wt in land]):
                    say("settle=" + line)
            except Stop as exc:
                say("settle=kept: %s" % exc.msg)
            return OK
        branch = "land/%s-%s-%s" % (slugify(a.skill, 40), stamp(), os.urandom(2).hex())
        push_ref(repo, tip, branch)
        landed = [[p, wt] for p, _, wt in land]
        log_row(repo, "pushed", branch=branch, sha=tip, skill=a.skill, landed=landed, klass="docs", parent=parent)
        say("branch=%s" % branch, "head=%s" % tip, "base=%s" % base)
        title = "docs(%s): %s" % (a.skill, a.title)
        body = write_body(repo, pr_body("docs", a.skill, a.title, a.summary, a.tasks, touched, base, None, None))
        held = docs_mode(cfg, a.skill) == "pr"
        if not gh_ok():
            say("body_file=%s" % body, "title=%s" % title, "next=open-pr",
                "then: open the PR (base %s, head %s) with the session's GitHub tooling and label it docs-land." % (repo.trunk, branch))
            if held:
                say("merge=held (.claude/landing.json asks docs from /%s to wait for a person: do NOT merge it)" % a.skill)
            else:
                say("      Read the PR (get) and its check runs into files, then run:",
                    "      land.sh merge --pr <N> --sha %s --pr-json <pr file> --checks-json <checks file>" % tip)
            return NOGH
        number, url = gh_create_pr(repo, branch, title, body, label="docs-land")
        log_row(repo, "pr-open", branch=branch, sha=tip, pr=number, url=url, landed=landed, skill=a.skill, klass="docs")
        say("pr=%s" % url)
        if held:
            say("merge=held (.claude/landing.json asks docs from this skill to wait for a person)")
            return OK
    return merge_flow(repo, number, tip, branch, landed, cfg, wait=a.wait, skill=a.skill)


def pr_facts(repo, pr, sha, pr_json=None):
    """What the PR itself says: its base, head branch, head commit and
    title, from gh or from a read made with other tooling (--pr-json). The
    read must be of this PR and of this head."""
    if gh_ok():
        r = run(["gh", "pr", "view", str(pr), "--json", "number,baseRefName,headRefName,headRefOid,title"],
                cwd=repo.top, check=False)
        try:
            d = json.loads(r.stdout)
        except ValueError:
            raise Stop(ERR, "could not read PR #%s: %s" % (pr, (r.stderr or r.stdout).strip()[:200]))
        facts = {"number": d.get("number"), "base": d.get("baseRefName"), "head_ref": d.get("headRefName"),
                 "head_sha": d.get("headRefOid"), "title": d.get("title") or ""}
    elif pr_json:
        try:
            d = json.load(open(pr_json, encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise Stop(USAGE, "could not read --pr-json %s: %s" % (pr_json, exc))
        b, h = d.get("base"), d.get("head")
        facts = {"number": d.get("number"),
                 "base": (b.get("ref") if isinstance(b, dict) else None) or d.get("baseRefName"),
                 "head_ref": (h.get("ref") if isinstance(h, dict) else None) or d.get("headRefName"),
                 "head_sha": (h.get("sha") if isinstance(h, dict) else None) or d.get("headRefOid"),
                 "title": d.get("title") or ""}
    else:
        raise Stop(REFUSED, "without gh, pass --pr-json <a read of PR #%s> so its base can be checked" % pr)
    if facts["number"] is not None and str(facts["number"]) != str(pr):
        raise Stop(REFUSED, "the PR read is of #%s, not #%s" % (facts["number"], pr))
    if facts["head_sha"] and facts["head_sha"] != sha:
        raise Stop(REFUSED, "the PR read shows head %s, not %s: read it again after the last push" % (facts["head_sha"][:12], sha[:12]))
    if facts["base"] != repo.trunk:
        raise Stop(REFUSED, "PR #%s targets %s, not %s: a docs landing only merges into the trunk" % (pr, facts["base"] or "?", repo.trunk))
    return facts


def merge_flow(repo, pr, sha, branch, landed, cfg, wait=None, checks_json=None, skill="", pr_json=None):
    """Verify, wait for CI, merge pinned to the head, settle. The lock is
    taken for the steps that push, merge or touch the checkout, never for
    the wait."""
    secs = cfg["check_wait_secs"] if wait is None else wait
    touched = [p for p, _ in landed]
    facts = pr_facts(repo, pr, sha, pr_json)
    skill = skill or skill_of(facts.get("head_ref"), facts.get("title"))
    branch = branch or facts.get("head_ref") or ""
    for _round in range(3):
        base, fresh, files = verify(repo, pr, sha, "docs")
        touched = touched or files  # a clone with no record of this landing gates what the PR carries
        if docs_mode(load_config(repo), skill) == "pr":
            raise Stop(REFUSED, "held for a person: .claude/landing.json asks docs from /%s to wait for review; merge PR #%s by hand"
                       % (skill or "an unnamed skill", pr))
        if not fresh:
            if not branch:
                raise Stop(CHECKS, "PR #%s is behind %s; sync it (land.sh sync-pr) and read its checks again" % (pr, repo.trunk))
            with Lock(repo):
                base = repo.fetch_trunk()
                new = merge_trunk_into(repo, sha, base, touched)
                push_ref(repo, new, branch)
            log_row(repo, "pushed", branch=branch, sha=new, pr=pr, landed=landed, klass="docs", skill=skill)
            say("synced=%s now carries %s (%s)" % (branch, repo.trunk, new[:12]))
            sha = new
            if checks_json:
                say("head=%s" % sha)
                raise Stop(CHECKS, "the landing branch was brought up to date; read the PR and its checks again and re-run merge with --sha %s" % sha)
            continue
        wait_checks(repo, pr, base, secs, checks_json, sha, branch or "land/x")
        with Lock(repo):
            # The trunk may have moved while CI ran: merge only what contains it.
            if not repo.is_ancestor(repo.fetch_trunk(), sha):
                if checks_json:
                    raise Stop(CHECKS, "%s moved while the checks ran; run land.sh merge again to bring it in" % repo.trunk)
                continue
            if not gh_ok():
                log_row(repo, "merge-ready", branch=branch, sha=sha, pr=pr, landed=landed, klass="docs", skill=skill)
                say("merge=ready", "next=merge",
                    "then: merge PR #%s with the session's GitHub tooling: merge_method=squash, expectedHeadSha=%s," % (pr, sha),
                    "      then run: land.sh settle --pr %s" % pr)
                return NOGH
            r = run(["gh", "pr", "merge", str(pr), "--squash", "--delete-branch", "--match-head-commit", sha],
                    cwd=repo.top, check=False)
            if r.returncode != 0:
                raise Stop(CHECKS, "the merge was refused (%s). The PR stays open." % (r.stderr or r.stdout).strip()[:300])
            log_row(repo, "merged", branch=branch, sha=sha, pr=pr, landed=landed, klass="docs")
            say("merged=#%s" % pr)
            try:
                for line in settle(repo, branch, landed):
                    say("settle=" + line)
                log_row(repo, "settled", branch=branch, pr=pr)
            except Stop as exc:
                say("settle=not yet: %s (run land.sh settle --pr %s later)" % (exc.msg, pr))
            return OK
    raise Stop(CHECKS, "the trunk kept moving; PR #%s stays open" % pr)


def cmd_merge(repo, a, cfg):
    row = None
    for r in log_rows(repo):
        if r.get("klass") == "docs" and (r.get("pr") == a.pr or (r.get("sha") == a.sha and r.get("branch"))):
            row = r
    landed = (row or {}).get("landed") or []
    branch = (row or {}).get("branch") or ""
    if row and row.get("pr") is None:
        log_row(repo, "pr-open", branch=branch, sha=a.sha, pr=a.pr, landed=landed, klass="docs", skill=row.get("skill"))
    return merge_flow(repo, a.pr, a.sha, branch, landed, cfg, wait=a.wait, checks_json=a.checks_json or None,
                      skill=(row or {}).get("skill") or "", pr_json=a.pr_json or None)


def cmd_settle(repo, a):
    """After a merge made with other tooling. Matches the exact PR or branch,
    only for a landing whose files are on record, and deletes the branch
    only once git shows the content on the trunk."""
    want_branch = a.branch
    if not want_branch and a.pr is not None and gh_ok():
        r = run(["gh", "pr", "view", str(a.pr), "--json", "headRefName"], cwd=repo.top, check=False)
        try:
            want_branch = json.loads(r.stdout).get("headRefName") or ""
        except ValueError:
            want_branch = ""
    rows = [r for r in log_rows(repo)
            if (a.pr is not None and r.get("pr") == a.pr) or (want_branch and r.get("branch") == want_branch)]
    if not rows:
        raise Stop(USAGE, "no landing on record for %s%s" % (("PR #%s" % a.pr) if a.pr else a.branch,
                   "" if want_branch else " (a PR opened with other tooling: pass --branch <its head branch>)"))
    br = rows[-1].get("branch")
    landed = []
    for r in log_rows(repo):
        if r.get("branch") == br and r.get("landed"):
            landed = r["landed"]
    if not br or not landed:
        raise Stop(REFUSED, "nothing recorded as landed on %s; a code PR is merged and settled by its reviewer" % (br or "that PR"))
    for line in settle(repo, br, landed):
        say("settle=" + line)
    if br in protected_names(repo) or br.startswith("refs/"):
        raise Stop(REFUSED, "%s names the trunk; it is never deleted" % br)
    if repo.git("ls-remote", "--exit-code", "origin", "refs/heads/" + br, check=False).returncode == 0:
        d = repo.git("push", "-q", "origin", "--delete", br, check=False)
        say(("deleted=%s" % br) if d.returncode == 0 else ("kept=%s (the delete was refused: %s)" % (br, (d.stderr or "").strip()[:160])))
    log_row(repo, "settled", branch=br, pr=rows[-1].get("pr"))
    return OK


def cmd_verify(repo, a):
    base, fresh, files = verify(repo, a.pr, a.sha, "docs")
    say("verified=docs-only", "files=%d" % len(files), "base=%s" % base, "fresh=%s" % ("yes" if fresh else "no"))
    return OK if fresh else CONFLICT


def cmd_fresh(repo, a):
    base = repo.fetch_trunk()
    if a.pr:
        repo.git("fetch", "-q", "origin", "+refs/pull/%s/head:refs/land/pr-%s" % (a.pr, a.pr))
    sha = a.sha
    if repo.is_ancestor(base, sha):
        say("fresh=yes", "base=%s" % base)
        return OK
    say("fresh=no", "base=%s" % base, "next=land.sh sync-pr --pr <N> --branch <head-branch>")
    return CONFLICT


def cmd_sync_pr(repo, a):
    """Bring the trunk into a PR's branch without touching the checkout."""
    with Lock(repo):
        base = repo.fetch_trunk()
        repo.git("fetch", "-q", "origin", "+refs/heads/%s:refs/land/sync-%s" % (a.branch, os.getpid()))
        tip = repo.git("rev-parse", "refs/land/sync-%s" % os.getpid()).stdout.strip()
        repo.git("update-ref", "-d", "refs/land/sync-%s" % os.getpid(), check=False)
        if repo.is_ancestor(base, tip):
            say("fresh=yes", "head=%s" % tip)
            return OK
        new = merge_trunk_into(repo, tip, base, ["tasks/history.tsv"])
        push_ref(repo, new, a.branch)
        say("synced=%s" % a.branch, "head=%s" % new)
        return OK


def cmd_sync(repo, a):
    """Bring the latest trunk into the current checkout. On the trunk:
    fast-forward. On a side branch: merge (never rebase, never force)."""
    op = repo.op_in_progress()
    if op:
        raise Stop(REFUSED, "a git operation is in progress (%s)" % op)
    base = repo.fetch_trunk()
    say("base=%s" % base)
    if a.fetch_only:
        return OK
    cur, head = repo.branch(), repo.head()
    if head is None:
        repo.git("reset", "-q", base)
        say("synced=unborn HEAD now at %s" % repo.trunk)
        return OK
    if cur == repo.trunk and not repo.is_ancestor(head, base):
        return rescue_trunk(repo, head, base)
    if repo.is_ancestor(base, head):
        say("sync=up to date")
        return OK
    if not cur:
        if not repo.is_ancestor(head, base):
            raise Stop(REFUSED, "detached HEAD with commits of its own: check out a branch first")
        # A detached checkout of the trunk (a planning worktree): move it on.
        moved = align_identical(repo, head, base)
        r = repo.git("checkout", "-q", "--detach", base, check=False)
        if r.returncode != 0:
            restore_aligned(repo, moved)
            raise Stop(CONFLICT, "could not move this detached checkout to origin/%s: %s" % (repo.trunk, (r.stderr or r.stdout).strip()[:300]))
        say("synced=detached HEAD now at origin/%s (%s)" % (repo.trunk, base[:12]))
        return OK
    env = repo.identity_env()
    moved = align_identical(repo, head, base)
    if cur == repo.trunk:
        r = repo.git("merge", "-q", "--ff-only", base, check=False, env=env)
        if r.returncode != 0:
            restore_aligned(repo, moved)
            raise Stop(CONFLICT, "could not fast-forward %s: %s" % (cur, (r.stderr or r.stdout).strip()[:300]))
        say("synced=%s fast-forwarded to %s" % (cur, base[:12]))
        return OK
    r = repo.git("merge", "-q", "--no-edit", base, check=False, env=env)
    if r.returncode != 0:
        conflicted = repo.git("diff", "--name-only", "--diff-filter=U", check=False).stdout.split()
        if os.path.exists(os.path.join(repo.git_dir, "MERGE_HEAD")):
            repo.git("merge", "--abort", check=False)
        restore_aligned(repo, moved)
        if not conflicted:
            raise Stop(ERR, "merging %s into %s failed: %s" % (repo.trunk, cur, (r.stderr or r.stdout).strip()[:300]))
        raise Stop(CONFLICT, "merging %s into %s conflicts in: %s. The merge was undone; resolve it by hand."
                   % (repo.trunk, cur, ", ".join(conflicted)))
    say("synced=%s now contains %s (%s)" % (cur, repo.trunk, base[:12]))
    if a.push and repo.git("rev-parse", "--abbrev-ref", "@{u}", check=False).returncode == 0:
        pr = repo.git("push", "-q", check=False)
        if pr.returncode != 0:
            raise Stop(ENVREFUSED if ENV_REFUSAL.search(pr.stderr or "") else ERR,
                       "push after sync failed: %s" % (pr.stderr or "").strip()[:200])
        say("pushed=%s" % cur)
    return OK


def align_identical(repo, head, base):
    """Files the incoming trunk changes that this checkout already holds
    byte for byte (a landing merged elsewhere, never settled): put them back
    to HEAD's state so the fast-forward, merge or reset can write them. The
    index and each file are saved first; `restore_aligned` puts both back if
    that step then fails, so a failed sync leaves the checkout — staged work
    included — as it found it."""
    moved = {"files": [], "index": None}
    keep = os.path.join(repo.state, "stash", "align-%s-%s" % (stamp(), os.urandom(2).hex()))
    mb = repo.git("merge-base", head, base, check=False).stdout.strip() or head
    # Only what the trunk changed since this checkout left it: a branch's own
    # changes (and an uncommitted revert of them) are never touched.
    for f in [x for x in repo.git("diff", "--name-only", "-z", mb, base).stdout.split("\0") if x]:
        wt = repo.wt_blob(f)
        hb = repo.blob_at(head, f)
        if wt is None or wt == hb or wt != repo.blob_at(base, f):
            continue
        if moved["index"] is None:
            os.makedirs(keep, exist_ok=True)
            idx = os.path.join(repo.git_dir, "index")
            moved["index"] = os.path.join(keep, "index.snapshot")
            if os.path.exists(idx):
                shutil.copy2(idx, moved["index"])
            else:
                open(moved["index"] + ".absent", "w").close()
        full = os.path.join(repo.top, f)
        os.makedirs(os.path.dirname(os.path.join(keep, f)), exist_ok=True)
        shutil.copy2(full, os.path.join(keep, f), follow_symlinks=False)
        if hb:
            repo.git("checkout", "-q", head, "--", f)
        else:
            repo.git("rm", "-q", "--cached", "--ignore-unmatch", "--", f, check=False)
            if os.path.lexists(full):
                os.unlink(full)
        moved["files"].append((f, os.path.join(keep, f)))
    return moved


def restore_aligned(repo, moved):
    """Undo align_identical after the step it prepared for failed: the files,
    then the index exactly as it was."""
    for f, copy in moved.get("files") or []:
        full = os.path.join(repo.top, f)
        if os.path.exists(copy):
            os.makedirs(os.path.dirname(full) or ".", exist_ok=True)
            if os.path.lexists(full):
                os.unlink(full)
            shutil.copy2(copy, full, follow_symlinks=False)
    snap = moved.get("index")
    if snap:
        idx = os.path.join(repo.git_dir, "index")
        if os.path.exists(snap):
            shutil.copy2(snap, idx + ".land-tmp")
            os.replace(idx + ".land-tmp", idx)
        elif os.path.exists(snap + ".absent") and os.path.exists(idx):
            os.unlink(idx)


def rescue_trunk(repo, head, base):
    """The local trunk has commits origin does not. The trunk only moves
    through a merged PR, so they cannot stay there; nothing may be lost
    either. If origin already carries their content (a squash-merge of the
    branch they went up on), the local trunk simply moves to origin.
    Otherwise they go to a rescue/ branch first (pushed, so a container that
    ends does not take them along) to be proposed by PR. Either way the
    trunk is then moved to origin, keeping uncommitted changes."""
    trunk = repo.trunk
    mb = repo.git("merge-base", head, base).stdout.strip()
    count = repo.git("rev-list", "--count", "%s..%s" % (base, head)).stdout.strip()
    changed = [f for f in repo.git("diff", "--name-only", "-z", mb, head).stdout.split("\0") if f]
    on_origin = all(repo.blob_at(base, f) == repo.blob_at(head, f) for f in changed)
    if on_origin:
        moved = align_identical(repo, head, base)
        r = repo.git("reset", "-q", "--keep", base, check=False)
        if r.returncode != 0:
            restore_aligned(repo, moved)
            raise Stop(CONFLICT, "could not move %s to origin/%s: your uncommitted changes overlap what it changes (%s). Commit or put them aside, then sync again."
                       % (trunk, trunk, (r.stderr or r.stdout).strip()[:200]))
        log_row(repo, "trunk-reset", branch=trunk, old=head, new=base)
        say("local=%s commit(s) on %s were already on origin in content (was %s; `git branch <name> %s` recovers them)"
            % (count, trunk, head[:12], head[:12]))
        say("synced=%s now at origin/%s (%s)" % (trunk, trunk, base[:12]))
        return OK
    # A rescue branch for these very commits may exist from an earlier try.
    have = [x for x in repo.git("for-each-ref", "--format=%(refname:short)", "--points-at", head,
                                "refs/heads/rescue/", check=False).stdout.split() if x]
    rescue = have[0] if have else "rescue/%s-%s-%s" % (slugify(trunk, 20), stamp(), os.urandom(2).hex())
    if not have:
        repo.git("branch", rescue, head)
    moved = align_identical(repo, head, base)
    r = repo.git("reset", "-q", "--keep", base, check=False)
    if r.returncode != 0:
        restore_aligned(repo, moved)
        if not have:
            repo.git("branch", "-q", "-D", rescue, check=False)  # the commits are still on the trunk
        raise Stop(CONFLICT, "could not move %s to origin/%s: your uncommitted changes overlap what it changes (%s). Nothing moved; "
                   "commit or put them aside, then sync again." % (trunk, trunk, (r.stderr or r.stdout).strip()[:200]))
    log_row(repo, "rescued", branch=rescue, sha=head)
    pushed = repo.git("push", "-q", "origin", "%s:refs/heads/%s" % (head, rescue), check=False)
    say("rescued=%s commit(s) of local %s onto %s%s" % (count, trunk, rescue,
        " (pushed)" if pushed.returncode == 0 else " (local only: the push failed: %s)" % (pushed.stderr or "").strip()[:160]))
    say("next=propose them: `git checkout %s` then /push, or land.sh pr from that branch" % rescue)
    say("synced=%s now at origin/%s (%s)" % (trunk, trunk, base[:12]))
    return OK


def branch_name(a, repo, stable=False):
    """task/<ID>-<slug> for task work; chore/<skill>-<slug> otherwise. A
    stable name (PRs built aside) lets a later run update the same PR; it
    gets a short hash of the exact title whenever the slug had to drop or
    change characters, so two titles never share a branch."""
    if a.branch:
        return a.branch
    if a.tasks:
        return "task/%s-%s" % (a.tasks[0], slugify(a.title, 32))
    if stable:
        slug = slugify(a.title, 48)
        plain = re.sub(r"\s+", "-", (a.title or "").strip().lower())
        if slug != plain:
            slug = "%s-%s" % (slug, hashlib.sha1((a.title or "").encode("utf-8")).hexdigest()[:6])
        return "chore/%s-%s" % (slugify(a.skill, 40), slug)
    return "chore/%s-%s-%s" % (slugify(a.skill, 20), slugify(a.title, 24), stamp())


def open_code_pr(repo, a, branch, tip, base):
    """Open (or reuse) the code PR for `branch`. Never merges."""
    title = ("%s: %s" % (a.tasks[0], a.title)) if a.tasks else a.title
    files = [l for l in repo.git("diff", "--name-only", "%s...%s" % (base, tip)).stdout.split()]
    body = write_body(repo, pr_body("code", a.skill, a.title, a.summary, a.tasks,
                                    [repo.rel(f) or f for f in files], base, a.verified, a.risk))
    if not gh_ok():
        say("body_file=%s" % body, "title=%s" % title, "next=open-pr",
            "then: open (or reuse) the PR base %s head %s%s with the session's GitHub tooling. Never merge it." %
            (repo.trunk, branch, " as a draft" if a.draft else ""))
        return NOGH
    existing = gh_pr_for_branch(repo, branch)
    if existing:
        say("pr=%s (already open; the push updated it)" % existing.get("url"))
        return OK
    number, url = gh_create_pr(repo, branch, title, body, draft=a.draft)
    log_row(repo, "pr-open", branch=branch, sha=tip, pr=number, url=url, skill=a.skill, klass="code")
    say("pr=%s" % url, "merge=never by this skill (/peer-review, /auto-merge or a person)")
    return OK


# ── PRs built aside: isolated and rolling ─────────────────────────────────
#
# From the trunk (or with --rolling, from anywhere), a code PR is built away
# from the checkout on a stable branch that a later run updates. Each named
# path is resolved on its own, by one rule: the checkout's change is what its
# copy holds now against the copy it started from (B), and that change is
# merged into the branch's copy (O) — line by line for append-only files; a
# real overlap stops the run. B is recorded per worktree: what `land.sh
# pending` brought in, or what the checkout held after its last push here;
# with no record, the file as it was where this checkout left the trunk.
# So a revert is a revert, and a copy someone else changed (a reviewer, the
# trunk, another session) is merged, never overwritten.

UNION_PATHS = re.compile(r"^(docs/notes/INDEX\.md|\.claude/inbox/[^/]+\.md|tasks/history\.tsv|tasks/ROADMAP\.md|tasks/AUDIT\.md)$")


def remote_tip(repo, branch):
    """The branch's tip on origin (fetched), or None when it does not exist."""
    if repo.git("ls-remote", "--exit-code", "origin", "refs/heads/" + branch, check=False).returncode != 0:
        return None
    ref = "refs/land/aside/%s" % branch
    repo.git("fetch", "-q", "origin", "+refs/heads/%s:%s" % (branch, ref))
    return repo.git("rev-parse", ref).stdout.strip()


def branch_pr_state(repo, branch, told=None):
    """'open', 'merged' or 'closed' for the newest PR from `branch`, 'none'
    when it has none, None when that cannot be known. Without gh the caller
    can tell it (--pr-state, read with the session's GitHub tooling)."""
    if told:
        return told
    if not gh_ok():
        return None
    r = run(["gh", "pr", "list", "--head", branch, "--state", "all", "--limit", "1",
             "--json", "number,state,url"], cwd=repo.top, check=False)
    try:
        rows = json.loads(r.stdout) if r.returncode == 0 else None
    except ValueError:
        rows = None
    if rows is None:
        return None
    return str(rows[0].get("state") or "").lower() if rows else "none"


def aside_start(repo, branch, base, touched, told=None):
    """(tip, start, superseded, state). `start` is what the new commit is
    built on: the branch brought up to date with the trunk, or the trunk
    when there is no branch or its PR is over (merged, or closed without
    merging: its content is not carried forward)."""
    tip = remote_tip(repo, branch)
    if not tip:
        return None, base, False, None
    state = branch_pr_state(repo, branch, told)
    if state in ("merged", "closed") or repo.is_ancestor(tip, base):
        return tip, base, True, state
    if state is None:
        say("pr_state=unknown (no gh): %s is treated as an open PR. If its PR is already merged or closed, run again with "
            "--pr-state merged (or closed); read it with the session's GitHub tooling" % branch)
    return tip, merge_trunk_into(repo, tip, base, touched), False, state


def aside_file(repo, branch):
    """Per worktree: two sessions in two worktrees never share a base."""
    return os.path.join(repo.git_dir, "land-aside", branch.replace("/", "__") + ".json")


def load_aside(repo, branch):
    """{path: {"blob", "head", "data"}}: the copy each file started from, and
    HEAD's copy when that was recorded."""
    try:
        d = json.load(open(aside_file(repo, branch), encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return {p: e for p, e in (d.get("files") or {}).items() if isinstance(e, dict)}


def save_aside(repo, branch, entries):
    """entries: {path: (blob|None, head_blob|None)}. The content goes into the
    record too (small files), so a gc that prunes a loose blob loses nothing."""
    import base64
    files = {}
    for p, (blob, head) in entries.items():
        e = {"blob": blob, "head": head, "data": None}
        if blob:
            size = repo.git("cat-file", "-s", blob, check=False).stdout.strip()
            if size.isdigit() and int(size) <= (1 << 20):
                e["data"] = base64.b64encode(git_bytes(repo, "cat-file", "blob", blob).stdout).decode()
        files[p] = e
    f = aside_file(repo, branch)
    os.makedirs(os.path.dirname(f), exist_ok=True)
    with open(f + ".tmp", "w", encoding="utf-8") as fh:
        json.dump({"branch": branch, "files": files}, fh)
    os.replace(f + ".tmp", f)


def record_base(repo, entry, head_blob):
    """The recorded start copy, when it still describes this checkout: HEAD's
    copy is the one it was recorded against, or the recorded copy itself
    (it was committed since). None otherwise — HEAD moved under it."""
    import base64
    if not entry or head_blob not in (entry.get("head"), entry.get("blob")):
        return None, False
    blob = entry.get("blob")
    if blob is None:
        return None, True
    if repo.git("cat-file", "-e", blob, check=False).returncode != 0:
        if not entry.get("data"):
            return None, False
        back = git_bytes(repo, "hash-object", "-w", "--stdin",
                         input_bytes=base64.b64decode(entry["data"])).stdout.decode().strip()
        if back != blob:
            return None, False
    return blob, True


def merge3(repo, base_blob, ours_blob, theirs_blob, union=False):
    """git merge-file over three blobs (None = empty). The merged blob, or
    None when they conflict."""
    data = [git_bytes(repo, "cat-file", "blob", b).stdout if b else b""
            for b in (base_blob, ours_blob, theirs_blob)]
    out = merge_bytes(repo, data[0], data[1], data[2], union=union)
    if out is None:
        return None
    return git_bytes(repo, "hash-object", "-w", "--stdin", input_bytes=out).stdout.decode().strip()


def merge_bytes(repo, base, ours, theirs, union=False):
    """The three-way merge of three versions of a file (bytes), or None when
    they conflict. With `union` (an append-only file: the inbox, the notes
    index), a conflict where both sides only added lines at one place keeps
    both additions, when that loses and doubles nothing (union_safe)."""
    d = tempfile.mkdtemp(prefix="land-m3-", dir=repo.state)
    try:
        names = []
        for name, data in (("ours", ours), ("base", base), ("theirs", theirs)):
            names.append(os.path.join(d, name))
            with open(names[-1], "wb") as fh:
                fh.write(data)
        # The plain conflict style whatever the user's merge.conflictStyle: a
        # union under diff3 style repeats what both sides added alike.
        plain = ("-c", "merge.conflictStyle=merge", "merge-file", "-p")
        r = git_bytes(repo, *(plain + tuple(names)), check=False)
        if r.returncode == 0:
            return r.stdout
        if not (union and 0 < r.returncode < 128 and union_safe(repo, names, base, ours, theirs)):
            return None
        r = git_bytes(repo, *(plain + ("--union",) + tuple(names)), check=False)
        if r.returncode != 0 or doubled(r.stdout, base, ours, theirs):
            return None
        return r.stdout
    finally:
        shutil.rmtree(d, ignore_errors=True)


# The records of the append-only files: an inbox message (`### `#0001``), a
# notes-index row (its link to the note). Two versions of one record are an
# edit, never two records.
RECORD_KEYS = (re.compile(r"^###\s+`#(\d+)`"), re.compile(r"\]\(([^)\s]+\.md)\)"))


def union_safe(repo, names, base, ours, theirs):
    """A union of the conflicts in the merge of `names` (ours, base, theirs)
    keeps everything and doubles nothing: in every conflict both sides only
    added lines at one place (no line of the base is in it: an edit or a
    removal next to the other side's addition is not an append, and a union
    would keep both the old and the new line), and no record was added by
    both sides in different versions (an inbox status flip on one side, the
    unflipped message on the other). Edits elsewhere in the file merge as
    usual."""
    size = 7  # conflict markers longer than any line of the file starts with
    for text in (base, ours, theirs):
        for line in text.splitlines():
            c = line[:1]
            if c in (b"<", b"|", b"=", b">"):
                size = max(size, len(line) - len(line.lstrip(c)) + 1)
    r = git_bytes(repo, "merge-file", "-p", "--diff3", "--marker-size=%d" % size, *names, check=False)
    if not 0 < r.returncode < 128:
        return False
    mark = dict((c, c * size) for c in (b"<", b"|", b"=", b">"))
    part = None  # outside a conflict, or the side of it being read
    for line in r.stdout.splitlines():
        if part is None:
            part = "ours" if line.startswith(mark[b"<"]) else None
        elif part == "ours":
            part = "base" if line.startswith(mark[b"|"]) else "ours"
        elif part == "base":
            if not line.startswith(mark[b"="]):
                return False  # a line of the base is in this conflict
            part = "theirs"
        elif line.startswith(mark[b">"]):
            part = None
    if part is not None:
        return False
    old = set(base.splitlines())

    def added(side):
        keys = {}
        for line in side.splitlines():
            if line in old:
                continue
            text = line.decode("utf-8", "replace")
            for rx in RECORD_KEYS:
                m = rx.search(text)
                if m:
                    keys.setdefault(m.group(1), set()).add(line)
        return keys

    a, b = added(ours), added(theirs)
    return all(a[k] == b[k] for k in set(a) & set(b))


def doubled(merged, base, ours, theirs):
    """True when `merged` holds a line more often than either side does, or
    than both sides' additions together: a union that wrote a line of the
    base twice (git joins conflicts separated only by lines with no letter
    or digit, a blank line, a rule, and a union repeats those lines)."""
    import collections
    m, b, o, t = (collections.Counter(x.splitlines()) for x in (merged, base, ours, theirs))
    return any(n > max(o[v], t[v], o[v] + t[v] - b[v]) for v, n in m.items())


def resolve_appends(repo, sc, path):
    """In a scratch merge, settle a conflict in an append-only file (the
    inbox, the notes index) when both sides only added lines where they
    clash. False leaves the conflict standing."""
    rel = repo.rel(path)
    if not rel or not UNION_PATHS.match(rel):
        return False
    stages = {}
    for line in sc.git("ls-files", "-u", "-z", "--", path, check=False).stdout.split("\0"):
        if not line.strip():
            continue
        meta, _name = line.split("\t", 1)
        _mode, sha, stage = meta.split()
        stages[stage] = sha
    if "2" not in stages or "3" not in stages:
        return False
    blob = lambda k: git_bytes(repo, "cat-file", "blob", stages[k]).stdout if k in stages else b""
    out = merge_bytes(repo, blob("1"), blob("2"), blob("3"), union=True)
    if out is None:
        return False
    with open(os.path.join(sc.path, path), "wb") as fh:
        fh.write(out)
    sc.git("add", "--", path)
    return True


def fork_point(repo, base):
    head = repo.head()
    if not head:
        return None
    r = repo.git("merge-base", head, base, check=False)
    return r.stdout.strip() or None


def resolve_aside(repo, paths, start, branch, base, where=None):
    """[(path, (mode, blob) | None)] the aside branch must change."""
    rec = load_aside(repo, branch)
    fp = fork_point(repo, base)
    head = repo.head()
    where = where or branch
    out = []
    for p in paths:
        tp = repo.top_path(p)
        w = wt_entry(repo, tp)
        W = w[1] if w else None
        O = repo.blob_at(start, tp)
        B, ok = record_base(repo, rec.get(p), repo.blob_at(head, tp) if head else None)
        if not ok:
            B = repo.blob_at(fp, tp) if fp else None
        if W == O or W == B:
            continue  # nothing of this checkout's to add: the copy there stays
        if O == B:
            out.append((p, w))  # only this checkout changed it
            continue
        if W is None or O is None:
            raise Stop(CONFLICT, "%s: %s and this checkout both changed it, one of them by deleting it. Nothing was pushed. "
                       "Run `land.sh pending` to start from that copy (yours is kept aside), redo the change, then run this again." % (p, where))
        merged = merge3(repo, B, O, W, union=bool(UNION_PATHS.match(p)))
        if merged is None:
            raise Stop(CONFLICT, "%s: %s has changes this checkout never saw, on the same lines as yours. Nothing was pushed. "
                       "Run `land.sh pending` to start from that copy (yours is kept aside), redo the change, then run this again." % (p, where))
        say("combined=%s (with changes on %s that this checkout had not seen)" % (p, where))
        out.append((p, (w[0], merged)))
    return out


def commit_aside(repo, start, changes, message, extra_parent=None):
    """A commit on `start` with `changes` applied (a merge with
    `extra_parent` first when the branch is carried over a finished PR). None
    when it would change nothing."""
    env = repo.identity_env(scratch=True)
    idx = tempfile.NamedTemporaryFile(prefix="land-idx-", dir=repo.state, delete=False)
    idx.close()
    env["GIT_INDEX_FILE"] = idx.name
    try:
        g = lambda *a, **k: run(["git", "-C", repo.top] + list(a), env=env, **k)
        g("read-tree", start)
        for p, entry in changes:
            tp = repo.top_path(p)
            if entry is None:
                g("update-index", "--force-remove", "--", tp)
            else:
                g("update-index", "--add", "--cacheinfo", "%s,%s,%s" % (entry[0], entry[1], tp))
        tree = g("write-tree").stdout.strip()
        if tree == repo.git("rev-parse", start + "^{tree}").stdout.strip():
            return None
        parents = (["-p", extra_parent] if extra_parent else []) + ["-p", start]
        return g("commit-tree", tree, *parents, "-m", message).stdout.strip()
    finally:
        os.unlink(idx.name)


def restore_checkout(repo, paths):
    """After a rolling push: the content is on the PR branch, so the
    checkout goes back to its own HEAD for these files (a copy is kept in
    the land state). `land.sh pending` brings the PR's copy back."""
    head = repo.head()
    keep = os.path.join(repo.state, "stash", "%s-%s" % (stamp(), os.urandom(2).hex()))
    for p in paths:
        tp = repo.top_path(p)
        full = os.path.join(repo.top, tp)
        if os.path.lexists(full) and not os.path.isdir(full):
            os.makedirs(os.path.dirname(os.path.join(keep, tp)), exist_ok=True)
            shutil.copy2(full, os.path.join(keep, tp), follow_symlinks=False)
        if head and repo.blob_at(head, tp):
            repo.git("checkout", "-q", head, "--", tp)
        else:
            repo.git("rm", "-q", "--cached", "--ignore-unmatch", "--", tp, check=False)
            if os.path.lexists(full):
                os.unlink(full)
    return keep


def check_branch_arg(repo, a):
    """--branch may never name the trunk or a ref: a PR goes to a branch."""
    b = a.branch or ""
    if b and (b.startswith("refs/") or b in protected_names(repo) or b.lstrip("+") != b):
        raise Stop(REFUSED, "--branch %s names the trunk or a ref; a PR goes up on a branch of its own" % b)


def pr_aside(repo, a, base, rolling=False):
    """Build the PR branch away from the checkout, push it, open or update
    the PR. Isolated (from the trunk): the checkout keeps its edits, and
    `land.sh settle --branch <b>` tidies it after the merge. Rolling: the
    checkout is put back to its HEAD for these files."""
    branch = branch_name(a, repo, stable=True)
    paths = []
    for p in a.paths:
        if repo.git("check-ignore", "-q", "--", repo.top_path(p), check=False).returncode == 0:
            say("skipped=%s (ignored by .gitignore)" % p)
            continue
        paths.append(p)
    if not paths:
        say("result=nothing to land")
        return OK
    tip, start, superseded, state = aside_start(repo, branch, base, paths, a.pr_state or None)
    if tip and superseded:
        say("previous=%s (its PR is %s): starting again from %s" % (branch, state or "in the trunk", repo.trunk))
    elif tip:
        say("reusing=%s (brought up to date with %s)" % (branch, repo.trunk))
    where = branch if (tip and not superseded) else repo.trunk
    changes = resolve_aside(repo, paths, start, branch, base, where)
    for p, entry in changes:
        if entry and entry[0] != "120000":
            text = git_bytes(repo, "cat-file", "blob", entry[1]).stdout.decode("utf-8", "replace")
            hit = secret_hit(text)
            if hit:
                raise Stop(REFUSED, "%s looks like it holds a credential (%s); nothing was pushed" % (p, hit))
    msg = a.message or ("%s: %s" % (a.tasks[0], a.title) if a.tasks else "%s: %s" % (a.skill, a.title))
    new = commit_aside(repo, start, changes, msg, extra_parent=tip if superseded else None)
    if new is None:
        new = start
    touched = [p for p, _ in changes]
    if any(p.startswith("tasks/") for p in touched) and new != start:
        gate_commit(repo, new, base, touched)

    def after_push():
        # What each file of this checkout now stands for on the branch — the
        # base of its next change here — and HEAD's copy it stands against.
        head = repo.head()
        hb = lambda p: repo.blob_at(head, repo.top_path(p)) if head else None
        if rolling:
            keep = restore_checkout(repo, paths)
            save_aside(repo, branch, {p: (hb(p), hb(p)) for p in paths})
            return keep
        save_aside(repo, branch, {p: (repo.wt_blob(repo.top_path(p)), hb(p)) for p in paths})
        return None

    if new == base:
        differs = [p for p in paths if repo.wt_blob(repo.top_path(p)) != repo.blob_at(base, repo.top_path(p))]
        if differs:
            # This checkout's copy is what it already proposed on a PR that
            # is over: a PR that is over is not carried forward.
            over = "whose PR is %s" % (state or "in the trunk") if tip else "which is gone from origin"
            say("result=nothing new to propose: %s already went up on %s, %s; a PR that is over is not carried "
                "forward. To propose it again, use a new --title." % (", ".join(differs), branch, over))
        else:
            say("result=nothing to propose: these files match %s" % repo.trunk)
        after_push()
        return OK
    if new != tip:
        try:
            push_ref(repo, new, branch)
        except Stop as exc:
            if exc.code == ERR and re.search(r"non-fast-forward|fetch first|rejected", exc.msg):
                raise Stop(CONFLICT, "the PR branch %s moved while this ran (another session pushed to it). Nothing was lost; run this again." % branch)
            raise
    landed = [[p, repo.blob_at(new, repo.top_path(p))] for p in paths]
    log_row(repo, "pushed", branch=branch, sha=new, skill=a.skill, klass="code", landed=landed, rolling=rolling)
    say("pushed=%s" % branch if new != tip else "unchanged=%s (it already carries these files)" % branch, "head=%s" % new)
    keep = after_push()
    if rolling:
        say("checkout=restored to HEAD for %s (the content is on %s; a copy is in %s; `land.sh pending` brings the PR's copy back)"
            % (", ".join(paths), branch, keep))
    else:
        say("checkout=untouched (you stay on %s; after the merge: land.sh settle --branch %s)" % (repo.branch() or "HEAD", branch))
    return open_code_pr(repo, a, branch, new, base)


def gate_commit(repo, commit, base, touched):
    """The ledger gate for a commit built outside a scratch worktree."""
    with Scratch(repo, base) as sb:
        baseline = check_tasks_errors(os.path.join(sb.path, repo.prefix) if repo.prefix else sb.path)
    with Scratch(repo, commit) as sc:
        gate_tree(sc, repo, touched, baseline)


def pending_source(repo, a, base):
    """(branch, tip, start, superseded, label) for a rolling PR's files."""
    branch = branch_name(a, repo, stable=True)
    tip, start, superseded, state = aside_start(repo, branch, base, a.paths, a.pr_state or None)
    if tip and not superseded:
        label = "the open PR on %s" % branch if state == "open" else "the PR branch %s (its PR state is unknown without gh)" % branch
    else:
        label = repo.trunk
    return branch, tip, start, superseded, label


def cmd_pending(repo, a):
    """Before editing a file a rolling PR carries: bring the PR's copy into
    the checkout (or the trunk's, when there is no open PR), merged with any
    uncommitted changes of yours. When those overlap it, your copy is kept
    aside (its path is printed) and the PR's copy is brought in, so the edit
    can be redone on it. Recorded for this worktree, so the next
    `land.sh pr --rolling` knows what the edit started from."""
    with Lock(repo):
        base = repo.fetch_trunk()
        branch, tip, start, superseded, source = pending_source(repo, a, base)
        head = repo.head()
        entries, kept = {}, []
        for p in a.paths:
            tp = repo.top_path(p)
            full = os.path.join(repo.top, tp)
            S = repo.blob_at(start, tp)
            W = repo.wt_blob(tp)
            H = repo.blob_at(head, tp) if head else None
            entries[p] = (S, H)
            if W == S:
                say("file=%s (already %s's copy)" % (p, source))
                continue
            if S == H:
                say("file=%s (kept: your copy already has everything %s has)" % (p, source))
                entries[p] = (H, H)
                continue
            how = "from %s" % source
            S_write = S
            if W != H:
                merged = merge3(repo, H, S, W, union=bool(UNION_PATHS.match(p))) if W is not None else None
                if merged is not None:
                    S_write, how = merged, "merged with your uncommitted changes"
                elif W is None:
                    kept.append((p, None))
                    how = "from %s; you had deleted it, and the copy there changed since" % source
                else:
                    keep = os.path.join(repo.state, "stash", "pending-%s-%s" % (stamp(), os.urandom(2).hex()), tp)
                    os.makedirs(os.path.dirname(keep), exist_ok=True)
                    shutil.copy2(full, keep, follow_symlinks=False)
                    kept.append((p, keep))
                    how = "from %s; your uncommitted copy overlapped it and is kept at %s" % (source, keep)
            if S_write is None:
                if os.path.lexists(full):
                    os.unlink(full)
            else:
                os.makedirs(os.path.dirname(full) or ".", exist_ok=True)
                with open(full, "wb") as fh:
                    fh.write(git_bytes(repo, "cat-file", "blob", S_write).stdout)
            say("file=%s (%s)" % (p, how))
        save_aside(repo, branch, entries)
        say("pending=%s" % branch, "source=%s" % ("pr" if tip and not superseded else "trunk"))
        if kept:
            say("next=redo your change on the copy now in the checkout (yours: %s), then run land.sh pr again" %
                ", ".join(k or "%s, deleted" % p for p, k in kept))
        return OK


def cmd_show(repo, a):
    """Print the copy a rolling PR holds (or the trunk's), without touching
    the checkout: for reading what is waiting to merge."""
    with Lock(repo):
        base = repo.fetch_trunk()
        branch, tip, start, superseded, source = pending_source(repo, a, base)
    for p in a.paths:
        blob = repo.blob_at(start, repo.top_path(p))
        say("==> %s (%s)" % (p, source))
        if blob:
            sys.stdout.flush()
            out = getattr(sys.stdout, "buffer", None)
            data = git_bytes(repo, "cat-file", "blob", blob).stdout
            if out is not None:
                out.write(data)
                out.flush()
            else:
                sys.stdout.write(data.decode("utf-8", "replace"))
    return OK


def cmd_pr(repo, a):
    """Code-class landing: commit, sync with the trunk, push, open a PR.
    Never merges. From the trunk the branch is built in isolation unless
    --switch asks to move the checkout onto it."""
    op = repo.op_in_progress()
    if op:
        raise Stop(REFUSED, "a git operation is in progress (%s); finish it first" % op)
    for p in a.paths:
        if os.path.isdir(os.path.join(repo.root, p)):
            raise Stop(USAGE, "%s is a directory; name the files" % p)
        full = os.path.join(repo.root, p)
        if os.path.isfile(full):
            try:
                hit = secret_hit(open(full, encoding="utf-8", errors="replace").read())
            except OSError:
                hit = None
            if hit:
                raise Stop(REFUSED, "%s looks like it holds a credential (%s); nothing was committed" % (p, hit))
    with Lock(repo):
        base = repo.fetch_trunk()
        cur = repo.branch()
        head = repo.head()
        tps = [repo.top_path(p) for p in a.paths]
        on_trunk = (cur == repo.trunk) or not cur
        if a.rolling:
            return pr_aside(repo, a, base, rolling=True)
        if on_trunk and not a.switch:
            return pr_aside(repo, a, base)
        env = repo.identity_env()
        branch = cur
        if on_trunk:
            branch = branch_name(a, repo)
            carry = head is not None and not repo.is_ancestor(head, base)
            if carry:
                # Local trunk commits origin does not have: they ride this
                # branch into the PR, and the trunk goes back to origin.
                r = repo.git("switch", "-q", "-c", branch, "--no-track", check=False)
                if r.returncode != 0:
                    raise Stop(REFUSED, "could not cut %s: %s" % (branch, (r.stderr or "").strip()[:200]))
                if cur == repo.trunk:
                    repo.git("branch", "-f", repo.trunk, base)
                n = repo.git("rev-list", "--count", "%s..%s" % (base, head)).stdout.strip()
                say("branch=%s cut from your %s, carrying its %s commit(s) not on origin; %s is back at origin/%s"
                    % (branch, cur or "HEAD", n, repo.trunk if cur == repo.trunk else "HEAD", repo.trunk))
            else:
                overlap = []
                if head:
                    changed = set(repo.git("diff", "--name-only", head, base).stdout.split())
                    all_dirty = set(repo.git("diff", "--name-only", "HEAD").stdout.split()) | \
                        set(repo.git("ls-files", "--others", "--exclude-standard").stdout.split())
                    overlap = sorted(changed & all_dirty)
                if overlap:
                    raise Stop(REFUSED, "the trunk moved under uncommitted files: %s. Run land.sh pr without --switch, or sync first." % ", ".join(overlap[:6]))
                r = repo.git("switch", "-q", "-c", branch, "--no-track", base, check=False)
                if r.returncode != 0:
                    raise Stop(REFUSED, "could not cut %s from %s: %s" % (branch, repo.trunk, (r.stderr or "").strip()[:200]))
                say("branch=%s cut from %s (%s), carrying your changes" % (branch, repo.trunk, base[:12]))
        head = repo.head()
        dirty = [tp for tp in tps if repo.wt_blob(tp) != (repo.blob_at(head, tp) if head else None)]
        msg = a.message or ("%s: %s" % (a.tasks[0], a.title) if a.tasks else "%s: %s" % (a.skill, a.title))
        if dirty:
            repo.git("add", "--", *tps)
            r = repo.git("commit", "-q", "-m", msg, "--only", "--", *tps, check=False, env=env)
            if r.returncode != 0:
                raise Stop(ERR, "commit failed: %s" % (r.stderr or r.stdout).strip()[:300])
            say("committed=%s" % repo.git("rev-parse", "--short", "HEAD").stdout.strip())
        elif head and repo.is_ancestor(head, base):
            raise Stop(REFUSED, "nothing to land: the named files match %s and the branch adds nothing" % repo.trunk)
        # Someone else may have pushed to this branch (/peer-review and
        # /auto-merge bring the trunk in with sync-pr): take theirs first, by
        # a merge, so the push is a fast-forward.
        if repo.git("ls-remote", "--exit-code", "origin", "refs/heads/" + branch, check=False).returncode == 0:
            repo.git("fetch", "-q", "origin", "+refs/heads/%s:refs/remotes/origin/%s" % (branch, branch))
            theirs = "refs/remotes/origin/%s" % branch
            if not repo.is_ancestor(theirs, "HEAD"):
                r = repo.git("merge", "-q", "--no-edit", theirs, check=False, env=env)
                if r.returncode != 0:
                    conflicted = repo.git("diff", "--name-only", "--diff-filter=U", check=False).stdout.split()
                    if os.path.exists(os.path.join(repo.git_dir, "MERGE_HEAD")):
                        repo.git("merge", "--abort", check=False)
                    raise Stop(CONFLICT if conflicted else ERR,
                               "origin/%s has commits that conflict with yours (%s). Your commit is on %s; merge origin/%s by hand and re-run."
                               % (branch, ", ".join(conflicted) or (r.stderr or r.stdout).strip()[:160], branch, branch))
                say("took=the commits pushed to %s elsewhere" % branch)
        if not repo.is_ancestor(base, repo.head()):
            r = repo.git("merge", "-q", "--no-edit", base, check=False, env=env)
            if r.returncode != 0:
                conflicted = repo.git("diff", "--name-only", "--diff-filter=U", check=False).stdout.split()
                if os.path.exists(os.path.join(repo.git_dir, "MERGE_HEAD")):
                    repo.git("merge", "--abort", check=False)
                raise Stop(CONFLICT if conflicted else ERR,
                           "%s could not take the latest %s (%s). Your commit is on %s; resolve by hand and re-run."
                           % (branch, repo.trunk, ", ".join(conflicted) or (r.stderr or r.stdout).strip()[:160], branch))
            say("synced=%s now contains %s" % (branch, repo.trunk))
        r = repo.git("push", "-q", "-u", "origin", "HEAD:refs/heads/%s" % branch, check=False)
        if r.returncode != 0:
            err = (r.stderr or r.stdout).strip()
            if ENV_REFUSAL.search(err):
                raise Stop(ENVREFUSED, "the remote or this environment refused the push to %s: %s. Your commit is safe on %s locally."
                           % (branch, err[:200], branch))
            raise Stop(ERR, "push failed: %s" % err[:300])
        tip = repo.git("rev-parse", "HEAD").stdout.strip()
        log_row(repo, "pushed", branch=branch, sha=tip, skill=a.skill, klass="code")
        say("pushed=%s" % branch, "head=%s" % tip)
        return open_code_pr(repo, a, branch, tip, base)


def cmd_auto(repo, a, cfg):
    """Split a skill's outputs by class: docs land, code goes by PR."""
    imports = repo.imports()
    docs, code = [], []
    for p in a.paths:
        full = os.path.join(repo.root, p)
        mode = wt_mode(full) if os.path.lexists(full) else None
        (docs if classify(p, imports, mode)[0] == "docs" else code).append(p)
    say("docs_paths=%s" % " ".join(docs), "code_paths=%s" % " ".join(code))
    worst = OK
    if docs:
        a.paths = docs
        try:
            worst = max(worst, land_docs(repo, a, cfg))
        except Stop as s:
            say("docs_result=exit %d: %s" % (s.code, s.msg))
            worst = max(worst, s.code)
    if code:
        a.paths = code
        try:
            worst = max(worst, cmd_pr(repo, a))
        except Stop as s:
            say("code_result=exit %d: %s" % (s.code, s.msg))
            worst = max(worst, s.code)
    return worst


def cmd_status(repo):
    say("trunk=%s" % repo.trunk, "install=%s" % repo.root, "prefix=%s" % (repo.prefix or "(top)"))
    hooks_dir = repo.git("rev-parse", "--git-path", "hooks").stdout.strip()
    pp = os.path.join(repo.top, hooks_dir, "pre-push") if not os.path.isabs(hooks_dir) else os.path.join(hooks_dir, "pre-push")
    layer = "installed" if os.path.exists(pp) and PREPUSH_BEGIN in open(pp, encoding="utf-8", errors="replace").read() else "ABSENT"
    hp = repo.git("config", "core.hooksPath", check=False).stdout.strip()
    say("guard_prepush=%s%s" % (layer, (" (core.hooksPath=%s)" % hp) if hp else ""))
    have_hooks = land_hook_commands(repo.root)
    missing = sorted(set(["guard-bash", "guard-edit", "guard-mcp", "session"]) - have_hooks)
    say("guard_claude_hooks=%s" % ("installed" if not missing else "ABSENT: " + ", ".join(missing)))
    lock = os.path.join(repo.state, "lock", "owner")
    if os.path.exists(lock):
        say("lock=%s" % open(lock, encoding="utf-8", errors="replace").read().strip())
    for r in inflight(repo):
        say("inflight=%s class=%s pr=%s state=%s since=%s" % (r.get("branch"), r.get("klass") or "?", r.get("pr") or "-",
                                                              r.get("event"), r.get("at")))
    if gh_ok():
        r = run(["gh", "api", "repos/{owner}/{repo}/rules/branches/%s" % repo.trunk], cwd=repo.top, check=False)
        if r.returncode == 0:
            try:
                rules = json.loads(r.stdout)
            except ValueError:
                rules = []
            kinds = sorted({x.get("type") for x in rules if isinstance(x, dict)})
            say("trunk_rules=%s" % (",".join(kinds) or "none"))
            if "pull_request" not in kinds:
                say("advice=the trunk accepts direct pushes on the server. A ruleset that requires a pull request closes every path this guard cannot: "
                    "gh api -X POST repos/{owner}/{repo}/rulesets --input <ruleset.json> (see land/SKILL.md)")
    return OK


# ── guards ────────────────────────────────────────────────────────────────

def deny(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "deny",
                                             "permissionDecisionReason": reason}}))
    return OK


def _trunk_for(cwd):
    try:
        r = Repo(cwd)
        return r, r.trunk
    except Stop:
        return None, "main"


def protected_names(repo):
    """Branch names the guard treats as the trunk. Local state is writable
    (`git remote set-head` re-points origin/HEAD), so the set is the union of
    the resolved trunk, the cached one, and main/master — never just one."""
    names = set(["main", "master"])
    if repo is not None:
        names.add(repo.trunk)
        cache = os.path.join(repo.state, "trunk")
        try:
            names.add(open(cache, encoding="utf-8", errors="replace").read().strip())
        except OSError:
            pass
    names.discard("")
    return names


def _dest_branch(ref):
    """Normalise a push destination the way git resolves it."""
    r = ref.lstrip("+")
    if r.startswith("refs/heads/"):
        return r[len("refs/heads/"):]
    if r.startswith("refs/"):
        return None
    if r.startswith("heads/"):
        return r[len("heads/"):]
    return r


WRITEISH = re.compile(r"(>|\brm\b|\bmv\b|\bcp\b|\bchmod\b|\btee\b|sed\s+-i|\bln\b|\binstall\b|\btruncate\b|\bunlink\b|\bdd\b|\bperl\b|\bpython3?\b)")
GUARD_FILES = re.compile(r"\.git/hooks|hooks/pre-push|pre-push\.land-chained|\.git/land|git-dir\)/hooks|git-common-dir\)/hooks|git-path hooks")
SHELL_OPS = set(["&&", "||", ";", "|", "&", "(", ")", ";;", "|&", "\n"])
# Commands that run another command: the real one follows them.
WRAPPERS = set(["command", "exec", "env", "nohup", "time", "timeout", "nice", "ionice", "sudo", "doas",
                "xargs", "stdbuf", "chronic", "caffeinate", "setsid", "flock"])
# git commit options that take a value, so the value is never read as flags.
COMMIT_VALUED = set(["-m", "-F", "-C", "-c", "-t", "--message", "--file", "--author", "--date",
                     "--template", "--reuse-message", "--reedit-message", "--fixup", "--squash",
                     "--cleanup", "--trailer", "-S", "--gpg-sign"])


def _strip_heredocs(cmd):
    """Drop heredoc bodies: they are data, not arguments."""
    out, lines, i = [], cmd.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        tags = re.findall(r"<<-?\s*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?", line)
        i += 1
        for tag in tags:
            while i < len(lines) and lines[i].strip() != tag:
                i += 1
            i += 1
    return "\n".join(out)


def _segments(cmd):
    """Shell-split a command line into simple-command token lists.
    None when it cannot be split (unbalanced quotes)."""
    import shlex
    try:
        lex = shlex.shlex(_strip_heredocs(cmd), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        return None
    segs, cur = [], []
    for t in toks:
        if t in SHELL_OPS or (t and set(t) <= set(";&|()")):
            if cur:
                segs.append(cur)
            cur = []
        else:
            cur.append(t)
    if cur:
        segs.append(cur)
    out = []
    for seg in segs:
        # Commands run through another shell or eval are checked too.
        name = os.path.basename(seg[0]) if seg else ""
        if name in ("bash", "sh", "zsh", "dash", "ksh") and "-c" in seg:
            i = seg.index("-c")
            if i + 1 < len(seg):
                inner = _segments(seg[i + 1])
                if inner is None:
                    return None
                out += inner
                continue
        if name == "eval":
            inner = _segments(" ".join(seg[1:]))
            if inner is None:
                return None
            out += inner
            continue
        out.append(seg)
    return out


def _find_cmd(seg, name):
    """Index of the token that runs `name` (git, gh) in a segment, looking
    past assignments, wrappers and their options; None if absent."""
    i = 0
    while i < len(seg):
        t = seg[i]
        base = os.path.basename(t)
        if base == name:
            return i
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t) or t.startswith("-") or base in WRAPPERS or re.match(r"^\d+[smhd]?$", t):
            i += 1
            continue
        return None
    return None


def _git_call(seg):
    """(global_opts, subcommand, args) for a git invocation in `seg`, or None."""
    i = _find_cmd(seg, "git")
    if i is None:
        return None
    i += 1
    gopts = []
    while i < len(seg) and seg[i].startswith("-"):
        t = seg[i]
        if t in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env") and i + 1 < len(seg):
            gopts += [t, seg[i + 1]]
            i += 2
            continue
        gopts.append(t)
        i += 1
    if i >= len(seg):
        return gopts, "", []
    return gopts, seg[i], seg[i + 1:]


def _short_flags(args, valued):
    """Letters of short-flag clusters, skipping the values of valued options."""
    letters, skip = "", False
    for t in args:
        if skip:
            skip = False
            continue
        if t == "--":
            break
        if t in valued:
            skip = True
            continue
        if t.startswith("-") and not t.startswith("--") and len(t) > 1:
            for ch in t[1:]:
                letters += ch
                if "-" + ch in valued:
                    break
    return letters


def _is_no_verify(tok):
    return len(tok) >= 5 and "--no-verify".startswith(tok) and tok.startswith("--no-v")


def _switch_target(sub, args):
    """The branch `git checkout`/`git switch` moves to, when it says so; None
    for a file checkout or anything unclear (the pre-push hook still sees the
    real destination of a later push)."""
    create = ("-b", "-B", "--orphan") if sub == "checkout" else ("-c", "-C", "--create", "--force-create", "--orphan")
    for i, t in enumerate(args):
        if t == "--":
            return None
        if t in create and i + 1 < len(args):
            return args[i + 1]
        for c in create:
            if c.startswith("--") and t.startswith(c + "="):
                return t.split("=", 1)[1]
    pos = [t for t in args if not t.startswith("-")]
    if len(pos) == 1 and "--" not in args:
        return pos[0]
    return None


def cmd_guard_bash(stdin_text):
    """PreToolUse on Bash. The pre-push hook is what sees a push's real
    destination; this denies the ways around it, plus the direct pushes it
    can read, so a refusal comes before the network."""
    try:
        payload = json.loads(stdin_text or "{}")
    except ValueError:
        return OK
    cmd = ((payload.get("tool_input") or {}).get("command") or "")
    cwd = payload.get("cwd") or os.getcwd()
    why = _bash_reason(cmd, cwd)
    return deny(why) if why else OK


KNOWN_GIT = set("""add am apply archive bisect blame branch bundle cat-file check-ignore checkout cherry cherry-pick
clean clone commit commit-tree config count-objects describe diff diff-tree fetch for-each-ref format-patch fsck gc
grep hash-object help init interpret-trailers log ls-files ls-remote ls-tree maintenance merge merge-base merge-file
mktree mv name-rev notes prune pull push range-diff read-tree rebase reflog remote repack replace reset restore
rev-list rev-parse revert rm send-pack shortlog show show-ref sparse-checkout stash status submodule switch
symbolic-ref tag update-index update-ref var verify-commit version whatchanged worktree write-tree""".split())


def _expand_alias(sub, args, gopts, cwd):
    """A git alias, inline (-c alias.X=...) or configured: ("git", sub, args)
    or ("shell", text); None when `sub` is no alias."""
    val = ""
    for k in range(len(gopts) - 1):
        if gopts[k] == "-c" and gopts[k + 1].lower().startswith("alias.%s=" % sub.lower()):
            val = gopts[k + 1].split("=", 1)[1]
    if not val:
        try:
            r = run(["git", "-C", cwd, "config", "--get", "alias." + sub], check=False)
            val = r.stdout.strip() if r.returncode == 0 else ""
        except OSError:
            val = ""
    if not val:
        return None
    if val.startswith("!"):
        return ("shell", val[1:])
    import shlex
    try:
        toks = shlex.split(val)
    except ValueError:
        return ("shell", val)
    return ("git", toks[0], toks[1:] + list(args)) if toks else None


def _bash_reason(cmd, cwd, depth=0):
    """Why a Bash command must be refused, or None."""
    body = _strip_heredocs(cmd)
    low = body.lower()
    if re.search(r"alias\.[^\s=]+[\s=]", low) and re.search(r"--no-v|\bcommit\b[^;&|]*\s-[a-z]*n", low):
        return ("Defining a git alias that skips hooks is refused: the trunk guard lives in them.")
    if "git_guard_allow_main" in low:
        return ("GIT_GUARD_ALLOW_MAIN is refused for Claude: the trunk changes only through a merged PR (land.sh docs / land.sh pr).")
    if re.search(r"\bclaudecode\s*=|\benv\b[^;&|]*\s-(u\s*claudecode|i\b|-ignore-environment)|\bunset\b[^;&|]*\bclaudecode\b", low):
        return ("CLAUDECODE tells the trunk guard that Claude is pushing; clearing or overriding it is refused.")
    if re.search(r"git_config_(count|key_\d+|value_\d+|parameters)|--config-env", low):
        return ("Injecting git config through the environment or --config-env can switch off the trunk guard. Refused.")
    if "hookspath" in low and not re.search(r"config\s+(--get|--get-all|--list|-l|--show-origin|--unset|--unset-all)\b", low) \
            and not re.search(r"config\s+core\.hookspath\s*($|[;&|])", low):
        return ("Changing core.hooksPath switches off the trunk guard. Refused.")
    if GUARD_FILES.search(body) and WRITEISH.search(body):
        segs0 = _segments(body) or []
        first = os.path.basename(segs0[0][1]) if segs0 and len(segs0[0]) > 1 and os.path.basename(segs0[0][0]) == "bash" else ""
        if first != "land.sh":
            return ("Writing the git hooks or land.sh's state is refused: the trunk guard lives there.")
    if re.search(r"remote\s+set-head|symbolic-ref\s+(-[a-z-]+\s+)*refs/remotes/|update-ref\s+(-[a-z-]+\s+)*refs/remotes/[^\s]*/head\b", low):
        return ("Re-pointing refs/remotes/*/HEAD changes what the guard treats as the trunk. Refused.")
    segs = _segments(cmd)
    if segs is None:
        if re.search(r"\bgit\b", cmd) and re.search(r"\b(push|send-pack)\b", cmd):
            return ("This command could not be parsed and looks like a git push. Write it plainly (git push origin <branch>).")
        return None
    switched = None  # the branch an earlier part of this command moves to
    for seg in segs:
        gi = _find_cmd(seg, "gh")
        if gi is not None and gi + 1 < len(seg) and seg[gi + 1] == "api":
            text = " ".join(seg[gi:])
            method = re.search(r"(?:-X|--method)[\s=]*([A-Za-z]+)", text)
            writes = (method and method.group(1).upper() != "GET") or \
                re.search(r"(^|\s)(-f|-F|--field|--raw-field|--input)(=|\s|\S)", text)
            if writes and re.search(r"/merges\b|/git/refs|/contents/|/pulls/\d+/merge\b", text):
                return ("Writing the repository through `gh api` (merges, refs, contents) goes around pull requests. Use land.sh or gh pr.")
            if "graphql" in text and re.search(r"createCommitOnBranch|mergeBranch|updateRefs?\b|mergePullRequest", text):
                return ("GraphQL mutations that move a branch go around pull requests. Use land.sh or gh pr.")
            continue
        call = _git_call(seg)
        if call is None:
            continue
        gopts, sub, args = call
        if sub and sub not in KNOWN_GIT and not sub.startswith("-"):
            exp = _expand_alias(sub, args, gopts, cwd)
            if exp and exp[0] == "shell":
                why = _bash_reason(exp[1], cwd, depth + 1) if depth < 3 else None
                if why:
                    return "git alias `%s` runs: %s" % (sub, why)
                continue
            if exp:
                sub, args = exp[1], exp[2]
        for k in range(len(gopts) - 1):
            if gopts[k] in ("-c", "--config-env") and "hookspath" in gopts[k + 1].lower():
                return ("`-c core.hooksPath` switches off the trunk guard. Refused.")
        if sub in ("send-pack", "http-push", "receive-pack") or sub.startswith("remote-"):
            return ("`git %s` updates remote refs without the pre-push hook. Use git push to a branch." % sub)
        if sub in ("commit", "push", "merge", "rebase", "am", "cherry-pick", "revert", "pull") and any(_is_no_verify(t) for t in args):
            return ("--no-verify skips the hooks that keep the trunk PR-only. Refused.")
        if sub == "commit" and "n" in _short_flags(args, COMMIT_VALUED):
            return ("`git commit -n` skips the pre-commit hooks. Refused.")
        if sub in ("checkout", "switch"):
            to = _switch_target(sub, args)
            if to:
                switched = to
            continue
        if sub != "push":
            continue
        opts = [t for t in args if t.startswith("-")]
        pos, skip = [], False
        for t in args:
            if skip:
                skip = False
                continue
            if t in ("-o", "--push-option", "--repo", "--receive-pack", "--exec"):
                skip = True
                continue
            if not t.startswith("-"):
                pos.append(t)
        if "--mirror" in opts or "--all" in opts or "--branches" in opts:
            return ("`git push --all/--mirror` can move the trunk. Push the one branch you mean.")
        if "--tags" in opts and len(pos) <= 1:
            continue  # tags only: the trunk does not move
        repo, _trunk = _trunk_for(cwd)
        names = protected_names(repo)
        if "--delete" in opts or "-d" in opts:
            dests = [_dest_branch(r) for r in pos[1:]]
        else:
            dests = [_dest_branch(r.split(":", 1)[1]) if ":" in r.lstrip("+") else _dest_branch(r) for r in pos[1:]]
        if any(d in names for d in dests if d):
            return ("Pushing to %s is refused: the trunk changes only through a merged PR. Push a branch and open a PR (land.sh pr), or land docs with land.sh docs." % "/".join(sorted(n for n in dests if n in names)))
        cur = switched if switched is not None else (repo.branch() if repo is not None else "")
        if cur in names and (len(pos) <= 1 or any(d in ("HEAD", "@") for d in dests if d)):
            return ("You are on %s: this push would move the trunk. Put the work on a branch (land.sh pr)." % cur)
    return None


def cmd_guard_edit(stdin_text):
    """PreToolUse on file-writing tools: never write git's own directory
    (the hooks, land.sh's state)."""
    try:
        payload = json.loads(stdin_text or "{}")
    except ValueError:
        return OK
    ti = payload.get("tool_input") or {}
    path = ti.get("file_path") or ti.get("notebook_path") or ""
    norm = path.replace("\\", "/")
    if re.search(r"(^|/)\.git(/|$)", norm):
        return deny("Writing inside .git/ is refused: the trunk guard's hooks live there.")
    return OK


def cmd_guard_mcp(stdin_text):
    """PreToolUse on GitHub write tools that commit straight to a branch."""
    try:
        payload = json.loads(stdin_text or "{}")
    except ValueError:
        return OK
    tool = payload.get("tool_name") or ""
    ti = payload.get("tool_input") or {}
    if not re.search(r"__(push_files|create_or_update_file|delete_file)$", tool):
        return OK
    repo, _trunk = _trunk_for(payload.get("cwd") or os.getcwd())
    names = protected_names(repo)
    br = (ti.get("branch") or "").replace("refs/heads/", "")
    if not br or br in names:
        return deny("%s would commit straight to %s. Commit to a branch and open a PR (land.sh pr / land.sh docs)." % (tool.split("__")[-1], br or "the default branch"))
    return OK


def origin_key(url):
    u = (url or "").strip().lower()
    u = re.sub(r"^(https?|ssh|git)://", "", u)
    u = re.sub(r"^[^@/]+@", "", u)
    u = u.replace(":", "/")
    u = re.sub(r"\.git/?$", "", u).rstrip("/")
    parts = u.split("/")
    return "/".join(parts[-2:]) if len(parts) >= 2 else u


def cmd_guard_push(argv, stdin_text):
    """Body of the git pre-push hook: refuse updates of the trunk when Claude
    is the one pushing — on origin, on `upstream`, and on any remote whose URL
    names the same repository. Humans are not constrained here; creating the
    trunk on an empty remote is allowed (the first push). Deploy remotes (a
    different repository) are untouched."""
    if os.environ.get("CLAUDECODE") != "1":
        return OK
    remote = argv[0] if argv else ""
    url = argv[1] if len(argv) > 1 else ""
    try:
        repo = Repo(os.getcwd())
    except Stop:
        return OK
    watched = set()
    for name in ("origin", "upstream"):
        u = repo.git("remote", "get-url", name, check=False).stdout.strip()
        if u:
            watched.add(origin_key(u))
    if remote not in ("origin", "upstream") and origin_key(url or remote) not in watched:
        return OK
    names = protected_names(repo)
    r = repo.git("ls-remote", "--symref", url or remote, "HEAD", check=False)
    m = re.search(r"ref:\s+refs/heads/(\S+)\s+HEAD", r.stdout or "")
    if m:
        names.add(m.group(1))
    zero = "0" * 40
    for line in (stdin_text or "").splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        _lref, lsha, rref, rsha = parts[:4]
        if not rref.startswith("refs/heads/") or rref[len("refs/heads/"):] not in names:
            continue
        if rsha.strip("0") == "" and lsha != zero and not m:
            continue  # the first push of the trunk to an empty remote
        print("land: refused — this push would move %s on %s. The trunk changes only through a merged PR:" % (rref[11:], remote or url),
              file=sys.stderr)
        print("      land docs with `land.sh docs`, code with `land.sh pr` (or /open-pr).", file=sys.stderr)
        return 1
    return OK


# ── hooks: installation ───────────────────────────────────────────────────

PREPUSH_BEGIN = "# >>> rasa land guard >>>"
PREPUSH_END = "# <<< rasa land guard <<<"


def _prepush_block(land_sh, root):
    """The managed block. It keeps stdin byte-exact for whatever runs after
    it (other hooks' blocks in this file, and chained hooks), finds land.sh
    from the repository when the baked path is gone, and refuses a Claude
    push it cannot check."""
    return "\n".join([
        PREPUSH_BEGIN,
        "# Installed by rasa.domain.code land.sh: refuses Claude pushes that would move",
        "# the trunk. Content outside this block belongs to other tools and is kept.",
        '_land_in="$(mktemp "${TMPDIR:-/tmp}/land-prepush.XXXXXX")" || exit 1',
        'cat > "$_land_in"',
        '_land_sh="%s"' % land_sh,
        '[ -f "$_land_sh" ] || _land_sh="$(git rev-parse --show-toplevel 2>/dev/null)/%s.claude/skills/land/land.sh"' % root,
        'if [ -f "$_land_sh" ]; then',
        '  bash "$_land_sh" guard-push "$@" < "$_land_in" || { rm -f "$_land_in"; exit 1; }',
        'elif [ "${CLAUDECODE:-}" = "1" ]; then',
        '  echo "land: refused — the trunk guard (land.sh) is missing, so this push cannot be checked" >&2',
        '  rm -f "$_land_in"; exit 1',
        "fi",
        'for _land_h in "$(dirname "$0")"/pre-push.land-chained*; do',
        '  [ -x "$_land_h" ] || continue',
        '  "$_land_h" "$@" < "$_land_in" || { _land_rc=$?; rm -f "$_land_in"; exit $_land_rc; }',
        "done",
        'exec < "$_land_in"; rm -f "$_land_in"',
        PREPUSH_END,
    ]) + "\n"


def _chain_aside(hooks, f):
    """Move an existing pre-push (a script in another language, or a
    symlink into the repository) aside as a chained hook, kept whole."""
    n = 0
    chained = os.path.join(hooks, "pre-push.land-chained")
    while os.path.lexists(chained):
        n += 1
        chained = os.path.join(hooks, "pre-push.land-chained.%d" % n)
    os.rename(f, chained)
    return chained


def install_prepush(repo, land_sh):
    """Arm the pre-push layer in this repository's own hooks directory. The
    managed block always sits straight after the shebang, so it reads the
    ref lines before anything else can consume them (it hands the same stdin
    on). Returns (armed: bool, message)."""
    hp = repo.git("config", "core.hooksPath", check=False).stdout.strip()
    if hp:
        full = os.path.realpath(hp if os.path.isabs(hp) else os.path.join(repo.top, hp))
        if full == repo.top or full.startswith(repo.top + os.sep):
            return False, "NOT armed: core.hooksPath=%s is a folder inside the repository (e.g. husky); only the Claude hooks and a server-side ruleset guard the trunk here" % hp
        return False, "NOT armed: core.hooksPath=%s is shared outside this repository; land.sh will not write there (a ruleset on the trunk is the guard)" % hp
    hooks = os.path.join(repo.common, "hooks")
    os.makedirs(hooks, exist_ok=True)
    f = os.path.join(hooks, "pre-push")
    block = _prepush_block(land_sh, repo.prefix)
    note = ""
    if os.path.islink(f):
        # Never write through a link: it usually points at a tracked file.
        chained = _chain_aside(hooks, f)
        note = " (the linked hook runs after it as %s)" % os.path.basename(chained)
    if os.path.exists(f):
        text = open(f, encoding="utf-8", errors="surrogateescape").read()
        first = text.splitlines()[0] if text else ""
        shell = re.match(r"^#!\s*(/usr/bin/env\s+)?(/bin/)?(ba|da|z|k)?sh\b|^#!/bin/sh|^#!/usr/bin/env (ba)?sh", first) \
            or not first.startswith("#!")
        if PREPUSH_BEGIN in text and PREPUSH_END in text:
            rest = re.sub(re.escape(PREPUSH_BEGIN) + r".*?" + re.escape(PREPUSH_END) + r"\n?", "", text, count=1, flags=re.S)
        else:
            rest = text
        if shell:
            body = rest.split("\n", 1)[1] if (rest.startswith("#!")) else rest
            new = (first if first.startswith("#!") else "#!/bin/sh") + "\n" + block + body
        else:
            chained = _chain_aside(hooks, f)
            note = " (the existing hook runs after it as %s)" % os.path.basename(chained)
            new = "#!/bin/sh\n" + block + "exit 0\n"
        if new == text:
            return True, "present"
    else:
        new = "#!/bin/sh\n" + block + "exit 0\n"
    with open(f, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(new)
    os.chmod(f, 0o755)
    return True, "installed at %s%s" % (f, note)


def land_hook_commands(root):
    """The land.sh hook commands registered in .claude/settings.json."""
    path = os.path.join(root, ".claude", "settings.json")
    try:
        d = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        return set()
    found = set()
    for groups in (d.get("hooks") or {}).values():
        for g in groups or []:
            for h in g.get("hooks") or []:
                c = str(h.get("command") or "")
                m = re.search(r"land\.sh[\"']?\s+(guard-bash|guard-edit|guard-mcp|session)\b", c)
                if m:
                    found.add(m.group(1))
    return found


def install_claude_hooks(root):
    path = os.path.join(root, ".claude", "settings.json")
    try:
        d = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
    except ValueError:
        raise Stop(ERR, "%s is not valid JSON; fix it first" % path)
    hooks = d.setdefault("hooks", {})
    changed = []
    # Absolute through CLAUDE_PROJECT_DIR: a guard must still run after a `cd`.
    cmd = 'bash "${CLAUDE_PROJECT_DIR:-.}/.claude/skills/land/land.sh"'
    old_cmd = "bash .claude/skills/land/land.sh"

    for event in list(hooks):
        for g in hooks[event]:
            before = len(g.get("hooks", []))
            g["hooks"] = [h for h in g.get("hooks", []) if not str(h.get("command", "")).startswith(old_cmd + " ")]
            if len(g["hooks"]) != before:
                changed.append("replaced the relative %s land hook" % event)
        hooks[event] = [g for g in hooks[event] if g.get("hooks")]

    def ensure(event, matcher, command):
        groups = hooks.setdefault(event, [])
        for g in groups:
            if g.get("matcher", "") == matcher and any(h.get("command") == command for h in g.get("hooks", [])):
                return
        for g in groups:
            if g.get("matcher", "") == matcher:
                g.setdefault("hooks", []).append({"type": "command", "command": command})
                break
        else:
            groups.append({"matcher": matcher, "hooks": [{"type": "command", "command": command}]})
        changed.append("%s [%s] -> %s" % (event, matcher or "*", command))

    ensure("PreToolUse", "Bash", cmd + " guard-bash")
    ensure("PreToolUse", "Edit|Write|MultiEdit|NotebookEdit", cmd + " guard-edit")
    ensure("PreToolUse", "mcp__.*__(push_files|create_or_update_file|delete_file)", cmd + " guard-mcp")
    ensure("SessionStart", "", cmd + " session")
    if changed:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(d, fh, indent=2)
            fh.write("\n")
        os.replace(tmp, path)
    return changed


EXCLUDE_BEGIN = "# >>> rasa land: this checkout's own state >>>"
EXCLUDE_END = "# <<< rasa land: this checkout's own state <<<"
# Written by the Element for this checkout alone (the active mode, who "me"
# is in the inbox): never part of a commit, so /push and autosave skip them.
CHECKOUT_STATE = (".claude/mode.md", ".claude/mode.md.last", ".claude/mode-stats.md", ".claude/inbox/_me.md")


def ensure_local_excludes(repo):
    """Keep the checkout's own state out of git through .git/info/exclude
    (per clone, never committed), in a managed block. Tracked copies are not
    affected: git never ignores a tracked file."""
    f = repo.git("rev-parse", "--git-path", "info/exclude").stdout.strip()
    f = f if os.path.isabs(f) else os.path.join(repo.top, f)
    block = "\n".join([EXCLUDE_BEGIN] + ["/%s%s" % (repo.prefix, x) for x in CHECKOUT_STATE] + [EXCLUDE_END]) + "\n"
    try:
        text = open(f, encoding="utf-8", errors="surrogateescape").read() if os.path.exists(f) else ""
    except OSError:
        return False
    if block in text:
        return True
    text = re.sub(re.escape(EXCLUDE_BEGIN) + r".*?" + re.escape(EXCLUDE_END) + r"\n?", "", text, flags=re.S)
    if text and not text.endswith("\n"):
        text += "\n"
    os.makedirs(os.path.dirname(f), exist_ok=True)
    with open(f, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(text + block)
    return True


def cmd_hooks(root, land_sh):
    """The Claude hooks need no git; the pre-push layer does. In a folder
    that is not a git repository yet, the SessionStart hook arms it later."""
    for c in install_claude_hooks(root):
        say("hooks: installed " + c)
    try:
        repo = Repo(root)
    except Stop as exc:
        # Deferred, not failed: the session start arms it once there is git.
        say("prepush: deferred: %s. The SessionStart hook arms it once this is a git repository." % exc.msg)
        return OK
    armed, msg = install_prepush(repo, land_sh)
    say("prepush: " + msg)
    ensure_local_excludes(repo)
    return OK if armed else REFUSED


def cmd_session(repo, land_sh):
    """SessionStart: arm the pre-push layer in this clone (fresh cloud
    containers have no .git/hooks), and name landings still in flight.
    Never fails a session."""
    try:
        armed, msg = install_prepush(repo, land_sh)
        if not armed:
            say("land: ⚠ pre-push trunk guard %s" % msg)
    except Exception as exc:  # noqa: BLE001 — a session hook must not fail
        say("land: ⚠ could not arm the pre-push trunk guard: %s" % exc)
    try:
        ensure_local_excludes(repo)
    except Exception:  # noqa: BLE001
        pass
    cfg = load_config(repo)
    rows = inflight(repo)
    docs = [r for r in rows if r.get("klass") == "docs"]
    code = [r for r in rows if r.get("klass") == "code"]
    if docs:
        say("land: %d docs landing(s) not finished:" % len(docs))
        for r in docs[:5]:
            held = docs_mode(cfg, r.get("skill") or skill_of(r.get("branch") or "")) == "pr"
            nxt = "held for a person (.claude/landing.json)" if held else \
                "land.sh merge --pr <N> --sha %s" % (r.get("sha") or "")
            say("  %s  PR %s  (%s since %s) → %s" %
                (r.get("branch"), r.get("pr") or "not opened", r.get("event"), r.get("at"), nxt))
    if code:
        # One bounded read of the remote's branches: a code row whose branch
        # is gone (merged and deleted, or closed) is closed in the log.
        try:
            r = repo.git("ls-remote", "--heads", "origin", check=False, timeout=15,
                         env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
            heads = set(l.split("refs/heads/", 1)[1] for l in r.stdout.splitlines() if "refs/heads/" in l) \
                if r.returncode == 0 else None
        except (subprocess.TimeoutExpired, OSError):
            heads = None
        if heads is not None:
            for row in code:
                if row.get("branch") not in heads:
                    log_row(repo, "closed", branch=row.get("branch"), klass="code")
            code = [row for row in code if row.get("branch") in heads]
        if code:
            say("land: %d code PR branch(es) pushed from here are still open; a reviewer merges them (land.sh status lists them)" % len(code))
    return OK


# ── argument parsing (kept tiny; land.sh validates the verb) ──────────────

class Args(object):
    pass


def parse(argv):
    a = Args()
    a.skill, a.title, a.summary, a.tasks, a.wait = "manual", "", "", [], None
    a.paths, a.pr, a.sha, a.branch, a.checks_json = [], None, "", "", []
    a.draft, a.verified, a.risk, a.message, a.fetch_only, a.push = False, "", "", "", False, False
    a.switch, a.pr_json, a.rolling, a.pr_state = False, "", False, ""
    i = 0
    while i < len(argv):
        t = argv[i]
        if t == "--":
            a.paths += argv[i + 1:]
            break
        val = argv[i + 1] if i + 1 < len(argv) else None
        if t in ("--skill", "--title", "--summary", "--tasks", "--wait", "--pr", "--sha", "--branch",
                 "--checks-json", "--verified", "--risk", "--message", "--pr-json", "--pr-state"):
            if val is None:
                raise Stop(USAGE, "%s needs a value" % t)
            if t == "--tasks":
                a.tasks = [x for x in re.split(r"[\s,]+", val) if x]
                bad = [x for x in a.tasks if not re.match(r"^[A-Z][A-Z0-9]*-\d+$", x)]
                if bad:
                    raise Stop(USAGE, "not task ids: %s" % " ".join(bad))
            elif t == "--wait":
                if not val.isdigit():
                    raise Stop(USAGE, "--wait takes whole seconds")
                a.wait = int(val)
            elif t == "--pr":
                if not val.lstrip("#").isdigit():
                    raise Stop(USAGE, "--pr takes a number")
                a.pr = int(val.lstrip("#"))
            elif t == "--sha":
                if not re.match(r"^[0-9a-f]{40}$", val):
                    raise Stop(USAGE, "--sha takes a full 40-character commit id")
                a.sha = val
            elif t == "--checks-json":
                a.checks_json.append(val)
            elif t == "--pr-state":
                if val.lower() not in ("open", "closed", "merged", "none"):
                    raise Stop(USAGE, "--pr-state takes open, closed, merged or none")
                a.pr_state = val.lower()
            elif t == "--skill":
                if not re.match(r"^[a-z0-9][a-z0-9-]*$", val):
                    raise Stop(USAGE, "--skill takes a skill name like audit")
                a.skill = val
            else:
                setattr(a, t[2:].replace("-", "_"), val)
            i += 2
            continue
        if t == "--draft":
            a.draft = True
        elif t == "--switch":
            a.switch = True
        elif t == "--rolling":
            a.rolling = True
        elif t == "--fetch-only":
            a.fetch_only = True
        elif t == "--push":
            a.push = True
        elif t.startswith("-"):
            raise Stop(USAGE, "unknown flag: %s" % t)
        else:
            a.paths.append(t)
        i += 1
    norm = []
    for p in a.paths:
        q = p[2:] if p.startswith("./") else p
        norm.append(q)
    a.paths = norm
    return a


def main(argv):
    if not argv:
        raise Stop(USAGE, "no verb")
    verb, rest = argv[0], argv[1:]
    land_sh = os.path.join(HERE, "land.sh")
    if verb == "guard-bash":
        return cmd_guard_bash(sys.stdin.read())
    if verb == "guard-mcp":
        return cmd_guard_mcp(sys.stdin.read())
    if verb == "guard-edit":
        return cmd_guard_edit(sys.stdin.read())
    if verb == "guard-push":
        return cmd_guard_push(rest, sys.stdin.read())
    root = os.environ.get("LAND_ROOT") or os.getcwd()
    if verb == "classify":
        a = parse(rest)
        if not a.paths:
            raise Stop(USAGE, "classify needs paths")
        try:
            repo = Repo(root)
        except Stop:
            repo = None
        return cmd_classify(repo, a.paths)
    if verb == "hooks":
        return cmd_hooks(root, land_sh)
    repo = Repo(root)
    if verb == "session":
        return cmd_session(repo, land_sh)
    if verb == "status":
        return cmd_status(repo)
    a = parse(rest)
    cfg = load_config(repo)
    if verb in ("docs", "auto", "pr"):
        if not a.title:
            raise Stop(USAGE, "%s needs --title" % verb)
        if not a.paths:
            raise Stop(USAGE, "%s needs the files after --" % verb)
        if verb == "docs":
            return land_docs(repo, a, cfg)
        check_branch_arg(repo, a)
        if verb == "auto":
            return cmd_auto(repo, a, cfg)
        return cmd_pr(repo, a)
    if verb in ("pending", "show"):
        if not a.title or not a.paths:
            raise Stop(USAGE, "%s needs --skill S --title T -- <files> (the same as the land.sh pr --rolling that goes with it)" % verb)
        check_branch_arg(repo, a)
        return cmd_pending(repo, a) if verb == "pending" else cmd_show(repo, a)
    if verb == "merge":
        if not a.pr or not a.sha:
            raise Stop(USAGE, "merge needs --pr N --sha <40-hex>")
        return cmd_merge(repo, a, cfg)
    if verb == "verify":
        if not a.pr or not a.sha:
            raise Stop(USAGE, "verify needs --pr N --sha <40-hex>")
        return cmd_verify(repo, a)
    if verb == "settle":
        if not a.pr and not a.branch:
            raise Stop(USAGE, "settle needs --pr N or --branch B")
        check_branch_arg(repo, a)
        return cmd_settle(repo, a)
    if verb == "sync":
        return cmd_sync(repo, a)
    if verb == "fresh":
        if not a.sha:
            raise Stop(USAGE, "fresh needs --sha <40-hex>")
        return cmd_fresh(repo, a)
    if verb == "sync-pr":
        if not a.branch:
            raise Stop(USAGE, "sync-pr needs --branch <head-branch>")
        check_branch_arg(repo, a)
        return cmd_sync_pr(repo, a)
    raise Stop(USAGE, "unknown verb: %s" % verb)


def _utf8_stdio():
    """Hook payloads and messages are UTF-8 whatever the locale."""
    for name in ("stdin", "stdout", "stderr"):
        stream = getattr(sys, name)
        enc = (getattr(stream, "encoding", "") or "").lower().replace("-", "")
        if enc != "utf8" and hasattr(stream, "buffer"):
            setattr(sys, name, io.TextIOWrapper(stream.buffer, encoding="utf-8",
                                                errors="surrogateescape" if name == "stdin" else "replace",
                                                line_buffering=(name != "stdin")))


if __name__ == "__main__":
    _utf8_stdio()
    try:
        sys.exit(main(sys.argv[1:]))
    except Stop as s:
        warn(s.msg)
        sys.exit(s.code)
