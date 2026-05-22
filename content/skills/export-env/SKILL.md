---
name: export-env
description: Generate a .env-template (or per-profile / per-runtime variant) from env-var stamps under env/stamps/. Inverse of /import-env — takes stamp metadata, emits a placeholder-filled template grouped by stamp.group with inline comments. Triggered when the user wants to regenerate the template — e.g. "/export-env", "rebuild .env-template", "make a template for production", "what env vars does the api runtime need".
---

# /export-env — Generate `.env-template` from stamps

Reads every stamp under `env/stamps/` and emits a `.env-template` (or filtered variant) at the project root, with placeholder values and inline metadata comments. The mechanics live in **`export-env.sh`**; this SKILL.md routes the user through choosing filters and confirming overwrites.

Inverse of `/import-env`. The two skills round-trip:
- `/import-env` reads `.env*` → writes stamps
- `/export-env` reads stamps → writes `.env-template`

Pairs with `env-rules.md`.

## Behavior contract

### Discover, don't assume

1. Run `export-env.sh list-profiles` to see what profile names are referenced by stamps.
2. Check `import-env.sh list` to see how many stamps exist and their groups.
3. Check whether `.env-template` already exists at project root.
4. If `.claude/runtimes/*.md` exists, list runtime names — useful for `--runtime` filter.
5. If `.claude/clouds/*.md` exists, list cloud names — useful for `--cloud` filter.

### Pick the scope

Ask the user what kind of template they want:

> What should I generate?
>
>   (1) Full `.env-template` — every active stamp, default for new projects
>   (2) Required-only template — minimum set the system needs to boot
>   (3) Per-profile — only stamps used by a specific profile (e.g. `production`)
>   (4) Per-runtime — only stamps a specific runtime needs (e.g. `api`)
>   (5) Per-cloud — only stamps a specific cloud needs
>   (6) Per-group — only one domain (e.g. `database`)
>
> Multiple filters combine — you can do "production + required-only", etc.

For each, suggest the corresponding `export-env.sh build` flags.

### Default output: `.env-template` at project root

If the user is doing the canonical full export, output is always `<project-root>/.env-template`. For variants, suggest naming:
- `--profile production` → `.env.production-template`
- `--runtime api` → `.env.api-template`
- `--required-only` (no other filter) → `.env-required-template`
- Combined: `.env.<profile>-<runtime>-template` (or just `.env-custom-template`)

These are conventions; the user can override `--output` to any path.

### Preview before writing

Always offer a preview first:

> I'll run: `export-env.sh build --profile production --required-only --output .env.production-template`
>
> Preview the output before writing? [yes / just-do-it / cancel]

If yes, run `export-env.sh preview <same flags>` and show the result. Then ask if it should be written.

### Confirm overwrite

If the target file exists:

> `.env-template` already exists. Options:
>   (1) Overwrite (`--force`) — replaces the file
>   (2) Diff first — show what would change vs current
>   (3) Cancel
>
> For diffing the existing file vs current stamps, use `export-env.sh diff <file>`.

Don't auto-`--force`. Confirm.

### Run the build

Invoke `export-env.sh build` with the chosen flags. Capture stdout/exit code:

- Exit 0 = wrote successfully → report the path and var count
- Exit 1 = error (file exists without `--force`, missing stamps dir, etc.) → surface the message
- Exit 2 = usage error → bug in this skill's invocation, surface and abort

### Report

After writing, show:

```markdown
## ✓ `.env.production-template` written

**Filters:** profile=production, required-only
**Vars exported:** 14
**Groups:** database/postgres (5), database/redis (3), auth/jwt (1), external-apis/openai (1), cloud/azure (4)

### What's in it

Required-only — minimum vars to boot in `production`. Optional/feature-flag
vars are excluded; they default to their stamp's `default` field if you add
them later.

### Diff vs prior `.env.production-template`

(skipped — no prior file existed)

OR (if file existed and was overwritten):

### Diff vs prior `.env.production-template`

  + Added (in this run, not in prior file):
    - SENTRY_DSN
    - DATADOG_API_KEY
  - Removed (in prior file, not in this run):
    - LEGACY_FEATURE_FLAG (retired stamp)

### Next steps

1. Inspect: `git diff .env.production-template`
2. Copy to actual profile: `cp .env.production-template .env.production && # fill in values`
3. Commit the template: `git add .env.production-template && git commit -m "chore: regenerate .env.production-template from stamps"`

