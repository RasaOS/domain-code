# Database Migrations Log

Running log of all database migrations applied to this project. Every execution is logged here with date, author, environment, and reason.

**See `migration-rules.md` for conventions and how to write migrations.**

---

## 20260513 — (example entries below)

### 20260513_001 — Initialize schema
**Date applied:** 2026-05-13
**Time:** 14:32 UTC
**Author:** Chazz
**Environment:** Development
**Status:** ✓ Success
**Duration:** 0.3s
**Script:** `migrations/20260513_001_init_schema.sql`
**Reason:** Initial schema setup for user authentication system
**Reversible:** Yes (DROP TABLE users, etc.)
**Notes:** Ran locally before first commit

---

### 20260513_002 — Add users table
**Date applied:** 2026-05-13
**Time:** 14:35 UTC
**Author:** Chazz
**Environment:** Staging → Production
**Status:** ✓ Success
**Duration:** 0.5s
**Script:** `migrations/20260513_002_add_users_table.sql`
**Reason:** Support user authentication flow
**Reversible:** Yes (DROP TABLE users;)
**Notes:** Approved in code review #42. Applied to staging first (2026-05-13 18:00), then to prod after verification (2026-05-13 20:15).

---

## Template

Copy this for new migrations:

```
## YYYYMMDD — (brief title)

### YYYYMMDD_NNN — (full description)
**Date applied:** YYYY-MM-DD
**Time:** HH:MM UTC
**Author:** Name
**Environment:** Development / Staging / Production
**Status:** ✓ Success / ✗ Failed (rollback: yes/no) / ⏸ Pending
**Duration:** Xs
**Script:** `migrations/YYYYMMDD_NNN_*.{sql|py|js}`
**Reason:** One sentence explaining why this migration was needed
**Reversible:** Yes / No (if no, explain why and backup requirements)
**Notes:** Any additional context (code review link, issues encountered, etc.)
```

---

## Quick Stats

- **Total migrations:** 0
- **Last applied:** Never
- **Pending:** 0
