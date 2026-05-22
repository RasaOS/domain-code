---
name: audit
description: Audit a section of the codebase (or docs, config, architecture, security) and produce a uniformly-structured report — TL;DR, breakdown with library table, what's working, severity-tagged findings (CRITICAL/HIGH/MEDIUM/LOW), tradeoffs, open questions, bottom line. Rendered in chat AND saved to `docs/audits/<YYYY-MM-DD>-<target-slug>.md` so audits accumulate as durable project history. Script (`audit.sh`) handles deterministic scaffolding + persistence; `auditor` agent (context-isolated) handles the judgment. Same output shape every invocation, regardless of target. Triggered when the user wants a structured read on a slice — e.g. "/audit src/firebase", "audit the inspection flow", "give me a read on the auth code", "audit the docs", "/audit --lens security src/api".
---

# /audit — Uniformly-structured codebase audit

Take a target and produce a single readable report — how it's built,
how it holds up, severity-tagged findings, honest tradeoffs, bottom
line. No marketing voice. No soft-pedaling.

The report is rendered in chat **and** persisted to disk under
`docs/audits/`. Past audits are durable context — future Claude
sessions can read them when they need the historical read on a
slice without re-doing the work.

Per CLAUDE.md ethos: blunt resonant honesty, calibrated confidence,
no narratives.

## Behavior contract

- **Script-driven mechanics + agent-driven judgment.** Three layers
  of structure enforcement:
  1. **`audit.sh scaffold`** renders the deterministic header (title,
     scope counts, library table, section H2s, severity tier
     scaffolding).
  2. The **`auditor` agent** (at `kit/agents/auditor.md`,
     context-isolated, read-only) reads the target and fills in
     the scaffold's `<to-fill>` placeholders.
  3. **`audit.sh validate`** post-checks the agent's output for
     required sections + placeholder completion before persisting.
- **Output passes to the user verbatim.** Same rule as `/status` —
  see the **Output policy** section below. The AI is a pass-through
  for the assembled audit. No paraphrasing, no preamble, no closing
  chat.
- **No fix work.** This skill produces a report only. No code edits,
  no task filing, no patches proposed. Follow-ups route through
  `/task` after the user reads.
- **Persist always.** Even if the user just asked "give me a read,"
  the audit lands at `docs/audits/<date>-<slug>.md`. The chat
  response and the disk file are the same content.
- **Updatability.** Sections, severity tiers, lenses, and manifest
  parsers are declared in arrays at the top of `audit.sh`. Add or
  remove by editing one list — no code rewrites needed. See "Evolving
  this skill" below.

## Output policy (the load-bearing rule)

The assembled audit — script header + agent body + script footer —
is the user-facing output. **Show it to the user as it is.**

**MUST:**
- Run the agent → validate → save pipeline.
- Output the final assembled audit in your reply, **unchanged and
  unsummarized**.
- Surface the saved file path in a single closing line.

**MUST NOT:**
- Summarize the audit ("Here's the gist: …"). The user wanted the
  full structured read — that's why they invoked `/audit`.
