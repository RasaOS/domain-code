---
name: codify
description: Capture a rule that emerged from the current conversation ("from now on do X", "we just decided Y") into a durable place — either project `CLAUDE.md` (project-specific) or kit `task-rules.md` (kit-level, via `/contribute` PR). Confirms the exact wording with the user, asks scope, drafts the edit, shows the diff, applies on approval. The fix for tribal knowledge that evaporates into transcript history. Triggered when the user wants to write down a rule mid-session — e.g. "/codify", "from now on do X", "let's add this as a rule", "make this a rule", "we just decided this — write it down".
---

# /codify — Capture a session rule into durable storage

Take a rule that emerged from the current conversation and put
it where it survives session boundaries. Either the project's
`CLAUDE.md` (default) or the kit's `task-rules.md` (when the rule
is general enough to apply across projects).

Per CLAUDE.md ethos: a vague rule is worse than no rule.
Confirm exact wording with the user before writing anything.

## Behavior contract

- **Confirm wording first, write second.** The skill never
  paraphrases unilaterally. The user agrees on the exact text
  before any file is touched.
- **Default scope is project.** Most rules are project-specific.
  Promotion to kit-level needs explicit user say-so. (And if the
  user later finds the rule applies across projects, they run
  `/rule-promote` to graduate it.)
- **One rule per invocation.** Don't bulk-codify. Each rule is a
  distinct decision; surface them one at a time.
- **Cite the conversation.** When writing the rule, include a
  one-line "why" that points at the situation that prompted it.
  Rules without context rot.
- **Place in the right section.** Read the target file first;
  find the section where the rule belongs (testing, schema,
  process, etc.). If no section fits, ask before creating one.
- **Never auto-commit.** Edits land in the working tree. The
  user reviews with `git diff`.
- **Kit-level rules go through `/contribute`.** This skill
  drafts the kit edit; the actual PR happens via `/contribute`.
  Keeps the kit-write path single-channel.

## Process

### Step 1 — Capture the rule

If the user invoked `/codify` without quoting the rule, ask:

```markdown
What's the rule? Give me the imperative form — what should
always/never happen, or what's preferred?

Example: "Always run `make schema-check` before committing
changes to schema files."
```

If the user said something like "from now on do X" earlier,
quote that statement back and confirm:

```markdown
You said: *"<exact quote from earlier>"*

Should I codify this as: **"<normalized imperative form>"**?
```

Wait for confirmation. Don't proceed with paraphrased wording
the user hasn't approved.

### Step 2 — Ask scope

```markdown
Where does this rule belong?

1. **Project** — only applies to this project. Goes in
   `CLAUDE.md`.
2. **Kit (universal)** — applies to every project. Goes in
   `kit/task-rules.md` (via `/contribute` PR back to claude-kit).
3. **Kit (platform-specific)** — applies to all projects on a
   given platform. Goes in `kit/<platform>-task-rules.md`.

Default: project.
```

If the user picks kit-level but the working directory isn't the
kit repo, that's fine — the skill drafts the edit and routes
through `/contribute`. If working in the kit repo directly, the
edit applies in place but still doesn't auto-commit.

### Step 3 — Find the right section

Read the target file. Identify candidate sections.

For `CLAUDE.md`:
- Common section names: "Tech stack", "Conventions", "Schema
  discipline", "Testing", "Process", "Gotchas", "Working
  rules".

For `kit/task-rules.md`:
- Whatever sections exist in the file. Don't invent new ones
  without asking.

If no section fits cleanly, surface the options:

```markdown
This rule is about <topic>. Options for placement:

1. Add to existing section "**<closest section>**"
2. Add to existing section "**<second-closest>**"
3. Create new section "**<proposed name>**"

Which?
```

### Step 4 — Draft the edit

Compose the rule entry. Pattern for the kit's existing style:

```markdown
- **<short imperative claim>** — <one-line rationale, optionally
  with a `path:line` citation if the rule references specific
  code>
```

For `CLAUDE.md`, the format is whatever the project already
uses (read first). Don't impose a style change.

### Step 5 — Show the diff

```markdown
**Proposed edit to `<path>`:**
```diff
@@ section: <section name> @@
 ...existing rules...
+- **<rule>** — <rationale>
```

**Source.** This rule emerged from <one-line context — what
prompted it in the current conversation>.

**Apply?** (yes / no / edit wording)
```

### Step 6 — Apply (or route)

- **Project scope** → write the edit to `CLAUDE.md` in the
  working tree. Don't commit. Tell the user to `git diff` and
  commit when ready.
- **Kit scope** → write the edit to the kit-managed file (if
  in the kit repo) or stage the diff for `/contribute` to
  package. Either way: don't commit.

### Step 7 — Closing summary

```markdown
# ✍️ Codified

> **<rule, exact final wording>**

- **Where it landed:** `<path>` *(section: <section>)*
- **Source.** <one-line context>
- **Status:** uncommitted in working tree.

`git diff <path>` to review. Commit when ready.

*(If kit scope:)* Run `/contribute` to package this as a PR
upstream.
```

## Style rules

- **Imperative voice.** "Always X", "Never Y", "Prefer X over
  Y". Not "It would be good to X".
- **One sentence per rule.** Compound rules become two rules.
- **Quote source verbatim.** When showing the user "you said
  X", quote exactly. Paraphrasing here erodes trust.
- **Inline citations are gold.** A rule that includes
  `path:line` is anchored to the code that prompted it.

## What you must NOT do

- **Don't write a rule the user hasn't approved verbatim.**
  Wording matters. A rule the user didn't sign off on isn't a
  rule.
- **Don't bulk-codify.** Each invocation handles one rule. If
  the user has three, run the skill three times.
- **Don't auto-place.** When section choice is ambiguous, ask.
  Wrong placement = forgotten rule.
- **Don't auto-commit.** Standard kit rule.
- **Don't infer scope from context.** Ask. The user knows
  whether the rule generalizes; you don't.
- **Don't promote project rules to kit-level unilaterally.**
  That's `/rule-promote`'s job, and it requires the rule
  appearing in 2+ projects.
- **Don't edit kit-managed files in a project repo without
  routing through `/contribute`.** The single-channel write
  path is intentional.

## Edge cases

- **The "rule" is actually a TODO.** Not a rule — a task. Route
  to `/task` instead.
- **The "rule" is actually a decision** (architecture, vendor
  choice). Route to `/decision` for a richer artifact.
- **The "rule" contradicts an existing rule** in the same file.
  Surface the conflict; don't silently both-write. Ask the user
  to reconcile.
- **CLAUDE.md doesn't exist yet.** Ask whether to create it.
  Don't create it silently.
- **The user wants a rule that's about the kit itself**
  (e.g. "/sync should check X first"). That's not a rule for
  `task-rules.md`; that's a feature request for a skill. Route
  to a normal conversation about the skill.
- **Working tree is dirty in the file being edited.** Warn
  before writing — the user may be in the middle of an unrelated
  edit.

## When NOT to use this skill

- **Filing a task** → `/task`.
- **Recording a decision with rationale** → `/decision`.
- **Promoting a rule that already exists across projects** →
  `/rule-promote`.
- **Fixing or updating an existing rule** → just edit the file
  directly; codify is for new rules.
- **Capturing an incident** → `/postmortem`.
- **Capturing a regret** → `/regret`.

## What "done" looks like for a /codify session

One rule, exact wording approved by the user, written to the
right section of either `CLAUDE.md` or a kit-managed file (with
`/contribute` queued if kit-level). Working tree dirty,
uncommitted. The user knows where the rule landed and what to
do next.
