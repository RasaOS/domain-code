---
name: update-docs
description: Pause and reconcile documentation against reality. Walks every core doc — README, CLAUDE.md, DEPLOY.md, task-rules, PHASES, ROADMAP, AUDIT, .env.example, skill files — and flags what's drifted from the actual state of the code, then proposes targeted edits. Triggered when the user wants a doc-sync pass — e.g. "/update-docs", "let's check our docs", "are our docs still accurate", "make sure everything is documented properly".
---

# /update-docs — Documentation reconciliation

Stop building for a beat. Walk the docs against the code. Find the
drift. Propose edits. Don't write everything from scratch — surgical
updates only.

Per CLAUDE.md: honest reporting. If a doc is fine, say it's fine.
If it's stale, say what's stale and why. Don't manufacture work.

## Behavior contract

- **Read before editing.** Read every doc in scope AND the code it
  describes. A doc is only "drifted" if you've verified the code
  contradicts it.
- **Propose, don't apply by default.** First pass produces a report
  of proposed changes. The user approves which ones to apply. Only
  after explicit approval do you make the edits.
- **Surgical edits.** When you do edit, change only what's drifted.
  Don't rewrite a paragraph because one sentence is wrong. Don't
  reformat. Don't "improve" prose that's accurate.
- **No new docs unless asked.** This skill reconciles existing docs.
  It does not invent new READMEs or `.md` files. If a gap genuinely
  needs a new doc, propose it in the report and let the user decide.
- **Don't touch docs the user explicitly owns** without asking —
  vision/marketing copy, personal notes, anything that reads like
  the user's voice rather than reference material.
- **Honest about confidence.** "This is wrong, the code says X" vs
  "I think this is stale, but couldn't fully verify" — distinguish
  them in the report.

## Doc surfaces in scope

Walk these. Skip any that don't exist in the repo.

**Repo-level:**
- `README.md` — the front door
- `CLAUDE.md` — working contract for Claude sessions
- `DEPLOY.md` — release / hosting / rollback
- `.env.example` — env-var contract
- The project's package manifest (e.g. `package.json`, `Package.swift`,
  `pyproject.toml`, `build.gradle`) — implicit doc of how to run things
- Any `docs/` directory

**Task system (`.claude/` + `tasks/`):**
- `.claude/task-rules.md` — execution rules
- `.claude/task-template.md` — task spec format
- `tasks/PHASES.md` — phase scopes + status
- `tasks/ROADMAP.md` — phase + task registry
- `tasks/AUDIT.md` — chronological log

**Skills:**
- `.claude/skills/*/SKILL.md` — each skill's frontmatter +
  description should still match what the skill does

**Tests:**
- `e2e/README.md` (if present) — how E2E works
- Test/task pairing — every active task should have a matching spec
  per the rule

## Process

### Step 1 — Inventory

List every doc in scope that exists. Output a one-line "found N
docs" header so the user sees the surface area.

### Step 2 — Reconcile

For each doc, compare claims to reality:

- **CLAUDE.md** — does the tech stack match the project's manifest
  (the file documented in CLAUDE.md as the project's package /
  module / dependency declaration)? Do the listed model files
  exist? Are the documented data paths still in use? Are the
  folder-layout sections current?
- **README.md** — do the install / run / test steps actually work?
  Does the feature list match what the app does today?
- **DEPLOY.md** — do the deploy commands match what the project's
  manifest / build config actually defines? Is the live URL still
  right?
- **.env.example** — does it list every `VITE_*` / `PW_*` var the
  code reads? (Grep the codebase for `import.meta.env.` and
  `process.env.` to find them.)
- **task-rules.md** — are the documented rules still followed in
  recent task closing reports / PRs?
- **PHASES.md / ROADMAP.md** — do the listed phases and tasks match
  the contents of `tasks/{backlog,active,blocked,completed}/`?
- **AUDIT.md** — does the most recent entry reflect the most
  recent shipped work? (Check git log against the audit's top
  entries.)
- **SKILL.md files** — does the description's trigger phrasing
  still match what the skill actually does?

For each finding, record:
- **Doc + section** (file path + heading or line range)
- **Claim in doc** (quoted or paraphrased)
- **Reality** (what the code/state actually shows)
- **Severity** (see rubric below)
- **Proposed edit** (the specific change, ready to apply)

### Step 3 — Report

