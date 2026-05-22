---
name: contract
description: Manage the project's system contracts — schemas, API endpoints, and system docs that other code (and other repos) depend on. Contracts live in contracts/ as versioned, date-stamped stamps. A lock flag freezes a contract; a locked contract blocks any task that needs to change it until the user explicitly unlocks it. A PreToolUse guard hook denies hand-edits under contracts/; every change is recorded in an append-only ledger (who/what/why/when). Subcommands: init, status, new, update, bump, lock, unlock, off, check. Triggered when the user wants to manage system contracts — e.g. "/contract", "lock the schema", "add a contract for the new endpoint", "is the schema locked", "set up the contracts folder", "unlock the user schema".
---

# /contract — system-contract registry with lock + ledger

A project has a handful of definitions that other code depends on
being stable — the database schema, an API endpoint shape, a
system doc. When one of those drifts silently, things break far
from the change. `/contract` gives those definitions a home: a
`contracts/` folder where each is a versioned, date-stamped stamp,
and a **lock** that turns "please don't change this" into a hard
block.

Built on **`/install-hook`**. The script `contract.sh` owns every
file mutation — stamp writes, version bumps, the lock flag, the
ledger — so the audit trail can never lie. This SKILL.md routes
the verb and synthesizes contract bodies; it does not hand-edit
anything under `contracts/`.

Per CLAUDE.md ethos: the ledger is a factual record. Every entry's
**why** is the real reason, written plainly — not a narrative.

## Behavior contract

- **Script-driven mechanics.** `contract.sh` owns the `contracts/`
  folder, stamp format, version stamping, lock flag, ledger, and
  index — per `script-craft.md`. The AI synthesizes contract
  *content* and routes the verb. Never hand-write the files the
  script manages. Always invoke as `bash <skill-dir>/contract.sh …`.
- **The guard blocks hand-edits — including yours.** After
  `/contract init`, a `PreToolUse` hook denies `Edit`/`Write`/
  `MultiEdit` anywhere under `contracts/`. To create or change a
  contract you **synthesize the body, write it to a temp file
  outside `contracts/`, and pass `--from <tempfile>`**. The script
  writes the stamp via shell, which the hook does not intercept.
- **A locked contract is a hard stop.** If a task needs to change a
  locked contract, `contract.sh` refuses (exit 3) and the guard
  hook denies the edit. Do not work around it. Stop, tell the user
  which contract is locked and why the change is needed, and wait
  for them to unlock it. That is the whole point of the lock.
- **Every change carries a `--why`.** `new`, `update`, `bump`,
  `lock`, `unlock` all require `--why "<reason>"`. The reason goes
  straight into the ledger. No silent changes.
- **The hook is shared, not personal.** It installs into
  `.claude/settings.json` (committed) so every contributor's
  session enforces the same discipline — unlike most kit hooks,
  which are per-user.
- **Never auto-commit.** Standard kit rule. `contract.sh` mutates
  files; the user reviews with `git diff` and commits.
- **Stay in scope.** This skill manages a project's *own*
  contracts. Cross-repo linking and drift scanning are a separate
  concern — see "When NOT to use this skill".

## What the guard hook covers — honestly

The `PreToolUse` hook denies the `Edit`, `Write`, and `MultiEdit`
tools on paths under `contracts/`. That catches the realistic
failure mode: an agent reaching for an edit tool to change a
contract. It does **not** police raw shell — a determined
`Bash` redirection into `contracts/` is out of its reach. The
hard guarantee for the sanctioned path is the script itself:
`contract.sh update`/`bump` refuse a locked contract outright.
The hook + the script + the documented rule (`contract-rules.md`)
are three layers; none is individually airtight, together they
cover every path an honest session takes. A git `pre-commit`
guard would close the raw-shell gap — noted as a future hardening.

## Interface

```text
bash <skill-dir>/contract.sh init
    Scaffold contracts/ + install the guard hook. Idempotent.

bash <skill-dir>/contract.sh status
    List every contract (name, kind, version, status, lock) and
    whether the guard hook is installed.

bash <skill-dir>/contract.sh new <name> --kind <schema|endpoint|doc>
        --why <reason> [--from <body-file>] [--owner <name>]
    Create a contract stamp. Body from --from, else a stub.

bash <skill-dir>/contract.sh update <name> --from <body-file> --why <reason>
    Replace a contract's body. Refused (exit 3) if locked.

bash <skill-dir>/contract.sh bump <name> <major|minor|patch> --why <reason>
    Bump the version. Refused if locked.

bash <skill-dir>/contract.sh lock <name> --why <reason>
    Freeze the contract. Refused changes until unlocked.

bash <skill-dir>/contract.sh unlock <name> --why <reason>
    Permit changes again.

bash <skill-dir>/contract.sh check <path>
    Exit 3 if <path> is a locked contract, else 0. Pre-flight
    check for a task about to touch a contract.

bash <skill-dir>/contract.sh off
    Remove the guard hook. Leaves contracts/ intact.

bash <skill-dir>/contract.sh guard
    PreToolUse hook handler — called by the hook, not by hand.
```

Exit codes: `0` success, `1` operational, `2` usage, `3` refused
(locked / name collision / precondition unmet). Surface stderr
verbatim on non-zero.

## Process

### Step 1 — Map intent to a verb

