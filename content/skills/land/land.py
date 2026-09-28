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
)
DOCS_FILES = ("docs/glossary.md", "tasks/history.tsv")
# Loaded into every session as instructions, wherever they sit.
INSTRUCTION_NAMES = ("claude.md", "claude.local.md", "agents.md")
# Named explicitly as code even though a docs rule would match them:
# tasks.config.yml declares the ledger's actors and targets (a decision, not
# a record); docs/notes/INDEX.md is @-imported by the seeded CLAUDE.md.
ALWAYS_CODE = ("tasks/tasks.config.yml", "docs/notes/INDEX.md")
# Prototype scope never reaches the trunk except through /prototype graduate.
CODE_PREFIXES = (".claude/", ".github/", "tasks/proto/", "docs/proto/")


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
    if parts[-1].lower() in INSTRUCTION_NAMES:
        return "code", "agent instructions (%s)" % parts[-1]
    if p in imports:
        return "code", "imported by CLAUDE.md, so every session loads it"
    if p in ALWAYS_CODE:
        return "code", "named as code (a decision or an imported file)"
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


def claude_imports(read):
    """Every install-relative path @-imported by CLAUDE.md or
    .claude/CLAUDE.md, transitively (depth 3). `read(path)` returns the text
    or None. Relative imports resolve against the importing file's folder."""
    seen, found = set(), set()
    queue = [("CLAUDE.md", 0), (".claude/CLAUDE.md", 0)]
    while queue:
        f, depth = queue.pop()
        if f in seen:
            continue
        seen.add(f)
        text = read(f)
        if text is None:
            continue
        base = os.path.dirname(f)
        for m in re.finditer(r"(?m)^\s*@(\S+)", text):
            target = m.group(1)
            if target.startswith("~") or target.startswith("/"):
                continue
            norm = os.path.normpath(os.path.join(base, target)).replace("\\", "/")
            if norm.startswith("../"):
                continue
            found.add(norm)
            if depth < 3 and norm.endswith(".md"):
                queue.append((norm, depth + 1))
    return found


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

def run(args, cwd=None, env=None, check=True, input_text=None):
    p = subprocess.run(args, cwd=cwd, env=env, input=input_text,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       universal_newlines=True)
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
            t = open(cache).read().strip()
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
            with open(cache, "w") as fh:
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
        """CLAUDE.md imports from the working tree and the fetched trunk."""
        if self._imports is not None:
            return self._imports
        found = set()

        def from_wt(p):
            f = os.path.join(self.root, p)
            try:
                return open(f, encoding="utf-8", errors="replace").read()
            except OSError:
                return None

        def from_trunk(p):
            r = self.git("show", "refs/remotes/origin/%s:%s" % (self.trunk, self.top_path(p)), check=False)
            return r.stdout if r.returncode == 0 else None

        found |= claude_imports(from_wt)
        found |= claude_imports(from_trunk)
        self._imports = found
        return found

    def identity_env(self):
        """An environment whose author/committer is the user's, or a named
        stand-in when the repository has none configured."""
        env = dict(os.environ)
        name = self.git("config", "user.name", check=False).stdout.strip()
        email = self.git("config", "user.email", check=False).stdout.strip()
        if not name:
            env.setdefault("GIT_AUTHOR_NAME", "rasa land")
            env.setdefault("GIT_COMMITTER_NAME", "rasa land")
        if not email:
            env.setdefault("GIT_AUTHOR_EMAIL", "land@localhost")
            env.setdefault("GIT_COMMITTER_EMAIL", "land@localhost")
        env["GIT_LFS_SKIP_SMUDGE"] = "1"
        return env


# ── state: lock, log ──────────────────────────────────────────────────────

class Lock(object):
    """One landing at a time per repository (all worktrees). A mkdir lock;
    an owner whose pid is gone, or older than an hour, is taken over."""

    def __init__(self, repo):
        self.path = os.path.join(repo.state, "lock")
        os.makedirs(repo.state, exist_ok=True)

    def __enter__(self):
        for _ in range(30):
            try:
                os.mkdir(self.path)
                with open(os.path.join(self.path, "owner"), "w") as fh:
                    fh.write("%d %d\n" % (os.getpid(), int(time.time())))
                return self
            except FileExistsError:
                if self._stale():
                    shutil.rmtree(self.path, ignore_errors=True)
                    continue
                time.sleep(1)
        raise Stop(REFUSED, "another landing holds %s; wait for it or remove it if its process is gone" % self.path)

    def _stale(self):
        try:
            pid, since = open(os.path.join(self.path, "owner")).read().split()[:2]
            pid, since = int(pid), int(since)
        except (OSError, ValueError):
            return True
        if time.time() - since > 3600:
            return True
        try:
            os.kill(pid, 0)
            return False
        except ProcessLookupError:
            return True
        except PermissionError:
            return False

    def __exit__(self, *exc):
        shutil.rmtree(self.path, ignore_errors=True)
        return False


