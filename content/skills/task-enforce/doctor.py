#!/usr/bin/env python3
"""doctor.py — a read-only check of every record this Element writes.

Run it as `.claude/skills/task-enforce/task-enforce.sh doctor [<root>]`.

It reads and reports. It never writes: no --fix, no cache, no state file
(check-tasks, by contrast, writes tasks/.state). So it can be pointed at any
project — before it takes a release, and after.

Records: task files (tasks/<stage>/), run records (tasks/runs/), deploy and
env-transfer records and their index (deploys/), contract stamps
(contracts/stamps/), env-var and test stamps (env/stamps/, tests/stamps/),
and the release tracker (tasks/RELEASES.md).

FAIL — a W-class precondition, or damage: bytes a reader or writer that
does not follow the frontmatter contract gets wrong, as every one before
0.54.0 did.
  bom        a UTF-8 BOM before the opening fence
  cr         a CR byte (CRLF line endings)
  fence      a blank after a fence, or a block that opens and never closes
  body-kv    below a blank-edged closing fence, a body line an exact-fence
             reader takes for a frontmatter key (the W1 signature)
  dup-key    a frontmatter key that appears twice
  escaped    a value holding a literal \\n or \\r, or a control character
  actor      an auto-* run recorded as `actor_kind: human`: the agent that
             ran it is not who the record names
  blank-row  a DEPLOYS.md row with no record id (a record it could not read)
  approval   a release with a second **Approved.**, **Shipped.**, **Theme.**
             or **Target.** line — the forgery signature
WARN — drift the other rules disagree with.
  dup-id     one id on two records
  name       a record whose id or name disagrees with its file name
  enum       a status, kind, lock or version outside its set
  status     a task carrying `status:` (the directory is the state)
  outcome    a task with an outcome while it is still in an open stage
  second-fm  a second frontmatter block below the first
  no-fm      a script-written record with no frontmatter at all
  heading    a release-tracker heading that is not `## v<semver> — …`
  unreadable a record that cannot be read

Values are never printed — keys, ids, files and line numbers only — so the
report is safe to share from any project.

Exit: 0 no failures (warnings allowed) · 1 failures · 2 usage.
Stdlib only; Python >= 3.8. Run it with -B.
"""
import os
import re
import sys

BOM = b"\xef\xbb\xbf"
FENCE = re.compile(rb"---[ \t]*\Z")
KEY = re.compile(rb"([A-Za-z_][A-Za-z0-9_.-]*)[ \t]*:(.*)\Z")
CTRL = re.compile(rb"[\x00-\x08\x0b-\x1f\x7f]")      # C0 except tab, and DEL
ESCAPED = re.compile(rb"\\[nr]")
SEMVER = re.compile(r"\d+\.\d+\.\d+\Z")
TEST_STAMP_PREFIX = re.compile(r"\d{8}_\d{3}_")    # tests/stamps/<YYYYMMDD>_<NNN>_<slug>.md
RELEASE_HEADING = re.compile(r"## v\d+\.\d+\.\d+ — ")
RELEASE_LINES = ("**Approved.**", "**Shipped.**", "**Theme.**", "**Target.**")

TASK_STAGES = ("triage", "backlog", "active", "review", "blocked", "completed", "closed")
OPEN_STAGES = ("triage", "backlog", "active", "review", "blocked")
RUN_STATUS = {"in-flight", "completed", "stopped", "failed"}
DEPLOY_STATUS = {"success", "failed", "in-flight"}
DEPLOY_KIND = {"deploy", "release", "env-transfer"}


