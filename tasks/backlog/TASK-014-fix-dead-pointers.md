---
id: TASK-014
category: stub
phase: P1
status: backlog
---

# TASK-014: Fix dead pointers shipped into every seeded repo

**User story.** As a **developer onboarding a repo**, I want **the links in my seeded CLAUDE.md to point at things that exist** so that **I am not sent to an archived repo or an unbuilt command on day one**.

**Why.** `seed/CLAUDE.md.template` hands every seeded repo a link to the archived `ChazzCoin/claude-orchestrator` and a reference to `/migration`, which exists in none of the RasaOS Elements; `/review` deflects PR review to `/ultrareview`, referenced four times and never built.

**Notes.** Also sweep the forbidden legacy term `bootstrap/`, which survives in wrangle, stamps, vocabulary, lint-kit and sync despite the vocabulary lock.

STATUS: STUB — full spec drafted before implementation.
