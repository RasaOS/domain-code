---
id: TASK-012
category: bug
phase: P1
status: active
---

# TASK-012: The test gate cannot pass vacuously

**User story.** As a **release engineer**, I want **the production test gate to
fail whenever nothing actually ran** so that **a deploy can never report green
on a gate that executed no tests**.

## What's broken — three independent routes, all reproduced by hand

A full production release ships with zero tests and exits 0. Reproduced
end-to-end in a fresh `bin/init` install with a prod environment configured:
`FORCE_APPROVAL=1 ./build/deploy --env=prod --intent=release` prints
`Suite 'pre-deploy' has no tests listed. Skipping.`, then
`[deploy.sh] SHIPPING to prod`, then `✓ release complete`, exit 0.

Recon found two further routes that are arguably worse, because in both the
operator believes the gate is armed:

| # | Route | Measured behavior |
|---|---|---|
| 1 | `tests: []` (the seeded default) | `Skipping.` → exit 0 at prod |
| 2 | `tests: [alpha]` inline-flow YAML | parses as **zero** tests → exit 0 |
| 3 | suite lists `alpha`, stamps hold `alpha` + `alpha-extended` | runs the **wrong** stamp, prints `✓ pass` while the real `alpha` (exit 7) never runs |

Route 2: the awk parser at `content/build/stages/30-test.sh:49-57` only
understands block sequences with leading whitespace. Arming the gate by editing
`tests: []` into `tests: [auth, api-health]` — the obvious edit — arms nothing
and warns nobody.

Route 3: `30-test.sh:72` uses `grep -lE "^name:[[:space:]]*${TEST_NAME}\b" ... | head -1`.
`\b` treats a hyphen as a word boundary, so `alpha` matches `alpha-extended`
too, and `head -1` takes whichever sorts first. Verified: both files match, the
pick is `alpha-extended`, and the gate reports a pass for a test that never ran.
A false PASS inside the gate is worse than an empty one — "fail closed" is
meaningless if a non-empty list lies.

## Scope

**In scope:** the test gate cannot report success unless tests actually ran.

**Out of scope — item (b) of the original stub is DROPPED.** The stub said
"seed a real `prod-gate.md`". Measured: suite selection is first-match-on-
existence (`30-test.sh:24-27`), so shipping an empty `prod-gate.md` alongside a
consumer's *populated* `pre-deploy.md` switches the stage to the empty prod-gate
and **removes** production coverage from exactly the consumers who did the right
thing. The existing fallback already works — at prod class, `pre-deploy` runs
when `prod-gate` is absent. The Element also has no universally-runnable test to
put in such a file (`container-greenlight` exits on `IMAGE_NAME:?` in any
non-container repo). **No `prod-gate.md` ships in `content/` or `seed/`.**

## Two prerequisites — the fix is actively harmful without them

**P1 — `ENV_CLASS` is computed by two disagreeing classifiers.** `build/deploy`
uses a substring test (`*prod*|*live*`); `gates/class-guard.sh:86-96` uses a
token test with explicit preprod/nonprod exclusions. Measured:
`./build/deploy --env=preprod --intent=deploy` prints
`✓ class-guard: deploy → preprod (class: unclassified)` and on the next line
banners `(class: prod)`. A gate keyed on the driver's `ENV_CLASS` would hard-fail
ordinary deploys to `preprod`, `nonprod`, `myprod`, `alive-service`. Reconcile
first. Safe: token-prod is a strict subset of substring-prod, so reconciling only
ever relaxes the driver and never un-guards anything class-guard calls prod.

**P2 — `tests/suites/` is `directory-mirror`, and re-running `bin/init` IS the
update path.** `/sync` and `/sync-all` gate on `foundation.json` + `MANIFEST.json`,
neither of which has existed since the vocabulary lock, so they are dead. Measured
twice in pristine installs: a populated `tests:` array reverts to `tests: []` on
re-init, silently, because `rasa.lock.json#overrides` ships `[]`. So without this,
the same run that delivers the gate empties the suite the gate then treats as
fatal — "the toolkit update broke my pipeline", which is how a gate gets deleted.
Move the suite to `seed/` + `skip-if-exists` **in the same release, before the
gate**.

## Files expected to change

- `content/build/deploy` — classifier reconcile; re-derive `BUILD_DIR`/`PROJECT_DIR`
  after sourcing env.sh; invoke the new gate; refuse `--skip-tests` at prod
- `content/build/gates/suite-lib.sh` (new) — the one shared parser
- `content/build/gates/tests-required.sh` (new) — the fail-closed gate
- `content/build/stages/30-test.sh` — rewrite on `suite-lib.sh`
- `content/tests/suites/pre-deploy.md` → `seed/pre-deploy.md.template` + `rasa.json`
- `content/test-rules.md`, `content/pipeline-rules.md`,
  `content/skills/deploy/SKILL.md`, `content/build/environments/example/env.sh`
- `VERSION`, `rasa.json#version`, `CHANGELOG.md` — 0.48.1 → 0.49.0

## Execution order

Ordering is the whole risk. Prerequisites land before the gate.