def log_row(repo, event, **fields):
    os.makedirs(repo.state, exist_ok=True)
    row = dict(fields)
    row["event"] = event
    row["at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with open(os.path.join(repo.state, "log.jsonl"), "a") as fh:
        fh.write(json.dumps(row, sort_keys=True) + "\n")


def log_rows(repo):
    f = os.path.join(repo.state, "log.jsonl")
    rows = []
    if os.path.exists(f):
        for line in open(f):
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

def load_config(repo):
    f = os.path.join(repo.root, ".claude", "landing.json")
    cfg = {"docs": "auto", "skills": {}, "check_wait_secs": 180}
    try:
        user = json.load(open(f))
    except (OSError, ValueError):
        user = {}
    if user.get("docs") in ("auto", "pr"):
        cfg["docs"] = user["docs"]
    if isinstance(user.get("skills"), dict):
        cfg["skills"] = {k: v for k, v in user["skills"].items() if v in ("auto", "pr")}
    try:
        cfg["check_wait_secs"] = max(0, min(3600, int(user.get("check_wait_secs", 180))))
    except (TypeError, ValueError):
        pass
    for k in user:
        if k not in ("docs", "skills", "check_wait_secs") and not k.startswith("_"):
            warn(".claude/landing.json: unknown key '%s' ignored (the docs class is fixed in land.py)" % k)
    return cfg


def docs_mode(cfg, skill):
    """'auto' only if both the project and the skill allow it."""
    if cfg["docs"] == "pr" or cfg["skills"].get(skill) == "pr":
        return "pr"
    return "auto"


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
        self.env = repo.identity_env()

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
            if not os.path.exists(f) or open(f).read() != want:
                with open(f, "w") as fh:
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
        lines = open(path, encoding="utf-8").read().splitlines()
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
    with open(path, "w", encoding="utf-8") as fh:
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
    r = run([sys.executable, ct, "--json", tree_root], check=False)
    try:
        d = json.loads(r.stdout)
    except ValueError:
        return {("unreadable", "", (r.stderr or r.stdout)[:200])}
    return {(f.get("invariant"), f.get("file"), f.get("message"))
            for f in d.get("findings", []) if f.get("severity") == "ERROR"}


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

def plan_paths(repo, paths, base, want_class):
    """Sort each requested path into land / skip, with reasons."""
    head = repo.head()
    mb = None
    if head:
        r = repo.git("merge-base", head, base, check=False)
        mb = r.stdout.strip() if r.returncode == 0 else None
    imports = repo.imports()
    land, skip = [], []
    for p in paths:
        tp = repo.top_path(p)
        full = os.path.join(repo.top, tp)
        mode = "120000" if os.path.islink(full) else None
        klass, why = classify(p, imports, mode)
        if want_class == "docs" and klass != "docs":
            raise Stop(REFUSED, "%s is %s class (%s). Docs land by themselves; this goes through `land.sh pr`." % (p, klass, why))
        if os.path.isdir(full):
            raise Stop(USAGE, "%s is a directory; name the files" % p)
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
        hb = repo.blob_at(head, tp) if head else None
        if wt != hb:
            land.append((p, "delta", wt))
        elif tb is None and (mb is None or repo.blob_at(mb, tp) is None):
            land.append((p, "new-on-branch", wt))
        else:
            skip.append((p, "committed on %s and changed there; it lands with that branch" % (repo.branch() or "HEAD")))
    return land, skip


def build_commit(repo, land, base, message):
    """C = HEAD (minus files new on the branch) + the landed contents.
    Built with plumbing in a private index: no checkout, no hooks."""
    head = repo.head() or base
    env = repo.identity_env()
    idx = tempfile.NamedTemporaryFile(prefix="land-idx-", dir=repo.state, delete=False)
    idx.close()
    env["GIT_INDEX_FILE"] = idx.name
    try:
        g = lambda *a, **k: run(["git", "-C", repo.top] + list(a), env=env, **k)
        g("read-tree", head)
        parent = head
        newfiles = [repo.top_path(p) for p, kind, _ in land if kind == "new-on-branch"]
        if newfiles:
            g("update-index", "--force-remove", "--", *newfiles)
            tree = g("write-tree").stdout.strip()
            parent = g("commit-tree", tree, "-p", head, "-m", "land: base without files new on this branch").stdout.strip()
        for p, _kind, wt in land:
            tp = repo.top_path(p)
            if wt is None:
                g("update-index", "--force-remove", "--", tp)
            else:
                blob = g("hash-object", "-w", "--", tp).stdout.strip()
                g("update-index", "--add", "--cacheinfo", "100644,%s,%s" % (blob, tp))
        tree = g("write-tree").stdout.strip()
        return g("commit-tree", tree, "-p", parent, "-m", message).stdout.strip()
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
    """Bring the trunk into a pushed landing branch: a merge, never a rewrite."""
    with Scratch(repo, tip) as sc:
        r = sc.git("merge", "--no-edit", "-q", base, check=False)
        if r.returncode != 0:
            conflicted = sc.git("diff", "--name-only", "--diff-filter=U", check=False).stdout.split()
            sc.git("merge", "--abort", check=False)
            raise Stop(CONFLICT, "the trunk now conflicts with this landing in: %s" % (", ".join(conflicted) or "?"))
        hist = repo.top_path("tasks/history.tsv")
        if "tasks/history.tsv" in touched and sort_history(os.path.join(sc.path, hist)):
            sc.git("add", "--", hist)
            sc.git("commit", "-q", "-m", "land: keep the transition log in date order")
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
    f = tempfile.NamedTemporaryFile("w", prefix="land-body-", suffix=".md", dir=repo.state, delete=False)
    f.write(text)
    f.close()
    return f.name


def gh_ok():
    return have("gh")


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


def trunk_requires_checks(repo, base):
    """True when the trunk has a workflow that runs on pull requests, so an
    empty rollup means 'not started yet', never 'nothing to run'."""
    wf = repo.git("ls-tree", "-r", "--name-only", base, "--", ".github/workflows", check=False).stdout.split()
    for f in wf:
        if f.endswith((".yml", ".yaml")) and "pull_request" in repo.git("show", "%s:%s" % (base, f), check=False).stdout:
            return True
    return False


def classify_rollup(rollup):
    """(state, failing, pending) through peer-review.sh classify — one
    classifier for every merge gate in the Element."""
    pr = os.path.join(HERE, "..", "peer-review", "peer-review.sh")
    r = run(["bash", pr, "classify"], input_text=json.dumps({"statusCheckRollup": rollup}), check=False)
    out = dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l)
    return out.get("checks_state", "fail"), out.get("failing_checks", ""), out.get("pending_checks", "")


