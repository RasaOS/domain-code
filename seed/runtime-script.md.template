---
name: <kebab-case-runtime-name>
kind: script
language: <python | javascript | typescript | bash | ruby | go | rust | other>
framework: <click | typer | yargs | commander | cobra | other | none>

commands:
  install: "<install deps — e.g. pip install -e ., npm ci>"
  run: "<run script — e.g. python -m mycli, node ./bin/cli.js>"
  test: "<test command — e.g. pytest, npm test>"
  lint: "<lint command — e.g. ruff check ., eslint .>"

# CLI scripts typically take args
default_args: ""        # e.g. "--help"

env:
  template: ".env-template"           # committed example
  file: ".env"                        # default local
  environments:                       # named profiles (optional)
    local: ".env"
  required: []
  optional: {}

depends_on: []          # services or other runtimes the script needs

process:
  type: one-shot        # not long-running

tags: []
---

# <Name> — CLI / script runtime

> One-shot script (CLI tool, batch job, generator). Builds-and-exits
> rather than runs-as-a-daemon.

## What this is

<One paragraph: what the script does, who runs it, when. E.g.
"Data importer for the analytics pipeline. Run manually for
backfill; cron'd in prod for nightly imports.">

## How to run

```sh
<install command>
<run command> [--your-args]
```

Default args (no args): see `default_args` in the stamp.

## Common invocations

```sh
# <One-line description>
<run command> --flag value

# <Another invocation pattern>
<run command> subcommand --arg
```

## Arguments / subcommands

| Flag / subcommand | Purpose |
|---|---|
| `<flag>` | <description> |
| `<flag>` | <description> |

Or: `<run command> --help` lists everything.

## First-time setup

1. Install: `<install command>`
2. If env vars required: copy `.env.example` → `.env` and fill in

## Gotchas

- ...

## References

- <link to framework / CLI library docs>
- <link to internal usage notes, if any>

---

*Last verified working: <YYYY-MM-DD>.*
