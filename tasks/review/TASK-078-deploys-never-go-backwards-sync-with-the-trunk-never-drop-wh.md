---
id: TASK-078
type: change
created: 2026-10-03
created_by: claude
updated: 2026-10-03
phase: P1
---
# TASK-078: Deploys never go backwards: sync with the trunk, never drop what is live

## Intent

As **an operator whose project several Claude sessions deploy at once**, I
want every deploy to contain the latest trunk and whatever is live in the
target right now, so that one session's deploy can never silently remove
what another session shipped.

Incident (2026-10-03, a consumer project): session A deployed hosting from
its own merge commit; session B had just merged a newer PR on top and
deployed it. A's tree lacked B's merge, the deploy replaced the whole site,
and B's live feature vanished until someone noticed. No gate, skill or rule
said "sync with main first" or "contain what is live".

## Scope

**In scope**

- `content/build/gates/deploy-sync-lib.sh` (new): the two checks.
- `content/build/gates/trunk-sync.sh`, `content/build/gates/live-contained.sh`
  (new), wired into `content/build/deploy` for every intent.
- `content/skills/deploy/deploy-check.sh` (new): the standalone checker for
  raw deploy commands.
- `content/skills/deploys/deploys.sh`: `overrides:` and `replaces:` record
  fields (written only when given; earlier bytes unchanged).
- Rule text: `pipeline-rules.md` (canonical), `release-rules.md`,
  `git-flow-rules.md`; skills deploy, release, ios-release, setup-deploy,
  mission, auto-merge; the example `env.sh` documents the `live_sha` hook.
- `bin/test-deploy-sync` (new), `bin/test-pipeline` (+10 cases; fixture
  envs gain a `live_sha` hook), CI steps in both jobs.
- Release bookkeeping: v0.62.0.

**Out of scope**

- A server-side record of what is live: the gate is only as complete as the
  project's `live_sha` hook. Without one it reads the ship log, which sees
  only this checkout's deploys and records committed to the trunk.
- Verifying a release PR's head through `gh` when `RELEASE_PR` is set; the
  existing `land.sh fresh` + `--match-head-commit` in `/release` pin it.

## Acceptance criteria

- [x] Prod refuses any HEAD that is not the freshly fetched trunk tip
      (except `/release`'s `RELEASE_PR=<n>` path, recorded); lower envs
      refuse a HEAD that lacks the tip; refusals list the missing commits.
- [x] Offline: prod refuses, lower envs warn.
- [x] A live commit HEAD lacks, or one git does not know after fetching,
      is refused; an unknown live commit is refused at prod unless
      `LIVE_SHA_UNKNOWN_OK=1`, warned below.
- [x] Overrides are loud and recorded in the ship-log record.
- [x] `deploy-check.sh` gives PASS/REFUSED with exit 0/1 (2 usage), from
      any cwd and from a monorepo sub-directory install.
- [x] Every shipping skill states the rule and the post-deploy live check.
- [x] All existing suites green; `bin/check-manifest` passes.

## Notes

- 2026-10-03 — `bin/test-deploy-sync` 57/57 (bash 5 and /bin/bash 3.2.57);
  `bin/test-pipeline` 92/92 (was 82; bash 5 and 3.2). `check-manifest`,
  `check-bash32` (76 files), `check-invocations`, `check-frontmatter`,
  `test-contract` 40, `test-root` 21, `test-release` 26, `test-writers` 88,
  `test-readers` 31, `check-reader-parity`, `test-git-guard` 24,
  `test-peer-review` 19, `test-open-pr` 59, `test-reconcile` 33,
  `test-auto-merge` 84, `test-land` 350: all green. `bin/lint` exit 0,
  same 9 MEDIUM findings as `main`. `bin/init` smoke install: the gates,
  lib and checker install; the checker runs there.
