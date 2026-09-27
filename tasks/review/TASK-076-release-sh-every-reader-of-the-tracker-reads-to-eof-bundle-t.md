---
id: TASK-076
type: defect
created: 2026-09-26
created_by: chazzcoin
updated: 2026-09-26
phase: P2
---
# TASK-076: release.sh: every reader of the tracker reads to EOF — bundle, target and create no longer die of SIGPIPE

Issue #18. Seen on galt `packages/controller` (v0.54.0 installed; the file
is byte-identical at v0.60.0): `release.sh bundle TASK-467 v2.43.0` said
`error: no release v2.43.0` while `state v2.43.0` said `Planned`, on a
21 KB tracker.

## Intent

`release.sh` answers "is this release in the tracker?" from the file, every
time, whatever the tracker's size — never from whether `tr` survived the
pipe.

## Why it failed

`ledger_text | grep -q "^## $version "` under the script's `set -o
pipefail`: `grep -q` leaves at the first match, `tr` is killed (SIGPIPE,
141) writing the rest of the tracker, and 141 is the pipeline's status. A
race `tr` usually loses on macOS from ~20 KB; deterministic past one pipe
buffer (64 KB). `create` (line 332) then wrote a duplicate heading; `target`
(461) and `bundle` (509) refused. `cmd_manifest` had dodged it with a
heredoc. `section_body` / `subsection` had the same shape one level down
(an awk `exit` at the next heading): past a pipe buffer beyond the section,
bundle's "already bundled" and single-**Approved.** checks read false.
`check`'s legacy detection (`printf '%s' "$text" | grep -q '{{NEXT}}'`) is
the same pattern on a builtin.

## Scope

- `content/skills/release/release.sh`: `ledger_has_release` greps the file
  itself, for manifest, create, target and bundle; `section_body` and
  `subsection` are single awks over the file (they drop a CR themselves), so
  their early `exit` has no producer to kill; every `| grep -q` on a reader's
  output becomes `| grep … >/dev/null`. No output changes: the golden history
  stays byte-identical.
- `bin/test-release` case 5: a tracker larger than a pipe buffer (forty
  planned releases with a 3 KB theme, ~130 KB) driven through create (and
  its duplicate refusal), bundle (and its no-op with one **Approved.**),
  target, manifest, ship, check, and a large legacy tracker still
  recognised. The v0.60.0 script fails 8 of its 10 checks.
- `CHANGELOG.md` under Unreleased. No version bump here — the release
  commit does that.

Not done: `check` still leaks one process-substitution fd per heading on
bash 3.2 (the inner id loop's `< <(…)`); harmless at the sizes trackers
reach, and the shape that tripped over it is gone (Notes).

## Acceptance criteria

- [x] `bin/test-release` passes 26/26 on the fixed script and fails case 5
      on the v0.60.0 script.
- [x] `release.sh bundle TASK-467 v2.43.0` on galt's real tracker (main,
      21 KB) answers `already bundled`, where v0.60.0 answered `no release`.
- [x] The golden history (case 1) is byte-identical to the 0.53.1 writer's.
- [x] `bin/check-bash32` clean; `bin/check-manifest` and `bin/lint` exit 0.
- [x] `check` at 300 / 800 headings costs what it did: 6.0 s / 23.4 s
      (v0.60.0: 6.9 s / 23.7 s).

## Verification

`bash bin/test-release` (and `bash bin/test-release <the v0.60.0 script>`
to watch it fail); the real-tracker check from a scratch project holding
galt main's `tasks/RELEASES.md` and `tasks/completed/TASK-467-*.md`.

## Notes

- 2026-09-26 — reproduced 3/3 on the 21 KB tracker: `bash -c 'set -o
  pipefail; tr -d "\r" < tasks/RELEASES.md | grep -q "^## v2.43.0 "; echo
  ${PIPESTATUS[@]}'` → `141 0`; `grep … >/dev/null` → `0 0`; an awk `exit`
  → `0 0` at 21 KB and `141 0` at 21 MB; the flag form `0 0`. test-release:
  fixed 26/26 in 5 s; v0.60.0 18 passed, 8 failed (all in case 5). Real
  tracker: old `error: no release v2.43.0`, new `already bundled: TASK-467
  in v2.43.0`. check at 100 headings: 2.4 s new, 2.2 s old. bash 3.2 gate
  clean (68 files); check-manifest 0; lint 0.
- 2026-09-26 (second cut) — the first cut had the two readers read on with
  a flag instead of `exit`; test-release passed, but at 300 headings `check`
  never finished: bash 3.2's child for the inner id loop's `<( … )` spun at
  98% CPU with no children and ~250 inherited pipe fds (one leaks per
  heading), the trace ending at its `read -r id`. Bisected: the flag in
  `subsection` alone reproduces it (45 s cap hit); in `section_body` alone
  8.4 s. Old script: 300 → 6.9 s, 800 → 23.7 s. Second cut (each reader one
  awk over the file, early `exit` kept): 300 → 6.0 s, 800 → 23.4 s;
  test-release 26/26, v0.60.0 18/8; real tracker `already bundled`; the
  same tracker with CRLF line ends: bundle and manifest correct.
