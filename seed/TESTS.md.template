# Tests Registry

Append-only log of test stamps in this project. Records when stamps were created, status changes (active → quarantined → retired), and audit-relevant notes.

**See `.claude/test-rules.md` for the test stamp model.**

Test files themselves live where their native framework wants them (XCTest in Xcode, jest alongside source, pytest in `tests/`, scripts under `tests/scripts/`). This registry is metadata — the stamps are in `tests/stamps/`.

---

## Template

Copy this for new entries:

```markdown
## YYYYMMDD_NNN — (test name)

**Date created:** YYYY-MM-DD
**Stamp:** `tests/stamps/YYYYMMDD_NNN_<slug>.md`
**Kind:** unit / integration / smoke / regression / container
**Status:** active
**Task:** T-XXX (origin task ID, optional)
**Suites:** pre-deploy, prod-gate, ...
**Notes:** any context (why created, gotchas, related tests)
```

---

## Status changes

When a test's status changes, append a row below — don't edit the original entry. This preserves the audit trail.

```markdown
## YYYYMMDD_NNN — (test name) — STATUS CHANGE

**Date:** YYYY-MM-DD
**Old status:** active
**New status:** quarantined
**Reason:** flaky in CI, runs 3/10 — needs investigation, see issue #123
```

---

## Quick stats

- **Total stamps:** 0
- **Active:** 0
- **Quarantined:** 0
- **Retired:** 0
- **Last added:** never