def rollup_from_json(files):
    """Normalise GitHub reads made with other tooling: a gh rollup, REST
    check-runs ({check_runs: [...]}) and REST combined status
    ({statuses: [...]}). Unknown shapes contribute nothing (never a pass)."""
    rollup, understood = [], False
    for f in files:
        try:
            d = json.load(open(f))
        except (OSError, ValueError) as exc:
            raise Stop(USAGE, "could not read checks JSON %s: %s" % (f, exc))
        if isinstance(d, dict) and isinstance(d.get("statusCheckRollup"), list):
            rollup += d["statusCheckRollup"]
            understood = True
        if isinstance(d, dict) and isinstance(d.get("check_runs"), list):
            understood = True
            for c in d["check_runs"]:
                rollup.append({"__typename": "CheckRun", "name": c.get("name") or "?",
                               "status": str(c.get("status") or "").upper(),
                               "conclusion": str(c.get("conclusion") or "").upper()})
        if isinstance(d, dict) and isinstance(d.get("statuses"), list):
            understood = True
            for s in d["statuses"]:
                rollup.append({"__typename": "StatusContext", "context": s.get("context") or "?",
                               "state": str(s.get("state") or "").upper()})
        if isinstance(d, list):
            understood = True
            rollup += d
    if not understood:
        raise Stop(REFUSED, "the checks JSON is in no shape land.sh knows (gh statusCheckRollup, REST check_runs, REST statuses)")
    return rollup


def wait_checks(repo, pr, base, secs, checks_json=None):
    """'pass' or a Stop. An empty rollup is 'pending' while the trunk runs PR
    workflows, and never a pass on its own."""
    need = trunk_requires_checks(repo, base)
    if checks_json:
        state, failing, pending = classify_rollup(rollup_from_json(checks_json))
        return _judge(state, failing, pending, need, final=True)
    deadline = time.time() + secs
    poll = max(1, int(os.environ.get("LAND_POLL", "15")))
    grace_polls = 2
    while True:
        r = run(["gh", "pr", "view", str(pr), "--json", "statusCheckRollup"], cwd=repo.top, check=False)
        if r.returncode != 0:
            raise Stop(ERR, "could not read PR #%s checks: %s" % (pr, (r.stderr or "").strip()[:200]))
        rollup = (json.loads(r.stdout) or {}).get("statusCheckRollup") or []
        state, failing, pending = classify_rollup(rollup)
        final = time.time() >= deadline
        verdict = _judge(state, failing, pending, need, final=final, grace_left=grace_polls > 0)
        if verdict == "pass":
            return "pass"
        if state == "none" and not need:
            grace_polls -= 1
        time.sleep(poll)


def _judge(state, failing, pending, need, final, grace_left=False):
    if state == "fail":
        raise Stop(CHECKS, "checks failing: %s. The PR stays open." % (failing or "?"))
    if state == "pass":
        return "pass"
    if state == "none" and not need and not grace_left:
        return "pass"  # no workflow runs on pull requests here: nothing to wait for
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

def landed_on(repo, base, p, blob):
    """Is this landing's content on the trunk? A whole file for new or
    rewritten docs; for ledgers merged line by line (history.tsv, ROADMAP.md,
    AUDIT.md) every line the landing added must be there."""
    tp = repo.top_path(p)
    tb = repo.blob_at(base, tp)
    if tb == blob:
        return True
    if blob is None or tb is None:
        return False
    mine = repo.git("cat-file", "blob", blob).stdout.splitlines()
    theirs = set(repo.git("cat-file", "blob", tb).stdout.splitlines())
    head = repo.head()
    hb = repo.blob_at(head, tp) if head else None
    before = set(repo.git("cat-file", "blob", hb).stdout.splitlines()) if hb else set()
    added = [l for l in mine if l not in before and l.strip()]
    return bool(added) and all(l in theirs for l in added)


