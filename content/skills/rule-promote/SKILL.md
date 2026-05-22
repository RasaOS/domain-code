---
name: rule-promote
description: Find rules that have crystallized in two or more projects' `CLAUDE.md` files (or kit-managed rule files) and surface them as candidates for promotion to kit-level `task-rules.md`. Takes a list of project paths from the user, scans each `CLAUDE.md` for rule-shaped statements, clusters semantically equivalent rules across repos, and proposes the shared ones for graduation. Drafts the kit edit; routes through `/contribute` for the actual PR. The kit gets stronger as patterns repeat across projects. Triggered when the user wants to find shared conventions worth standardizing — e.g. "/rule-promote", "what rules are duplicated across my projects", "promote shared rules to the kit", "find conventions worth graduating".
---

# /rule-promote — Graduate cross-project rules to the kit

Find rules the user has written into multiple projects'
`CLAUDE.md` files and propose promoting them to kit-level
`task-rules.md`. The kit is meant to crystallize patterns; this
skill is how patterns get noticed.

Per CLAUDE.md ethos: a rule that exists in one project might be
project-specific. A rule that exists in two or more, in similar
words, is a kit candidate. **Two is the threshold, not one.**

## Behavior contract

- **Cross-repo by design.** This skill operates over multiple
  project paths supplied by the user. There's no implicit
  registry — keep it boring and explicit.
- **Read CLAUDE.md per project.** That's the canonical home for
  project-level rules. Optionally also read `.claude/task-rules.md`
  if a project has overridden the kit version (rare, but legal).
- **Cluster semantically.** Exact-match would miss "always run
  `npm test` before push" vs "run tests before pushing". Use
  rough semantic equivalence — same imperative, same scope,
  same trigger. When in doubt, surface to the user; don't
  cluster aggressively.
- **Two-project minimum to surface.** A rule appearing in only
  one project stays in that project's CLAUDE.md. Three+ is a
  strong signal; two is the threshold.
- **Honest about ambiguity.** If a rule cluster is fuzzy
  ("these three rules are kind of about testing"), say so —
  don't over-merge.
- **Read-only here, write via `/contribute`.** This skill
  surfaces candidates and drafts a kit edit. The actual PR back
  to the kit goes through `/contribute`. Don't open PRs
  directly — keeps the kit-write path single-channel.
- **Don't auto-edit project CLAUDE.md.** Even after promotion,
  the user decides whether each project's CLAUDE.md keeps the
  rule (redundant but local) or removes it (relies on the kit).
  This skill flags both options; the user picks.
- **Consent before clustering.** If the user gives 5 paths and
  one is a fork or stale snapshot, ask whether to include it.

## Process

### Step 1 — Gather project paths

Ask the user:

```markdown
Which projects should I scan? Paste one or more paths — absolute
or relative to where I'm running from. I'll read each project's
`CLAUDE.md` and look for rules that appear in 2+ of them.

Two is the minimum threshold. One project = project-specific.
```

If the user gives one path, stop and explain. Don't fall back
to scanning ancestors or guessing.

### Step 2 — Verify each path

