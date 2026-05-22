# Secret Handling Rules

How secret *values* are handled in kit-bootstrapped projects: the AI
never sees one, the user enters it directly, and the bytes live
outside the repo. **Read this file when a project needs real secret
values set, or when wiring up the secret guards.**

Pairs with `env-rules.md` — that file owns the env-var *registry*
(what each var is, via stamps); this file owns the *values* (how they
get entered and kept away from the AI). The `/secrets` skill
implements everything below.

## The cardinal rule

**A secret value never enters the AI's context.** Not in a chat
message, not in a file the AI reads, not in command output the AI
sees. The AI handles everything *around* the value — the registry,
the guided form, the completeness check — and nothing of the value
itself.

This is not a soft preference. A value that reaches the transcript is
a leak, and the transcript is durable. Treat any flow that would
expose one as a bug to fix, not a judgment call.

## Where values live

- **Central store, outside any repo:**
  `~/.claude/projects/<project-key>/secrets/env`, mode `0600`. This
  follows the kit's user-separation convention — personal, per-machine
  state lives under `~/.claude/`, never in the project tree.
- **`<repo>/.env` is a symlink** to that store, and is gitignored.
  The symlink's value is structural: the secret's bytes physically
  cannot sit inside the repo directory, so no `git add`, editor
  "save all", or folder backup can capture them. A committed symlink
  records only a path. Gitignore it anyway — defense in depth.
- **All worktrees of a project share one store.** Set a secret once;
  every worktree sees it.

## How a value gets entered

The only actor who handles a value is the **user**, in their **editor**:

1. `/secrets` builds a guided form in the store — per key, a comment
   block (what it is, required/optional, type, where to obtain it)
   above a blank `KEY=`.
2. The form opens in a GUI editor at the first blank field.
3. The user types the value and saves. The value's whole path is
   keyboard → editor → file. No process the AI drives ever holds it.
4. The AI runs `secrets.sh check` — which reports `set` / `empty` /
   `missing` per key, never a value — and loops until complete.

The AI never writes the value, never reads it back, never asks for it
in chat. If the user starts to paste one, stop them and run `/secrets`
so it goes into the editor instead.

## The AI never reads a secret file

`<repo>/.env` and the central store are off-limits to the AI — no
`Read`, no `cat` / `grep` / `head` / `sed`, no editor open. To learn
whether a key has a value, run `secrets.sh check`. `.env-template` and
`.env.example` are *not* secret files (placeholders only) and may be
read freely.

This holds whether or not the guard hooks are installed. The hooks
*enforce* the rule; they are not what *creates* it.

## The guard hooks

`/secrets hooks on` installs two Claude Code hooks per-machine (in
`.claude/settings.local.json`, gitignored), built on `/install-hook`:

- **`PreToolUse` [`Read`|`Bash`]** — denies the AI reading a secret
  file. `Read` denial is exact; `Bash` denial is best-effort pattern
  matching (the AI is not adversarial, so best-effort suffices).
- **`UserPromptSubmit`** — blocks a chat message carrying a secret-
  shaped string *before it reaches the model*. High-precision patterns
  only (known key prefixes, PEM blocks, `SECRET=<high-entropy>`), so
  false positives are rare. They are not zero: a blocked message is
  cleared by resending it prefixed with `!secret-ok`.

Overrides are deliberate and visible (`!secret-ok`, `SECRETS_EDITOR`).
Never reach for `--no-verify`-style blanket bypasses.

## What this rule does NOT require

- It does not encrypt the store. `0600` + outside-the-repo is the v1
  bar. A project that needs encryption-at-rest layers it on top.
- It does not manage profile files (`.env.staging`, `.env.production`)
  or non-`.env` secret targets yet — v1 is the default `.env`.
- It does not forbid the AI from *naming* a secret (`DATABASE_URL`),
  describing it, or documenting where to get it. Only the *value* is
  off-limits.