def settle(repo, branch, landed, merged=True):
    """landed: list of [path, blob|None]. Runs only once this landing's
    content is on the fetched trunk. Never loses a byte: saves copies first."""
    base = repo.fetch_trunk()
    for p, blob in landed:
        if not landed_on(repo, base, p, blob):
            raise Stop(CHECKS, "not on %s yet: %s. Settle again after the merge." % (repo.trunk, p))
    report = []
    if repo.op_in_progress():
        return ["checkout left as is: an operation is in progress"]
    stash = os.path.join(repo.state, "stash", stamp())
    touched = []
    for p, blob in landed:
        tp = repo.top_path(p)
        full = os.path.join(repo.top, tp)
        if repo.wt_blob(tp) != blob:
            report.append("%s changed since it landed; kept as is" % p)
            continue
        os.makedirs(os.path.dirname(os.path.join(stash, tp)), exist_ok=True)
        if os.path.exists(full):
            shutil.copy2(full, os.path.join(stash, tp))
        touched.append((p, tp, full))
    if not touched:
        return report or ["nothing to settle"]
    head = repo.head()
    cur = repo.branch()
    if not cur:
        return report + ["detached HEAD: landed files kept in the checkout"]
    if cur == repo.trunk and head and not repo.is_ancestor(head, base):
        return report + ["local %s has commits that are not on origin: landed files kept; those commits must land through a PR" % cur]
    if os.path.exists(os.path.join(repo.git_dir, "index.lock")):
        return report + ["index.lock present: landed files kept"]

    def restore_copies():
        for p, tp, full in touched:
            src = os.path.join(stash, tp)
            if os.path.exists(src):
                os.makedirs(os.path.dirname(full), exist_ok=True)
                shutil.copy2(src, full)

    for p, tp, full in touched:
        hb = repo.blob_at(head, tp) if head else None
        if hb is None:
            if os.path.exists(full):
                os.unlink(full)
        else:
            data = repo.git("cat-file", "blob", hb).stdout
            with open(full, "w", encoding="utf-8", newline="") as fh:
                fh.write(data)
    if cur == repo.trunk:
        r = repo.git("merge", "-q", "--ff-only", base, check=False)
    else:
        r = repo.git("merge", "-q", "--no-edit", base, check=False)
        if r.returncode != 0 and os.path.exists(os.path.join(repo.git_dir, "MERGE_HEAD")):
            repo.git("merge", "--abort", check=False)
    if r.returncode != 0:
        restore_copies()
        return report + ["could not bring %s into %s (%s); landed files kept as they were" %
                         (repo.trunk, cur, (r.stderr or r.stdout).strip()[:160])]
    return report + ["%s now carries the landed files from %s" % (cur, repo.trunk)]


# ── verbs ─────────────────────────────────────────────────────────────────

def cmd_classify(repo, paths):
    imports = repo.imports() if repo else set()
    worst = OK
    for p in paths:
        mode = None
        if repo and os.path.islink(os.path.join(repo.root, p)):
            mode = "120000"
        klass, why = classify(p, imports, mode)
        say("%s\t%s\t%s" % (klass, p, why))
        if klass != "docs":
            worst = REFUSED
    say("class=%s" % ("docs" if worst == OK else "code"))
    return worst


def land_docs(repo, a, cfg):
    """The docs landing, end to end."""
    op = repo.op_in_progress()
    if op:
        raise Stop(REFUSED, "a git operation is in progress (%s); finish it first" % op)
    with Lock(repo):
        base = repo.fetch_trunk()
        land, skip = plan_paths(repo, a.paths, base, "docs")
        for p, why in skip:
            say("skipped=%s (%s)" % (p, why))
        if not land:
            say("landed=nothing", "result=nothing to land")
            return OK
        touched = [p for p, _, _ in land]
        msg = "docs(%s): %s" % (a.skill, a.title)
        c = build_commit(repo, land, base, msg)
        tip = pick_onto(repo, c, base, touched, msg)
        if tip is None:
            say("landed=already", "result=the trunk already has all of it")
            try:
                for line in settle(repo, "", [(p, wt) for p, _, wt in land]):
                    say("settle=" + line)
            except Stop as exc:
                say("settle=kept: %s" % exc.msg)
            return OK
        branch = "land/%s-%s-%s" % (slugify(a.skill, 20), stamp(), os.urandom(2).hex())
        push_ref(repo, tip, branch)
        landed = [[p, wt] for p, _, wt in land]
        log_row(repo, "pushed", branch=branch, sha=tip, skill=a.skill, landed=landed, klass="docs")
        say("branch=%s" % branch, "head=%s" % tip, "base=%s" % base)
        title = "docs(%s): %s" % (a.skill, a.title)
        body = write_body(repo, pr_body("docs", a.skill, a.title, a.summary, a.tasks, touched, base, None, None))
        if not gh_ok():
            say("body_file=%s" % body, "title=%s" % title, "next=open-pr",
                "then: open the PR (base %s, head %s) with the session's GitHub tooling, label it docs-land," % (repo.trunk, branch),
                "      read its check runs into a file, and run: land.sh merge --pr <N> --sha %s --checks-json <file>" % tip)
            return NOGH
        number, url = gh_create_pr(repo, branch, title, body, label="docs-land")
        log_row(repo, "pr-open", branch=branch, sha=tip, pr=number, url=url, landed=landed, skill=a.skill, klass="docs")
        say("pr=%s" % url)
        if docs_mode(cfg, a.skill) == "pr":
            say("merge=held (.claude/landing.json asks docs from this skill to wait for a person)")
            return OK
        return merge_flow(repo, number, tip, branch, landed, cfg, wait=a.wait)