For each path:
- Confirm it's a directory.
- Confirm `CLAUDE.md` exists at the root (or surface that it
  doesn't and ask whether to skip or look elsewhere).
- Note the project name (from `git remote get-url` or the
  directory basename).

### Step 3 — Extract rule-shaped statements

Read each `CLAUDE.md`. A "rule-shaped statement" looks like
one of:

- **Bulleted imperative** — "Always X." / "Never Y." /
  "Prefer X over Y."
- **Numbered convention** — items in a numbered list that
  describe behavior the project enforces.
- **Bolded gotcha** — "**Important:** …" / "**Note:** …" with
  imperative content.

Skip:
- Project identity (what the project is).
- Tech stack (what it's built with).
- Configuration values (env var names, ports).
- One-time setup instructions ("clone the repo", "run
  install").

The output of this step is, per project, a list of extracted
rule strings with their source location (`CLAUDE.md:line`).

### Step 4 — Cluster across projects

Group rules by semantic equivalence. A cluster is a set of
≥2 rules from ≥2 different projects that say the same thing.

Heuristic for "same thing":
- Same imperative verb (run, prefer, avoid, never).
- Same direct object (tests, schema, formatter, etc.).
- Same trigger condition or scope, if present.

Reject clusters where the rules conflict (e.g. "always X" in
one project, "never X" in another). Surface the conflict — it's
useful information but not promotable.

### Step 5 — Render the candidate report

```markdown
# 🎓 Rule promotion — candidates

Scanned <N> projects. Found <count> clusters of rules appearing
in ≥2 projects.

---

## Promotable *(strong signal — appears in <N>+ projects)*

### Cluster 1 — *<paraphrased one-line summary>*

**Appears in:**
- `<project-A>/CLAUDE.md:<line>` — *"<rule text>"*
- `<project-B>/CLAUDE.md:<line>` — *"<rule text>"*
- `<project-C>/CLAUDE.md:<line>` — *"<rule text>"*

**Proposed kit rule (drafted):**
> <one or two lines, normalized wording, phrased to apply
> universally>

**Where it goes:** `kit/task-rules.md` — section "<which
section, e.g. 'Testing & verification'>"

---

## Worth considering *(weaker signal — only 2 projects)*

*(same shape, but flagged as borderline)*

---

## Conflicting rules *(do not promote)*

### `<topic>`

- `<project-A>/CLAUDE.md:<line>` — "<rule text>"
- `<project-B>/CLAUDE.md:<line>` — "<rule text>"

These conflict. Worth a conversation before either lands in
the kit.

---

## Project-specific rules *(stay where they are)*

Rules found in only one project. Listed for awareness, not
action:

- `<project>/CLAUDE.md:<line>` — "<rule>"
- …

---

## Bottom line

<2-3 sentences. Recommended action — promote the strong-signal
cluster, defer the weak ones, surface the conflict for a human
call.>

**To promote a cluster:** tell me which (e.g. "promote 1, 2",
"promote all strong"). I'll draft the kit edit and route through
`/contribute` for the PR.
```

### Step 6 — Draft the kit edit

For each cluster the user picks:

1. Locate the right section of `kit/task-rules.md` (or a
   platform-prefixed variant if the rule is platform-specific —
   e.g. `kit/ios-task-rules.md`). Ask the user if uncertain.
2. Draft the addition: a single bullet or short paragraph in the
   normalized wording shown in the report.
3. Show the user the proposed diff:

```markdown
**Proposed edit to `kit/task-rules.md`:**
```diff
@@ section: <section name> @@
 ...existing rules...
+- **<normalized rule>** — <one-line rationale, optional>
```

4. On approval, route to `/contribute`. That skill packages the
   diff into a PR back to claude-kit.

### Step 7 — Per-project cleanup (optional)

After promotion, ask per project:

```markdown
The rule is now in the kit. Each project's CLAUDE.md still has
its local copy. Three options per project:

1. **Remove it** — rely on the kit. Cleaner CLAUDE.md.
2. **Keep it as-is** — redundant but explicit. Useful if the
   project has a stronger version.
3. **Replace with a one-liner pointer** — "See kit task-rules
   §<section>" or similar.

Which for `<project>`?
```

Apply per project in the working tree (don't commit). Skip
projects the user doesn't currently have open.

### Step 8 — Closing summary

```markdown
# 🎓 Rule promotion summary

- **Clusters surfaced:** <count>
- **Promoted to kit:** <count> (PR drafted via `/contribute`)
- **Deferred:** <count>
- **Conflicts surfaced:** <count>
- **Per-project cleanups staged:** <count>

Next: review the `/contribute` PR draft, open it when ready.
After it merges, run `/sync` in each project to pull the kit
update.
```

## Style rules

- **Quote rules verbatim from each project.** Italics around
  the quoted text. The reader sees the actual wording, not the
  paraphrase.
- **Cluster headers paraphrase.** The header is a one-line
  summary; the body has the literal quotes.
- **Project paths are clickable.** Cite `<project>/CLAUDE.md:line`.
- **Don't reformat CLAUDE.md sections in the report.** The
  report is about the rules, not the file structure.
- **Strong/weak/conflicting are headings, not bullets.** They
  carry navigation weight.

## What you must NOT do

- **Don't promote single-project rules.** One occurrence is
  not a pattern. Wait for the second project.
- **Don't merge conflicting rules silently.** If two projects
  disagree, the disagreement is the surfaceable thing.
- **Don't auto-edit project CLAUDE.md files.** Cleanup is
  consent-gated and per-project.
- **Don't open the kit PR directly.** Always route through
  `/contribute`.
- **Don't extrapolate beyond CLAUDE.md.** If a rule lives in
  README or a doc folder, it's not in scope for this skill.
  Surface that as adjacent observation, but don't include in
  the cluster set.
- **Don't auto-commit anywhere.** Same rule as every kit-write
  skill.

## Edge cases

- **User points at the same project twice** (e.g. via a worktree
  and the main checkout). Deduplicate — don't double-count.
- **CLAUDE.md is empty or minimal.** Note it, skip it, move on.
- **A "rule" turns out to be a quoted external rule** (e.g.
  pointing to RFC 7231). Don't promote external standards as
  kit rules.
- **The kit already has the rule** in `task-rules.md`. Mark the
  cluster as "already in kit; consider removing per-project
  copies".
- **Platform-specific rules across platform-mismatched projects**
  (e.g. an iOS rule appears in an iOS project + a web project's
  iOS-section). Promote to `kit/ios-task-rules.md`, not the
  universal one.
- **Many small clusters** (>10). Group by section and let the
  user pick by section, not item.

## When NOT to use this skill

- **Capturing a rule from one project** → `/codify`.
- **Pushing one specific local edit upstream** →
  `/contribute`.
- **Pulling kit updates into a project** → `/sync`.
- **Reviewing what's in `task-rules.md`** → just read it.
- **You only have one project on the kit** → wait until you
  have two.

## What "done" looks like for a /rule-promote session

A report of cross-project rule clusters with promoted ones
drafted as kit edits and queued for `/contribute`. Optional
per-project cleanups staged in the working tree, uncommitted.
The user knows which `/contribute` PR to track and that running
`/sync` after merge brings the standardized rule home.
