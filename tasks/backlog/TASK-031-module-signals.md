---
id: TASK-031
type: change
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P4
---
# TASK-031: rasa.module.signals — inbound production signal to task

**User story.** As an **on-call engineer**, I want **an alert, ticket or advisory to become a task without a human transcribing it** so that **defect detection is not the one part of engineering still fully human-staffed**.

**Why.** No production signal can become a task today. Every incident, customer bug and upstream advisory waits on a person noticing it, mapping it to one repo out of 200, and phrasing it well enough for `/auto-hotfix` to accept — while agents raise change velocity.

**Notes.** New Element, `module` kind. Normalize to a task with an idempotency key, a `source` and a provenance link. Closes the work-intake gap in the same stroke. Needs TASK-043's trust field so inbound text is treated as data.

STATUS: STUB — full spec drafted before implementation.
