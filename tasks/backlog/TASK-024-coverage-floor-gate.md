---
id: TASK-024
type: change
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P3
---
# TASK-024: Coverage-floor gate for autonomous change

**User story.** As an **operator**, I want **autonomous change refused on a surface with no executable behavioral evidence** so that **an agent cannot silently rewrite ten years of untested behavior**.

**Why.** Nothing measures whether the code an agent is about to change has any test covering it. In a legacy repo the verification re-walk and the deploy gate are both vacuous, so the system is architecturally incapable of noticing it broke something.

**Notes.** New `content/build/gates/coverage-floor.sh`, following the `class-guard.sh` precedent of having no bypass env var. Pairs with TASK-025 — refusing change on untested code is only actionable if there is a sanctioned way to add the missing tests.

STATUS: STUB — full spec drafted before implementation.