- Paraphrase any section. The agent's wording is the wording.
- Drop sections. Empty-state lines are intentional information.
- Add a preamble ("Here's your audit:") or closing remarks ("Let
  me know if you have questions!"). End on the saved-path line.
- Re-render the box-drawing or severity glyphs differently. Byte-
  for-byte fidelity to the script + agent output.

**MAY:**
- Add a follow-up question *below* the saved-path line if the
  audit surfaces something action-shaped ("Want me to file
  TASK-NNN for the CRITICAL finding?"). The audit itself is
  sacrosanct.

## The script

Lives at `kit/skills/audit/audit.sh` (or `.claude/skills/audit/audit.sh`
in synced projects). Always invoke with `bash` per `script-craft.md`.

### Interface

```text
bash <skill-dir>/audit.sh resolve <target>
    Emit key=value scope info — file list, line counts, libraries.
    Used as input to the auditor agent.

bash <skill-dir>/audit.sh scaffold <target> [--lens <lens>]
    Emit the scaffolded markdown to stdout. Contains the title,
    target, scope, library table, all section H2s, and
    <to-fill> placeholders.

bash <skill-dir>/audit.sh validate <content-file>
    Check that all required sections are present and no <to-fill>
    placeholders remain. Exit 0 if compliant, 3 if not.

bash <skill-dir>/audit.sh save <target> <content-file>
    Persist to docs/audits/<YYYY-MM-DD>-<slug>.md (with -2, -3
    collision suffix). Echo the saved path.

bash <skill-dir>/audit.sh lenses
    List supported lenses (read from the LENSES array in the script).
```

Exit codes: `0` success, `1` operational (file not found, not in
git repo), `2` usage error, `3` refused / validation failed.

### Supported lenses

Run `bash <skill-dir>/audit.sh lenses` for the live list. Current set:
`code` / `docs` / `config` / `architecture` / `security` / `mixed`.

## The agent

`kit/agents/auditor.md` is a context-isolated subagent with
Read/Glob/Grep/Bash tools and an opus model default. It receives
the target + scope info + scaffold and returns the completed
markdown.

See its system prompt for the full behavior contract. Key points:
- Read-only — never writes files (the calling skill persists).
- Severity scheme: CRITICAL / HIGH / MEDIUM / LOW.
- Render only severity tiers with findings; "No findings across
  all severity tiers" if zero.
- Must complete every `<to-fill>` placeholder; validate catches
  incomplete output.

## Process

### Step 1 — Resolve the target

If the user gives a vague target ("audit the inspection stuff"),
do a quick `Glob`/`Grep` pass to enumerate candidates and state in
one sentence what you're auditing before diving in. If genuinely
ambiguous, ask once.

### Step 2 — Run resolve to get scope info

```bash
bash .claude/skills/audit/audit.sh resolve <target>
```

The output is key=value lines + `[files]` + `[libraries]` blocks.
You'll pass this to the agent.

### Step 3 — Render the scaffold

```bash
bash .claude/skills/audit/audit.sh scaffold <target> --lens <lens>
```

If the user didn't specify a lens, pass `--lens auto` and let the
agent declare in the output what it actually applied.

Write the scaffold to a temp file (`$(mktemp -t audit-XXXX).md`).

### Step 4 — Delegate to the auditor agent

Invoke the `auditor` subagent with these inputs:
- The target string
- The scope info from `resolve`
- The scaffold file path (or contents)
- The lens (if specified)

The agent reads files via Read/Glob/Grep, fills in every
`<to-fill>` placeholder, and returns the **complete** markdown.

Write the agent's output to a new temp file.

### Step 5 — Validate

```bash
bash .claude/skills/audit/audit.sh validate <agent-output-file>
```

Exit 0 → proceed to save.
Exit 3 → surface the validation errors to the user, ask whether
to re-prompt the agent or accept the partial output.

### Step 6 — Save

```bash
bash .claude/skills/audit/audit.sh save <target> <agent-output-file>
```

Echoes the saved path (`docs/audits/<date>-<slug>.md`, with -2/-3
collision suffix).

### Step 7 — Surface to user

Pass the agent's complete output to the user **verbatim** (per the
Output policy above), followed by a single closing line:

```markdown
*Saved to* `docs/audits/<date>-<slug>.md`
```

No preamble, no summary, no follow-up questions inside the audit
proper.

## Evolving this skill

This skill is designed to be updated as the team learns what makes
an audit useful. Things that change:

- **Add a section** → append to `AUDIT_SECTIONS` in `audit.sh` AND
  update the auditor agent's system prompt to write content for it.
- **Add a severity tier** → append to `SEVERITY_TIERS` in `audit.sh`
  AND update the auditor agent's severity scheme.
- **Add a lens** → append to `LENSES` in `audit.sh` AND add a
  stanza to the auditor agent's "## The lens" section.
- **Support a new manifest** (e.g. `pyproject.toml`) → add an entry
  to `MANIFEST_PARSERS` in `audit.sh` AND write the parser function.

Avoid restructuring the audit *shape* (TL;DR + Breakdown + What's
working + Findings + Tradeoffs + Open questions + Bottom line)
without a /codify or /decision pass — the uniformity is the value.

## What you must NOT do

- **Don't hand-write the audit.** All structure comes from the
  script; all judgment from the agent. Hand-rendering bypasses the
  validation layer and breaks uniformity across audits.
- **Don't summarize, paraphrase, or rephrase** the agent's output
  before showing it to the user. The whole point is identical
  shape every time.
- **Don't propose patches or file tasks.** Audit produces findings;
  the user routes follow-ups via `/task`.
- **Don't auto-commit.** Saved audit lands uncommitted in the
  working tree; user reviews + commits.
- **Don't expand scope.** If something out-of-scope catches your
  eye, the agent footers it as an Open question. Don't grow the
  audit unilaterally.

## When NOT to use this skill

- **Pre-merge review of a specific change** — `/audit` works with
  `--lens code` for this, but the scope is "the slice as a whole,"
  not "this PR." For PR-specific review against a base ref, the
  auditor agent can be invoked directly with a diff target.
- **Single-decision capture** → `/decision`.
- **Incident postmortem** → `/postmortem`.
- **Strategic "what should we do next"** → `/plan`.
- **Code-level help fixing the findings** → after `/audit`, route
  individual items through `/task` or pick them up directly.

## What "done" looks like for a /audit session

- Audit rendered in chat verbatim from the script + agent pipeline.
- Saved to `docs/audits/<YYYY-MM-DD>-<slug>.md`.
- One closing line surfacing the saved path.
- No file modifications outside `docs/audits/`.
- No commits.
- User can re-read the audit later (it's durable history) or route
  findings to `/task`.
