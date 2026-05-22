---
name: pre-deploy
kind: test-suite
suite_kind: gate
runs_for: [dev, staging, prod]
tests: []
---

# Suite: pre-deploy

Default test suite invoked by `build/stages/30-test.sh` for every deploy. Add test stamp names to the `tests:` array above.

**Membership criteria:** anything that, if broken, would cause user-facing failure within the first 5 minutes of deploy. Keep this lean — it runs on every deploy. Heavier regression suites go in `prod-gate.md` or environment-specific suites.

## Adding a test

1. Create a test stamp under `tests/stamps/YYYYMMDD_NNN_slug.md` (see `test-rules.md`)
2. Add the stamp's `name` to the `tests:` array in this file's frontmatter
3. Verify locally: `./build/stages/30-test.sh dev`

## Notes

- Test execution order matches array order — put fast tests first.
- Failed tests abort the deploy. The `30-test.sh` stage exits non-zero, the pipeline halts before publish/deploy.
- For container projects, include `container-greenlight` (the kit-shipped image validation suite).
