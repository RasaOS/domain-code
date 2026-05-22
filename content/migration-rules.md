# Migration Rules

Migrations are the permanent record of all schema and data changes. This file defines how they're structured, named, and applied.

## Core Principles

**Atomic.** Each migration file contains one logical change. If reverting part of a change requires reverting others, they should have been one migration.

**Idempotent.** Migrations must be safe to run multiple times. Use `IF EXISTS`, `IF NOT EXISTS`, `CREATE OR REPLACE`, or equivalent. Never assume prior state.

**Reversible.** Every migration should include logic to undo itself (explicit rollback, or natural consequence of the change). Document the rollback path in the migration file.

**Immutable.** Once applied to production, a migration file is never edited. Fix mistakes with a new migration, not by changing the old one.

**Language-agnostic.** SQL, Python, JavaScript, Bash — any language that can be run and logged is valid. Store by language subdirectory if useful (`migrations/sql/`, `migrations/python/`, etc.), or keep flat.

## Naming Convention

```
YYYYMMDD_NNN_semantic_description.{sql|py|js|sh}
```

- **YYYYMMDD** = date migration was written (not when it runs)
- **NNN** = sequence number for that day (001, 002, …)
- **semantic_description** = what the migration does in snake_case
- **extension** = file type (sql, py, js, sh, etc.)

### Examples

```
20260513_001_init_schema.sql
20260513_002_add_users_table.sql
20260514_001_backfill_user_created_at.py
20260514_002_add_index_on_email.sql
```

Within a single day, sequence numbers prevent collisions if multiple migrations are written concurrently. The date is fixed at write time; the actual execution date goes in `MIGRATIONS.md`.

## File Format

### SQL Migrations

```sql
-- 20260513_002_add_users_table.sql
-- Reason: Support user authentication flow
-- Reversible: DROP TABLE users;

BEGIN TRANSACTION;

CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

COMMIT;
```

For PostgreSQL/MySQL: wrap in transactions. For SQLite: use explicit `BEGIN` / `COMMIT`.

### Python Migrations

```python
#!/usr/bin/env python3
"""
20260514_001_backfill_user_created_at.py
Reason: Add created_at timestamp to existing users
Reversible: No (data modification) — ensure full backup before running
"""

import os
from datetime import datetime

# Your DB connection logic
# conn = get_connection()

# Migration logic
# cursor = conn.cursor()
# cursor.execute("""
#   UPDATE users SET created_at = ? WHERE created_at IS NULL
# """, (datetime.now(),))
# conn.commit()

if __name__ == "__main__":
    print("Dry-run: this migration updates created_at for null users")
    # Uncomment above to actually run
```

Include logic to detect if the migration has already been applied (idempotency check).

### JavaScript Migrations

Similar structure: comment header with reason, reversibility note, and idempotent logic.

## Execution & Logging

**Never auto-run migrations.** Migrations are applied manually or via explicit CI/CD job with review gates.

**Log every execution** in `MIGRATIONS.md`:
- Which migration(s) ran
- When
- Who ran it
- Which environment (dev, staging, prod)
- Result (success, failure, rollback)
- Why it was run (if not routine)

See `MIGRATIONS.md` template for format.

## When Migrations Are Applied

- **Development:** Applied locally; developers apply manually or via `npm run migrate` / equivalent
- **Staging:** Applied before deployment; auto-run in CI or manual pre-deploy step
- **Production:** Applied with explicit approval; logged with metadata

## Rollback

**Reversible migrations** (schema changes with clear undo path):
```sql
-- Rollback: DROP TABLE users;
CREATE TABLE IF NOT EXISTS users ( ... );
```

**Irreversible migrations** (data deletion, destructive transformation):
```sql
-- Rollback: Restore from backup. This migration is destructive.
DELETE FROM users WHERE status = 'inactive';
```

Document rollback steps in the migration file. For destructive migrations, ensure backups exist before execution.

## Approval & Safety

Add project-specific approval gates in `CLAUDE.md` if needed:
- Production migrations require review (diff, reversibility check, estimated impact)
- Destructive migrations require backup verification
- Large data migrations (1M+ rows) require performance estimation

## Checking Migration Status

Maintain a migration tracking table or external log. The `MIGRATIONS.md` file is a human-readable record; for automated checks, consider:

```sql
-- Example: PostgreSQL tracking table
CREATE TABLE IF NOT EXISTS schema_migrations (
  id SERIAL PRIMARY KEY,
  version VARCHAR(255) NOT NULL UNIQUE,
  applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

Run `SELECT * FROM schema_migrations` to see applied migrations; check against your `migrations/` folder to find unapplied ones.

---

**See also:** `MIGRATIONS.md` for the running log of what's been applied and when.
