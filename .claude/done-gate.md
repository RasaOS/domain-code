# Done-gate — the `rasa.domain.code` Element repository

What `review/` → `completed/` requires for **this repository's own tasks**
(`tasks/` here). It is not the gate this Element ships to consumers — that
is `seed/done-gate.md.template`. The gates below are the ones this repo's
`CLAUDE.md` ("Verify before you finish") and `.github/workflows/checks.yml`
already hold every change to; this file only gives them the position
`.claude/bin/task pass` reads them from.

A task passes with `python3 content/bin/task pass <id> --root . --by <who>
--note "<evidence>"` only when every acceptance criterion is met and
verified, and every gate below passes. A failing gate is `reject`, never a
waiver.

## Gates

- [ ] **Manifest** — `bin/check-manifest` passes: `rasa.json` is a complete
      inventory and every vendored file matches its pin.
- [ ] **Lint** — `bin/lint` passes.
- [ ] **Scripts** — every shipped or `bin/` script parses with its own
      interpreter, and `bin/check-bash32` passes.
- [ ] **Behaviour** — the scripts the change touched were exercised, not
      only parsed; `bin/test-contract` passes. A change to `bin/init` or
      to what it installs is smoke-tested with `bin/init` into a
      temporary directory.
- [ ] **Ledger** — `python3 content/bin/check-tasks .` reports zero errors.
- [ ] **CI** — every check on the PR is green.
- [ ] **Merged** — the PR is merged to `main` with the owner's explicit
      go-ahead (`content/git-flow-rules.md` Rule 2).
- [ ] **Public** — nothing in the change names a private repository, a
      company, or another project's task text. This repository is public.

Evidence goes in the task's `## Completion report`; the `--note` on `pass`
names it (the tool records it as `gate: …`).
