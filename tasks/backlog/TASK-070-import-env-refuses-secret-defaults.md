---
id: TASK-070
type: defect
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P1
---
# TASK-070: import-env refuses secret defaults

**Why.** `import-env` can record a secret as an env var's default value in a committed stamp, and every flag value reaches the stamp raw.

## Acceptance criteria

- [ ] When `--purpose` is omitted, the classifier's purpose is used; an explicit `--purpose` always wins, with a warning.
- [ ] A default is refused (rc 3) when `required` is false and the purpose is secret; a URL default carrying a password (`://user:pass@`) is always refused.
- [ ] Every flag value is written through the library; array items are validated against a safe character set; add-profile is rebuilt on the library's get and set.

## Notes

- Stabilization plan Step 1 (the plan's TASK-67), renumbered.
