---
name: inbox
description: Multi-dev messaging plus personal scratchpad. Write directed notes to teammates ("/inbox to michael: don't refactor auth without me") that they pick up via git pull on their next session, and write self-notes ("/inbox @self: think about caching layer") for friction-free "I'll deal with this later" capture. Identity is derived from `git config user.name` (lowercased, first word). Each recipient has one file at `.claude/inbox/<name>.md`. On invocation, surfaces messages addressed to *you* (unread first). Lower bar than `/task` (no spec, no commitment); higher coordination value than a private TODO. Triggered when the user wants to message a teammate or capture something for later — e.g. "/inbox", "/inbox to michael: ...", "/inbox @self: ...", "check my inbox", "any messages for me".
---

# /inbox — Multi-dev messaging + personal scratchpad

A flat-file message bus that ships with the repo. Write a note
to a teammate; they get it on their next `git pull`. Write a
note to yourself for the "I'll think about this later" pile.

The whole thing is `.claude/inbox/<name>.md` files in version
control. No server, no API, no notifications — just files
diff-and-merge under git. Honest, simple, multi-dev-friendly.

Per CLAUDE.md ethos: messages are durable artifacts. Write them
like the recipient will read them in a different timezone after
context-switching from another project — because they will.

## Behavior contract

- **One file per recipient.** `.claude/inbox/<name>.md`. Name
  is kebab-case lowercase first-word from input. "Michael S."
  → `michael`; "Sam-Joe" → `sam-joe`.
