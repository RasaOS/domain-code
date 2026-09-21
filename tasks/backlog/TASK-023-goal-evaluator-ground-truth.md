---
id: TASK-023
category: stub
phase: P3
status: backlog
---

# TASK-023: Give the /goal evaluator ground truth

**User story.** As an **operator**, I want **the independent evaluator to read the repo, not only the transcript** so that **the second opinion is about the work rather than about the narration of the work**.

**Why.** `content/autonomy-rules.md` documents the `/goal` loop's separate fast-model evaluator and then states its limit outright: it "runs no tools and reads no files — it judges what Claude has surfaced in the conversation", and the guidance tells the operator to write conditions "Claude's own output demonstrates".

**Notes.** The fix is not to add an evaluator — one exists and is correctly separated. It is to give the existing one tools and file access.

STATUS: STUB — full spec drafted before implementation.
