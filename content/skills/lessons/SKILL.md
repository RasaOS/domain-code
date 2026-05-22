---
name: lessons
description: After a task is completed (or at any moment worth capturing), spin up an introspective sub-agent that reads the conversation, extracts durable learnings — pro tips, pain points, surprises, forward warnings, graduation candidates — and writes them to `docs/notes/<YYYY-MM-DD>-<task-slug>.md` plus appends a one-liner to `docs/notes/INDEX.md`. The INDEX.md is the file CLAUDE.md references so future sessions load prior notes on start. Closes the loop where tribal knowledge from one task lights up the next session. Triggered when a task is approved/done — e.g. "/lessons", "wrap this task", "capture what we learned", "introspect on this session", "notes to future self".
---

# /lessons — Capture introspective notes for future-self

A task just wrapped. Before you move on, spin up an introspective
sub-agent that reads the conversation, extracts the durable
learnings, and writes them to a place future Claude sessions can
find. Over time, this builds a journal of pro tips, pain points,
and forward warnings that compounds.

Per CLAUDE.md ethos: honest about what was hard, what worked, and
what we got wrong. A note that hedges everything is useless; one
that overstates confidence is dangerous. Future-you reads these
without nuance — write so they survive that.

## Behavior contract

- **Writes durable docs only.** Output lands at
  `docs/notes/<YYYY-MM-DD>-<task-slug>.md` plus an updated
  `docs/notes/INDEX.md`. No source-code edits, no commits.
- **Sub-agent does the introspection.** Spawn an `Agent`
  (subagent_type: `general-purpose` is fine; `Explore` if the
  conversation references a lot of code) to read conversation
  context and extract learnings. The sub-agent returns a
  structured report; this skill writes it to disk after user
  confirmation.
- **Two modes:** **full** (default — full task wrap-up,
  multi-section note) and **quick** (single-insight capture
  mid-task). Pick based on user invocation:
  - `/lessons` or `/lessons full` → full mode.
  - `/lessons quick "<one-line tip>"` → quick mode.
- **Confirm before writing.** Show the user the extracted notes
  in chat first; let them edit, drop items, or expand. The disk
  write is the second step, after consent.
- **Refuse to capture secrets.** If the conversation contains
  credentials, API keys, or sensitive internal URLs, surface
  them and skip — never write secrets to the notes file.
- **Surface graduation candidates, don't auto-promote.** A
  pro-tip that looks general gets a 🎓 marker with a suggested
  next step (`/codify`, `/decision`, `/regret`, `/postmortem`).
  This skill writes the note; the user routes promotion.
- **Compaction-aware.** If the conversation has been compacted,
  the sub-agent works from what's still visible. The note
  explicitly says "Earlier context compacted; notes drawn from
  remaining session only."
- **Never auto-commit.** Standard kit rule.

## Process

### Step 1 — Detect mode + capture metadata

If the user invoked with a single-line argument
(`/lessons quick "watch out for X"`), enter **quick mode**.

Otherwise (default), enter **full mode**. Collect:
- **Task title** — ask if not obvious from context. Prefer the
  in-flight task name from `tasks/active/` if available.
- **Task slug** — kebab-case derivation of the title.
- **Date** — today, `YYYY-MM-DD`.
- **Outcome** — shipped / partial / abandoned. One word.

Filename: `docs/notes/<YYYY-MM-DD>-<task-slug>.md`. If a same-day
note for the same slug exists, suffix `-2`, `-3`.

### Step 2 — Spawn the introspective sub-agent (full mode)

```
Agent({
  description: "Introspect session for lessons",
  subagent_type: "general-purpose",
  prompt: "<see introspection prompt below>"
})
```

**Introspection prompt** (literal — adapt only the task title):

> Read the conversation context for the task: **<task title>**.
> You are extracting *durable learnings for future Claude
> sessions* — not summarizing what happened.
>
> For each category below, list 0-5 items. **Each item must be
> specific** (cite `file:line` or quote a command if relevant).
> Generic statements like "be careful with state management"
> are banned — they have to point at the actual moment.
>
> Categories:
>
> 1. **💡 Pro tips** — patterns that worked. What's the
>    reusable insight?
> 2. **🚧 Pain points** — where we got stuck or wasted time.
>    What was the root cause? What unstuck us?
> 3. **⚠️ Surprises** — assumptions that turned out wrong.
>    Bugs that surprised us. Behaviors that contradicted the
>    docs.
> 4. **🛠 Reusable snippets** — commands, regex, code blocks
>    worth saving verbatim.
> 5. **🔭 Forward warnings** — "if you ever do X again, watch
>    out for Y." Cite the place we'd want the warning.
> 6. **🎓 Graduation candidates** — lessons that look broad
>    enough to belong as project rules (CLAUDE.md), kit rules
>    (`task-rules.md`), formal decisions, regrets, or
>    postmortems. Tag each with the suggested skill route.
>
> Output as structured markdown with the headers above.
> Include only categories that had real material — don't
> stub. Skip "I think" hedging unless the uncertainty itself
> is the lesson.
>
> If the conversation has been compacted, note that and work
> from what's visible.
>
> If sensitive content (credentials, keys, internal URLs)
> appears in the conversation, **flag it and refuse to
> include it in the notes**.

