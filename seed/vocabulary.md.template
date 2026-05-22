# Project vocabulary overrides

> This file overrides kit defaults defined in
> `.claude/vocabulary.md` (sync'd from `kit/vocabulary.md`).
> Skills consult this file first and fall back to kit defaults
> for any term not listed here.
>
> The kit's `/sync` will **never overwrite this file** — it's
> yours to evolve. Override only what your project means
> differently. Anything you don't list inherits the kit default
> silently.

## Override format

Use the same section names as `.claude/vocabulary.md`. Only the
terms you want different. For each override include:

- **The project's definition** of the term (replacing the kit
  default).
- **The rationale** — usually a platform constraint, a team
  convention, or a tool boundary that makes the kit default the
  wrong shape for this project.

Don't restate kit defaults. The signal is *which* terms are
listed at all. If a term isn't here, it inherits.

---

## Examples (delete the ones you don't need)

### Versioning

{{Override the meaning of patch / minor / major if your project
has a platform constraint that changes practical semantics.}}

**Example — iOS build-number monotonic constraint:**

> - **Patch** — bump `CFBundleVersion` (build number) under the
>   existing `CFBundleShortVersionString` (marketing version).
>   Tag format: `vMAJOR.MINOR.PATCH-BUILD` (e.g.
>   `v5.0.10-110` → `v5.0.10-111`).
> - **Minor** — bump the marketing version's PATCH component
>   (e.g. `5.0.10` → `5.0.11`), reset build number relative to
>   the new marketing version, retag.
> - **Major** — marketing version MINOR or MAJOR bump
>   (e.g. `5.0.x` → `5.1.0` or `6.0.0`), reserved for breaking
>   changes or significant feature ships.
>
> **Rationale.** Apple enforces `CFBundleVersion` strictly
> increasing per `CFBundleShortVersionString` at upload time.
> Two TestFlight uploads under the same marketing version cannot
> share a build number; abandoned uploads consume their build
> number permanently. The semver "patch" semantic from the kit
> default doesn't fit — most ship cycles bump only the build
> number against an unchanged marketing version. See
> `.claude/ios-task-rules.md` "Apple build-number constraint"
> for the underlying rule.

### Lifecycle states

{{Override if your project tracks task state somewhere other than
the `tasks/{backlog,active,done}/` directories.}}

**Example — issue tracker is the source of truth:**

> Task lifecycle is tracked in Linear, not in the filesystem.
> The `tasks/` directory is for spec drafts only.
>
> - **Backlog** — Linear status `Backlog` or `Todo`.
> - **Active** — Linear status `In Progress`. The agent owns the
>   ticket while working it.
> - **Done** — Linear status `Done`, set when the PR merges to
>   `main`.
>
> **Rationale.** The team coordinates priorities in Linear; the
> filesystem-only flow doesn't match how non-engineering
> stakeholders see the work.

### Verification gate

{{Override if your project's gate includes more than the headless
test command.}}

**Example — gate is test + lint + type-check:**

> Verification gate = `npm run verify` (runs `lint`, `type-check`,
> and `test:e2e` in sequence; any failure fails the gate).
> Individual commands available but the agent must run `verify`
> as the unfiltered gate before opening a PR.
>
> **Rationale.** Lint and type errors used to slip past the test-
> only gate and waste reviewer time. Bundling makes the gate
> match the CI workflow exactly.

### Hotfix

{{Override if your project uses a different word for the same
concept, or a different escalation discipline.}}

**Example — paging policy bundled into the term:**

> Hotfix invocation requires a paged on-call acknowledgment in
> #incidents Slack before the hotfix branch is cut. The 48-hour
> postmortem deadline becomes 24 hours for any hotfix that
> involved customer-visible downtime.
>
> **Rationale.** SLA contracts with two enterprise customers
> require documented incident response within 24 hours of
> detection.

---

## Your overrides

{{Replace this whole section with the actual overrides for this
project. Delete examples above when you've made your decisions.
Empty is fine — every term inheriting kit defaults is a valid
state.}}
