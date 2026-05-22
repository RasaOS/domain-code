---
name: container-greenlight
kind: test
test_kind: container
language: bash
location: tests/container/greenlight.sh
run_command: tests/container/greenlight.sh
created: 2026-05-13
status: active
tags: [container, pre-deploy, image-validation]
---

# Test: container-greenlight

Pre-deploy validation of the container image. Composes three checks:

1. **`validate-image.sh`** — static checks (hadolint, optionally trivy / size budget). No container is run.
2. **`run-local.sh`** — boots the image locally on the deploy runner, waits for the configured health endpoint, tears down on exit.
3. **`check-logs.sh`** — scans the booted container's logs for expected startup patterns and the absence of forbidden patterns (panic, fatal, etc.).

Green light = all three pass → deploy proceeds.

**Why this matters:**

Image-level bugs (broken entrypoint, missing runtime config, log format regression) are caught before any environment is touched. Cheaper than a failed staging deploy and a rollback.

**Customization:**

- `validate-image.sh` — uncomment trivy/size-budget blocks as needed
- `run-local.sh` — set `PORT`, `HEALTH_PATH`, `READY_TIMEOUT` env vars to match the project
- `check-logs.sh` — edit `EXPECTED_PATTERNS` and `FORBIDDEN_PATTERNS` arrays

Wire into `tests/suites/pre-deploy.md` by adding `container-greenlight` to the `tests:` array.
