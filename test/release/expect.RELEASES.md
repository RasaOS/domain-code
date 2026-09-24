# Releases

The release plan and the release archive. One section per release,
newest first.

- `/release-plan` creates a release and targets phases/tasks at it.
- `/release-add` bundles completed work into one.
- `/release` ships it and stamps this file.

States: 📋 Planned · 🚧 Next (has bundled work) · ✅ Shipped.
Format reference: `.claude/release-rules.md`.
Validate with `.claude/skills/release/release.sh check`.

## v1.3.0 — 📋 Planned

**Theme.** Rate limits
**Target.** 2026-10

### Targeted
- TASK-002 — Rate-limit the API

### Bundled
_(nothing yet)_

## v1.2.0 — ✅ Shipped

**Theme.** Login and export
**Shipped.** 2026-09-24 · tag `v1.2.0-9f3a1c7-prod` · sha 9f3a1c7
**Approved.** release-bot via invocation

### Targeted
_(nothing yet)_

### Bundled
- TASK-001 — Add login
- TASK-003 — Fix the export timeout (large files)
