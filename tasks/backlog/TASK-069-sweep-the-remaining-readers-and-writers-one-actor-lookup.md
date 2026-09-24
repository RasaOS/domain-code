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

- [ ] env-sync keeps its commit-less-repo idiom and no longer returns 0 silently when its ledger cannot be written.
- [ ] Every remaining reader uses the library; `environment.sh` and `runtime.sh` use `frontmatter.py` and warn on a stamp they cannot read instead of skipping it.
- [ ] One `rasa_actor`, in the library: it refuses control characters and identities over 128 characters, and is resolved once, before the first write.
- [ ] `phase: Phase 3: Foo # x` reads back verbatim.
- [ ] `test-rules.md` no longer teaches the broken reader.
- [ ] `bin/check-frontmatter` part 4 — a grep gate banning exact-fence readers, `> "$tmp" && mv`, unmarked `awk -v NAME="$var"`, `grep '^key:'` readers, `sed -i` and `\\A---` — is clean and runs as a hard CI step; exempt sites carry a `# rfm-ok:` marker.

## Notes

- Stabilization plan Step 1 (the plan's TASK-66), renumbered.