class Record:
    """One file's frontmatter, read strictly and without interpretation."""

    def __init__(self, data):
        self.bom = data.startswith(BOM)
        if self.bom:
            data = data[len(BOM):]
        self.first_cr = None
        if b"\r" in data:
            self.first_cr = data[:data.index(b"\r")].count(b"\n") + 1
        self.lines = [l[:-1] if l.endswith(b"\r") else l for l in data.split(b"\n")]
        self.has_fm = FENCE.match(self.lines[0]) is not None
        self.open_blank = self.has_fm and self.lines[0] != b"---"
        self.close = None
        self.close_blank = False
        self.keys = []                                  # (line number, key, raw value)
        if not self.has_fm:
            return
        for i in range(1, len(self.lines)):
            if FENCE.match(self.lines[i]):
                self.close, self.close_blank = i, self.lines[i] != b"---"
                break
        if self.close is None:
            return
        for i in range(1, self.close):
            m = KEY.match(self.lines[i])
            if m:
                self.keys.append((i + 1, m.group(1).decode("utf-8", "replace"), m.group(2).strip(b" \t")))

    def get(self, key):
        for _, k, v in self.keys:
            if k == key:
                return v.decode("utf-8", "replace")
        return None


def md_files(directory, recursive=True):
    if not os.path.isdir(directory):
        return []
    out = []
    for base, dirs, files in os.walk(directory):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        out.extend(os.path.join(base, f) for f in sorted(files) if f.endswith(".md"))
        if not recursive:
            break
    return out


