# TASK-006 — Cross-repo handoff & communication shared system

**User story.** As a developer, I want a schema-like shared
structure that holds cross-repo handoffs and communication — so
when a backend adds an endpoint it can drop that contract into a
shared folder (and open a PR) for the frontend repo that needs it,
with drift detection built in.

**Why.** Cross-repo contracts (new endpoints, schema changes)
currently spread by word of mouth; a shared handoff system plus a
session-start drift scan catches divergence early.

**Notes (raw idea).** A schema-like structure holding all
cross-repo handoffs/communication. Backend creates an endpoint →
drops it in its own shared system → knows the web frontend needs
it → drops it in their shared folder + opens a PR. A better way to
link repos for communication, with drift detection. A session-start
hook enforces a drift scan of the other repo's shared docs.

STATUS: STUB