Render the findings using the output structure below. Stop and wait
for user approval before editing anything.

### Step 4 — Apply (only after approval)

Apply only the changes the user approves. Use `Edit` for surgical
changes; only use `Write` for full rewrites the user explicitly
requested.

After edits:
- If `task-rules.md` says doc updates require an audit-log entry
  (it does — process changes get their own entries), append one
  to `AUDIT.md`.
- Don't commit unless the user says so.

## Severity rubric

- **🔴 Wrong** — the doc says something the code contradicts. A
  reader will be misled or break their setup. Fix with priority.
- **🟡 Stale** — the doc is missing recent additions or describes
  a previous state. Not actively misleading, but incomplete.
- **🟢 Drift-watch** — small inconsistencies (a renamed file, a
  reordered section). Worth fixing in the same pass since you're
  here.
- **⚪ Note** — observations that aren't doc bugs but are worth
  surfacing (e.g., "this section has grown to 200 lines, might
  want to split"). User decides.

## Output structure

```markdown
# 📚 Documentation reconciliation

> **Headline.** <one-sentence read on overall doc health. e.g.
> "Mostly accurate; 3 wrong claims in CLAUDE.md and the env example
> is missing two vars.">

**Docs reviewed.** <count> — <comma list of file paths>
**Code areas cross-checked.** <short list — e.g. src/firebase, package.json, tasks/*>

---

## 🔴 Wrong — fix these

### 1. `path/to/doc.md` — <section name>

**Doc says:**
> <quoted or paraphrased claim>

**Reality:**
<what the code actually shows, with `path:line` citation>

**Proposed edit:**
```diff
- <old line>
+ <new line>
```

### 2. …

---

## 🟡 Stale — should update

*(same shape as above)*

---

## 🟢 Drift-watch — small fixes

- `path/to/doc.md:line` — <one-line description + proposed change>
- …

---

## ⚪ Notes — surfacing for your call

- <observation, no edit proposed>
- …

---

## ✅ Verified accurate

Quick list — docs (or sections) you read and confirmed are still
correct. Useful so the user knows the silence isn't laziness.

- `README.md` — install / run section
- `CLAUDE.md` — RTDB paths section
- …

---

## Bottom line

<2–4 sentences. What's the recommended action? "Apply all 🔴 + 🟡
in one batch" or "Apply 🔴 only, defer the rest" or "Docs are in
good shape, nothing urgent". Be direct.>

**Next step.** <one sentence: tell me which to apply, or say "all
red", or "skip everything", and I'll edit accordingly.>
```

## Style rules

- **Cite `path:line` for every reality claim.** Same rule as
  `/audit` and `/review` — receipts.
- **Quote the doc, don't paraphrase, when the wording matters.** If
  you're saying it's wrong, the reader needs to see what "it" is.
- **Diff blocks for proposed edits.** `- old` / `+ new` is the
  fastest way for the user to scan.
- **Don't grade.** No "B+ on docs". Use the headline + bottom line.
- **No "you might want to consider".** If you propose an edit,
  propose it concretely. If you don't, say so.

## What you must NOT do

- **Don't apply edits in the report pass.** Report first; edit only
  after approval.
- **Don't reformat for taste.** If the doc uses 80-col wrap and
  trailing spaces, leave them. Match local style.
- **Don't add doc sections the user didn't ask for.** "I added a
  Contributing section" is out of scope.
- **Don't propose edits to user-voice docs** (vision statements,
  marketing copy, personal notes) without asking. You can flag
  them in ⚪ Notes.
- **Don't commit.** Doc-sync edits flow through the user's normal
  git approval like any other change.

## When NOT to use this skill

- **Writing one new doc** → just write it; don't go through this
  skill's report-then-apply flow for a single file.
- **Reviewing code quality** → `/audit` or `/review`.
- **Filing follow-up tasks for doc work** → use `/task` after this
  skill identifies a bigger doc effort.
- **Strategic phase planning** → `/plan`.

## What "done" looks like for an /update-docs session

The user leaves with one or more of:
- A clear report of what's drifted, ready for them to triage
- Approved edits applied surgically across the affected docs
- An `AUDIT.md` entry recording the doc-sync (when edits were made)
- Confidence that the docs reflect reality again

If the report comes back "everything's accurate, nothing to do" —
that's a valid outcome. Don't manufacture work to justify the run.
