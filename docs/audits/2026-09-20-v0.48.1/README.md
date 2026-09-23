# Program audit — `rasa.domain.code` v0.48.1 (2026-09-20)

On 2026-09-20 a 61-agent adversarial audit asked one question of v0.48.1:
what does this Element lack to run a company's engineering work at fleet
scale? 47 gaps were claimed, 38 survived skeptic review and 9 were refuted
as factually wrong. The program in `tasks/ROADMAP.md` (P1–P9) was filed
from the 38 survivors.

This folder keeps the part of that audit that belongs in a public
repository: **which task covers which gap**, so coverage can be re-checked
as tasks land instead of being reconstructed from session transcripts.

## Why the gap statements are not here

The full audit — each gap's statement and evidence, the refutations, the
sequencing argument and the 2026-09-23 re-verification — is kept in the
private RasaOS workspace repository (`RasaOS/rasa-tenant`, under
`docs/audits/2026-09-20-v0.48.1/`). Parts of it describe specific
installations, so it is not reproduced in this repository. The ROADMAP
already states each phase's scope; the table below links gaps to tasks by id
only.

## `gap-coverage.md`

| column | meaning |
|---|---|
| **Gap** | `S01`–`S38`, the survivor order in the audit result |
| **Severity** | as the audit graded it: `blocking`, `major` or `moderate` |
| **Covering tasks** | task ids in this repository's `tasks/` ledger; `—` when none |
| **Coverage** | see below |

| coverage | meaning |
|---|---|
| `done` | the covering tasks are completed and the gap was verified closed |
| `partial` | some covering work is complete, or the filed tasks address only part of the gap |
| `planned` | the filed tasks cover the gap and none has completed yet |
| `uncovered` | no filed task addresses the gap |

## Keeping it current

Update the table in the same change that completes a covering task, files a
task against an uncovered gap, or re-scopes one. An `uncovered` row is a
standing prompt to file a task, not a verdict that the gap does not matter.
