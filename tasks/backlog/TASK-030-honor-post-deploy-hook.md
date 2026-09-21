---
id: TASK-030
category: stub
phase: P4
status: backlog
---

# TASK-030: Make content/build/deploy honor [hooks] post_deploy

**User story.** As an **operator**, I want **the post-deploy hook I configured to actually run** so that **configuration that reads as supported is supported**.

**Why.** `content/build/deploy` reads pipeline config but never acts on `[hooks] post_deploy`.

**Notes.** Small. Verify against `seed/pipeline-config.toml.template` so the config surface and the driver agree.

STATUS: STUB — full spec drafted before implementation.
