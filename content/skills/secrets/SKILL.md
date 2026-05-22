---
name: secrets
description: Provision a project's secret values into a .env without the AI ever seeing one. secrets.sh builds a guided, commented form in a central store outside the repo, symlinks it in, opens it in the user's editor at the first blank field, and verifies completeness key-only. Triggered when secrets need to be set or checked — e.g. "/secrets", "set up my .env", "I need to enter API keys", "provision secrets", "the app needs DATABASE_URL", or when a run fails on a missing required env var.
---

# /secrets — Provision secrets the AI never touches

Gets real secret values into a project's `.env` **without a value ever
entering Claude's context**. The user types values into their editor;
the AI builds the form, opens it, and verifies it — and never reads it.

The mechanics belong to **`secrets.sh`**. This SKILL.md is the routing
layer: when to provision, how to run the verify loop, and how to make
the guided form genuinely helpful.

**Security guarantee.** A secret value never reaches the AI. The script
may read the store (to tell `set` from `empty`) but never prints a
value. Any flow that would expose one is a bug. See `secrets-rules.md`
for the full doctrine; pairs with `env-rules.md` (the env-var stamp
model) and `import-env` / `export-env`.

## How it works

- The real values live in a **central store outside any repo** —
  `~/.claude/projects/<project-key>/secrets/env`, mode `0600` — so the
  bytes physically cannot sit inside the repo directory. The kit's
  user-separation convention: personal state lives under `~/.claude/`.
- `<repo>/.env` is a **symlink** to that store, gitignored. All
  worktrees of one project share a single store — set a secret once.
- `provision` writes a **guided form**: per key, a comment block
  (what it is, required/optional, type, where to get it) above a blank
  `KEY=`. The user fills a form, not a blank page.

## The script

Lives at `kit/skills/secrets/secrets.sh` (or
`.claude/skills/secrets/secrets.sh` in synced projects). Always invoke
with `bash` per `script-craft.md`.

```text
bash <skill-dir>/secrets.sh provision [--keys K1,K2,…]
    Materialize the store + symlink, append guided-form blocks for any
    missing keys, open the store in a GUI editor at the first blank
    field. Append-only — never clobbers a filled value.

bash <skill-dir>/secrets.sh check [--keys K1,K2,…]
    Report set / empty / missing per key. Never prints a value.
    Exit 0 = all set; exit 3 = keys still unfilled.

bash <skill-dir>/secrets.sh path        Print the store file path.
bash <skill-dir>/secrets.sh migrate     Adopt an existing real .env
                                        into the store, symlink it.
bash <skill-dir>/secrets.sh hooks on|off|status   Manage the guards.
```

Key source, in priority order: `--keys` › `<repo>/.env-template` ›
`env/stamps/*.md`. Exit codes: `0` ok, `1` operational, `2` usage,
`3` refused / keys unfilled.

## Behavior contract

### Never read the secret

Do not `Read`, `cat`, `grep`, or otherwise open `<repo>/.env` or the
store. To learn whether a key is set, run `secrets.sh check` — it
answers key-only. This holds even when the guard hooks are not
installed; the hooks enforce it, they are not what makes it true.

### When to provision

`/secrets` is workflow-triggered — the user should never have to name
or find the file. Run `provision` when:

- A run, test, or `/setup-deploy` fails on a missing required env var.
- A freshly initialized project declares required secrets.
- The user explicitly asks to set or enter secrets.

### Make the form genuinely helpful

Before provisioning, make sure the env-var stamps the form is rendered
from are worth rendering. `provision` pulls each key's comment block
from its `env/stamps/*.md` stamp — `description`, `required`,
`purpose`, `type`, and any stamp-body line beginning `Get it:` or
`Source:`. So:

- If a key has **no stamp**, the form says so. Offer to run
  `/import-env` first so the key gets a real description.
- If a stamp lacks a **`Get it:`** line, you may add one to the stamp
  body — but only from the stamp's own recorded source, or, if you are
  inferring the acquisition URL yourself, mark it `Get it: <url>
  (unverified)`. A guessed URL must never look authoritative. Editing
  a stamp is always safe — stamps hold no values.

### Run the verify loop — don't assume

`provision` opening an editor is not the end. Close the loop:

1. Run `provision`. It opens the store at the first blank field.
2. Tell the user, in chat, **exactly which keys need a value** and that
   each has a comment block explaining it. Ask them to save and say
   when done.
3. When they confirm, run `check`.
4. If `check` exits 3, name the still-empty keys and offer to reopen
   (`provision` again — it re-opens at the next blank field).

"Entered where it needs to go" is confirmed by `check`, not hoped for.

### The editor

`provision` opens a GUI editor (`code`, `cursor`, `subl`, `zed`, or
macOS `open -t`). It will **not** launch a terminal editor — that would
fight Claude Code for the terminal. If no GUI editor is found, the
script prints the path and the user opens it themselves. `SECRETS_EDITOR`
overrides the choice.

### What the AI can and cannot do

The AI writes everything *around* the value — the form, the comments,
the `Get it:` hints, the cursor position. The AI cannot obtain the
value: an API key lives in a provider dashboard and only the user can
retrieve it. That boundary is the whole point.

## The guard hooks (opt-in, per-machine)

`hooks on` installs two Claude Code hooks into
`.claude/settings.local.json` (per-machine, gitignored) — built on
`/install-hook`:

- **`PreToolUse` [`Read`|`Bash`]** → `guard-read`: denies the AI
  reading `.env*` or the store. `.env-template` / `.env.example` stay
  readable. Bash matching is best-effort.
- **`UserPromptSubmit`** → `guard-prompt`: blocks a chat message that
  carries a secret-shaped string *before it reaches the model*. High-
  precision patterns only. A false positive is cleared by resending
  the message prefixed with `!secret-ok`.

Run `hooks on` once per machine per project after pulling via `/sync`.
The hooks enforce the doctrine; they do not replace it.

## Scope

v1 handles the default `.env`. Profile files (`.env.staging`,
`.env.production`) and non-`.env` secret targets are deliberate
follow-ons — keep generated guidance focused on `.env`.