def merge_flow(repo, pr, sha, branch, landed, cfg, wait=None, checks_json=None):
    secs = cfg["check_wait_secs"] if wait is None else wait
    touched = [p for p, _ in landed]
    for _round in range(3):
        base, fresh, _files = verify(repo, pr, sha, "docs")
        if not fresh:
            if not branch:
                raise Stop(CHECKS, "PR #%s is behind %s; sync it (land.sh sync-pr) and read its checks again" % (pr, repo.trunk))
            new = merge_trunk_into(repo, sha, base, touched)
            push_ref(repo, new, branch)
            log_row(repo, "pushed", branch=branch, sha=new, pr=pr, landed=landed, klass="docs")
            say("synced=%s now carries %s (%s)" % (branch, repo.trunk, new[:12]))
            sha = new
            if checks_json:
                say("head=%s" % sha)
                raise Stop(CHECKS, "the landing branch was brought up to date; read its checks again and re-run merge with --sha %s" % sha)
            continue
        wait_checks(repo, pr, base, secs, checks_json)
        # The trunk may have moved while CI ran: merge only what contains it.
        if not repo.is_ancestor(repo.fetch_trunk(), sha):
            if checks_json:
                raise Stop(CHECKS, "%s moved while the checks ran; run land.sh merge again to bring it in" % repo.trunk)
            continue
        if not gh_ok():
            log_row(repo, "merge-ready", branch=branch, sha=sha, pr=pr, landed=landed, klass="docs")
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
        if r.get("pr") == a.pr or (r.get("sha") == a.sha and r.get("branch")):
            row = r
    landed = (row or {}).get("landed") or []
    branch = (row or {}).get("branch") or ""
    if row and row.get("pr") is None:
        log_row(repo, "pr-open", branch=branch, sha=a.sha, pr=a.pr, landed=landed, klass="docs")
    with Lock(repo):
        return merge_flow(repo, a.pr, a.sha, branch, landed, cfg, wait=a.wait, checks_json=a.checks_json or None)


def cmd_settle(repo, a):
    rows = [r for r in log_rows(repo) if r.get("pr") == a.pr or (a.branch and r.get("branch") == a.branch)]
    if not rows:
        raise Stop(USAGE, "no landing on record for %s" % (("PR #%s" % a.pr) if a.pr else a.branch))
    last = rows[-1]
    landed = last.get("landed") or []
    for s in settle(repo, last.get("branch"), landed):
        say("settle=" + s)
    br = last.get("branch")
    if br and repo.git("ls-remote", "--exit-code", "origin", "refs/heads/" + br, check=False).returncode == 0:
        repo.git("push", "-q", "origin", "--delete", br, check=False)
        say("deleted=%s" % br)
    log_row(repo, "settled", branch=br, pr=last.get("pr"))
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
    if repo.is_ancestor(base, head):
        say("sync=up to date")
        return OK
    if not cur:
        raise Stop(REFUSED, "detached HEAD: check out a branch first")
    if cur == repo.trunk:
        if not repo.is_ancestor(head, base):
            ahead = repo.git("rev-list", "--count", "%s..%s" % (base, head)).stdout.strip()
            raise Stop(REFUSED, "local %s has %s commit(s) that are not on origin. They must land through a PR: land.sh pr" % (cur, ahead))
        r = repo.git("merge", "-q", "--ff-only", base, check=False)
        if r.returncode != 0:
            raise Stop(CONFLICT, "could not fast-forward %s: %s" % (cur, (r.stderr or r.stdout).strip()[:300]))
        say("synced=%s fast-forwarded to %s" % (cur, base[:12]))
        return OK
    r = repo.git("merge", "-q", "--no-edit", base, check=False)
    if r.returncode != 0:
        conflicted = repo.git("diff", "--name-only", "--diff-filter=U", check=False).stdout.split()
        if os.path.exists(os.path.join(repo.git_dir, "MERGE_HEAD")):
            repo.git("merge", "--abort", check=False)
        raise Stop(CONFLICT, "merging %s into %s conflicts in: %s. The merge was undone; resolve it by hand."
                   % (repo.trunk, cur, ", ".join(conflicted) or (r.stderr or r.stdout).strip()[:200]))
    say("synced=%s now contains %s (%s)" % (cur, repo.trunk, base[:12]))
    if a.push and repo.git("rev-parse", "--abbrev-ref", "@{u}", check=False).returncode == 0:
        pr = repo.git("push", "-q", check=False)
        if pr.returncode != 0:
            raise Stop(ENVREFUSED if ENV_REFUSAL.search(pr.stderr or "") else ERR,
                       "push after sync failed: %s" % (pr.stderr or "").strip()[:200])
        say("pushed=%s" % cur)
    return OK


def branch_name(a, repo):
    if a.branch:
        return a.branch
    if a.tasks:
        return "task/%s-%s" % (a.tasks[0], slugify(a.title, 32))
    return "chore/%s-%s-%s" % (slugify(a.skill, 20), slugify(a.title, 24), stamp())


