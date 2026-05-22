---
name: lint-kit
description: Lint the kit for platform-specific drift. Iterates over universal kit files (any `kit/*.md`, `kit/skills/<name>/SKILL.md`, and `bootstrap/*.template` whose basename does NOT start with a platform prefix) and reports content that should live in a platform-prefix file (`ios-`, `android-`, `web-`, `python-`, `go-`, `ruby-`, `rust-`). Wraps `bin/lint`. Triggered when the user wants to enforce the platform-prefix naming convention — e.g. "/lint-kit", "lint the kit", "check for platform drift", "any iOS stuff leaked into universal files?", "is the kit cross-platform clean?".
---

# /lint-kit — Catch platform drift in universal kit files

The kit's naming convention says iOS-specific content lives in
`ios-task-rules.md`, web-specific in `web-task-rules.md`, etc. —
universal files (no platform prefix) should stay platform-neutral.
Nothing else enforces this. This skill does.

Per CLAUDE.md ethos: calibrated confidence. The linter rates each
finding HIGH / MEDIUM / LOW. HIGH means "this looks like real drift";
MEDIUM means "worth a look"; LOW means "almost certainly a
multi-platform reference, listed for completeness." Report the
findings, name the calibration, let the user decide what to act on.

## Behavior contract

- **Read-only by default.** `/lint-kit` runs `bin/lint`, renders the
  §6 Severity audit report, and reports the exit code. It does not
  edit files. The `/lint-kit fix` flow is the consent-gated edit path.
- **Scope is the kit, only.** This skill lints `kit/*.md`,
  `kit/skills/<name>/SKILL.md`, and `bootstrap/*.template` — and
  only those whose names do NOT start with a platform prefix
  (`ios-`, `android-`, `web-`, `python-`, `go-`, `ruby-`, `rust-`,
  `kotlin-`, `swift-`). Project files (`.claude/`, `docs/`,
  `tasks/`) are out of scope.
- **The linter is the source of truth.** Don't second-guess the
  classification in the rendered report. If the user disagrees with
  a HIGH or MEDIUM, hear them out — false positives feed the
  calibration loop. But don't pre-emptively downgrade findings
  without explicit user input.
- **Exit code matters.** `bin/lint` exits non-zero if there are any
  HIGH findings. Surface this — "1 HIGH finding, exit 1" is part
  of the report.
- **Never auto-fix.** Even when the user invokes `/lint-kit fix`, no
  edit is applied without an explicit "yes" for that specific finding.
  The whole flow is consent-gated, item-by-item.

## Process

### Step 1 — Run `bin/lint`

```bash
./bin/lint
```

The script:
1. Enumerates universal kit files (per the scope rule above).
2. Greps each for platform-specific tokens (xcodebuild, fastlane,
   Package.swift, gradle, package.json, npm run, react, vite,
   pyproject.toml, pip install, Cargo.toml, Gemfile, etc.).
3. Classifies each hit by severity using the line itself plus a
   ±5-line context window — table rows, blockquotes, "etc.",
   multi-platform enumeration paragraphs, quoted style-rule
   examples, and template placeholders all suppress to LOW.
4. Renders a §6 Severity audit (severity bars + finding rows for
   HIGH and MEDIUM; LOW rolls up into a one-line summary).
5. Exits 1 if any HIGH; 0 otherwise.

If `bin/lint` returns no output (broken script, empty kit), say so
plainly and stop. Don't fabricate findings.

### Step 2 — Render the report verbatim

The script's stdout already follows §6 Severity audit. Render it
in chat as a code-fenced block (it uses Unicode box-drawing /
sparkline characters that need a monospace fence — see
`output-rules.md` "Rendering constraints").

If the user passes `verbose` (or `--verbose`), set `VERBOSE=1` in
the environment so LOW findings render too.

### Step 3 — Honest summary

After the rendered report, add a 1-2 line plain-prose summary:

- Total findings, exit code, and what the user should do next.
- If `n_high > 0`: "Run `/lint-kit fix` to walk through each HIGH
  finding interactively."
