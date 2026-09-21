---
id: TASK-047
category: stub
phase: P8
status: backlog
---

# TASK-047: License-compatibility gate in the dependency sweep

**User story.** As a **legal**, I want **dependency legality checked alongside dependency security** so that **an agent cannot pull a copyleft package into a proprietary product**.

**Why.** `content/release-rules.md` covers dependency *security* well — an audit command every release, a quarterly sweep, the manifest as a gated file — and dependency *legality* not at all. Grepping `GPL|copyleft|license compat|third-party licen` across the Element returns zero hits.

**Notes.** The first contamination is not a bug an agent can fix; it is a legal event discovered by the counterparty and unwound by lawyers.

STATUS: STUB — full spec drafted before implementation.
