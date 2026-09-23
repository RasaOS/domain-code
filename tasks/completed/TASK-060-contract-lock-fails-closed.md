---
id: TASK-060
category: bug
phase: P1
status: completed
owner: unassigned
blocked_by:
outcome: unrecorded
filed: 2026-09-23 20:14 UTC
origin: manual
severity: medium
---

# TASK-060: the contract lock fails open on bytes it did not write

**User story.** As an **operator**, I want **a locked contract to stay
locked whatever bytes its stamp holds** so that **the one mechanism that
freezes a load-bearing definition cannot be bypassed by a byte-order mark,
Windows line endings, a deleted line or a crafted argument**.

**Severity: medium today** — no installed copy holds a contract stamp yet,
so nothing can be overwritten in practice; it becomes high the day one does.

## What was wrong (reproduced on v0.52.0)

`content/skills/contract/contract.sh` read and wrote frontmatter with exact
string matching and `awk -v`. Every reproduction below exited **0**:

- A locked stamp with a **UTF-8 BOM** or **CRLF** line endings read as
  unlocked, so `update` overwrote it — old and new body both kept.
- A locked stamp with the **`is_locked` line deleted** or set to **`yes`**
  read as unlocked and was overwritten.
- An **unlocked** update on a CRLF stamp, or one with a trailing space on the
  closing fence, **appended** the new body instead of replacing it.
- A **CRLF `bump`** ledgered `version  → 0.1.0` and changed nothing.
- A **duplicate `version:` key** had both lines rewritten.
- **`lock` on a stamp with no `is_locked` key** ledgered "locked" and wrote
  nothing; PR #7's fail-closed fix turned the same gap into a deadlock.
- **`--owner`** containing a newline forged frontmatter keys; **`--why`**
  containing a newline forged a `## … · unlocked` ledger entry.
- `update`, `bump`, `lock` and `unlock` accepted a path-shaped name
  (`../../x`) and rewrote files outside `contracts/`.
- Every rewrite left the stamp at mode **600** (a `mktemp` leak).

A pre-commit adversarial review of the first 0.52.1 build found more, each
reproduced independently before it was fixed:

- **The edit guard failed open**: a locked stamp that was not valid UTF-8
  crashed the `PreToolUse` hook's Python before it printed a decision, so the
  edit went through (pre-existing). A second review round found the same
  failure class for a Write larger than the command-line limit: the payload
  was passed to python as an argument, so exec failed and nothing was printed.
- A **duplicated `is_locked`** (`false` then `true`) let `update` overwrite
  the stamp, while YAML readers saw it as locked.
- **NEL, LS and PS** (U+0085, U+2028, U+2029) passed the `--owner` check and
  can end a line for a YAML 1.1 reader.
- A **duplicated `last_updated`** made `bump` write the new version, fail,
  and ledger nothing — each retry bumped again.
- An `update` racing a `lock` could land the pre-lock frontmatter over the
  locked stamp (pre-existing); the build also broke read-only stamps, dropped
  body text after a NUL byte on BWK awk, accepted `01.2.3` as a version, and
  cut ledger text short at an invalid UTF-8 byte.

## What changed

- **Readers** ignore a BOM on line 1 and a trailing CR when matching, accept
  a fence of `---` followed by blanks, require the opening fence on line 1
  and take the first occurrence of a key; `is_locked` is read strictly, so a
  duplicate is its own state.
- **`fm_set` is an upsert** that rewrites the frontmatter only and copies the
  body byte for byte; it inserts a missing key, passes values through
  `ENVIRON` (never `awk -v`), refuses control characters and Unicode line
  breaks (rc 2) and duplicated keys (rc 4), preserves BOM, CRLF and mode
  (read-only included), renames atomically and reads the value back.
- **The lock fails closed.** Only an explicit `is_locked: false` is
  unlocked; missing, invalid, duplicated or unreadable is treated as locked.
  `lock` and `unlock` repair a missing or invalid key and ledger the repair;
  a duplicate or a stamp with no readable frontmatter is refused with
  hand-repair steps.
- `update` replaces the body and stamps `last_updated` in one rename; `bump`
  checks both keys for duplicates before writing and refuses a version that
  is not plain `x.y.z`; every verb validates the name; mutating verbs take a
  per-project `mkdir` mutex; ledger fields are collapsed bytewise; the guard
  denies on any read failure. Exit code 4 is documented.
- The guard reads its payload from stdin, and denies from bash if python
  cannot decide for a path under `contracts/`. C1 controls are refused
  alongside C0; an interrupted verb removes its temp file and the mutex.
- `bin/test-contract` — 37 cases, run in CI on ubuntu (mawk) and stock macOS
  bash 3.2. Not installed into consumers.

PR #7 (`ac977ad`) was the specification and the source of the regression
cases; its code was not reused (it kept `awk -v`, stripped CR on output, had
no insert branch, and sanitized neither `--owner` nor `--why`).

## Acceptance criteria

- [x] `bin/test-contract` passes 37/37 under `/bin/bash` 3.2.57 with BWK awk
- [x] The same test fails 30/37 against v0.52.0's `contract.sh`; the 11 cases
      added after the first review fail against the pre-review build, and the
      3 added after the second fail against the build before it
- [x] A locked stamp with BOM, CRLF, a deleted, garbled or duplicated
      `is_locked` refuses `update` with rc 3 and keeps its body
- [x] `unlock` on a stamp with no key inserts `is_locked: false`, and a
      subsequent `update` succeeds
- [x] Newlines, C1 controls and LS/PS in `--owner` are refused (rc 2); ordinary
      non-ASCII owners are accepted; a newline in `--why` yields one entry
- [x] The guard denies an edit to a locked stamp that is not valid UTF-8,
      and a Write larger than ARG_MAX
- [x] Mode (644 and 444) survives a rewrite; a NUL in the body survives; no
      temp files or mutex are left behind
- [x] `contract-rules.md`, `stamps.md` and the skill's `SKILL.md` describe
      the fail-closed rule and the repair paths
