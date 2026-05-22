# Audit log

Append-only chronological record of meaningful actions —
releases, task ships, rule changes, scaffolding events.

Newest entries on top. Each entry is one to a few lines —
*what happened*, *when*, and *where to find the receipts*
(PR numbers, tags, commit SHAs).

The git log is the ground truth; this file is the curated,
human-readable layer on top. Don't log every tweak — log the
things a future reader needs to navigate the project's history.

---

## Maintenance rule

Per `task-rules.md`'s "Audit log" section: every batch closing
report appends entries here for each task that landed and each
deploy that shipped. Process changes (new rules in
`task-rules.md`, new conventions) get their own entries.

The format is loose on purpose — readability beats parseability.
What matters: date, what changed, link to the PR / tag /
commit.

Use ISO dates (YYYY-MM-DD). Don't backdate; if you forgot to
log something, log it today with a "(retroactive)" marker.

Emoji set:
- 🚀 production deploys
- 📦 task ships
- 📜 rule / process changes
- 🏗 major scaffolding
- 🔥 hotfixes
- ⚠️ incidents and honest tradeoff calls

---

## {{TODAY'S DATE — YYYY-MM-DD}}

- 🏗 **Project bootstrapped from claude-kit.** Initial `.claude/`
  setup installed via `bin/init`. Source:
  https://github.com/chazzcoin/claude-kit.

---

## What this log is for

- **Project history.** A reviewer who joins later can read this
  top-to-bottom and understand what was built when.
- **Release retrospectives.** Search for a tag (`vX.Y.Z`) to find
  what shipped in it.
- **Process evolution.** Search for "rule added" to see how the
  workflow changed over time.
- **Honest tradeoff record.** When we made an opinionated call,
  the entry here is the receipt.
