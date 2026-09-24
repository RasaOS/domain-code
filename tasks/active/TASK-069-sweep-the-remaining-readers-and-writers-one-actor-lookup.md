---
id: TASK-069
type: defect
created: 2026-09-24
created_by: claude
updated: 2026-09-24
phase: P2
---
# TASK-069: Sweep the remaining readers and writers; one actor lookup

**Why.** After the writers, readers across the Element still use exact or unanchored fences (suite gates, status, env tooling, runtime), and seven copies of the actor lookup exist, none sanitized.

## Acceptance criteria

- [x] env-sync keeps its commit-less-repo idiom and no longer returns 0 silently when its ledger cannot be written.
- [ ] Every remaining reader uses the library; `environment.sh` and `runtime.sh` use `frontmatter.py` and warn on a stamp they cannot read instead of skipping it.
- [x] One `rasa_actor`, in the library: it refuses control characters and identities over 128 characters, and is resolved once, before the first write.
- [x] `phase: Phase 3: Foo # x` reads back verbatim.
- [x] `test-rules.md` no longer teaches the broken reader.
- [ ] `bin/check-frontmatter` part 4 — a grep gate banning exact-fence readers, `> "$tmp" && mv`, unmarked `awk -v NAME="$var"`, `grep '^key:'` readers, `sed -i` and `\\A---` — is clean and runs as a hard CI step; exempt sites carry a `# rfm-ok:` marker.

## Notes

- Stabilization plan Step 1 (the plan's TASK-66), renumbered.
- Part one (this commit). The last reader, import-env's `add-profile` (a `grep '^environments:'` plus `sed -i`), is rebuilt on `rfm_get`/`rfm_set` in TASK-070, which owns that writer. Part 4 of the gate becomes hard in CI once those three sites are gone, which closes the two criteria still open.
- One actor: `git grep -c 'rasa_actor()' content` is 0 outside `content/lib`. `build/deploy` and `gates/approval.sh` source the library (install layout first, then the Element's own tree). `build/deploy` resolves the deployer before anything is written: before, `export DEPLOY_USER="$(…)"` hid a failure. `approval.sh` resolves the approver before it asks, and does not approve under a refused identity. `contract.sh` resolves its actor once, in `main`, before a mutating verb writes; it now honours `RASA_ACTOR` (test-contract cases 39–40, both failing against 0.53.1). env-sync's private copy is gone.
- env-sync: the actor, the environment, the peer, this host and the commit (using the same 773d89b `--verify --quiet` idiom), and a writable ledger are checked before `scp` runs. Record lines are written with `rfm_line`. A record that cannot be written makes the command fail and say so ("the file WAS sent, but the transfer is not recorded"); the two silent `return 0`s are gone.
- Readers:
  - `suite-lib.sh`: `stamp_field` is now `rfm_get_scalar`. The old reader opened the block at the first `---` anywhere, so a BOM made it read the body. `suite_tests` uses `frontmatter.split`: the old test missed a BOM and read the suite as having no tests; an unterminated block is now rc 3, not zero tests.
  - `export-env.sh`: `rfm_get` / `rfm_get_child`.
  - `import-env.sh`: eight readers moved to `rfm_get`.
  - `secrets.sh`: `var_name` and the displayed fields come from the frontmatter only. The old reader read the first matching line anywhere in the file, and located a stamp with a regex built from the key.
  - `status.sh`: `rfm_title`.
  - `dashboard.py`: `frontmatter.title`, falling back to the file name when the library is absent.
  - `environment.sh` and `runtime.sh`: `frontmatter.split` finds the block and PyYAML parses the nested structure (runtime stamps are genuinely nested YAML). A stamp that cannot be read is named on stderr instead of silently left out.
- `awk -v` sites: `load.sh`, `save.sh` (×2) and `sync.sh` pass their values through ENVIRON. `bin/lint` passes its path values through ENVIRON; its regexes stay on `-v` because they rely on its escape processing, and its verbose output is byte-identical before and after (538 lines).
- `git-guard.sh`'s `_strip_block` keeps the hook's mode. `git-guard off` used to leave a shared pre-commit hook non-executable, disabling every other hook in it; this is the defect TASK-067 fixed in task-guard.
- The grep gate: the `\A---` pattern now matches the single-backslash raw string (it only matched the old double-escaped bug). A `grep '^key:'` reader is banned in shipped content. Comment lines are not hits. Six `secrets.sh` readers it had never caught are converted. The advisory list is down to import-env's three `add-profile` sites.
- Docs: `test-rules.md` teaches the library instead of the exact-fence awk. `contract-rules.md`, `env-rules.md` and `stamps.md` describe the one actor and its refusal. `export-project` names the project by its install root rather than the repository, and `foundation.json` becomes `rasa.lock.json`.
- Tests:
  - `bin/test-readers` (new, in CI): 14 cases, of which 13 fail against 0.53.1.
  - `bin/test-writers`: 72 cases. New are a golden env-transfer record (written by 0.53.1's env-sync), env-sync ×4, git-guard ×4 and build/deploy ×1. Of the 72, 40 fail against 0.53.1.
  - `check-frontmatter`: the phase value is checked through both twins.
  - CI: the ubuntu job gets `actions/setup-python`, because the runner's system Python refuses `pip install` (PEP 668), which would have failed the PyYAML step added in TASK-065.
- Gates: check-frontmatter clean, check-manifest, check-bash32 (54 files), check-invocations, schema OK, test-contract 40/40, test-root 21/21, test-release 16/16, test-writers 72/72, test-readers 14/14, reader parity 0 unexplained, every script parses, and the approval gate's three CI checks behave as before.
- Bookkeeping note (following the TASK-056 precedent): TASK-018's first criterion, "All three title parsers ignore frontmatter; verified against a fixture", was ticked while `dashboard.py`'s parser could not match. Its regex was double-escaped in a raw string and never matched until 0.53.0 fixed the escaping, and after that it matched exact LF fences only. It moves onto `frontmatter.title` here, with a fixture in `bin/test-readers` (a BOM, CRLF and a `#` comment in the frontmatter) that 0.53.1 fails.

