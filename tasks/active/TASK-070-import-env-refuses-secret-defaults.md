---
id: TASK-070
type: defect
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P1
---
# TASK-070: import-env refuses secret defaults

**Why.** `import-env` can record a secret as an env var's default value in a committed stamp, and every flag value reaches the stamp raw.

## Acceptance criteria

- [x] When `--purpose` is omitted, the classifier's purpose is used; an explicit `--purpose` always wins, with a warning.
- [x] A default is refused (rc 3) when `required` is false and the purpose is secret; a URL default carrying a password (`://user:pass@`) is always refused.
- [x] Every flag value is written through the library; array items are validated against a safe character set; add-profile is rebuilt on the library's get and set.

## Notes

- Stabilization plan Step 1 (the plan's TASK-67), renumbered.
- Classification: when `--purpose` is omitted, `add` now uses the purpose `suggest` gives; before, it was a flat `config`, so `STRIPE_SECRET_KEY` was recorded as config. An explicit `--purpose` always wins, and prints a warning when it disagrees with `suggest`. This is the escape hatch that returned rc 3 on PR #7.
- Refusals (rc 3, before anything is written):
  - A `--default` for a secret that is not required.
  - A URL `--default` with a password in its authority (`scheme://user:pass@…`), refused whatever the purpose. A port followed by an `@` in the path is not a password and is accepted.
- Writing:
  - The key must be an environment variable name. It becomes the file name, and `add '../x'` used to write outside `env/stamps/`.
  - Every scalar goes through `rfm_line`, so a newline in `--group` or `--description` is refused (rc 2) instead of forging keys in a committed stamp.
  - Array items must be `[A-Za-z0-9._/-]` (rc 2).
  - The stamp is written with `rfm_write_atomic`.
  - Clean output is byte-identical to 0.53.1: the golden files `env-stamp.md` and `env-stamp-profiled.md` were written by 0.53.1's own `import-env`.
- `add-profile`:
  - It reads and rewrites the frontmatter value with `rfm_get`/`rfm_set`. Before, it was a `grep '^environments:'` and a `sed -i` over the whole file, which also rewrote body lines.
  - It matches whole items. The old `\bprod\b` found `prod` inside `prod-eu` and never added it.
  - It refuses a profile outside the safe set. The old `sed` replacement turned `st&ge` into `stenvironments: [prod-eu]ge`, a corrupted stamp.
  - It keeps CRLF and the file mode.
- `bin/test-writers`: 88 cases, of which 14 are import-env and 2 are the new goldens. Against 0.53.1, 11 of the 14 import-env cases fail, and 51 of the 88 overall.
- This clears the last three sites of the grep gate, so TASK-069 can make it hard.

