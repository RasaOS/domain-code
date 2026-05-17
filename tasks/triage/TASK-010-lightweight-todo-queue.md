# TASK-010 — Lightweight todo queue (phaseless task-style backlog)

**User story.** As a developer, I want a lightweight todo queue that
works like the task system but without phases — a flat backlog of
todos that get pulled into done or blocked.

**Why.** Not every unit of work deserves a full phased task spec;
a phaseless todo lane captures small or loose items with the same
lifecycle ergonomics that make the task system work well.

**Notes (raw idea).** Same concept as task management, but a todo
queue/list — a backlog of todos, no phases. Add a new one; pull
todos out into done or blocked. The task-management concept works
well; this explores a lighter-weight variation of it. Open design
questions: single `TODO.md` checklist vs. file-per-todo; states
(todo / done / blocked, maybe doing); a `/todo` skill mirroring
`/task`; promotion path when a todo grows into a real task.

STATUS: STUB
