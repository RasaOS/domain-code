#!/usr/bin/env python3
"""body.py: writes the PR body skeleton for open-pr.sh `body`.

argv: <task-path> <id> <changed-files> <manifest-block> <phase> <release>
      <on_merge> <after> <merge> <title>

Every ledger field comes in through argv, read by bin/task (through
open-pr.sh's task_field). The task file is opened only for its body sections.

The skeleton is in the shape .github/pull_request_template.md and
pr-manifest.sh share: the merge manifest, then the sections a merger reads.
What the ledger knows is filled in. What only the author knows stays a
<!-- --> placeholder, which open-pr.sh `check` refuses until it is written.
"""
import os
import re
import sys

path, tid, changed, block, phase, release, on_merge, after, merge, title = sys.argv[1:11]
changed = [c for c in changed.splitlines() if c]
after = [a.lstrip("#") for a in re.split(r"[\s,]+", after) if a]
text = open(path, encoding="utf-8").read()


def section(name):
    m = re.search(r"(?ims)^##\s+" + name + r"[^\n]*\n(.*?)(?=^##\s|\Z)", text)
    return m.group(1) if m else ""


def matches(c, e):
    return e == c or c.endswith(e) or e.endswith(c) or c.startswith(e.rstrip("/") + "/")


# A change under migrations/ cannot declare `migrations: none`, and a revert
# does not undo a schema: both lines become placeholders the author replaces.
if any(c.startswith("migrations/") for c in changed):
    lines = []
    for line in block.splitlines():
        if line.startswith("migrations:"):
            line = "migrations: <name each migration and whether it reverses>"
        elif line.startswith("rollback:"):
            line = "rollback: <how the schema is undone; a revert alone does not>"
        lines.append(line)
    block = "\n".join(lines)

crit = re.findall(r"(?m)^\s*-\s+\[( |x|X)\]\s+(.+?)\s*$", section("acceptance criteria"))
arts = section("artifacts expected to change")
expected = sorted(set(t for t in re.findall(r"`([^`\s]+)`", arts) if "/" in t or "." in t))

out = []
say = out.append
say("**Merge manifest.** It is read by `/auto-merge` and the `pr-manifest` check, so keep the fence and every key.")
say("")
say(block)
say("")
say("## What & why")
say("")
say("<!-- one to three sentences: what this PR does and why -->")
say("")
# Named by id and file name, not by stage path: `task submit` moves the file
# from active/ to review/, and a path in the PR body would go stale.
say("## Part of")
say("")
say("- **Task:** `%s` · `%s`%s" % (tid, os.path.basename(path), (" — " + title) if title else ""))
say("- **Phase:** %s" % ("`%s` (tasks/ROADMAP.md)" % phase if phase != "none" else "none (unphased)"))
say("- **Release:** %s" % ("targeted at `%s` (tasks/RELEASES.md)" % release if release != "none"
                          else "not targeted at a release yet"))
say("- **Merges after:** %s" % (", ".join("#" + a for a in after) if after else "nothing; it is independent"))
say("")
say("## Acceptance criteria")
say("")
for mark, line in crit:
    say("- %s %s" % ("☑" if mark.lower() == "x" else "☐", line))
if not crit:
    say("<!-- the task file has no acceptance criteria — it is a stub, not a spec -->")
say("")
say("## Files changed")
say("")
for c in changed:
    say("- `%s`%s" % (c, "" if any(matches(c, e) for e in expected) else " — **not in the expected list**"))
for e in expected:
    if not any(matches(c, e) for c in changed):
        say("- `%s` — **expected, unchanged**" % e)
if not changed:
    say("<!-- nothing differs from the trunk yet — commit and push first -->")
say("")
say("Deviations: <!-- explain every bold line above, or write: none -->")
say("")
say("## How I verified")
say("")
say("<!-- the commands you ran and their real output: the unfiltered headless")
say("     test run (counts, time), the build. Never just \"tests pass\". -->")
say("")
say("## Risk & rollback")
say("")
say("<!-- what could break and who it touches; how to undo it once merged -->")
say("")
say("## After merge")
say("")
if on_merge == "hold":
    say("- **Hold.** Nothing runs on merge. The work ships with %s."
        % ("`%s`" % release if release != "none" else "the next release"))
elif on_merge.startswith("deploy:"):
    env = on_merge.split(":", 1)[1]
    say("- **Deploy to `%s`** from the trunk: `./build/build && ./build/test && "
        "./build/deploy --env=%s --intent=deploy`." % (env, env))
    say("  `/auto-merge` runs this itself only when `%s` is a dev- or staging-class "
        "environment. Otherwise a person runs it." % env)
else:
    say("- **Cut release `%s`** with `/release`. A person runs it; `/auto-merge` never does."
        % on_merge.split(":", 1)[1])
say("- **Ledger:** `%s` passes its done-gate inside this PR before the merge (`/peer-review`), "
    "so it lands in `tasks/completed/` with the merge." % tid)
say("- **Merge:** %s, using the manifest's method." % (
    "by `/auto-merge` once the PR has the auto-merge label and green CI" if merge == "auto"
    else "by a person or `/peer-review`"))
print("\n".join(out))
