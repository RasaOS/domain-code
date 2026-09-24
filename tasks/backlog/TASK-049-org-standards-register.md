---
id: TASK-049
type: change
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P8
---
# TASK-049: Org-level standards register

**User story.** As an **architect**, I want **a company standard to have one home** so that **"auth goes through our OIDC service" is not 200 copies of one paragraph**.

**Why.** `/codify` offers exactly two scopes — the project's CLAUDE.md or the repo-agnostic Element — so a company-specific architecture standard has nowhere to live.

**Notes.** `module-design`'s `@std-<slug>` model is the right primitive and is still a build plan; `module-drift` is a v0.1.0 shell with its register skills explicitly gated. Depends on TASK-032.

STATUS: STUB — full spec drafted before implementation.
