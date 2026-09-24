---
id: TASK-068
type: defect
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P2
---
# TASK-068: Convert the dormant writers: runs, task-enforce, deploys, contract

**Why.** `runs.sh`, the task-enforce writers and `deploys.sh` have the same defects as the live writer but have not produced records in installed projects yet. `contract.sh` carries its own hardened copy of the rules (0.52.1) that should become the library.

## Acceptance criteria

- [x] `runs.sh`, `task-enforce.sh`'s writers and `deploys.sh` write through the library; `contract.sh` uses the library instead of its private copy.
- [x] Every refusal leaves the file byte-identical; field order and file modes are unchanged; record `id` and timestamp formats are unchanged.
- [x] Values are validated before a record id is reserved: an actor or tag containing a newline leaves no reserved file behind.
- [x] 0 differences between the old and new readers across the parity comparisons.

## Notes

- Stabilization plan Step 1 (the plan's TASK-65), renumbered.
- `contract.sh`: the private 0.52.1 copy (174 lines: its awk preamble, `fm_value_ok`, `fm_clean`, `fm_get`, `fm_set`, `stamp_rewrite`) is now five thin wrappers over the library, with the same names and exit codes. `lock_state` reads an unreadable stamp as damaged: the library answers rc 4 for it, which the wrapper would otherwise have reported as a duplicated `is_locked`. `bin/test-contract` passes 38/38. The same 38 cases pass against 0.53.1's `contract.sh`, so behaviour is unchanged. Case 22 now checks `.rfm.*` temps as well, since it would otherwise pass vacuously. The new case 38 (unreadable → damaged) fails with the readability check removed.
- `deploys.sh`: `open` checks the environment, class, tag, approval, host, sha and branch, and resolves the actor, before the id is reserved (the reservation is the record and is never removed). The environment may not be a path. Lines are written with `rfm_line`, byte-identical to 0.53.1. `close` writes its four keys with `rfm_set` in one rename. Its id may not be a path, the duration must be whole seconds, and `error_stage` is `rfm_clean`ed. `index` is published with `rfm_write_atomic`, which keeps the mode. `check` counts in-flight records from each record's frontmatter. The private `rasa_actor` is gone.
- `runs.sh`: the same shape. `started_epoch` must be digits before it reaches shell arithmetic. On stock macOS bash 3.2, with `set -u`, 0.53.1's `close` ran a command planted in a run record as `started_epoch: BASH_VERSINFO[$(cmd)]`.
- `task-enforce.sh`: `fm_field` is `rfm_get_scalar`. `task_annotate` writes the key and `updated` with `rfm_set` in one rename. `task_note` puts the stub's note under the heading using a temp file in the same directory; it keeps the mode, and `tail` copies the rest byte for byte. `task_digest` re-records the digest row, as before. `stamp` refuses an id that is not a task id (`*` stamped whichever task `find` listed first). `ledger_row` writes one line per path and uses the task only as a plain id in the file name. `ledger_index` is published with `rfm_write_atomic`. The stub's title and history note are one line.
- Library: `_rfm_pairs` refuses a key given twice in one write; before, that wrote a duplicate key and then failed the read-back after the file had already changed (verified by a control run). `rfm_write_atomic` gives a new view the umask's mode instead of mktemp's 0600. `rfm_cleanup` and `rfm_trap_cleanup` remove a temp left beside a record on exit, INT or TERM.
- `bin/test-writers` (62 cases): golden 6, deploys 18, runs 12, task-enforce 15 (including a positive control for the I-34 probe), task-guard 11. The golden records `test/writers/*.md` were written by 0.53.1's own scripts (`--emit` run from the 0.53.1 tree), with times, hosts and SHAs masked, and the new writers reproduce them byte for byte. Control: the same suite against 0.53.1 fails 35 of 62.
- `bin/check-reader-parity` (new, and in CI) keeps 0.53.1's four readers verbatim as the reference:
  - This repo's ledgers: 83 files, 2,592 comparisons, 0 differences.
  - The RasaOS task ledgers in the workspace: 427 files, 6,828 comparisons, 0 unexplained differences. 23 are intended: task-enforce now unquotes a quoted value, where 0.53.1 kept the quotes.
  - The synthetic corpus: 3 documented convention changes, plus 71 differences on the damaged fixtures.
  - The comparison on fleet copies (R3's 1,550 comparisons) runs with this tool at the release-candidate step (plan 1.16).
- Gates: check-frontmatter clean (its grep list went from 48 sites to 29), check-manifest, check-bash32 (53 files), check-invocations, schema OK, test-contract 38/38, test-root 21/21, test-release 16/16, test-writers 62/62, every script parses.
- Left for 0.55.0: `build/deploy` discards a failed `deploys.sh open` (`2>/dev/null || true`), so a refused open (an actor with a control character, say) still deploys, without a record. Making the ledger open mandatory belongs to the deploy and release hardening.
