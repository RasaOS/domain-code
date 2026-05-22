---
name: new-skill
description: Scaffold a new skill that follows the kit's canonical conventions — frontmatter triggers, behavior contract, output structure, style rules, what-NOT-to-do, edge cases, when-NOT-to-use, and a "done" definition. Asks targeted questions about scope (kit-wide or project-local), what the skill produces (report / written files / applied edits), and the consent model, then writes a SKILL.md skeleton with TODO markers for the user to fill. Triggered when the user wants to author a new skill — e.g. "/new-skill", "scaffold a skill", "create a new skill called X", "I want to write a skill that does Y".
---

# /new-skill — Scaffold a new skill

Generate a SKILL.md skeleton that already follows every kit
convention. The user fills in the substance; the skill enforces
the shape.

Per CLAUDE.md ethos: blunt, calibrated. If the user's idea is
better served by extending an existing skill, say so — don't
default to "yes, let's create one".

## Behavior contract

- **Ask before scaffolding.** The skill needs six things from
  the user before writing anything:
  1. **Name** (kebab-case, single word preferred — e.g. `wrangle`,
     `blast-radius`).
  2. **One-sentence purpose** — what problem does this skill
     solve?
  3. **Triggers** — three to five concrete user phrases that
     should invoke it.
  4. **Scope** — kit-wide (lives in `kit/skills/` and propagates
     to all projects via `/sync`) or project-local (lives in
     `.claude/skills/` and stays in this repo only).
  5. **Mutation model** — does the skill (a) only render a
     report, (b) write durable `.md` files under `docs/`, or (c)
     edit source code? Each mode has a different consent boilerplate.
  6. **Script mechanics** — could the mechanics of this skill be
     locked into a script that runs in a defined manner, separating
     "what files to touch / what plumbing to do" (deterministic,
     script) from "what content / judgment the AI brings"
     (synthesis, AI)? Options: **none** (pure AI judgment — e.g.
     `/brainstorm`, `/decision`), **partial** (script owns
     plumbing, AI owns synthesis — like `/save`), or **full**
     (script owns end-to-end, AI just routes choices — rare for
     skills, common for `bin/`). See `script-craft.md` for the
     split.
- **Check for collisions.** Before writing, list existing skills
  (kit-level: `kit/skills/`; project-level: `.claude/skills/`).
  If the proposed name exists, surface it and ask whether to
  rename, replace, or extend the existing skill.
- **Push back honestly.** If the proposed skill overlaps heavily
  with an existing one (e.g. "another audit-style skill" when
  `/audit` already exists), say so before scaffolding. The kit's
  20-skill load is real cognitive cost.
- **Generate a skeleton, not a finished skill.** The output is a
  SKILL.md with every required section present, populated with
  the user's answers where possible, and `<!-- TODO: ... -->`
  markers everywhere the user still needs to write substance.
- **Never auto-commit.** Skeleton lands in the working tree,
  uncommitted. The user fills it out, reviews, and commits when
  ready.
- **Never modify other skills.** This skill creates one new
  directory and one new file. That's the whole blast radius.

## Process

### Step 1 — Gather the six inputs

Ask in one block:

```markdown
Before I scaffold, I need six things:

1. **Name** (kebab-case): _____
2. **One-sentence purpose** — what problem does it solve? _____
3. **Triggers** — 3-5 phrases users would type to invoke it
   (e.g. "/foo", "do the foo thing", "foo this codebase"): _____
4. **Scope** — kit-wide (propagates to all projects) or
   project-local (this repo only)? _____
5. **Mutation model** — report-only / writes-docs / edits-code? _____
6. **Script mechanics** — could the mechanics be locked into a
   script that runs in a defined manner? **none** (pure AI
   judgment), **partial** (script owns plumbing, AI owns synthesis
   — like `/save`), or **full** (script owns end-to-end)?
   See `script-craft.md`. _____
```

If the user gives partial answers, ask follow-ups for the missing
items — don't infer.

**Push back on the script question if the answer doesn't fit.**
If they pick "partial" or "full" but the purpose is pure synthesis
or judgment, say so: "the purpose you described is AI reasoning —
a script can't replace that. Should this be 'none' instead?"
Same direction: if they pick "none" but the description is full
of deterministic file plumbing, point out the candidate mechanics
that belong in a script.

### Step 2 — Sanity check

- **Name collision.** `ls kit/skills/` (kit-wide) or
  `ls .claude/skills/` (project-local) and check for
  `<name>/`. If present, stop and ask.
