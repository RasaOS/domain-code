---
id: TASK-041
type: change
created: 2026-09-20
created_by: chazzcoin
updated: 2026-09-20
phase: P7
---
# TASK-041: Port domain-core's /sync and /promote; retire /contribute

**User story.** As a **maintainer**, I want **a lesson learned in one repo to reach the Element and then every other repo** so that **improvement compounds across the fleet instead of dying where it was found**.

**Why.** The learning-return leg is severed: `/contribute` does not carry improvements back the way `domain-core`'s `/promote` does, so a lesson learned in repo 47 has no path home.

**Notes.** A one-file lift from `domain-core`. Cheap and high leverage — worth doing early even though the phase is late, because every day it is missing costs compounding.

STATUS: STUB — full spec drafted before implementation.