def cmd_pr(repo, a):
    """Code-class landing: commit, sync with the trunk, push, open a PR.
    Never merges."""
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
        branch = cur
        if on_trunk:
            branch = branch_name(a, repo)
            overlap = []
            if head:
                if not repo.is_ancestor(head, base):
                    raise Stop(REFUSED, "local %s has commits that are not on origin; move them to a branch first" % (cur or "HEAD"))
                changed = set(repo.git("diff", "--name-only", head, base).stdout.split())
                all_dirty = set(repo.git("diff", "--name-only", "HEAD").stdout.split()) | \
                    set(repo.git("ls-files", "--others", "--exclude-standard").stdout.split())
                overlap = sorted(changed & all_dirty)
            if overlap:
                raise Stop(REFUSED, "the trunk moved under uncommitted files: %s. Stash or commit them elsewhere, `land.sh sync`, then retry." % ", ".join(overlap[:6]))
            r = repo.git("switch", "-q", "-c", branch, "--no-track", base, check=False)
            if r.returncode != 0:
                raise Stop(REFUSED, "could not cut %s from %s: %s" % (branch, repo.trunk, (r.stderr or "").strip()[:200]))
            say("branch=%s cut from %s (%s), carrying your changes" % (branch, repo.trunk, base[:12]))
        head = repo.head()
        dirty = [tp for tp in tps if repo.wt_blob(tp) != (repo.blob_at(head, tp) if head else None)]
        if dirty:
            repo.git("add", "--", *tps)
            msg = a.message or ("%s: %s" % (a.tasks[0], a.title) if a.tasks else "%s: %s" % (a.skill, a.title))
            r = repo.git("commit", "-q", "-m", msg, "--only", "--", *tps, check=False)
            if r.returncode != 0:
                raise Stop(ERR, "commit failed: %s" % (r.stderr or r.stdout).strip()[:300])
            say("committed=%s" % repo.git("rev-parse", "--short", "HEAD").stdout.strip())
        elif not on_trunk and head and repo.is_ancestor(head, base):
            raise Stop(REFUSED, "nothing to land: the named files match %s and the branch adds nothing" % repo.trunk)
        if not repo.is_ancestor(base, repo.head()):
            r = repo.git("merge", "-q", "--no-edit", base, check=False)
            if r.returncode != 0:
                conflicted = repo.git("diff", "--name-only", "--diff-filter=U", check=False).stdout.split()
                if os.path.exists(os.path.join(repo.git_dir, "MERGE_HEAD")):
                    repo.git("merge", "--abort", check=False)
                raise Stop(CONFLICT, "%s conflicts with %s in: %s. Your commit is on %s; resolve the merge by hand and re-run."
                           % (branch, repo.trunk, ", ".join(conflicted) or "?", branch))
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


def cmd_auto(repo, a, cfg):
    """Split a skill's outputs by class: docs land, code goes by PR."""
    imports = repo.imports()
    docs, code = [], []
    for p in a.paths:
        mode = "120000" if os.path.islink(os.path.join(repo.root, p)) else None
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
    layer = "installed" if os.path.exists(pp) and "land.sh guard-push" in open(pp, errors="replace").read() else "absent"
    hp = repo.git("config", "core.hooksPath", check=False).stdout.strip()
    say("guard_prepush=%s%s" % (layer, (" (core.hooksPath=%s)" % hp) if hp else ""))
    settings = os.path.join(repo.root, ".claude", "settings.json")
    txt = open(settings).read() if os.path.exists(settings) else ""
    say("guard_claude_hooks=%s" % ("installed" if "land.sh guard-bash" in txt else "absent"))
    for r in inflight(repo):
        say("inflight=%s pr=%s state=%s since=%s" % (r.get("branch"), r.get("pr") or "-", r.get("event"), r.get("at")))
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


WRITEISH = re.compile(r"(>|\brm\b|\bmv\b|\bcp\b|\bchmod\b|\btee\b|sed\s+-i|\bln\b|\binstall\b|\btruncate\b|\bunlink\b)")
SHELL_OPS = set(["&&", "||", ";", "|", "&", "(", ")", ";;", "|&", "\n"])
# git commit options that take a value, so the value is never read as flags.
COMMIT_VALUED = set(["-m", "-F", "-C", "-c", "-t", "--message", "--file", "--author", "--date",
                     "--template", "--reuse-message", "--reedit-message", "--fixup", "--squash",
                     "--cleanup", "--trailer", "-S", "--gpg-sign"])


def _segments(cmd):
    """Shell-split a command line into simple-command token lists.
    None when it cannot be split (unbalanced quotes)."""
    import shlex
    try:
        lex = shlex.shlex(cmd, posix=True, punctuation_chars=True)
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


def _git_call(seg):
    """(global_opts, subcommand, args) for a git invocation in `seg`, or None.
    Leading VAR=value assignments and `command`/`exec`/`env` are skipped."""
    i = 0
    while i < len(seg) and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[i]) or seg[i] in ("command", "exec", "env", "nohup", "time")):
        i += 1
    if i >= len(seg) or os.path.basename(seg[i]) != "git":
        return None
    i += 1
    gopts = []
    while i < len(seg) and seg[i].startswith("-"):
        t = seg[i]
        if t in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path") and i + 1 < len(seg):
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
            cluster = t[1:]
            for k, ch in enumerate(cluster):
                if "-" + ch in valued:
                    # the rest of the cluster is this option's value
                    letters += ch
                    break
                letters += ch
    return letters