- **Overlap check.** Read each existing SKILL.md's frontmatter
  description (one line each is enough). If the proposed purpose
  duplicates an existing skill's, say so:

  > "/audit already covers focused codebase reviews. Is the new
  > skill genuinely different, or would extending /audit be
  > better?"

  If the user confirms it's distinct, proceed.

### Step 3 — Pick the right destination

- **Kit-wide** → `kit/skills/<name>/SKILL.md` (only valid when
  the working directory is the claude-kit repo itself).
- **Project-local** → `.claude/skills/<name>/SKILL.md`.

If the user picked "kit-wide" but the working directory isn't
the kit repo, stop and explain: kit skills must be authored in
the kit repo and propagate via `/sync`.

### Step 4 — Render the skeleton

Write the SKILL.md with this exact shape, substituting the
user's answers and leaving TODO markers everywhere the user
still owes substance.

If the script-mechanics answer was **partial** or **full**, also
write a second file: `<dest>/<name>.sh` using the **Script
skeleton** below. Both files land uncommitted in the working tree.

Use the **Skeleton template** (below) as the literal output,
with these substitutions:

- `<name>` → user's chosen name
- `<purpose>` → user's one-sentence purpose
- `<trigger-phrases>` → user's triggers, comma-separated
- `<mutation-mode-clause>` — pick one (Step 5)
- `<script-mode-clause>` — pick one (Step 6)

### Step 5 — Pick the mutation-model clause

Three pre-written contract paragraphs to drop into the skeleton's
behavior contract. Use exactly one.

**(a) Report-only:**

> **Read-only.** This skill produces a single rendered report
> in chat. It does not write files, edit code, or commit. If
> follow-ups are warranted, the user routes them through other
> skills (e.g. `/task`, `/plan`).

**(b) Writes durable docs:**

> **Writes durable docs only.** This skill creates `.md` files
> under `docs/<TODO: subdirectory>/`. It does not edit source
> code, config, or any other path. Files land in the working
> tree, uncommitted; the user reviews with `git diff` and commits
> when ready.

**(c) Edits source code (consent-gated):**

> **Edits are consent-gated.** This skill proposes changes
> first. The user picks which to apply, item by item. Approved
> edits land in the working tree, uncommitted. Never
> auto-commits. Never applies edits the user didn't explicitly
> approve.

### Step 6 — Pick the script-mechanics clause

Three pre-written paragraphs. Use exactly one.

**(none) Pure AI:**

> **No standalone script.** All work happens via AI synthesis and
> tool calls. The mechanics are described in this SKILL.md; the
> AI interprets them on each invocation. Appropriate when the
> work is judgment or prose, not deterministic plumbing.

**(partial) Script-driven (partial):**

> **Script-driven mechanics.** The deterministic plumbing (file
> moves, archive, format generation, validation) lives in
> `<name>.sh` in this skill's folder, per `script-craft.md`. The
> AI's job is to synthesize content and route choices; do NOT
> hand-write the files the script manages. Always invoke the
> script as `bash <skill-dir>/<name>.sh ...` — mode-bit-independent.

**(full) Script-driven (full):**

> **Script-driven, end-to-end.** `<name>.sh` in this skill's
> folder handles the full operation. The AI's role is to gather
> inputs from the user, route them to the right subcommand, and
> surface the script's output verbatim. Per `script-craft.md`.
> Always invoke as `bash <skill-dir>/<name>.sh ...`.

### Step 7 — Confirm and write

Show a summary:

```markdown
About to create:
- `<path>/SKILL.md`
- `<path>/<name>.sh` *(only if script-mechanics is partial or full)*

With:
- Name: `<name>`
- Triggers: <trigger phrases>
- Scope: <kit-wide|project-local>
- Mutation: <report-only|writes-docs|edits-code>
- Script mechanics: <none|partial|full>

This is a skeleton — every required section is present, but
sections marked `<!-- TODO -->` need your substance before the
skill is actually useful. Proceed?
```

On approval: write the file(s). On decline: stop, nothing written.

### Step 8 — Closing pointer

After writing:

```markdown
✅ Skeleton written:
- `<path>/SKILL.md`
- `<path>/<name>.sh` *(only if script-mechanics is partial or full)*

Next steps:
1. Read through the skeleton(s) and replace each `<!-- TODO -->`
   with substance.
2. If a script was scaffolded, read `script-craft.md` and use
   `kit/skills/save/save.sh` as the working reference. Test the
   script in a sandbox repo before wiring it into the SKILL.md
   process.
3. Once filled, test by invoking the skill on a real task.
4. If kit-wide: commit + push, then downstream projects pick it
   up via `/sync`.

Tip: `/audit kit/skills/<name>/SKILL.md` once it's filled in,
to get a critical read before it propagates.
```