- **Identity from git config.** "You" = `git config user.name`
  lowercased + first word. The skill auto-detects who's
  reading. If `git config user.name` isn't set, ask once and
  cache to `.claude/inbox/_me.md` (single-line file with the
  user's chosen handle).
- **Self-messages go to your own inbox.** `/inbox @self: ...`
  writes to `.claude/inbox/<your-name>.md` with sender =
  yourself. Future you reads them like any other message.
- **Append-only message log.** New messages append to the
  recipient's file. Read/done state is per-message via a
  status marker, not by deletion.
- **Read view filters to you.** `/inbox` (no args) reads all
  inbox files where you're the recipient and surfaces unread
  messages. Read messages stay in the file as history.
- **Never auto-commit.** Inbox writes land in the working tree;
  the user commits + pushes for the message to reach the
  recipient.
- **Refuse secrets.** Same rule as `/lessons` — if the message
  body contains credentials, refuse and flag. Inboxes are in
  git history forever.

## Process

### Step 1 — Detect identity

```sh
NAME=$(git config user.name | awk '{print tolower($1)}')
```

If empty, check `.claude/inbox/_me.md`. If both are empty,
ask the user once:

```markdown
Need a handle for the inbox. What should I call you? (Lowercase,
one word — e.g. "chazz", "michael", "sam"):
```

Cache to `.claude/inbox/_me.md` for next time.

### Step 2 — Detect mode

Parse the user's invocation:

- `/inbox` → **read mode** (show messages addressed to me)
- `/inbox to <name>: <message>` → **write mode** (send to
  someone)
- `/inbox @self: <message>` or `/inbox to me: <message>` →
  **self-write mode**
- `/inbox done <id>` → **mark-done mode**
- `/inbox done all` → mark all my unread as done
- `/inbox sent` → **sent mode** (messages I've sent — quick
  audit)
- `/inbox who` → list everyone with an inbox file (handy in
  multi-dev repos)

### Step 3 — Read mode

For every file under `.claude/inbox/` where I'm the recipient
(filename = my handle, or the file's "addressed to" frontmatter
matches me):

```markdown
# 📬 Inbox — @<my-handle>

**<count> unread** · **<count> read**

---

## Unread

### `#<id>` from `@<sender>` — <YYYY-MM-DD HH:MM>

> <message body — quote-formatted>

*(Mark done with `/inbox done <id>`)*

### `#<id>` from `@<sender>` — <YYYY-MM-DD HH:MM>

> <message body>

---

## Recently read *(last 5)*

- `#<id>` from `@<sender>` — *<one-line preview>* · <date>
- …

*(Older read messages stay in the file but aren't shown here.)*
```

If the inbox file is empty: "📭 Inbox empty." — that's the
whole response.

### Step 4 — Write mode (to someone else)

Parse `/inbox to <name>: <message body>`:

- Recipient handle: lowercase first word of `<name>`.
- Message body: everything after the colon.
- Sender: my handle (Step 1).
- Timestamp: `YYYY-MM-DD HH:MM` local time.
- Message ID: 4-digit incrementing per recipient file (next
  unused number).

**Confirm before writing:**

```markdown
**Drafting message #<id> to `@<recipient>`:**

> <message body, exactly as it'll be saved>

**From.** `@<sender>`
**At.** <timestamp>
**Lands at.** `.claude/inbox/<recipient>.md`

Apply? *(yes / edit / cancel)*
```

On confirm: append to `.claude/inbox/<recipient>.md`. Create
the file if it doesn't exist. Working tree dirty,
uncommitted.

```markdown
✉️ Written to `.claude/inbox/<recipient>.md`.

`<recipient>` will see the message on their next `/inbox` after
they pull. Commit + push when ready:

    git add .claude/inbox/<recipient>.md
    git commit -m "inbox: note for @<recipient>"
    git push
```

### Step 5 — Self-write mode

`/inbox @self: <message>` writes to my own inbox file with
sender = my handle. Same flow as Step 4 but recipient = sender.

Useful for "I'll think about this later" without a task spec.
Lower friction than `/task`.

### Step 6 — Mark-done mode

`/inbox done <id>` finds message `#<id>` in my inbox file and
flips its status from `unread` to `read` with a `*(read on
<date>)*` annotation. Don't delete — preserve history.

`/inbox done all` flips every unread message in my file.

### Step 7 — Sent mode

Read every `.claude/inbox/*.md` (skip my own); surface messages
where sender = my handle:

```markdown
# 📤 Sent — @<my-handle>

Recent messages I've sent (across all recipients):

- `#<id>` to `@<recipient>` — *<one-line preview>* · <date>
  · status: <unread / read by recipient>
- …
```

Useful for "did Michael read that note yet" without asking.

### Step 8 — Who mode

```sh
ls .claude/inbox/*.md
```

```markdown
# 👥 Inboxes in this repo

- `@chazz` *(you)* — <count> unread, <count> read
- `@michael` — <count> messages total *(you'd need to be Michael
  to see read state)*
- `@sam` — <count> messages total
```

## Output structure

The per-recipient inbox file at `.claude/inbox/<recipient>.md`:

```markdown
# 📬 Inbox — @<recipient>

> Messages addressed to @<recipient>. Run `/inbox` to read; mark
> done with `/inbox done <id>`. New messages append to the
> bottom — `unread` first, `read` after consumption.

---

### `#0001` `[unread]` from `@<sender>` · <YYYY-MM-DD HH:MM>

<message body, free-form markdown — can be multiline>

---

### `#0002` `[read]` from `@<sender>` · <YYYY-MM-DD HH:MM> *(read on <YYYY-MM-DD>)*

<message body>

---

### `#0003` `[unread]` from `@<sender>` · <YYYY-MM-DD HH:MM>

<message body>

---

*Messages append; never reorder. IDs are stable per-file.*
```

## Style rules

- **`@handle` for people, `#NNNN` for message IDs.** Visual
  consistency.
- **Status in square brackets.** `[unread]`, `[read]`. Easy
  to grep.
- **Append-only.** Never reorder, never delete. Status flips
  in place.
- **Message bodies can be markdown.** Code blocks, links,
  lists fine.
- **Timestamps in local time.** No timezone gymnastics —
  inboxes are read by humans who can infer.
- **One emoji per mode header.** 📬 inbox, 📤 sent, 👥 who,
  ✉️ written, 📭 empty. Don't add others.

## What you must NOT do

- **Don't auto-commit.** Same rule as every kit-write skill.
  The user commits + pushes; that's the message-delivery
  step.
- **Don't delete messages.** Status flip only. Inboxes are
  history.
- **Don't store secrets.** Refuse if a credential or key
  appears in the message body.
- **Don't broadcast.** No "to all". Each message has one
  recipient. Multi-recipient = multiple writes (the user
  decides explicitly).
- **Don't reformat received messages.** A message's body is
  preserved verbatim; the skill only manages metadata
  (status, IDs, timestamps).
- **Don't read others' inboxes uninvited.** Read mode shows
  messages addressed to *me*. `/inbox sent` shows what *I*
  sent. `/inbox who` shows file existence + counts only.
  Don't dump someone else's full message body unless asked
  explicitly.

## Edge cases

- **Identity collision.** Two devs with the same first name
  ("Michael S." and "Michael R."). Surface and ask the user
  to pick a unique handle (e.g. `michael-s`, `michael-r`).
  Update `.claude/inbox/_me.md` accordingly.
- **Recipient doesn't exist** (no one with that handle in the
  repo yet). The file gets created anyway — the recipient
  picks it up when they next run `/inbox`. Surface a heads-up:
  "No prior messages for `@<recipient>`. Creating a new
  inbox file."
- **Massive inbox.** If a file has 100+ messages, render only
  unread + last 5 read in chat; tell the user the rest are in
  the file. Don't paginate.
- **Merge conflict on the inbox file.** Surface as: "Looks
  like there's a merge conflict on `.claude/inbox/<name>.md`
  — multiple people wrote to the same recipient. Resolve by
  keeping both blocks; renumber IDs if they collide." Don't
  try to auto-merge.
- **Self-message after handle change.** Old self-messages stay
  in the old-handle file. New self-messages go to the new
  one. Surface the old file once with: "You have <N> messages
  in `.claude/inbox/<old-handle>.md` from your previous
  handle." Move manually if desired.
- **`/inbox done <id>` for an ID that doesn't exist.** Surface
  the available IDs. Don't fail silently.
- **Working tree is dirty in inbox file already.** Append the
  new message to the existing dirty file; warn the user that
  the file is now changed by both this skill and prior work.
- **No git config + first-time use.** Walk through the
  one-time handle setup in `.claude/inbox/_me.md`.

## When NOT to use this skill

- **Filing a real task** (with spec, owner, scope) → `/task`.
  Inbox is for under-the-radar communication.
- **Capturing a project rule** → `/codify`.
- **Recording a decision** → `/decision`.
- **End-of-session handoff** → `/handoff` (which writes to
  `.claude/welcome.md` for first-thing-on-session-start
  context).
- **Real-time chat** — this is async, file-based, git-merged.
  If you need a reply within seconds, use Slack/Discord/etc.

## What "done" looks like for a /inbox session

- **Read mode:** unread messages surfaced; user can mark done.
- **Write mode:** message appended to recipient's inbox file,
  uncommitted, ready to commit + push.
- **Self-write mode:** self-note captured for future-you.
- **Done mode:** statuses flipped; file dirty, uncommitted.

In all cases: working tree dirty, no commits made, the user
knows the next step (commit + push to deliver to teammates,
or just commit for self-notes).
