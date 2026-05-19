# TASK-002 — Schema registry with version stamp and lock flag

**User story.** As a developer, I want one core place that holds the
project's database schema — stamped with version + date — plus a
lock/unlock flag, so a locked schema blocks any task needing a
schema change until the user resolves it.

**Why.** Uncontrolled schema changes are a silent source of drift
and breakage; a single stamped, lockable schema makes every change
deliberate and gated.

**Notes (raw idea).** Core place to keep the DB schema, stamped
with version and date. A flag to lock/unlock. If a task requires a
schema change while the schema is locked, block the task until the
user resolves it.

STATUS: STUB