1. Build a reproducible install harness; confirm the defect reproduces
2. Reconcile the `ENV_CLASS` classifier in `build/deploy` (**P1**)
3. Re-derive `BUILD_DIR`/`PROJECT_DIR` after the env.sh source
4. Move the suite to `seed/` + `skip-if-exists`; update `rasa.json` (**P2**)
5. `suite-lib.sh` — one parser, shared by gate and stage
6. `tests-required.sh` — the gate, no bypass variable
7. Invoke the gate in `build/deploy` beside class-guard
8. Refuse `--skip-tests` at prod class
9. Rewrite `30-test.sh` on the shared parser
10-12. Docs: `test-rules.md`, `pipeline-rules.md`, `deploy/SKILL.md`, `env.sh`
13. Version + CHANGELOG
14. Final verification from a **fresh clone**

## Acceptance criteria

- [ ] Fresh install + prod env: `FORCE_APPROVAL=1 ./build/deploy --env=prod
      --intent=release` exits non-zero on an empty suite (today: exit 0)
- [ ] Gate refuses under `--skip-tests`, `--skip-gates`, `--dry-run`, and under
      `SKIP_TESTS`/`SKIP_GATES`/`DRY_RUN` set in the environment or assigned by
      `build/environments/<env>/env.sh`. No new bypass variable is introduced
- [ ] `--skip-tests` at prod class exits 2 with a refusal; below prod it still skips
- [ ] All-quarantined suite FAILS at prod, passes-with-warning below
- [ ] `status: retired` on a listed member FAILS (not treated as quarantined)
- [ ] Missing/unrecognized `status:` causes the test to RUN with a warning, never skip
- [ ] `tests: [a, b]` inline flow runs its tests at prod; zero-indent and tab
      block sequences parse; an unreadable `tests:` key is a hard failure at prod
- [ ] Suite listing `alpha` no longer resolves to `alpha-extended`; two stamps
      sharing a name fail as ambiguous rather than `head -1`
- [ ] A failing test's output is printed (today `>/dev/null 2>&1` hides it, and
      the stamp-not-found branch is dead code under `set -euo pipefail`)
- [ ] Re-running `bin/init` on a populated suite prints `skip (exists)` and
      leaves the `tests:` array intact
- [ ] Deploys to staging / preprod / nonprod with an empty suite still exit 0
- [ ] `check-manifest` + `check-bash32` pass **from a fresh clone**
- [ ] No `prod-gate.md` ships anywhere
- [ ] Every criterion verified by RUNNING the pipeline in a temp install

**Baselines that are not signals:** `bin/lint` already exits 1 (TASK-055);
`bin/check-invocations` prints ~14 advisory findings then exits 0.

## Migration

Single recommendation, no deprecation window and no opt-out flag: move the suite
to `seed/skip-if-exists` first, in the same release, and **make the gate's
refusal message the migration document**. There is no channel to warn through —
`/sync` is dead, so `bin/init` is the update path and a CHANGELOG entry reaches
nobody. First contact is the gate's stderr during a release, so that text must
name the suite path, the one-line fix, and list every stamp present in
`tests/stamps/` but not wired into the suite.

Calibration copied from class-guard: hard-fail at prod class, warn-and-pass
everywhere else, permanently.

**Explicitly rejected:** an `allow_empty:` frontmatter escape (re-creates the
vacuous pass with extra steps); `rasa.lock.json#overrides` as the mitigation
(works, but nothing writes it and 0 of 7 consumers use it); any env var such as
`ALLOW_EMPTY_SUITE=1`. `FORCE_DIRTY` is the in-repo proof that a comment saying
"don't use this for prod" is not a gate. The escape hatch is "write one test."

## Gotchas & learned lessons

- **Never `cp -R` this worktree to make a scratch Element copy.** A worktree's
  `.git` is a pointer *file*, so the copy shares the real index — a recon
  subagent's `git mv` + `git commit` inside such a copy rewrote the real
  `rasa.json` and added commit `8d86eb8` to this branch. It self-reverted with
  `git reset --hard`; integrity re-verified independently. Use `git clone`.
- **Commit or gitignore `deploys/` in the harness.** Accumulated untracked deploy
  records make the git-clean gate fail at 10-preflight and confound every result.
- **`git add` before trusting `check-manifest`** — it reads `git ls-files`, so an
  untracked-but-registered file prints OK and then crashes `bin/init` on a fresh clone.
- **Don't use `readonly` for the BUILD_DIR fix** — an env.sh assigning a readonly
  var is fatal under `set -e`. Re-derivation is idempotent and non-breaking.
- **`skip-if-exists` is `seed.files` only** (ELEMENT_CONTRACT §264); `bin/init`
  treats it as unknown in `element.files`.
- **Deleting the `directory-mirror` entry matters** — git does not track empty
  dirs, so leaving it goes dangling on a fresh clone while staying green locally.
- **`suite_kind` and `runs_for` are advisory and unread.** Do not start enforcing
  `runs_for` here; it would add a fourth vacuous-pass route.

## Blocker notes

(none)

---

**Definition of done:** all acceptance criteria checked, verified from a fresh
clone, committed on `task/TASK-012-fail-closed-test-gate`.
