---
name: env-sync
description: Move per-environment config (.env, .env.staging, .env.production) between the user's own machines over ssh/scp, and check whether two machines are in parity. Use for "/env-sync", "get my env files onto the other laptop", "why does this work on my desktop", "send the staging config to the server", "are my env files the same on both machines". Never reads secret values into context — it orchestrates a byte-mover it cannot see through. The destination host must be named by the user and is never inferred.
---

# /env-sync — Config parity across your machines

Credentials live in gitignored per-env dotfiles. That is simple and it
works, right up until the second machine, where the file does not exist
and nothing in the repo can tell you what was in it.

`/import-env` and `/export-env` move variable **names** and stamps; they
never move values, by construction. This moves the values.

Engine: `.claude/skills/env-sync/env-sync.sh`.

## Rules you do not get to relax

These are the reason this skill is safe to exist. Do not work around
them, and do not offer to.

1. **Never read a secret value into your context.** Not to check a
   transfer worked, not to "just confirm the key is right", not to
   summarize. Use `env-sync.sh fingerprint` and `parity`, which return
   digests and key names only. Do not `cat` a `.env*` file. Do not
   `grep` one for a value. If `/secrets` has its read-guard hook
   installed, the harness will already refuse — do not go around it.
2. **The destination is whatever the user typed.** Never infer a host
   from a git remote, `~/.ssh/config`, `known_hosts`, shell history, a
   deploy target in `environments.json`, or a hostname you saw in a
   file. If they did not name it, ask.
3. **ssh/scp to that host only.** Never a paste site, a bucket, a gist,
   an email, or any third party. If ssh cannot reach it, say so and
   offer the printed command — do not find another route.
4. **Never echo a value anywhere.** Not the terminal, not a task, not a
   ledger entry, not a commit message.
5. **Confirm before sending.** State the env, the file, and the exact
   destination, and get a yes. Sending credentials to a host is not
   reversible — the bytes are there now.

## Steps

### 1 — Look before you move

```bash
.claude/skills/env-sync/env-sync.sh status
```

Per file: present, gitignored, and a digest. **If anything shows
`IGNORED: no`, fix that first** — `env-sync.sh protect` adds `.env`,
`.env.*` and `!.env-template`. `/secrets` only ever adds the literal
`.env`, so `.env.staging` and `.env.production` are commonly exposed.
The script refuses to transport a file git does not ignore.

### 2 — Ask which direction, and where

`push` sends from here. `pull` brings here. The user names the host.

```bash
env-sync.sh command push staging user@host:/srv/app/.env.staging
```

`command` **prints the command and runs nothing**. Offer this whenever
the destination needs a passphrase, a hardware key, a jump host, or a
VPN this session cannot reach — it is a first-class outcome, not a
consolation prize. Hand them the line and let them run it.

### 3 — Transfer

```bash
env-sync.sh push staging user@host:/srv/app/.env.staging
env-sync.sh pull staging user@host:/srv/app/.env.staging
```

`scp` follows symlinks, so a `.env` managed by `/secrets` sends its
contents rather than the link. A `pull` **refuses** to overwrite a
symlink — that would orphan the secrets store — and backs up an existing
real file before writing.

Each transfer writes a ledger record (`deploys/records/ENV-*.md`, visible
via `/deploys`) holding that it happened, to which named host, when, and
the digest. Never contents, never the remote path.

### 4 — Verify parity

```bash
env-sync.sh parity staging user@host
```

Equal digests mean identical files. Different digests mean they differ —
and **which key differs is not knowable from here, by design.** A per-key
digest of a low-entropy secret is a brute-forceable value oracle, so the
script will not compute one. Compare key *names* with `fingerprint` on
both machines; for the values, the user reads their own files.

Do not promise parity you cannot prove. "Digests match" is a fact;
"your environments are in sync" is a bigger claim.

## What this does not do

- **It is not a secret manager.** It moves files you already have. To
  provision a value, use `/secrets`, which is built so the AI never sees
  it.
- **It does not do per-env secret stores.** `/secrets` keeps one store
  behind a symlinked `.env`; a per-env store plus a transport leg
  collide on every receiving machine, because `scp` deposits a real file
  and the store expects a link. The `dev`-vs-higher asymmetry is
  deliberate.
- **It does not know what the remote should contain.** Parity compares
  two files. Whether either is *correct* is `/environment` and
  `.env-template`'s question.

## Related

- `/secrets` — provision values without the AI seeing them.
- `/export-env` `/import-env` — move names and stamps, never values.
- `/environment` — the registry and each environment's class.
- `/deploys` — the ledger, including transfer records.
- `.claude/env-rules.md` — the dotenv convention.
