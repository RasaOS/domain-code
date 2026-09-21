---
id: TASK-016
category: stub
phase: P1
status: backlog
---

# TASK-016: bin/init enables task enforcement with a brownfield carve-out

**User story.** As an **operator**, I want **task enforcement on by default in a new install** so that **the default agent runtime has gates rather than none**.

**Why.** `bin/init` seeds `.claude/task-enforcement.json` with `"enabled": false`, so the shipped default is unenforced. The one brownfield-aware decision in the Element runs backwards — enforcement defaults off *because* the Element installs into existing projects.

**Notes.** The carve-out is the point: a legacy repo may legitimately need enforcement off at first, but that should be an explicit, recorded decision rather than the silent default. Depends on nothing; interacts with TASK-026 (autonomy tiering).

STATUS: STUB — full spec drafted before implementation.