- If `n_high == 0` and `n_medium > 0`: "No HIGH drift found. The
  MEDIUM findings are worth a read but don't block."
- If everything is clean: "Clean. No detectable platform drift."

Don't editorialize. The catalogue handles the visual; the summary
is one factual sentence.

## `/lint-kit fix` — Interactive remediation

When the user invokes `/lint-kit fix` (or "lint-kit and fix the
HIGH findings"), enter the consent-gated edit flow.

### Step 1 — Run lint, parse findings

Run `bin/lint` and collect HIGH findings. (Don't act on MEDIUM or
LOW unless the user asks for those tiers explicitly.)

### Step 2 — For each HIGH finding, ask

For each HIGH finding, present:

```markdown
**Finding 1 of <N>** — `<rel-path>:<lineno>`

  <line text, trimmed>

`<token>` is iOS-specific. Suggested move: `kit/ios-task-rules.md`
(or another `ios-*` file).

Options:
  (a) Move this content to <suggested ios-* path>
  (b) Rephrase in place to be platform-neutral (e.g. "the project's
      build command per CLAUDE.md")
  (c) Leave it — false positive
  (d) Skip for now

What's your call?
```

Wait for the user's response. Don't batch — handle one at a time.

### Step 3 — On (a) Move

- Read the source line and its enclosing paragraph (extend until a
  blank line or section heading).
- Show a diff preview: source removal + target append.
- Ask one more time: "Apply this move? (yes/no)"
- Only on explicit `yes`, write the changes (Edit / Write tool).
- The change lands in the working tree, uncommitted.

### Step 4 — On (b) Rephrase

- Propose a rewrite that uses neutral wording (e.g. `package.json` →
  `the project's manifest`, `xcodebuild test` → `the project's test
  command`).
- Show a diff: old line vs. new line.
- Ask: "Apply this rewrite? (yes/no)"
- On `yes`, edit the line. On `no`, log it as skipped and move on.

### Step 5 — On (c) Leave / (d) Skip

- (c) Leave — note the false positive in a footer at the end of
  the session. After all findings handled, surface those notes:
  "False positives noted (consider tuning `bin/lint` regex):
  - file:line — token — reason"
- (d) Skip — quietly skip; no footer entry.

### Step 6 — Closing summary

After all findings handled:

```markdown
✅ /lint-kit fix complete.

  Applied: <N moves, M rewrites>
  Skipped: <N>
  Marked false-positive: <N>

Re-run `/lint-kit` to verify HIGH count is now zero.

Files touched:
  - <path:line>
  - <path:line>

Diff:
  git diff <list of files>

Commit when ready.
```

## Output structure

**Catalogue entry.** §6 Severity audit (primary). The `bin/lint`
script's stdout already renders this; surface it inside a code fence
in chat.

The output rendered by `bin/lint`:

```
  KIT LINT   ·   <N> findings across <M> universal files


  ●  HIGH      ━━━━━━━━━━━━━━━━━━   <n_high>
  ●  MEDIUM    ━━━━━━━━━━━━━━━━━━   <n_medium>
  ●  LOW       ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ <n_low>


  ▌ HIGH     ·  <rel-path>:<lineno>
    <token> found · <line text, trimmed to 100 chars>
    └─ move to a <prefix>-* file (e.g. `<prefix>-task-rules.md`,
       `kit/skills/<prefix>-<name>/`)

  ▌ MEDIUM   ·  <rel-path>:<lineno>
    ...

  ⋮  <n_low> LOW findings suppressed (multi-platform reference
     contexts) · re-run with VERBOSE=1 to show
```

## Style rules

- **Render structured deliverables per `output-rules.md`.** The
  rendered §6 audit comes from `bin/lint`; treat it as canonical
  and don't reformat. Add only a 1-2 line plain-prose summary
  after.
- **Cite findings as `path:line`.** The linter already does this;
  preserve it verbatim when discussing findings in chat.
- **Calibrate the language.** "1 HIGH finding" is fine. "1
  critical drift issue" is not — HIGH is the linter's term, use it.
- **Don't editorialize the LOW summary.** The "⋮ N LOW findings
  suppressed" line is structural; don't comment on it unless the
  user asked.

## What you must NOT do

- **Don't fix without consent.** `/lint-kit` reports; `/lint-kit fix`
  asks per finding. There is no "auto-apply all" mode and never
  will be. The cost of an unwanted edit is higher than the cost of
  one extra round-trip.
- **Don't lint outside `kit/` and `bootstrap/`.** Project files,
  `docs/`, `tasks/`, the user's working code — out of scope. If
  the user asks to lint their project, redirect to `/audit` or
  `/scope-check`.
- **Don't tune `bin/lint` mid-flow.** If the user disagrees with a
  classification, log it as a false positive and keep moving. Regex
  tuning is a separate task — file a `/contribute` PR, not an
  inline edit.
- **Don't commit.** Standard kit rule. Edits land uncommitted; the
  user reviews with `git diff` and commits.
- **Don't expand scope unilaterally.** If something out-of-scope
  catches your eye while reading a file (a typo, a stale link),
  surface it in a one-line "Adjacent observations" footer at most.
  Don't grow the lint pass into a general kit-quality pass.

## Edge cases

- **README.md and other intentionally-cross-cutting files.** The
  kit's `README.md`, `CLAUDE.md.template`, `task-template.md`,
  `release-rules.md`, `output-rules.md`, and `output-styles.md` are
  *expected* to mention multiple platforms side-by-side as
  reference. The linter knows about these and applies a severity
  floor drop (HIGH → MEDIUM in those files). If the user disagrees
  with a finding in one of these files, default to "leave it."
- **A genuine cross-platform skill mentions platform-specific
  examples.** `/run`, `/build`, `/release`, `/task`, `/wrangle`,
  `/audit` — these are universal but reference per-platform
  manifests as a *table* or *bulleted list*. The linter
  recognizes this pattern and suppresses to LOW. If a HIGH still
  comes through, the line probably *isn't* in a list — it's prose
  that quietly assumed one platform. That's real drift.
- **Quoted style-rule examples.** Files like `lessons/SKILL.md`
  and `stuck/SKILL.md` use `"phrasing like this"` as
  illustrations. The linter detects 2+ double-quotes in the
  ±5-line window and suppresses to LOW.
- **`bin/lint` script broken or missing.** If the script doesn't
  exist or returns a non-zero exit without output, stop and tell
  the user — "Couldn't run `bin/lint`. Is the file present and
  executable?" Don't fabricate findings.
- **The kit grows a new platform prefix.** When `kit/swift-foo.md`
  becomes a thing, `bin/lint` already excludes the `swift-` prefix
  via its `PLATFORM_PREFIXES` list. New prefixes added there
  propagate without further skill edits.
- **The user asks to lint a single file.** Out of scope for this
  skill — the linter operates on the whole kit. If they want a
  single-file review, route to `/audit` or `/review`.
- **VERBOSE / NO_COLOR.** `VERBOSE=1` shows LOW findings;
  `NO_COLOR=1` strips ANSI codes. Pass these through if the user
  asks.

## When NOT to use this skill

- **Linting a project, not the kit** → `/audit` for codebase
  reviews, `/scope-check` for surface-area reality checks.
- **Looking for output-style violations** (catalogue mismatch,
  glyph misuse) → not in scope; this skill enforces *naming
  convention* drift, not *output* drift. File a `/contribute` PR
  with a separate output-lint proposal if needed.
- **Wanting to change the regex catalog** → that's a `/contribute`
  edit against `bin/lint`, not a `/lint-kit` invocation.
- **Cleaning up commit history or running other repo hygiene** →
  out of scope. This skill answers one question: does universal
  content reference single-platform tokens?

## What "done" looks like for a /lint-kit session

A rendered §6 Severity audit in chat, with HIGH / MEDIUM / LOW
counts and the finding rows. The user knows the exit code. If
they ran `/lint-kit fix`, the working tree has applied moves and
rewrites for the findings they approved (uncommitted), plus a
note about any they marked as false positives. The next step is
either commit (if changes were applied) or — if the report was
clean — nothing.
