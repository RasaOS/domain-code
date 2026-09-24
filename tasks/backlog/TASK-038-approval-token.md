---
id: TASK-038
type: change
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P6
---
# TASK-038: Approval token accepted in place of a TTY

**User story.** As an **operator**, I want **a headless run to be authorized without a human at a terminal** so that **the choice is not "50 live terminals" or "FORCE_APPROVAL=1 across 200 repos"**.

**Why.** `content/build/gates/approval.sh` reads yes from `/dev/tty` — correctly failing closed with no controlling terminal, and the Element's own CI asserts that — but the documented escape is a process-wide `FORCE_APPROVAL=1`, which deletes the gate everywhere at once.

**Notes.** Bind the token to a specific release + env + commit, carry an approver identity, and give it an expiry. Do not weaken the TTY path; add a second accepted proof. Depends on TASK-037.

STATUS: STUB — full spec drafted before implementation.