The actual `.env.production` file should NOT be committed (it's in
`.gitignore`). Only the template.
```

### Diff mode

If the user just wants to check drift between actual `.env*` and stamps (rather than regenerate):

> Run `export-env.sh diff <env-file>` to see:
>   - **Required vars missing** from the file (system won't boot)
>   - **Optional stamps not present** (probably expected)
>   - **Vars in file but no stamp** (run `/import-env` to register them)

Surface the script's diff output verbatim. Exit code 3 = required drift; exit 0 = clean.

### Validate the round-trip

Optionally, after exporting and before the user runs the result:

> Want to verify? I'll round-trip-check:
> 1. Re-parse the new `.env-template` to extract keys
> 2. Compare against the stamps it was built from
> 3. They should match exactly

Run `import-env.sh parse <new-template>` and `import-env.sh diff <new-template>`. If anything's NEW or MISSING, surface — could indicate a bug in `export-env.sh` or a stamp without a `var_name` field.

### Never auto-commit

Same kit convention as every other writing skill. Generated file is unstaged; the user reviews and commits.

## Output format the script generates

```bash
# .env-template — generated from env/stamps/ by export-env.sh
#
# Regenerate: /export-env  OR  ./kit/skills/export-env/export-env.sh build
# Values shown are placeholders. Copy this file to .env (or
# .env.<profile>) and replace placeholders with real values. Real
# values must never appear in committed files.
#
# Generated: 2026-05-13 22:48:05 UTC
# Filter: required-only

# ─── auth/jwt ──────────────────────────────────────────────
JWT_SECRET=__SECRET__    # required, secret, string — JWT signing key

# ─── database/postgres ──────────────────────────────────────────────
POSTGRES_HOST=__SET_ME__       # required, connection, string — Postgres server
POSTGRES_PASSWORD=__SECRET__   # required, secret, string — Connection password
POSTGRES_PORT=0                # required, connection, int — Port (typically 5432)
```

### Placeholder convention

| Stamp shape | Placeholder |
|---|---|
| required, type=string | `__SET_ME__` |
| required, purpose=secret | `__SECRET__` |
| required, type=url | `__URL__` |
| required, type=int | `0` |
| required, type=bool | `false` |
| required, type=list | `__COMMA_SEPARATED__` |
| required, type=json | `{}` |
| optional + default | the default value |
| optional, no default | empty (line is `KEY=` then nothing) |

The placeholders are intentionally distinct from real-looking values so a populated `.env` is obvious if it's accidentally committed.

## Script reference (`export-env.sh`)

```sh
export-env.sh build [opts]              # write template
export-env.sh preview [opts]            # same as build but stdout, no write
export-env.sh diff <env-file> [opts]    # compare file vs stamps
export-env.sh list-profiles             # all profile names referenced
export-env.sh help
```

Filter flags (apply to build/preview/diff):
- `--profile <name>` — stamps with `environments[]` containing name
- `--runtime <name>` — stamps with `used_by.runtimes[]` containing name
- `--cloud <name>` — stamps with `used_by.clouds[]` containing name
- `--group <pattern>` — substring match against `group:` field
- `--required-only` — skip `required: false` stamps
- `--include-deprecated` — include `status: deprecated` (default: skip)
- `--include-retired` — include `status: retired` (default: skip)

Build/preview-only:
- `--output <path>` — default: `.env-template`
- `--force` — overwrite existing `--output` without prompting
- `--stdout` — emit to stdout instead of file

Exit codes:
- `0` success / no drift
- `1` operational error (no stamps dir, file exists without --force)
- `2` usage error
- `3` diff drift (required vars missing from file)

## What this skill does NOT do

- **Doesn't write values.** Only placeholders. Real values live in gitignored profile files.
- **Doesn't auto-commit.** Generated template is left unstaged for review.
- **Doesn't read existing `.env*` values** (even to preserve them across regeneration). Templates are pure metadata.
- **Doesn't enforce stamp completeness.** If `env/stamps/` is empty, the output is just a header. Run `/import-env` first.
- **Doesn't manage secrets sources.** Per-stamp source documentation lives in the stamp's body (`env-rules.md`).

## When to invoke this skill

- After running `/import-env` for the first time — generate the canonical `.env-template`
- After adding/editing stamps — regenerate so the template stays in sync
- Setting up a new environment — generate `.env.<new-profile>-template` to fill in
- Auditing — `export-env.sh diff .env.production` to surface drift between deployed config and stamps
- Onboarding a new contributor — they get the template via `.env-template`, copy to `.env`, fill in placeholders

If `env/stamps/` is empty, run `/import-env` first (or write stamps by hand). `/export-env` has nothing to export without stamps.

---

**See also:** `import-env` (the inverse skill), `env-rules.md` (stamp model), `stamps.md` (universal stamp pattern), `script-craft.md` (doctrine: script owns mechanics).
