---
id: TASK-065
type: change
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P2
---
# TASK-065: Shared frontmatter reader and writer, with a gate

**Why.** Every record writer in this Element parses and writes frontmatter its own way, and the ways disagree: exact-fence matching (a trailing space on the closing fence makes a writer rewrite body lines), no BOM or CRLF handling (a close silently does nothing), and raw `echo` or `awk -v` values (a newline in a value forges keys — a failed deploy reads as a success). One library, used by every writer and reader, closes the class.

## Acceptance criteria

- [ ] `content/lib/domain-code/frontmatter.sh` and its Python twin `frontmatter.py` (run as `python3 -B`), installed to `.claude/lib/domain-code/`, each a `file-replace` entry in `rasa.json`.
- [ ] Reader rules: strip one BOM and each line's CR; a fence is `^---[ \t]*$` and the opening fence is line 1; keys match literally; the first occurrence wins; awk runs under `LC_ALL=C`. Return codes 0 found, 1 absent, 2 usage, 3 no or malformed frontmatter, 4 unreadable.
- [ ] Writer rules: values pass through `ENVIRON`, never `awk -v`; CR, LF, NUL and other controls are refused (rc 2); a missing key is inserted before the closing fence and a duplicate refused (rc 4); BOM, CRLF and body bytes are preserved; the file mode is kept (`cp -p`); a same-directory temp file, then a read-back. No quoting: values are written verbatim.
- [ ] Scripts find the library relative to their own path; a missing library exits 70 with "re-run bin/init".
- [ ] `test/frontmatter/`: the 12-fixture, 74-row corpus with synthetic text, marked `-text`; `bin/check-frontmatter` parts 1–3 (bash and Python agree on all 74 rows; writer checks; PyYAML round-trip); an exact-fence mutation fails the gate.
- [ ] No calling script is converted in this task. `git grep -niE` for private project names under `test/` is empty.

## Notes

- Stabilization plan Step 1 (the plan's TASK-62), renumbered.