def cmd_guard_bash(stdin_text):
    """PreToolUse on Bash. The pre-push hook is what sees a push's real
    destination; this denies the ways around it, plus the obvious direct
    pushes so a refusal comes before the network."""
    try:
        payload = json.loads(stdin_text or "{}")
    except ValueError:
        return OK
    cmd = ((payload.get("tool_input") or {}).get("command") or "")
    cwd = payload.get("cwd") or os.getcwd()
    low = cmd.lower()
    if "git_guard_allow_main" in low:
        return deny("GIT_GUARD_ALLOW_MAIN is refused for Claude: the trunk changes only through a merged PR (land.sh docs / land.sh pr).")
    if ".git/hooks" in low and WRITEISH.search(cmd) and "land.sh" not in low:
        return deny("Writing under .git/hooks is refused: the pre-push trunk guard lives there.")
    segs = _segments(cmd)
    if segs is None:
        if re.search(r"\bgit\b", cmd) and re.search(r"\bpush\b", cmd):
            return deny("This command could not be parsed and looks like a git push. Write it plainly (git push origin <branch>).")
        return OK
    for seg in segs:
        if seg and os.path.basename(seg[0]) == "gh" and len(seg) > 1 and seg[1] == "api":
            text = " ".join(seg)
            writes = re.search(r"(-X|--method)\s*(PUT|POST|PATCH|DELETE)|(^|\s)(-f|-F|--field|--raw-field|--input)(\s|$)", text)
            if writes and re.search(r"/merges\b|/git/refs|/contents/|/pulls/\d+/merge\b", text):
                return deny("Writing the repository through `gh api` (merges, refs, contents) goes around pull requests. Use land.sh or gh pr.")
            continue
        call = _git_call(seg)
        if call is None:
            continue
        gopts, sub, args = call
        for k in range(len(gopts) - 1):
            if gopts[k] == "-c" and gopts[k + 1].lower().startswith("core.hookspath"):
                return deny("`-c core.hooksPath` switches off the trunk guard. Refused.")
        if sub == "config" and any(x.lower() == "core.hookspath" for x in args) and \
                not any(x in ("--get", "--get-all", "--list", "-l", "--show-origin") for x in args):
            return deny("Changing core.hooksPath switches off the trunk guard. Refused.")
        if sub in ("commit", "push", "merge", "rebase", "am", "cherry-pick", "revert", "pull") and "--no-verify" in args:
            return deny("--no-verify skips the hooks that keep the trunk PR-only. Refused.")
        if sub == "commit" and "n" in _short_flags(args, COMMIT_VALUED):
            return deny("`git commit -n` skips the pre-commit hooks. Refused.")
        if sub != "push":
            continue
        opts = [t for t in args if t.startswith("-")]
        pos = []
        skip = False
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
            return deny("`git push --all/--mirror` can move the trunk. Push the one branch you mean.")
        if "--tags" in opts and len(pos) <= 1:
            continue  # tags only: the trunk does not move
        if "--delete" in opts or "-d" in opts:
            dests = pos[1:]
        else:
            dests = [r.lstrip("+").split(":", 1)[1] if ":" in r else r.lstrip("+") for r in pos[1:]]
            dests += [r.lstrip("+")[1:] for r in pos[1:] if r.lstrip("+").startswith(":")]
        repo, trunk = _trunk_for(cwd)
        if any(d in (trunk, "refs/heads/" + trunk) for d in dests):
            return deny("Pushing to %s is refused: the trunk changes only through a merged PR. Push a branch and open a PR (land.sh pr), or land docs with land.sh docs." % trunk)
        onto_trunk = repo is not None and repo.branch() == trunk
        if onto_trunk and (len(pos) <= 1 or any(d in ("HEAD", "@") for d in dests)):
            return deny("You are on %s: this push would move the trunk. Put the work on a branch (land.sh pr)." % trunk)
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
    _, trunk = _trunk_for(payload.get("cwd") or os.getcwd())
    br = (ti.get("branch") or "").replace("refs/heads/", "")
    if not br or br in (trunk, "main", "master"):
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
    """Body of the git pre-push hook: refuse updates of refs/heads/<trunk>
    on origin (by URL, so a second remote name is caught) when Claude is the
    one pushing. Humans are not constrained here; creating the trunk on an
    empty remote is allowed (the first push)."""
    if os.environ.get("CLAUDECODE") != "1":
        return OK
    remote = argv[0] if argv else ""
    url = argv[1] if len(argv) > 1 else ""
    try:
        repo = Repo(os.getcwd())
    except Stop:
        return OK
    trunk = repo.trunk
    o = repo.git("remote", "get-url", "origin", check=False).stdout.strip()
    if o and origin_key(url or remote) != origin_key(o) and remote != "origin":
        return OK
    zero = "0" * 40
    for line in (stdin_text or "").splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        _lref, lsha, rref, rsha = parts[:4]
        if rref != "refs/heads/" + trunk:
            continue
        if rsha.strip("0") == "" and lsha != zero:
            continue  # the first push of the trunk to an empty remote
        print("land: refused — this push would move %s on %s. The trunk changes only through a merged PR:" % (trunk, remote or url),
              file=sys.stderr)
        print("      land docs with `land.sh docs`, code with `land.sh pr` (or /open-pr).", file=sys.stderr)
        return 1
    return OK