class Doctor:
    def __init__(self, root):
        self.root = root
        self.findings = []
        self.counts = {}
        self.ids = {}

    def rel(self, path):
        return os.path.relpath(path, self.root)

    def add(self, sev, code, path, line, msg):
        self.findings.append((sev, code, self.rel(path), line, msg))

    def load(self, path, kind):
        try:
            with open(path, "rb") as fh:
                data = fh.read()
        except OSError as exc:
            self.add("WARN", "unreadable", path, 0, "cannot be read (%s)" % exc.__class__.__name__)
            return None
        self.counts[kind] = self.counts.get(kind, 0) + 1
        return data

    # ── the checks every record gets ──────────────────────────────────────────
    def generic(self, path, rec, needs_fm):
        """True when the frontmatter can be read further."""
        if rec.bom:
            self.add("FAIL", "bom", path, 1, "a UTF-8 BOM before the opening fence")
        if rec.first_cr is not None:
            self.add("FAIL", "cr", path, rec.first_cr, "a CR byte (CRLF line endings)")
        if not rec.has_fm:
            if needs_fm:
                self.add("WARN", "no-fm", path, 1, "a script-written record with no frontmatter")
            return False
        if rec.open_blank:
            self.add("FAIL", "fence", path, 1, "a blank after the opening fence")
        if rec.close is None:
            self.add("FAIL", "fence", path, 1, "the frontmatter block never closes")
            return False
        if rec.close_blank:
            self.add("FAIL", "fence", path, rec.close + 1, "a blank after the closing fence")
            names = set(k for _, k, _ in rec.keys)
            for i in range(rec.close + 1, len(rec.lines)):
                m = KEY.match(rec.lines[i])
                if m and m.group(1).decode("utf-8", "replace") in names:
                    self.add("FAIL", "body-kv", path, i + 1,
                             "body line '%s:' is frontmatter to an exact-fence reader"
                             % m.group(1).decode("utf-8", "replace"))
        seen = {}
        for line, key, value in rec.keys:
            if key in seen:
                self.add("FAIL", "dup-key", path, line,
                         "'%s' appears twice (lines %d and %d)" % (key, seen[key], line))
            else:
                seen[key] = line
            if ESCAPED.search(value):
                self.add("FAIL", "escaped", path, line, "the value of '%s' holds a literal \\n or \\r" % key)
            elif CTRL.search(value):
                self.add("FAIL", "escaped", path, line, "the value of '%s' holds a control character" % key)
        j = rec.close + 1
        while j < len(rec.lines) and rec.lines[j].strip() == b"":
            j += 1
        if j < len(rec.lines) and FENCE.match(rec.lines[j]):
            for k in range(j + 1, len(rec.lines)):
                if FENCE.match(rec.lines[k]):
                    if any(KEY.match(rec.lines[x]) for x in range(j + 1, k)):
                        self.add("WARN", "second-fm", path, j + 1, "a second frontmatter block below the first")
                    break
        return True

    def note_id(self, kind, rid, path):
        if rid:
            self.ids.setdefault((kind, rid), []).append(path)

    # ── one method per record kind ────────────────────────────────────────────
    def tasks(self):
        for stage in TASK_STAGES:
            for path in md_files(os.path.join(self.root, "tasks", stage)):
                data = self.load(path, "tasks")
                if data is None:
                    continue
                rec = Record(data)
                if not self.generic(path, rec, needs_fm=False):
                    continue
                tid = rec.get("id")
                self.note_id("task", tid, path)
                base = os.path.basename(path)
                if tid and not (base.startswith(tid + "-") or base == tid + ".md"):
                    self.add("WARN", "name", path, 1, "id %s, but the file is named %s" % (tid, base))
                if rec.get("status") is not None:
                    self.add("WARN", "status", path, 1, "carries status: — the directory is the state")
                if stage in OPEN_STAGES and (rec.get("x-outcome") or rec.get("outcome")):
                    self.add("WARN", "outcome", path, 1, "an outcome while still in %s/" % stage)

    def runs(self):
        for path in md_files(os.path.join(self.root, "tasks", "runs"), recursive=False):
            data = self.load(path, "runs")
            if data is None:
                continue
            rec = Record(data)
            if not self.generic(path, rec, needs_fm=True):
                continue
            rid = rec.get("run_id")
            self.note_id("run", rid, path)
            if rid and os.path.basename(path) != rid + ".md":
                self.add("WARN", "name", path, 1, "run_id %s, but the file is named %s" % (rid, os.path.basename(path)))
            if rec.get("status") not in RUN_STATUS:
                self.add("WARN", "enum", path, 1, "status is not one of %s" % ", ".join(sorted(RUN_STATUS)))
            kind = rec.get("kind") or ""
            if kind.startswith("auto-") and rec.get("actor_kind") != "agent":
                self.add("FAIL", "actor", path, 1,
                         "a %s run recorded as actor_kind: %s — not the agent that ran it"
                         % (kind, rec.get("actor_kind") or "(none)"))

    def deploys(self):
        for path in md_files(os.path.join(self.root, "deploys", "records"), recursive=False):
            data = self.load(path, "deploy records")
            if data is None:
                continue
            rec = Record(data)
            if not self.generic(path, rec, needs_fm=True):
                continue
            rid = rec.get("id")
            self.note_id("deploy", rid, path)
            if rid and os.path.basename(path) != rid + ".md":
                self.add("WARN", "name", path, 1, "id %s, but the file is named %s" % (rid, os.path.basename(path)))
            if rec.get("status") not in DEPLOY_STATUS:
                self.add("WARN", "enum", path, 1, "status is not one of %s" % ", ".join(sorted(DEPLOY_STATUS)))
            if rec.get("kind") not in DEPLOY_KIND:
                self.add("WARN", "enum", path, 1, "kind is not one of %s" % ", ".join(sorted(DEPLOY_KIND)))
        index = os.path.join(self.root, "deploys", "DEPLOYS.md")
        if os.path.isfile(index):
            data = self.load(index, "deploy index")
            if data is None:
                return
            if data.startswith(BOM):
                self.add("FAIL", "bom", index, 1, "a UTF-8 BOM")
            table = False
            for n, line in enumerate(data.split(b"\n"), 1):
                line = line.rstrip(b"\r").strip()
                if line.startswith(b"| When"):
                    table = True
                    continue
                if not table or not line.startswith(b"|") or line.startswith(b"|---"):
                    continue
                cells = line.strip(b"|").split(b"|")
                if cells[-1].strip().strip(b"`").strip() == b"":
                    self.add("FAIL", "blank-row", index, n, "a row with no record id — a record the index could not read")

    def stamps(self, subdir, kind, name_key):
        for path in md_files(os.path.join(self.root, subdir), recursive=False):
            data = self.load(path, kind)
            if data is None:
                continue
            rec = Record(data)
            if not self.generic(path, rec, needs_fm=True):
                continue
            name = rec.get(name_key)
            base = os.path.basename(path)
            stem = base[:-3]
            if subdir == "tests/stamps":        # the name is the slug after the date and sequence
                stem = TEST_STAMP_PREFIX.sub("", stem, count=1)
            if name and stem != name:
                self.add("WARN", "name", path, 1, "%s %s, but the file is named %s" % (name_key, name, base))
            if subdir == "contracts/stamps":
                if rec.get("is_locked") not in ("true", "false"):
                    self.add("WARN", "enum", path, 1, "is_locked is not true or false (contract.sh treats it as locked)")
                if not SEMVER.match(rec.get("version") or ""):
                    self.add("WARN", "enum", path, 1, "version is not x.y.z")

    def releases(self):
        path = os.path.join(self.root, "tasks", "RELEASES.md")
        if not os.path.isfile(path):
            return
        data = self.load(path, "release tracker")
        if data is None:
            return
        if data.startswith(BOM):
            self.add("FAIL", "bom", path, 1, "a UTF-8 BOM")
            data = data[len(BOM):]
        if b"\r" in data:
            self.add("FAIL", "cr", path, data[:data.index(b"\r")].count(b"\n") + 1, "a CR byte (CRLF line endings)")
        section, counts = None, {}
        for n, raw in enumerate(data.decode("utf-8", "replace").split("\n"), 1):
            line = raw.rstrip("\r")
            if line.startswith("## "):
                section, counts = None, {}
                m = RELEASE_HEADING.match(line)
                if m:
                    section = line[3:].split(" ")[0]
                else:
                    self.add("WARN", "heading", path, n, "a heading that is not '## v<semver> — …'")
                continue
            for head in RELEASE_LINES:
                if section and line.startswith(head):
                    counts[head] = counts.get(head, 0) + 1
                    if counts[head] == 2:
                        self.add("FAIL", "approval", path, n, "%s has a second %s line" % (section, head))

    # ── the report ────────────────────────────────────────────────────────────
    def run(self):
        self.tasks()
        self.runs()
        self.deploys()
        self.stamps("contracts/stamps", "contract stamps", "name")
        self.stamps("env/stamps", "env stamps", "name")
        self.stamps("tests/stamps", "test stamps", "name")
        self.releases()
        for (kind, rid), paths in sorted(self.ids.items()):
            for extra in paths[1:]:
                self.add("WARN", "dup-id", extra, 1, "%s %s is also %s" % (kind, rid, self.rel(paths[0])))

        print("doctor · %s" % self.root)
        order = ("tasks", "runs", "deploy records", "deploy index", "contract stamps",
                 "env stamps", "test stamps", "release tracker")
        read = " · ".join("%s %d" % (k, self.counts[k]) for k in order if k in self.counts)
        print("read: %s" % (read or "no records"))
        fails = [f for f in self.findings if f[0] == "FAIL"]
        warns = [f for f in self.findings if f[0] == "WARN"]
        if self.findings:
            print()
        for sev, code, rel, line, msg in sorted(fails) + sorted(warns):
            where = "%s:%d" % (rel, line) if line else rel
            print("  %s  %-10s %s — %s" % (sev, code, where, msg))
        print()
        verdict = ("W-class preconditions or damage found" if fails
                   else "no W-class precondition or damage")
        print("doctor: %d failure(s), %d warning(s) — %s" % (len(fails), len(warns), verdict))
        return 1 if fails else 0


def main(argv):
    if len(argv) != 2 or argv[1] in ("-h", "--help"):
        sys.stderr.write("usage: doctor.py <project-root>\n")
        return 2
    root = os.path.realpath(argv[1])
    if not os.path.isdir(root):
        sys.stderr.write("error: %s is not a directory\n" % argv[1])
        return 2
    return Doctor(root).run()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
