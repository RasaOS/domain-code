---
name: import-env
description: Parse an existing .env file into env-var stamps under env/stamps/. The actual file reading is done by import-env.sh — values never enter the AI's context. The skill routes the script's KEY-only output through one-question-per-var confirmations. Triggered when the user wants to register their env vars — e.g. "/import-env", "import my .env file into stamps", "register env vars", "parse .env-local into stamps".
---

# /import-env — Bulk-import env vars into stamps

Brings an existing project's env vars under the kit's env-stamp system. The mechanics (parse, diff, suggest defaults, generate stamp files) are owned by **`import-env.sh`**. This SKILL.md is the routing layer — it tells the AI which subcommands to run, when to ask the user a question, and what to put in the stamp.

**Security guarantee:** values never enter Claude's context. The script reads keys from `.env*` files; the AI never reads the file directly. Treat any flow that would expose a value as a bug.

Pairs with `env-rules.md` (stamp model). Doctrine: `script-craft.md` — script owns deterministic mechanics, SKILL.md owns content + choices.

## Behavior contract

### Discover, don't assume

1. Run `import-env.sh list` to see existing stamps.
2. List candidate `.env*` files (`.env-template`, `.env`, `.env.test`, `.env.staging`, `.env.production`, etc.) — *but do not read them*.
3. Read `env/ENV.md` if it exists (the project's narrative grouping).
4. Read `.claude/runtimes/*.md` for cross-reference hints (which runtimes declare which `env.required` vars).

### Pick the source file

Ask the user which `.env*` to import. List the files you see at project root (`ls .env*` is fine — `ls` doesn't reveal values). For each, get the line count via `wc -l <file>` to give a sense of size.

> Which `.env*` should I parse?
>
>   `.env-template`  — committed reference (24 lines)
>   `.env.staging`   — gitignored profile (28 lines)
>   `.env.production`— gitignored profile (30 lines)
>
> If picking a profile-specific file, I'll record that profile in each new stamp's `environments:` field.

### Parse without reading values

Run `import-env.sh parse <file>` — this returns one KEY per line, **no values**. That's the only file-read in the entire flow.

Then run `import-env.sh diff <file>` to split the keys into three sets:
- **NEW** — in the file, no stamp yet → walk these one by one
- **KNOWN** — in the file and already have stamps → maybe `add-profile` to record this profile
- **MISSING** — stamps exist for vars not in this file → flag for review (might be deprecated, or this profile doesn't need them)

### Walk new vars

For each KEY in the NEW set:

1. Run `import-env.sh suggest <KEY>` — gets heuristic defaults (`group`, `purpose`, `type`, `required`).
2. Check `.claude/runtimes/*.md` for any runtime declaring `env.required: [..., $KEY, ...]` — surface as a `--used-by-runtimes` hint.
3. Present to user:

```
Var 3 of 12: POSTGRES_PASSWORD

  Suggested:
    group:       database/postgres
    purpose:     secret   (auto-detected from "_PASSWORD" suffix)
    type:        string
    required:    true     (default — confirm if it's actually optional)
  
  Runtime cross-ref: used by `api` runtime (.claude/runtimes/api.md env.required)
  
  Confirm / edit:
    required?    [yes / no / not sure]
    group?       (current: database/postgres) — accept / change?
    purpose?     (current: secret) — accept / change?
    type?        (current: string) — accept / change?
    description? (one line — what is this var for?)
```

Defaults from `suggest` are accept-or-edit. Don't auto-write — always confirm.

4. Run `import-env.sh add <KEY> --required <bool> --group <path> --purpose <enum> --type <enum> --description "..." --environments <profile> --used-by-runtimes <list>` to generate the stamp.

The script writes `env/stamps/<kebab-name>.md`, stages it with `git add` is NOT done by the script — leave it as an untracked file so the user can review.

Actually let the user know they can run `git add env/stamps/` at the end.

### Bulk mode for large files

If NEW set has > 10 entries, offer:

> 23 new vars to register. Want to:
>   (1) Go one by one (recommended for the first run — establishes the taxonomy)
>   (2) Group-batch (I'll show 5 detected groups, you confirm/edit each batch)
>   (3) Accept all `suggest` defaults (fast, generates drafts you can edit after)

Bulk mode still calls `add` per-var; it just doesn't pause on each one.

For mode (3), after generating all stamps, surface which ones got `description: TODO — describe` so the user can sweep them.

### KNOWN vars — record the profile

For each KEY in the KNOWN set, if the current profile isn't in the stamp's `environments:`, offer:

> Found these vars already stamped but missing the `<profile>` profile:
>   - JWT_SECRET (currently: local, staging — missing production)
>   - SENTRY_DSN (currently: local — missing production)
>
> Add `<profile>` to their environments arrays? [yes / no / pick-by-one]

If yes, run `import-env.sh add-profile <KEY> <profile>` for each.

To know what each stamp's current environments are, parse the stamp's frontmatter (the AI can read the file — it's metadata, no values). Or use `import-env.sh list` and grep — but list doesn't print environments[] yet, so use direct file read.

### MISSING vars — flag for review

For each KEY in the MISSING set (stamp exists, not in this `.env*`):

> Stamps exist for these vars, but they're not in `<profile>` profile:
>   - OLD_FEATURE_X
>   - DEPRECATED_TOKEN
>
> Possible explanations:
>   1. This profile doesn't use them (expected — leave the stamp alone)
>   2. They've been retired (consider flipping `status: retired` in the stamp)
>   3. They should be in this profile but aren't yet (the deploy will fail when needed)
>
> Want me to drop into option 2 (mark as retired) for any?

Don't decide; surface.

### Update ENV.md (optional)

After all vars are processed:

> Update `env/ENV.md` with new entries grouped by their `group:` field?
> [yes / no / show-me-first]

If yes:
- Read all stamps (`import-env.sh list` gives the table)
- Group by their `group:` field
- Render an `ENV.md` rollup that preserves any project-authored prose outside the auto-generated groups

The AI can write this directly — no values involved.

### Resume gracefully

`/import-env` is safe to re-run. The script's `diff` subcommand identifies what's new vs known, so the second run on the same file is a no-op (or just adds the profile to already-stamped vars).

### Surface unknowns honestly

If the suggest defaults don't fit and the user doesn't know what a var is for:
- Use `import-env.sh add` with `--description "TODO — figure out what this is for"`
- `--purpose config` (the most neutral)
- `--required true` (safer — forces investigation later)
- Flag the TODO in the final summary

## Output structure

When the skill finishes, render:

```markdown
## ✓ Env vars imported from .env.staging

**Source:** `.env.staging`
**Profile recorded:** staging
**Mode:** one-by-one

### Stamps created (12)

- `env/stamps/postgres-host.md` — required, connection
- `env/stamps/postgres-password.md` — required, **secret**
- `env/stamps/chromadb-host.md` — required, connection
- `env/stamps/openai-api-key.md` — required, **secret**
- `env/stamps/log-level.md` — optional, config (default `info`)
- ... (7 more)

### Stamps updated (3)

`staging` profile added to existing stamps:
- `env/stamps/jwt-secret.md`
- `env/stamps/sentry-dsn.md`
- `env/stamps/feature-new-checkout.md`

### TODOs flagged (2)

These got `description: TODO — describe` — please review:
- `env/stamps/x-internal-token.md`
- `env/stamps/legacy-config-flag.md`

### Skipped lines

- Line 14: malformed (missing `=`)
- Line 31: comment

### Next steps

1. Review the diff: `git diff env/stamps/`
2. Sweep TODOs: `grep -l 'TODO — describe' env/stamps/*.md`
3. Update `env/ENV.md` to reflect new groupings (re-run with the rollup step, or edit by hand)
4. Stage + commit: `git add env/stamps/ && git commit -m "chore: import env vars from .env.staging into stamps"`
```

## What this skill does NOT do

- **Never reads values into Claude's context.** All file reads go through `import-env.sh` which returns KEYs only.
- **Never echoes values.** Even in error messages or summaries.
- **Never auto-commits.** Stamps are untracked files after generation; user stages and commits.
- **Never writes to `.env*` files.** Only reads (via the script) and writes to `env/stamps/`.
- **Never enforces the stamp model schema.** Best-effort drafts; user reviews and edits.

## Script reference (`import-env.sh`)

The skill calls these subcommands. See `import-env.sh help` for full details.

```sh
import-env.sh parse <file>                    # KEYs, one per line
import-env.sh diff <file>                     # NEW / KNOWN / MISSING sets
import-env.sh suggest <KEY>                   # heuristic defaults (key=value lines)
import-env.sh add <KEY> [opts]                # generate stamp
import-env.sh add-profile <KEY> <profile>     # append profile to environments[]
import-env.sh list [--required-only] [--group <pat>]   # tabulate existing stamps
import-env.sh validate                        # coverage check against .env-template
```

`add` flags: `--required`, `--group`, `--purpose`, `--type`, `--default`, `--description`, `--environments`, `--used-by-runtimes`, `--used-by-clouds`, `--tags`, `--force`.

All subcommands exit:
- `0` success
- `1` operational error
- `2` usage error
- `3` validation failed (validate only)

## When to invoke this skill

- New project with existing `.env*` files, no stamps yet — bulk import
- Existing project, added vars to `.env`, want to register them — incremental
- Migrating from another env-management system to the kit's stamp model
- Auditing — running on `.env.production` to surface drift from local

If a project has no `.env*` files, this skill has nothing to import. Write stamps by hand via `import-env.sh add` directly, or copy the example from `env-rules.md`.

---

**See also:** `env-rules.md` (full stamp model and conventions), `stamps.md` (universal stamp pattern), `script-craft.md` (doctrine: script owns mechanics, SKILL.md owns choices).
