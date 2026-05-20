# Task Intake

Pre-triage capture for the project. Raw notes that may or may not
become tasks. The lowest-friction layer in the task lifecycle.

```
intake.md  →  tasks/triage/  →  tasks/backlog/  →  active/  →  done/
  (raw)       (TASK-NNN,        (phase +
               no phase)         category)
```

Add an entry: a single bullet under today's date header. No
ceremony, no ID. When an entry matures into a real task, promote
it via `/task promote` (creates a stub in `tasks/triage/` and
removes the intake entry). Drop entries you've considered and
discarded via `/task drop`.

See `.claude/task-rules.md` "The intake layer" for the full
contract.

---

## <YYYY-MM-DD>

- **<short title>** — <one or two sentences of context. Be honest
  about what you know and what you don't. A line that says "the
  dashboard flickers on first load — saw it twice on Chrome, not
  sure if it's also on Firefox" is more useful than a line that
  says "dashboard bug".>

<!--
Example entries (delete these once the file has real content):

## 2026-01-15

- **Login is slow on mobile** — felt during the demo, 4-5s cold
  start on iPhone 12. Probably the analytics SDK init. Haven't
  measured on Android yet.
- **Onboarding "skip" button** — multiple users have asked. Need
  to think about what state they end up in if they skip.

## 2026-01-14

- **Dashboard timezone weirdness** — sometimes shows yesterday's
  date in the activity feed. Repro is intermittent. Possibly
  related to the recent date-fns upgrade.
-->