## Skeleton template

This is the literal file written in Step 4. Substitute the
bracketed placeholders. Keep the TODO markers — the user fills
those.

````markdown
---
name: <name>
description: <purpose> Triggered when the user wants to <TODO: rephrase the purpose as a triggering intent> — e.g. "/<name>", <trigger-phrases>.
---

# /<name> — <TODO: short tagline>

<TODO: 2-4 sentences explaining what this skill does and why it
exists. Keep it terse. The behavior contract carries the weight.>

Per CLAUDE.md ethos: <TODO: name the specific honesty rule that
matters most for this skill — calibrated confidence, no
narratives, no soft no's, etc.>

## Behavior contract

- <mutation-mode-clause>
- <script-mode-clause>
- **<TODO: rule>** — <TODO: one-line rationale>
- **<TODO: rule>** — <TODO: one-line rationale>
- **<TODO: rule>** — <TODO: one-line rationale>
- **Never auto-commit.** Standard kit rule. Apply edits to the
  working tree; the user reviews with `git diff` and commits.
- **Stay in scope.** <TODO: define what "in scope" means for
  this skill. Adjacent observations go in a footer at most.>

## Process

### Step 1 — <TODO: first phase>

<TODO: what the skill does first. Be specific. Cite the files
or commands it reads.>

### Step 2 — <TODO: second phase>

<TODO: what happens next.>

<!-- TODO: add more steps as needed. Each step should be a
discrete, observable action. -->

### Step <N> — Closing summary

Render a tight summary of what was produced or applied:

```markdown
<TODO: closing summary template — what the user sees at the end
of a successful run.>
```

## Output structure

<!-- TODO: only include this section if the skill produces a
rendered artifact (report, doc, plan). Otherwise delete the
section. -->

**Catalogue entry.** <TODO: pin the catalogue §-number(s) this skill
renders, per the selection table in `.claude/output-rules.md`. E.g.
"§5 Deployment report" for a release skill, "§6 Severity audit" for
an audit skill. Compose multiple entries when the output spans
sections — e.g. `/status` pins §2 Live dashboard + §17 Branch
overview + §28 Stats card grid.>

```markdown
<TODO: literal markdown the skill should output, embedding the
catalogue template(s) above. Code-fence the box-drawing art so it
renders in monospace. Use placeholder brackets like <thing> for
substitutions. Don't invent a new visual rhythm — the catalogue is
the kit's design language for structured deliverables.>
```

## Style rules

- **Render structured deliverables per `output-rules.md`.** Use the
  pinned catalogue §-entries above; follow the glyph and color
  discipline; don't invent visual patterns inline.
- **<TODO: style rule specific to this skill's output>** —
  <TODO: rationale>
- **Cite files as `path:line`.** Click-through links in chat.
- **Code snippets ≤ 15 lines.** If you need more, link with
  `path:line_start-line_end` and summarize.
- **Bold the claim, then dash, then the reason.** `- **Claim**
  — reason.`
- **No "let me know if you have questions" sign-offs.** End on
  the last actionable section.

## What you must NOT do

- **<TODO: anti-pattern this skill is most likely to drift
  into>** — <TODO: why it's wrong>
- **Don't auto-commit.** Standard kit rule.
- **Don't expand scope unilaterally.** If something out-of-scope
  catches your eye, footer it; don't grow the skill's
  responsibility silently.
- <!-- TODO: add 2-4 more anti-patterns specific to this skill -->

## Edge cases

- **<TODO: edge case>** — <TODO: how to handle it>
- **<TODO: edge case>** — <TODO: how to handle it>
- <!-- TODO: add 2-4 more. Common ones: missing source files,
     dirty working tree, network failure, ambiguous user input,
     destructive action requested. -->

## When NOT to use this skill

- **<TODO: scenario>** → use `/<other-skill>` instead.
- **<TODO: scenario>** → <TODO: alternative>.
- <!-- TODO: list 2-4 scenarios where another skill or a direct
     conversation is the right tool. This protects the skill's
     focus. -->

## What "done" looks like for a /<name> session

<TODO: 1-3 sentences describing the artifact the user walks away
with. What changed, what they should do next (typically: `git
diff` + commit, or "read X and decide").>
````

## Script skeleton