### Step 3 — Show the draft + ask for edits

Render the sub-agent's output in chat:

```markdown
# 📓 Lessons draft — <task title>

*From a scan of the conversation. Edit, drop, or expand any
item before I write to disk.*

## 💡 Pro tips
- ...

## 🚧 Pain points
- ...

## ⚠️ Surprises
- ...

## 🛠 Reusable snippets
- ...

## 🔭 Forward warnings
- ...

## 🎓 Graduation candidates
- **<lesson>** — looks like a general rule. Suggest:
  `/codify` (project) or `/rule-promote` (across projects).
- ...

---

**To proceed:** "write it" / "drop item N" / "edit item N: ..."
/ "skip section X" / "regenerate" / "cancel"
```

Wait for user input. Apply edits to the draft. Loop until the
user says "write it".

### Step 4 — Write the note + update INDEX.md

**Per-task note** at `docs/notes/<YYYY-MM-DD>-<task-slug>.md`:

```markdown
# <Task title>

> **Outcome.** <shipped / partial / abandoned>
> **Date.** <YYYY-MM-DD>
> **Branch.** `<branch>` *(if relevant)*
> **Slug.** `<task-slug>`

*(If conversation was compacted: "Earlier context was compacted
before these notes were captured.")*

---

## 💡 Pro tips
- ...

## 🚧 Pain points
- ...

## ⚠️ Surprises
- ...

## 🛠 Reusable snippets

```sh
<command>
```

## 🔭 Forward warnings
- ...

## 🎓 Graduation candidates

Lessons worth promoting — these don't promote themselves; the
user runs the suggested skill to land them durably:

- **<lesson>** — suggested route: `/codify` (CLAUDE.md) /
  `/rule-promote` / `/decision` / `/regret` / `/postmortem`

---

*Captured by `/lessons` on <YYYY-MM-DD>. Indexed in
[`INDEX.md`](INDEX.md).*
```

**INDEX.md** — append a one-liner at the top (newest first).

If `INDEX.md` doesn't exist, create it with this header:

```markdown
# 📓 Notes index

> Rolling index of `/lessons` notes — newest first. Each entry
> links to the per-task file. CLAUDE.md should reference this
> file so future Claude sessions read recent notes on start.

| Date | Task | Headline | File |
|---|---|---|---|
```

Append a row:

```markdown
| <YYYY-MM-DD> | <task title> | <one-line headline — the most worth-knowing item from the note> | [📄](<YYYY-MM-DD>-<task-slug>.md) |
```

### Step 5 — Quick mode (single-insight capture)

If `/lessons quick "<one-line>"` was invoked:

- **Task slug** = derived from the most-recent active task or
  the current branch name.
- **Filename** = same `docs/notes/<YYYY-MM-DD>-<task-slug>.md`,
  but in append mode — if the file exists, append the
  one-liner under a "**🗒 Quick captures**" section. Otherwise,
  create a minimal file with just the quick note.
- **INDEX.md** — only update when the per-task file is first
  created; subsequent quick captures don't add new INDEX rows.

### Step 6 — Surface graduation candidates

After writing, render in chat:

```markdown
# 📓 Lessons captured

`docs/notes/<YYYY-MM-DD>-<task-slug>.md` — <count> items across
<sections> sections.

[`docs/notes/INDEX.md`](docs/notes/INDEX.md) updated.

**Graduation candidates worth routing:**
- "<lesson>" → run `/codify` to land in CLAUDE.md
- "<lesson>" → consider `/decision` for the design choice we
  made tacitly
- ...

*(Skip section if no candidates.)*

**One-time setup, if not done yet:** Add a reference to
`docs/notes/INDEX.md` near the top of `CLAUDE.md` so future
sessions load these notes on start. Suggested line:

> *See [`docs/notes/INDEX.md`](docs/notes/INDEX.md) for prior
> session notes — pro tips, pain points, forward warnings.*

Want me to draft that edit? *(routes to `/codify`)*
```

If CLAUDE.md doesn't already reference `docs/notes/INDEX.md`,
include the prompt above. Once it does, omit it.

## Output structure

See per-task note + INDEX.md shapes in Step 4.

## Style rules

- **Specific over general.** "The `useEffect` cleanup ran twice
  because we forgot React strict mode" beats "watch out with
  effects".
- **One emoji per category, load-bearing.** 💡 🚧 ⚠️ 🛠 🔭 🎓
  🗒. Don't add others.
