---
id: TASK-032
category: stub
phase: P5
status: backlog
---

# TASK-032: tenant_root in rasa.lock.json and a /roster skill

**User story.** As an **agent in a member repo**, I want **to see the other repos in my company** so that **a repo can participate in work that spans repos**.

**Why.** A member repo has no pointer to its siblings. `/Volumes/256GB/vsi-tenant/rasa.json` carries a real `tenant.members[]` roster with git remotes, roles and release surfaces, and nothing in this Element can read it.

**Notes.** Canon SA-022 already locks the roster format, so this is a reader, not a new design.

STATUS: STUB — full spec drafted before implementation.