Only written when the script-mechanics answer was **partial** or
**full**. Lives at `<dest>/<name>.sh` alongside the SKILL.md.
Follows `script-craft.md` conventions; mirrors `kit/skills/save/save.sh`
in shape.

```bash
#!/usr/bin/env bash
# <name>.sh — <TODO: one-line purpose, same as SKILL.md tagline>
#
# <TODO: 2-3 lines describing what plumbing this handles vs. what
# the AI synthesizes. See script-craft.md for the split.>

set -euo pipefail

usage() {
  cat <<'EOF'
<name>.sh — <TODO: one-line purpose>

USAGE:
  <name>.sh status
      <TODO: one-line — what state does this report?>

  <name>.sh <TODO: verb> [<TODO: args>]
      <TODO: one-line description of this subcommand.>

EXIT CODES:
  0  success
  1  operational error (missing file, write failure)
  2  usage error (bad flag, missing required argument)
  3  refused (preconditions not met)
EOF
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    echo "error: not inside a git repo" >&2
    return 1
  }
}

# <TODO: helper functions here. Small, named, single-purpose.>

cmd_status() {
  # <TODO: implement. One line of state to stdout.>
  echo "status: TODO"
}

# <TODO: add more cmd_<verb> handlers — one per subcommand.>

main() {
  local action="${1:-}"
  shift || true

  case "$action" in
    -h|--help|help|"")
      usage
      return 0
      ;;
  esac

  local root
  root="$(repo_root)" || return 1

  case "$action" in
    status)
      cmd_status
      ;;
    # <TODO: route additional subcommands here>
    *)
      echo "error: unknown action: $action" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
```

## Style rules

- **Question block, not interrogation.** Ask the six inputs in
  one message, not six back-to-back prompts.
- **Honest collision feedback.** "Yes, this duplicates /audit"
  is more useful than "Sure, scaffolding now."
- **TODO markers are sacred.** They're how the skeleton stays
  honest about what's not done. Don't fill them in with filler
  prose just to make the file feel complete.

## What you must NOT do

- **Don't write substance for the user.** The skeleton's job is
  shape; the user supplies content. Pre-filling behavior rules
  with generic platitudes makes the skeleton worse, not better.
- **Don't skip the collision check.** Two skills with overlapping
  triggers is a kit-quality bug. Better to push back than
  scaffold.
- **Don't propagate kit-wide skills from a project repo.**
  Kit-wide skills must be authored in the claude-kit repo
  itself; otherwise they have no path to propagate.
- **Don't auto-commit.** Skeletons land uncommitted. Always.

## Edge cases

- **User wants to extend an existing skill, not create a new
  one.** Stop scaffolding; suggest editing the existing
  SKILL.md. (Optionally route to `/audit` for a critical read
  first.)
- **Name conflicts with a CLI command.** If the user picks
  `build` or `run` and one already exists, ask whether to pick
  a different name.
- **User can't decide on mutation model.** Default to
  report-only. It's the lowest-risk shape; can always be
  upgraded later.
- **User can't decide on script mechanics.** Default to **none**.
  A skill can always be upgraded to partial/full later by adding
  a `<name>.sh` and updating the SKILL.md per `script-craft.md`.
  Reverse direction (partial → none) requires deleting the script
  and is a more deliberate decision.
- **Script-mechanics answer mismatches the purpose.** User says
  "partial" for a purely synthetic skill like `/brainstorm`, or
  "none" for a skill that's clearly deterministic file plumbing.
  Push back per Step 1's pushback rule before scaffolding.
- **Scope mismatch.** User says "kit-wide" while in a project
  repo. Stop, explain, offer project-local instead.

## When NOT to use this skill

- **You want to extend an existing skill** → just edit its
  SKILL.md. No need to scaffold.
- **You want a one-off ad-hoc workflow** that won't be reused →
  don't make it a skill. Just describe it inline.
- **You want to rename a skill** → that's a manual rename + a
  `/contribute` PR, not a new skeleton.

## What "done" looks like for a /new-skill session

A new directory at `kit/skills/<name>/` (or `.claude/skills/<name>/`)
containing a `SKILL.md` skeleton with the user's name, purpose,
triggers, mutation-model clause, and script-mode clause filled
in, and TODO markers everywhere else. If the script-mechanics
answer was **partial** or **full**, also a `<name>.sh` skeleton
following `script-craft.md` conventions. Uncommitted. The user
knows the next step is to fill in the substance, test the script
(if any) in a sandbox repo, and wire it up.
