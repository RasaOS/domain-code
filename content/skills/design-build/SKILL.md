---
name: design-build
description: Build the planned UI in the product's own code, with its own components and tokens, and prove it per size class. Runs inside a /develop task, between start and /open-pr. `check` verifies each planned screen has evidence at compact, medium and expanded and that the plan's tokens and components slot is filled; `shoot` takes best-effort screenshots at the three size classes, never of production. Triggered by "/design-build", "build the screens from the plan", "screenshot this at mobile, tablet and desktop".
---

# /design-build — build the screens, then show them

The plan is `/design-plan`'s; the rules are `ui-rules.md`. This skill
builds in the product's code and checks the evidence. There is no mock
step: with no product screen yet, the evidence is the plan's described
layout per size class.

## The script

`bash <skill-dir>/design-build.sh` (`.claude/skills/design-build/` in an
install). Always invoke with `bash`.

```text
design-build.sh check <plan> [--slug <slug>]
design-build.sh shoot <url-or-file> --screen <name> [--slug <slug>] [--env <env>]
```

- **`check`**: for every `### Screen:` block and each size class, there
  is `.claude/scratch/design/<slug>/<screen>-<class>.png`, or a filled
  described layout line in the plan; and the plan's
  **Tokens and components reused** line is filled. Exit 3 lists the gaps.
- **`shoot`**: writes the three PNGs to that folder. It accepts a file,
  `file://`, or a local address. Any other address needs `--env <env>`,
  and that environment must be registered and not production
  (`environment.sh prod-env`). It refuses to write unless the folder is
  git-ignored, and tells you the line to add. With no browser it prints
  `screenshots: skipped (no browser)` and exits 0. A screenshot that
  times out is reported, never fatal.
  `DESIGN_BROWSER=<command>` picks the browser; `DESIGN_BROWSER=none`
  forces the skipped path.

## Process

1. Work inside the `/develop` task, between `start` and `/open-pr`.
2. Build each planned screen with the product's own components and
   tokens (the plan's Design source). No new hard-coded colour,
   spacing or type value where a token exists.
3. Start the app with `/run` and take the URL from it.
4. `shoot` each screen. Use seed or fixture data only. The five states
   are described in the plan, not screenshotted.
5. `check <plan>`. Fix every gap.
6. Attach the PNGs to the PR. They are never committed; only the
   described layouts, in the plan, are.

## What you must NOT do

- Screenshot production, or real person data.
- Commit a screenshot.
- Skip a size class because the screen "is mostly mobile".
