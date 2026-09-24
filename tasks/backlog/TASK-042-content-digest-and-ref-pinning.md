---
id: TASK-042
type: change
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P7
---
# TASK-042: Content digest in rasa.json, bin/init --ref, expected_sha

**User story.** As an **operator**, I want **to install a known version of the Element rather than whatever is on disk** so that **the governance layer has the same supply-chain discipline as any other dependency**.

**Why.** `bin/init` overwrites 74 SKILL.md and 27 rule files with whatever is on disk — no version gate, no signature, no cohort, no rollback. One bad edit to `autonomy-rules.md` becomes the operating rules of every repo that re-inits.

**Notes.** Hash every `element.files[]` entry so the kernel's existing trust-on-first-use actually covers what ships. Add `--ref <tag>`, refuse-unless-tagged, and a consumer-set `expected_sha`. Staged rollout wants TASK-032's repo inventory to be addressable.

STATUS: STUB — full spec drafted before implementation.
