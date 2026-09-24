---
id: TASK-043
type: change
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P7
---
# TASK-043: Input-trust rule: inbound text is data, never instructions

**User story.** As an **operator**, I want **agents to treat text from any channel but me as data** so that **a crafted PR body cannot become the operating instructions of 200 repos**.

**Why.** `/peer-review` reads attacker-authored PR titles and bodies and squash-merges on "invocation is consent", while `/sync` pulls SKILL.md files — literally agent instructions — into every repo. The full chain is: crafted PR to the Element repo, merged by an agent, poisoned SKILL.md, every agent on every repo.

**Notes.** Rule in `content/autonomy-rules.md`, backed by a `source`/`trust` field on the task stamp, enforced at the `UserPromptSubmit` seam. Urgent once TASK-031 automates intake.

STATUS: STUB — full spec drafted before implementation.