- "set up contracts" / "/contract init" → `init`
- "what contracts do we have" / "is X locked" → `status`
- "add a contract for X" → `new`
- "change / update contract X" → `update`
- "bump the version of X" → `bump`
- "lock X" / "freeze the schema" → `lock`
- "unlock X" → `unlock`
- "stop guarding contracts" → `off`

If `contracts/` isn't initialized yet and the user wants to add a
contract, run `init` first (tell them you're doing so).

### Step 2 — For a content change, synthesize the body first

`new` and `update` need a contract body. Because the guard hook
blocks edits under `contracts/`, the workflow is:

1. **Synthesize** the contract body — the actual schema DDL, the
   endpoint request/response shape, the system doc. Ground it: if
   it mirrors real code, read that code first.
2. **Write it to a temp file** outside `contracts/` — e.g.
   `/tmp/contract-body-<name>.md`. This is a normal `Write`, not
   blocked.
3. **Pass it** via `--from /tmp/contract-body-<name>.md`.

Show the user the body you synthesized before running the script.

### Step 3 — Run the verb

```bash
bash .claude/skills/contract/contract.sh <verb> <name> [flags]
```

Surface the script's stdout verbatim. On a non-zero exit, surface
stderr verbatim and stop — do not retry or work around it.

### Step 4 — Handle a lock refusal

If `update`/`bump` exits 3 because the contract is locked, **that
is the feature working.** Do not unlock it yourself to get
unblocked. Surface this to the user:

```markdown
🔒 Contract `<name>` is locked — this task is blocked.

**The change the task needs.** <one line — what would change>
**Why it's locked.** <from the ledger / the lock entry>

To proceed you'd run:
    /contract unlock <name> --why "<reason>"

Want to unlock it, or should this task stop here?
```

Then wait. The user decides.

### Step 5 — Closing summary

Brief. One block for a mutation, the table for `status`.

## Output structure

`status` renders the script's table verbatim. For a mutation, a
tight confirmation:

```markdown
✅ Contract `<name>` <verb-result>

- **Version.** <old → new, or current>
- **Lock.** <locked | unlocked>
- **Ledger.** Recorded — `contracts/LEDGER.md`

<next step if any — e.g. "Review with `git diff contracts/` and
commit.">
```

## Style rules

- **Surface script output verbatim.** The script already says what
  happened; don't paraphrase it.
- **Show the synthesized body before writing it.** A contract is a
  consequential artifact — the user reviews the content, the
  script handles the filing.
- **The ledger `why` is plain fact.** "Frozen ahead of the v3
  backend cutover" — not "Locked to ensure stability and
  alignment."
- **Don't render `guard` output in chat.** It's for the hook.
- **Cite `contracts/CONTRACTS.md` and `contracts/LEDGER.md`** as
  the durable artifacts when you close.

## What you must NOT do

- **Don't hand-edit anything under `contracts/`.** Not the stamps,
  not `LEDGER.md`, not `CONTRACTS.md`. The script owns them; the
  hook blocks you; the ledger depends on it.
- **Don't unlock a contract to get a task unblocked.** Unlocking
  is the user's call, always. A locked contract that you quietly
  unlock defeats the entire mechanism.
- **Don't skip `--why`.** An unexplained change in the ledger is
  worse than no ledger — it looks audited but isn't.
- **Don't fabricate contract content.** A schema stamp mirrors a
  real schema; an endpoint stamp mirrors a real endpoint. If you
  don't have the real shape, ask — don't invent fields.
- **Don't auto-commit.** Standard kit rule.
- **Don't put cross-repo logic here.** This skill is single-repo.

## Edge cases

- **`contracts/` not initialized.** `new`/`update`/etc. exit 1
  with "run /contract init first". Run `init`, then retry.
- **`install-hook.sh` missing.** `init`/`off` can't manage the
  hook — the script surfaces the error. The folder still works;
  the guard just isn't installed.
- **`python3` missing.** The `guard` hook can't parse its payload,
  so it allows the edit (fails open — a hook must never break a
  session). The script-level lock check still holds. Surface this
  as a known soft spot if it comes up.
- **Name collision on `new`.** Exit 3 — the contract exists. Use
  `update` instead.
- **Body file under `contracts/`.** Don't put the temp body file
  inside `contracts/` — the hook would block writing it. Use
  `/tmp/` or the repo root.
- **Guard hook fired before it existed.** Like any Claude Code
  hook, it takes effect on the *next* session start. The session
  that ran `init` is not yet guarded.

## When NOT to use this skill

- **Cross-repo contract sharing / drift detection** — out of
  scope here. `/schema-check` reconciles a local mirror against an
  externally-owned schema; cross-repo contract linking is a
  separate, later feature.
- **Filing a task to change a contract** → use `/task`. This skill
  manages the contract; `/task` files the work.
- **A one-off doc that nothing depends on** → just put it in
  `docs/`. Contracts are for definitions other code is bound to.
- **General schema design** → design it normally; register it as a
  contract once it's something others depend on.

## What "done" looks like for a /contract session

The `contracts/` folder reflects the change: a stamp created or
updated, a version bumped, or a lock flipped — with a matching
`LEDGER.md` entry recording who, what, why, and when, and a
regenerated `CONTRACTS.md` index. Uncommitted. If a task hit a
locked contract, the user has a clear decision in front of them:
unlock and proceed, or stop. The skill never made that call for
them.
