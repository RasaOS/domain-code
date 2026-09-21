---
id: TASK-036
category: stub
phase: P5
status: backlog
---

# TASK-036: Promote module.cto and extract module.taskflow

**User story.** As an **operator**, I want **the working org tier to be a published Element rather than one customer's folder** so that **company #2 and repo #47 get the org layer that already works for company #1**.

**Why.** `rasa.module.cto` v0.3.0 with 23 skills lives at `/Volumes/256GB/vsi-orchestration` with `source.repo` in a personal namespace and is absent from `elements/`; `/Volumes/256GB/vsi-tenant/taskflow/` plus 20 `bin/` scripts have no `rasa.json` at all — not an Element, no version, no `/sync` path.

**Notes.** **Cross-repo.** Executed from the workspace orchestrator seat, not from this repo. The problem is packaging and reachability, not design — 19 commits of real use and canon SA-022 already back it.

STATUS: STUB — full spec drafted before implementation.
