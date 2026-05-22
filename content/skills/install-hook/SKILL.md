---
name: install-hook
description: Install, remove, or list Claude Code hooks in a settings.json file. Reusable foundation for any skill that wires up event hooks (auto-save, session-start status reports, pre-commit gates, etc.). Default target is `.claude/settings.local.json` (per-user, gitignored). Subcommands: `add <Event> <command>`, `remove <Event> <command>`, `list`. Idempotent — safe to re-run. Triggered when the user wants to manage Claude Code hooks directly — e.g. "/install-hook add SessionStart 'echo hi'", "list installed hooks", "remove the pre-commit hook".
---

# /install-hook — Manage Claude Code hooks

A reusable foundation for installing Claude Code hooks. Pure JSON
manipulation — adds / removes / lists hook entries in a target
`settings.json` file.

Designed to be called both interactively (`/install-hook add ...`)
and programmatically (other skills calling `bash install-hook.sh add ...`).
`/auto-save` uses it. Future skills that need to install their own
hooks should use it too.

Per CLAUDE.md ethos: minimal, single-purpose, testable. The script
does one thing — wire up hooks — and exposes no extra knobs.

## Behavior contract

- **Read-only on failure.** If the target JSON is malformed or
  unparseable, the script refuses to write and surfaces the parse
  error. Never silently corrupts settings.
- **Idempotent.** Adding the same `Event + command` pair twice is a
  no-op. Removing a non-existent entry is a no-op.
- **Defaults to per-user (`settings.local.json`).** Per the kit's
  user-separation direction — hooks are typically personal preference
  unless the project explicitly wants them team-shared.
- **Creates target if missing.** If `.claude/settings.local.json`
  doesn't exist, the script creates it with `{ "hooks": {...} }`.
- **Doesn't validate that the command actually works.** Wires it
  up as-is. The user is responsible for the command being correct.
- **Never auto-commits.** Standard kit rule. The settings file may
  be `.claude/settings.json` (committed) or `.claude/settings.local.json`
  (gitignored); either way, the script doesn't run git.

## The script

Lives at `kit/skills/install-hook/install-hook.sh` (or
`.claude/skills/install-hook/install-hook.sh` in synced projects).
Always invoke with `bash` per `script-craft.md`.

### Interface

```text
bash <skill-dir>/install-hook.sh add <Event> <command> [--target <file>] [--matcher <pattern>]
    Add a hook entry for <Event> that runs <command>.
    Idempotent.

bash <skill-dir>/install-hook.sh remove <Event> <command> [--target <file>]
    Remove a hook entry matching Event + command.

bash <skill-dir>/install-hook.sh list [--target <file>]
    Print the hooks block from the target file in readable form.
```

Exit codes: `0` success, `1` operational (no python3, bad target),
`2` usage error.

### Targets

| Target | Use case |
|---|---|
| `.claude/settings.local.json` *(default)* | Per-user, gitignored. Most hooks. |
| `.claude/settings.json` | Project-shared, committed. Hooks the team agreed on. |
| `~/.claude/settings.json` | User-global, across all projects. |
| Any absolute path | Tooling experiments. |

### Hook events (Claude Code)

| Event | When it fires |
|---|---|
| `SessionStart` | At session start. Hook output can inject context. |
| `SessionEnd` | At session termination. |
| `Stop` | After each assistant response completes. |
| `PreCompact` | Before context window compaction. Useful for "save state before we lose it." |
| `UserPromptSubmit` | When the user submits a prompt. Hook output can inject context. |
| `PreToolUse` | Before any tool call. Can block. |
| `PostToolUse` | After any tool call. |
| `Notification` | When the assistant needs attention. |

### Schema written

```json
{
  "hooks": {
    "<Event>": [
      {
        "matcher": "<pattern, empty for session-lifecycle events>",
        "hooks": [
          { "type": "command", "command": "<shell command>" }
        ]
      }
    ]
  }
}
```

The matcher defaults to `""` (matches everything). For `PreToolUse`
/ `PostToolUse` hooks you'd typically pass `--matcher "Bash"` or
similar to scope to specific tool types.

## Language note

The script uses `python3` for JSON manipulation per `script-craft.md`'s
policy — JSON-by-bash is genuinely clumsy and error-prone. `python3`
is universally available on macOS + Linux without install.

## Process

### Step 1 — Identify what to install / remove

The user (or calling skill) provides: event name, command string,
optional target file, optional matcher.

### Step 2 — Run the subcommand

```bash
bash .claude/skills/install-hook/install-hook.sh add SessionStart 'echo "hi"'
```

The script handles file creation, idempotency, and JSON merging.

### Step 3 — Report

Surface the script's stdout to the user (single line per add/remove).

For `list`, surface the formatted output.

## Style rules

- **Minimal output.** One line per action. No preamble, no closing
  remarks.
- **Surface errors verbatim.** If the JSON is malformed or python3
  is missing, show the script's error and stop.
- **Don't reformat the target JSON unnecessarily.** The script
  writes back with 2-space indent — leave it alone, don't run it
  through other formatters.

## What you must NOT do

- **Don't manually edit `settings.local.json`** when this script
  exists. The script is the canonical entry point — it's idempotent
  and avoids the "I forgot a comma" failure mode.
- **Don't install hooks the user didn't ask for.** This script is
  a utility; calling skills decide what to install.
- **Don't commit `settings.local.json` changes.** The file is
  gitignored by convention; if the user has it tracked, ask before
  modifying.
- **Don't validate the command works.** That's the calling skill's
  job. install-hook just wires it up.

## Edge cases

- **`settings.local.json` doesn't exist.** Script creates it with
  `{}` and proceeds.
- **`settings.local.json` is malformed.** Script refuses and surfaces
  the parse error. User must fix manually.
- **`python3` missing.** Exit 1 with clear error.
- **Event name typo.** No validation (Claude Code's event names
  could change). The hook just won't fire if the event doesn't
  exist. Future improvement: validate against a known-events list.
- **Removing the last hook of an event.** Script drops the empty
  event entry entirely. Removing the last event drops the `hooks`
  block.

## When NOT to use this skill

- **Setting permissions** → use `/fewer-permission-prompts` for
  auto-allow patterns.
- **Setting env vars** → edit `settings.local.json` directly or
  `.env` if the tool reads from there.
- **Configuring the model** → edit `settings.local.json` directly
  (rare).
- **Hooks that need complex matchers + conditions** → write the
  JSON by hand for that one case, document why.

## What "done" looks like for an /install-hook session

The target `settings.json` (or `settings.local.json`) has the
requested hook added / removed. The hook fires at its event next
session start. No other files modified, no commits.
