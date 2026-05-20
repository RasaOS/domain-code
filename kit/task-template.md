---
id: TASK-XXX
category: spec
phase: <phase-id>
status: backlog | active | blocked | completed
---

# TASK-XXX: <short title>

> Spec-category task — feature work, new functionality. Copy this
> file to `tasks/backlog/TASK-XXX-slug.md`, fill in every section,
> then move to `tasks/active/` when work begins.
>
> Before starting: read `CLAUDE.md` and `.claude/task-rules.md`.
>
> For other task categories: `task-template-stub.md` (light
> tracking), `task-template-bug.md` (fix broken behavior),
> `task-template-hotfix.md` (urgent prod fix).

## User story

As a **<role>**, I want **<capability>** so that **<outcome>**.

## Why this matters

One or two sentences. What breaks today without this? What does the
iOS app do that the web app doesn't? Link the relevant CLAUDE.md
section if applicable.

## Scope

**In scope:**
-

**Out of scope (explicit):**
-

## References

- iOS source: `<file or class name>` — relevant fields/behavior
- Web model: `src/models/<File>.js`
- Existing pattern to follow: `<component or hook>`
- Related CLAUDE.md section: `<heading>`

## Files expected to change

List every file you expect to create or modify. The agent must not
touch files outside this list without updating the task first.

- `src/...`
- `src/...`
- `e2e/tests/<task-slug>.spec.js` (new)

## Execution order

Step-by-step, numbered. Guides the developer on what to do first,
second, third. Helps them not get stuck mid-task.

1. Edit `src/...` — add function X
2. Edit `src/...` — update component Y to use function X
3. Run test for component Y locally — verify it passes
4. Edit `e2e/tests/...` — add test case Z
5. Run full test suite — verify all green
6. Manual check: [specific verification step]

## Scope boundary

One clear statement of what's in and what's not.

**In scope:** <what this task does>

**Out of scope:** <if you find yourself doing X, that's a
separate task — file it separately>

## Acceptance criteria

Specific, verifiable. Each item must be checkable by either an E2E
test, a build/lint command, or a one-line manual verification.

- [ ]
- [ ]
- [ ]

## Test plan (E2E)

Write this **before** implementation. The test is a contract, not a
rationalization of whatever the code ended up doing.

1. Setup: <seeded state, signed-in user>
2. Steps:
   1.
   2.
3. Assertions:
   -

## Manual verification (in addition to E2E)

Steps the human reviewer will run locally:

1.
2.

## Gotchas & learned lessons

Specific to this task. Things to watch out for, things that broke
in prior attempts, anti-patterns for this area.

- **Don't do X** — here's why it breaks, and what to do instead
- **Watch for Y** — easy to miss, but critical
- **Cache/state issue:** [specific detail]
- **Backwards-compat note:** [what old code paths exist and
  why they matter]

## Open questions / risks

- 

## Blocker notes

(Agent fills this in if it gets stuck. Leave empty when creating.)

## Self-review checklist

Before opening a PR, the implementer should verify:

- [ ] I followed the execution order in the spec
- [ ] All acceptance criteria are met
- [ ] I tested each step in the execution order locally
- [ ] No gotchas/learned lessons were missed
- [ ] Backwards-compat verified (if applicable)
- [ ] Code follows the conventions documented in the spec
- [ ] Tests pass (both new tests and existing)
- [ ] No console/log errors on affected screens
- [ ] Build is clean (no warnings)
- [ ] I didn't touch files outside "Files expected to change"
  (or updated the task if I needed to)

## Optional sections (include if applicable)

### Decision rationale

Why this approach over alternatives. Reference recon findings.

### Risk & dependencies

- **Blocks / blocked by:** [task list if any]
- **Schema-owned by:** [team / N/A]
- **Requires:** [coordination, feature flag, migration, approval]

### Performance & scale contract

- **Expected scale:** [numbers / N/A]
- **Pagination required at:** [threshold / N/A]
- **Performance test:** [specific assertion / N/A]

### Observability

- **Key metrics:** [what to track]
- **Alert condition:** [when to page / N/A]
- **Dashboard:** [link or owner / N/A]

### Deployment strategy

- **Rollout:** [all at once | feature flag | gradual]
- **Coordination:** [other teams, platforms / N/A]

### Design & accessibility

- **Design spec:** [link or file]
- **A11y requirements:** [WCAG level, specific needs / N/A]

### Backwards compatibility

- **Breaking change?** [yes / no / N/A]
- **Migration path:** [if breaking]
- **Deprecation plan:** [if applicable]

---

**Definition of done:**
- All acceptance criteria checked
- E2E test passes (or N/A documented)
- The project's build command clean (per `CLAUDE.md` / `/build`)
- PR opened, linked from this file, ready for human review