- **Cite where it bit.** `path:line`, command, error message
  verbatim. Otherwise the future-self reading the note can't
  verify.
- **Pull-quote forward warnings.** They're the most valuable
  category — the failure mode you can warn the next person
  about *before* they hit it. Use `> ` quotes inline.
- **No end-of-note feel-good summary.** Stop after the last
  category. The note is the artifact, not a personal essay.
- **INDEX.md headlines are honest.** The headline is the most
  worth-knowing item, not a marketing title. "Realm migrations
  silently drop unmapped fields — keep the schema.json in sync
  manually" beats "Schema work".

## What you must NOT do

- **Don't summarize what happened.** A summary belongs in
  `tasks/AUDIT.md` (via `/release` or `/task done`). This
  skill captures *learnings*, which are different.
- **Don't fabricate.** If the sub-agent can't verify an item
  from the conversation context, it doesn't go in the note.
- **Don't capture secrets.** Credentials, API keys, internal
  URLs that look like secrets — refuse and surface to the
  user.
- **Don't auto-promote graduation candidates.** Surface the
  route (`/codify`, `/decision`, etc.) and let the user pick.
- **Don't auto-commit.** Standard kit rule.
- **Don't write empty sections.** A category with zero items
  is omitted, not stubbed.
- **Don't backdate.** The date in the note is today's, not the
  date the task started. The note is *captured today*.

## Edge cases

- **Conversation compacted.** The sub-agent works from what's
  still visible. Note explicitly says so. Encourage the user
  to invoke `/lessons` *before* compaction next time when
  they know a task is wrapping.
- **Multiple tasks in one session.** Ask the user to scope the
  notes — typically the most-recent task is the intent. If
  unclear, surface the candidates and let them pick.
- **No active task** (just exploration / debugging). Use the
  branch name or a user-supplied slug. Notes don't require a
  formal task.
- **Same-day, same-slug note already exists.** Suffix `-2`,
  `-3`. Don't overwrite.
- **`docs/notes/` doesn't exist.** Create it. Standard kit
  pattern.
- **CLAUDE.md doesn't exist or is the bootstrap stub.** Skip
  the "add reference to INDEX.md" prompt. The user has bigger
  documentation gaps to address (`/wrangle` covers that).
- **Sub-agent returns nothing useful** (low-substance task,
  short conversation). Surface honestly: "Nothing durable
  worth capturing from this session. Skipping the write."
  Don't write a low-value note just to have one.

## Automating the trigger *(opt-in)*

`/lessons` is invoked manually by default. Three opt-in
patterns to make it more automatic — pick what fits the
project. None of these are mandatory.

### Pattern A — Pair with task-completion (recommended)

When the user marks a task done (e.g. moves a file from
`tasks/active/` to `tasks/completed/`, or invokes a future
`/task done` flow), invoke `/lessons` next. This keeps
captures tightly bound to task boundaries — the moment most
worth introspecting.

The user types two commands; the second is `/lessons`.

### Pattern B — SessionEnd hook *(via `update-config`)*

For sessions that don't map cleanly to one task, configure a
`SessionEnd` hook in `.claude/settings.json` that prompts:

```jsonc
{
  "hooks": {
    "SessionEnd": [
      {
        "command": "echo 'Session ending — consider /lessons before closing.'"
      }
    ]
  }
}
```

This is a nudge, not an automation — it prints a reminder.
True auto-invocation of `/lessons` from a hook is possible
but expensive (LLM call per session); skip unless the user
explicitly wants it.

### Pattern C — Auto-load notes on session start

The reverse direction — make sure future sessions *read* the
notes. Add a single line near the top of `CLAUDE.md`:

> *See [`docs/notes/INDEX.md`](docs/notes/INDEX.md) for prior
> session notes — pro tips, pain points, forward warnings.*

This is the highest-leverage automation: notes captured by
this skill get loaded into every future Claude session via
the standard `CLAUDE.md` discovery path.

## When NOT to use this skill

- **Capturing one rule** → `/codify` puts it directly in
  CLAUDE.md. `/lessons` is for the broader narrative bundle.
- **Logging an incident** → `/postmortem`.
- **Recording a decision with rationale** → `/decision`.
- **Recording an architectural regret** → `/regret`.
- **Marking a task complete** → that's a task-management
  skill, not this. `/lessons` follows completion; it doesn't
  do the completion itself.
- **The task was trivial** (5 minutes, no friction). Save the
  skill for tasks where there's something to learn.

## What "done" looks like for a /lessons session

A new file at `docs/notes/<YYYY-MM-DD>-<task-slug>.md` with
categorized learnings (only the categories that had material),
and `docs/notes/INDEX.md` updated with a one-line headline
linking to the new note. Uncommitted. Optionally: a `/codify`
prompt for the highest-leverage graduation candidate.
Future Claude sessions read `INDEX.md` via the CLAUDE.md
reference and pick up where the prior session left off.