# ── hooks: installation ───────────────────────────────────────────────────

PREPUSH_BEGIN = "# >>> rasa land guard >>>"
PREPUSH_END = "# <<< rasa land guard <<<"


def install_prepush(repo, land_sh):
    """Arm the pre-push layer: our block first, then any hook that was
    already there (kept intact as pre-push.land-chained and called with the
    same stdin and arguments)."""
    hp = repo.git("config", "core.hooksPath", check=False).stdout.strip()
    if hp:
        full = os.path.realpath(hp if os.path.isabs(hp) else os.path.join(repo.top, hp))
        if full == repo.top or full.startswith(repo.top + os.sep):
            return "skipped: core.hooksPath=%s lives in the repository; the Claude hooks and branch protection guard the trunk there" % hp
        hooks = full
    else:
        hooks = os.path.join(repo.common, "hooks")
    os.makedirs(hooks, exist_ok=True)
    f = os.path.join(hooks, "pre-push")
    chained = os.path.join(hooks, "pre-push.land-chained")
    script = "\n".join([
        "#!/bin/sh",
        PREPUSH_BEGIN,
        "# Installed by rasa.domain.code land.sh: refuses Claude pushes that would",
        "# move the trunk. A hook that was here before runs after it, unchanged.",
        PREPUSH_END,
        '_land_in="$(cat)"',
        'if [ -f "%s" ]; then' % land_sh,
        '  printf \'%%s\\n\' "$_land_in" | bash "%s" guard-push "$@" || exit 1' % land_sh,
        "fi",
        'if [ -x "$(dirname "$0")/pre-push.land-chained" ]; then',
        '  printf \'%s\\n\' "$_land_in" | "$(dirname "$0")/pre-push.land-chained" "$@" || exit $?',
        "fi",
        "exit 0",
    ]) + "\n"
    if os.path.exists(f):
        text = open(f, errors="replace").read()
        if text == script:
            return "present"
        if PREPUSH_BEGIN not in text:
            if os.path.exists(chained):
                return "skipped: %s and %s both exist; resolve them by hand" % (f, chained)
            os.rename(f, chained)
    with open(f, "w") as fh:
        fh.write(script)
    os.chmod(f, 0o755)
    return "installed at %s" % f


def install_claude_hooks(repo):
    path = os.path.join(repo.root, ".claude", "settings.json")
    try:
        d = json.load(open(path)) if os.path.exists(path) else {}
    except ValueError:
        raise Stop(ERR, "%s is not valid JSON; fix it first" % path)
    hooks = d.setdefault("hooks", {})
    changed = []
    cmd = "bash .claude/skills/land/land.sh"

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
    ensure("PreToolUse", "mcp__.*__(push_files|create_or_update_file|delete_file)", cmd + " guard-mcp")
    ensure("SessionStart", "", cmd + " session")
    if changed:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as fh:
            json.dump(d, fh, indent=2)
            fh.write("\n")
        os.replace(tmp, path)
    return changed


def cmd_hooks(repo, land_sh):
    for c in install_claude_hooks(repo):
        say("hooks: installed " + c)
    say("prepush: " + install_prepush(repo, land_sh))
    return OK


def cmd_session(repo, land_sh):
    """SessionStart: arm the pre-push layer in this clone (fresh cloud
    containers have no .git/hooks), and name landings still in flight.
    Never fails a session."""
    try:
        install_prepush(repo, land_sh)
    except Exception as exc:  # noqa: BLE001 — a session hook must not fail
        warn("could not arm the pre-push guard: %s" % exc)
    rows = inflight(repo)
    if rows:
        say("land: %d landing(s) not finished:" % len(rows))
        for r in rows[:5]:
            say("  %s  PR %s  (%s since %s) → land.sh merge --pr <N> --sha %s" %
                (r.get("branch"), r.get("pr") or "not opened", r.get("event"), r.get("at"), (r.get("sha") or "")[:12]))
    return OK


# ── argument parsing (kept tiny; land.sh validates the verb) ──────────────

class Args(object):
    pass


def parse(argv):
    a = Args()
    a.skill, a.title, a.summary, a.tasks, a.wait = "manual", "", "", [], None
    a.paths, a.pr, a.sha, a.branch, a.checks_json = [], None, "", "", []
    a.draft, a.verified, a.risk, a.message, a.fetch_only, a.push = False, "", "", "", False, False
    i = 0
    while i < len(argv):
        t = argv[i]
        if t == "--":
            a.paths += argv[i + 1:]
            break
        val = argv[i + 1] if i + 1 < len(argv) else None
        if t in ("--skill", "--title", "--summary", "--tasks", "--wait", "--pr", "--sha", "--branch",
                 "--checks-json", "--verified", "--risk", "--message"):
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
    repo = Repo(root)
    if verb == "hooks":
        return cmd_hooks(repo, land_sh)
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
        if verb == "auto":
            return cmd_auto(repo, a, cfg)
        return cmd_pr(repo, a)
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
        return cmd_sync_pr(repo, a)
    raise Stop(USAGE, "unknown verb: %s" % verb)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Stop as s:
        warn(s.msg)
        sys.exit(s.code)
