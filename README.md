# claude-kit

A portable foundation for Claude Code projects — skills, rules, and
templates that work across any repo, any language, any platform.

> **Why this exists.** Iteration never stops. When a skill or process
> rule gets better in one project, every project should benefit.
> claude-kit is the central source of truth; projects pull from it
> via the `/sync` skill or bootstrap from it via `bin/init`.

---

## What's in the kit

```
claude-kit/
├── kit/                          # synced into target's .claude/ and build/, tests/, etc.
│   ├── skills/                   # slash commands
│   │   ├── audit/                #   universal
│   │   ├── …                     #   (more universal)
│   │   └── ios-release/          #   iOS-specific (prefix marks scope)
│   ├── modes/                    # drives — voice that primes appetite
│   │   ├── README.md
│   │   ├── task.md
│   │   └── cleanup.md
│   ├── task-rules.md             # universal execution rules
│   ├── migration-rules.md        # database migration conventions
│   ├── pipeline-rules.md         # CI/CD pipeline conventions (platform-agnostic)
│   ├── test-rules.md             # test stamp model + suite-as-gate conventions
│   ├── env-rules.md              # env-var stamp model + profile convention + secret discipline
│   ├── build/                    # deploy pipeline scaffolding
│   │   ├── deploy                #   universal entry point (executable)
│   │   ├── stages/               #   ordered stage scripts (10..50)
│   │   ├── gates/                #   reusable checks (git-clean, approval, ...)
│   │   └── environments/example/ #   per-env template (env.sh + deploy.sh)
│   ├── tests/                    # test scaffolding
│   │   ├── suites/               #   named test suites (pre-deploy, etc.)
│   │   ├── stamps/               #   kit-shipped test stamps (e.g. container-greenlight)
│   │   ├── container/            #   container greenlight scripts
│   │   └── scripts/              #   fallback test scripts (no native framework)
│   ├── ios-task-rules.md         # iOS platform extensions
│   ├── web-task-rules.md         # web platform extensions (placeholder)
│   ├── ios-conventions.md        # iOS architectural reference
│   └── task-template.md          # spec template for new tasks
├── bootstrap/                    # one-time files (init only, never synced)
│   ├── CLAUDE.md.template
│   ├── PHASES.md.template
│   ├── ROADMAP.md.template
│   ├── AUDIT.md.template
│   ├── pact.md.template          # working-relationship contract
│   ├── welcome.md.template       # session-start landing file
│   ├── wont-do.md.template       # anti-feature list
│   ├── playlists.md.template     # curated skill chains
│   ├── bookmarks.md.template     # path:line treasure map
│   ├── MIGRATIONS.md.template    # database migrations log template
│   ├── TESTS.md.template         # test stamp registry template
│   ├── ENV.md.template           # env-var rollup template
│   ├── pipeline-config.toml.template  # project pipeline config
│   ├── deploy-log.md.template    # appended-to log of every deploy
│   └── foundation.json           # initial sync-tracking file
├── bin/
│   └── init                      # bootstrap a target project
├── MANIFEST.json                 # what files this kit ships
└── README.md                     # this file
```

**`kit/`** = synced files. Improvements here propagate to every
project that runs `/sync`.

**`bootstrap/`** = one-time files. Init copies them once if they
don't exist; they belong to the project after that and never get
overwritten. `migrations/MIGRATIONS.md` is created at init as a template
that projects fill with their migration execution log.

**`migrations/`** = folder structure for database migration scripts (SQL,
Python, JavaScript, etc.), managed by the project. See `migration-rules.md`
for conventions on naming, format, idempotency, and logging.

**`build/`** = platform-agnostic deploy pipeline. Universal vocabulary:
**stages** (numbered scripts in `build/stages/`), **gates** (reusable
checks in `build/gates/`), **args** (`--env`, `--tag`, `--skip-tests`,
etc.), and **environments** (one folder per env under `build/environments/`,
each with `env.sh` + `deploy.sh`). The entry point is `./build/deploy
--env=<env>` — `--env` is always required, never defaulted. After
`/setup-deploy` fills in the project-specific commands, deploys are
dumb shell calls — no AI reasoning at run time. See `pipeline-rules.md`.

**`tests/`** = first-class test infrastructure. Tests live where their
native framework wants them (XCTest in Xcode, jest alongside source,
pytest in `tests/`, scripts under `tests/scripts/`); the kit references
them via **stamps** (`tests/stamps/<dated>.md`) with frontmatter declaring
where the test lives and how to run it. **Suites** (`tests/suites/<name>.md`)
group stamps into pipeline gates — `30-test.sh` runs the suite matching
the deploy env. Container projects get a built-in **greenlight** pattern
(validate → run-local → check-logs) under `tests/container/`. See
`test-rules.md` for the stamp model.

**`env/`** = environment-variable registry. One YAML-frontmatter stamp
per env var under `env/stamps/`, recording `var_name`, `group`,
`required`/optional, `purpose` (connection / credential / feature-flag /
config / secret / url / derived), `used_by` (which runtime/cloud stamps),
and `environments` (which profiles set it). **No values** — only
metadata. `env/ENV.md` is a human-readable rollup grouped by domain
(database, auth, external-apis, etc.). Profile files at project root
follow the kit's dotenv convention: `.env-template` (committed
reference), `.env` (local), `.env.test`, `.env.staging`, `.env.production`.
Use `/import-env` to bulk-parse an existing `.env*` into stamps. See
`env-rules.md` for the full model.

### Platform-prefix naming convention

The kit uses **filename prefixes** to mark platform scope:

| Pattern | Scope | Example |
|---|---|---|
| no prefix | Universal — every project | `task-rules.md`, `skills/audit/` |
| `ios-*` | iOS-specific | `ios-task-rules.md`, `skills/ios-release/` |
| `web-*` | Web-specific | `web-task-rules.md`, `skills/web-deploy/` |
| `python-*` | Python-specific (future) | `python-task-rules.md` |
| `android-*` | Android-specific (future) | `android-task-rules.md` |

**Important:** the prefix is a **discovery hint, not a gate.** Every
project that runs `bin/init` pulls *everything* — universal files
plus all platform-prefix files. The prefix tells Claude which files
are relevant to the current work. So an iOS project where Claude is
working on the HTTP layer can naturally read `python-task-rules.md`
to understand the API conventions on the other end.

This makes multi-platform projects (e.g., a monorepo with iOS + web,
or an iOS app talking to a Python backend) work without `--platform`
flags — every project installs everything; each work session reads
the prefix files that apply.

The universal `task-rules.md` documents this convention at the top
so every Claude session is aware of it.

---

## Skills shipped

Run `/skills` inside any project after init to see the live list.
Current set, grouped by intent:

### Universal — read & assess

Read-only: answer "what is this?" / "what's the state?" / "what's the
surface?" without touching the working tree.

| Skill | Purpose |
|---|---|
| `/audit` | Two-part architectural read; saves to `docs/audits/` |
| `/review` | Senior line-by-line peer review of a given area |
| `/wrangle` | Tame an unfamiliar codebase; writes durable map under `docs/wrangle/` and `.claude/context/project-map.md` |
| `/status` | Quick "where do things stand right now" snapshot |
| `/dashboard` | Live HTML project dashboard — production, git state, tasks, PRs, activity, warnings |
| `/onboard` | Guided onboarding for new contributors |
| `/skills` | List every locally-defined skill |
| `/backlog` | Forward-looking task list, grouped by phase |
| `/roadmap` | Per-phase view including completed work |
| `/build` | Toolchain-detecting "does it build?" |
| `/run` | Toolchain-detecting launcher |
| `/schema-check` | Cross-platform schema mirror reconciliation |
| `/scope-check` | Reality-check planned-change surface area vs estimate |
| `/blast-radius` | Pre-mortem the surface a destructive change touches |
| `/glossary` | Generate or sync `docs/glossary.md` from code + docs |
| `/export-project` | Single beautifully-formatted project summary doc |

### Universal — plan & scope

| Skill | Purpose |
|---|---|
| `/plan` | Socratic roadmap-planning partner |
| `/mvp` | Define minimum shippable+marketable for a new app/feature |
| `/prototype` | Rapid R&D mode in a `proto/<slug>` branch |
| `/spec-phase` | Expand every stub in a phase to a spec; propose order |
| `/task` | Per-task action skill (file, move, expand) |
| `/instruct` | Convert human instructions into an atomic AI instruction recipe |
| `/brainstorm` | Resume or start a tradeoff session at `.claude/tradeoffs/<topic>.md` |
| `/stuck` | Socratic unblock-the-human partner |

### Universal — autonomous execution

Hands-off variants — decide everything, ask nothing, flag every
assumption, stop only at hard gates. Shared contract in
`autonomy-rules.md`.

| Skill | Purpose |
|---|---|
| `/auto-task` | Autonomous `/task` — file and fully spec a task without questions |
| `/auto-phase` | Autonomous `/spec-phase` — expand every stub in a phase to a full spec |
| `/auto-develop` | Autonomously implement a task spec — write the code, run the build |
| `/auto-test` | Autonomously write and run the tests for a task or feature |

### Universal — capture & reflect

Durable records — each writes to a typed location under `docs/`.

| Skill | Purpose |
|---|---|
| `/decision` | ADR drafter for real architectural calls |
| `/postmortem` | Incident postmortem drafter |
| `/regret` | Architectural hindsight (distinct from postmortem) |
| `/lessons` | Per-task introspection; writes to `docs/notes/` |
| `/retro` | Longitudinal retrospective over a date window |
| `/handoff` | Snapshot in-flight context; updates `.claude/welcome.md` |
| `/codify` | Capture a session-emerged rule into CLAUDE.md or kit rules |

### Universal — ship

| Skill | Purpose |
|---|---|
| `/release` | End-to-end production release orchestrator (delegates to platform skills) |
| `/setup-deploy` | Interactive walkthrough that fills `build/` and `tests/` with project-specific deploy commands |
| `/environment` | Read and manage the `.claude/environments.json` registry; switch the current environment |
| `/runtime` | Preflight `.claude/runtimes/<name>.md` stamps — env + dependency checks, READY / NOT-READY verdict |
| `/secrets` | Provision secret values into `.env` without the AI ever seeing one |
| `/import-env` | Parse an existing `.env*` file into env-var stamps under `env/stamps/`; one question per new var |
| `/export-env` | Generate `.env-template` (or per-profile / per-runtime variant) from `env/stamps/`; inverse of `/import-env` |

### Universal — coordination & hygiene

| Skill | Purpose |
|---|---|
| `/sync` | Reconcile this project's `.claude/` with claude-kit |
| `/update-docs` | Reconcile core docs against reality |
| `/inbox` | Multi-dev messaging plus personal scratchpad |
| `/contract` | System-contract registry — version, lock, and ledger for schemas, endpoints, and system docs |
| `/save` | Mid-session state-save for an active thread of work |
| `/load` | Rehydrate context from the most recent `/save` snapshot |
| `/auto-save` | Toggle session-lifecycle auto-save hooks — in-session merges, pre-compaction archive |
| `/git-guard` | Toggle git-hygiene lockdown — auto-capture WIP, surface abandoned work, block trunk commits |
| `/task-guard` | Toggle the change-audit rule — every code/config commit gets a linked task, auto-stubbed if missing, ledgered |
| `/install-hook` | Install, remove, or list Claude Code event hooks in a settings file |

### Universal — kit-level meta

Push improvements back upstream so every project benefits.

| Skill | Purpose |
|---|---|
| `/new-skill` | Scaffold a new skill following the kit's canonical conventions |
| `/contribute` | Package a local kit-file edit as a PR back to claude-kit |
| `/rule-promote` | Find rules duplicated across projects; propose for kit graduation |
| `/lint-kit` | Lint the kit for platform-specific drift in universal files |

### Universal — drive

Modes shape Claude's *appetite* for the work — what to want, what
feels wrong when off-track. Drives, not filters. See
[kit/modes/README.md](kit/modes/README.md) for the concept.

| Skill | Purpose |
|---|---|
| `/mode` | Switch, end, or report the current work mode (`task` / `cleanup` / `normal`). Stats persist across sessions in `.claude/mode-stats.md`. |

### Platform-specific

| Skill | Scope | Purpose |
|---|---|---|
| `/ios-release` | iOS | Archive + export + validate + upload to TestFlight via xcodebuild + altool |

---

## Bootstrapping a new project

### Greenfield (new repo)

```sh
git clone https://github.com/ChazzCoin/claude-kit /tmp/claude-kit
/tmp/claude-kit/bin/init /path/to/your/new/project
cd /path/to/your/new/project
```

The init script reads `MANIFEST.json` and installs everything it
declares — there is no hardcoded file list in the script itself. Each
entry is applied by its policy:

1. **Kit-managed files** — skills, modes, agents, the rule files, the
   `build/` pipeline scaffold, and kit test scripts are mirrored into
   `.claude/`, `build/`, and `tests/`. `/sync` updates these later.
2. **One-time bootstrap files** — created **only if they don't already
   exist**, never overwritten by `/sync`: `CLAUDE.md`,
   `tasks/{PHASES,ROADMAP,AUDIT}.md`, the primitive layer
   (`.claude/pact.md`, `welcome.md`, `wont-do.md`, `playlists.md`,
   `bookmarks.md`), the stamp templates under `.claude/clouds/`,
   `.claude/runtimes/`, `.claude/tests/`, plus `settings.json`,
   `env/ENV.md`, `build/pipeline-config.toml`, and more.
3. **`.claude/foundation.json`** — stamped with the kit's commit SHA so
   `/sync` knows what to compare against.
4. **Scaffold directories** — empty output destinations the kit's
   skills write to (`tasks/`, `docs/`, `env/`, …), each with a
   `.gitkeep`.
5. Prints next steps (fill in the `CLAUDE.md` placeholders, declare the
   project's `## Platform`).

`MANIFEST.json` is the single source of truth: adding a kit file is a
one-line manifest edit, picked up by both `bin/init` and `/sync`.
`bin/check-manifest` guards the manifest against drifting from the tree.

### Existing project

Same command — `bin/init` is safe on existing projects because it
preserves any file that already exists. After running, run `/sync` to
diff your local `.claude/` against the kit and pull the parts you want.

```sh
/tmp/claude-kit/bin/init .
# review what changed
git diff
# fill in CLAUDE.md placeholders
# commit
```

---

## Integrating into an existing project (agent-friendly)

If you're a Claude agent already working in a project that has its
own `.claude/`, `tasks/`, and `CLAUDE.md` — and you want to bring
the kit in without losing project-specific work — follow this exact
flow. Designed to be runnable on a single read of this section, no
prior kit knowledge required.

### What `bin/init` will do to an existing project

The table below shows the **policy classes** — `MANIFEST.json` is the
authoritative, complete list, and every kit file falls into one of
these policies. `bin/init` never overwrites a project-content file that
already exists.

| File / dir | Policy | What you should know |
|---|---|---|
| `.claude/skills/` | additive — overlays kit skills, doesn't delete project-only ones | If a kit skill name collides with a project-only skill, the kit wins. **Rename project-only skills with a `local-` prefix BEFORE init** if they share a name with a kit skill. |
| `.claude/modes/` | additive — overlays kit modes | Mode definitions (drive prose) sync from `kit/modes/`. Local edits to `.claude/modes/<name>.md` are preserved across `/sync` if listed as overrides in `foundation.json`. |
| `.claude/mode.md` | **never touched** by init or sync | Project-owned activation record (created by `/mode <name>`, removed by `/mode normal`). |
| `.claude/mode-stats.md` | **never touched** by init or sync | Project-owned cross-activation accumulator. |
| `.claude/task-rules.md` | **OVERWRITE** with kit version | If your project has elaborated this file with project-specific content (gated files, verification commands, baselines, project trust modes), **back it up first** — see "Save your work" below. |
| `.claude/task-template.md` | **OVERWRITE** with kit version | Same — back it up first if project-customized. |
| `.claude/<platform>-*.md` (e.g. `ios-task-rules.md`) | added | New file — won't collide unless you happen to already have one with a matching name. |
| `.claude/foundation.json` | created if missing | Skipped if exists — your existing pin stays. |
| `.claude/pact.md`, `welcome.md`, `wont-do.md`, `playlists.md`, `bookmarks.md` | `skip-if-exists` | Primitive-layer files. Existing versions stay; user owns them after init. |
| `tasks/{backlog,active,done}/` | scaffolded if missing/empty | Existing task files preserved. |
| `tasks/PHASES.md`, `tasks/ROADMAP.md`, `tasks/AUDIT.md` | `skip-if-exists` | Existing project-specific versions stay. |
| `CLAUDE.md` | `skip-if-exists` | Existing CLAUDE.md stays. **You'll edit it after init** to add the new `## Platform` section and migrate any project-specific content from the old task-rules.md. |
| `docs/{decisions,postmortems,notes,audits,handoff,regrets,retros,blast-radius,scope,exports,proto,mvp}/` | scaffolded if missing | Empty `.gitkeep` only. Skill output destinations. |
| `.claude/{tradeoffs,inbox}/` | scaffolded if missing | Empty `.gitkeep` only. `/brainstorm` and `/inbox` write here. |

### Save your work BEFORE running init

If your project has elaborated `.claude/task-rules.md` or
`.claude/task-template.md` beyond the kit's defaults, save them
first:

```sh
cp .claude/task-rules.md /tmp/_pre-kit-task-rules.bak
cp .claude/task-template.md /tmp/_pre-kit-task-template.bak
```

These will be overwritten by `bin/init`. After init, you'll diff
the backups to identify project-specific content and move it to
`CLAUDE.md` (where the kit's design says project-specifics belong).

### The integration sequence

```sh
# 1. Branch off main (or your equivalent default).
git checkout main && git pull
git checkout -b chore/integrate-claude-kit

# 2. Save your project-elaborated kit files.
cp .claude/task-rules.md /tmp/_pre-kit-task-rules.bak 2>/dev/null || true
cp .claude/task-template.md /tmp/_pre-kit-task-template.bak 2>/dev/null || true

# 3. Clone the kit.
git clone https://github.com/ChazzCoin/claude-kit /tmp/claude-kit

# 4. Run init.
/tmp/claude-kit/bin/init .

# 5. Inspect what changed.
git status
git diff .claude/

# 6. Reconcile. Diff the backup against the new kit version.
diff /tmp/_pre-kit-task-rules.bak .claude/task-rules.md

# Identify content that's:
#   - Project-specific (move to CLAUDE.md)
#   - Generic improvement (consider PR'ing back to claude-kit)
#   - Already covered by the kit (drop)

# 7. Edit CLAUDE.md:
#    - Add the new "## Platform" section (right after "## What this is")
#      and declare your project's platform.
#    - Move project-specific gated files from old task-rules.md into
#      the "Gated files" section.
#    - Move project-specific verification baselines (e.g. warning count)
#      into the "Commands" section or a verification subsection.
#    - Move project trust modes (e.g. "approval gate", "stabilization
#      mode") into a "Phase" section in CLAUDE.md.

# 8. Verify nothing important was lost.
diff /tmp/_pre-kit-task-rules.bak .claude/task-rules.md | grep "^<"
# Anything starting with "<" was in your original but not in the kit.
# It either landed in CLAUDE.md (good), is now redundant (good), or
# was lost (fix).

# 9. Run the project's verification gate (build/test).
# 10. Open an integration PR.
```

### What goes where (the kit's design)

The kit's principle: **`task-rules.md` and prefix files are generic;
project-specifics live in `CLAUDE.md`.**

| Project-specific content | Goes in |
|---|---|
| This project's actual scheme name, baseline warning count | `CLAUDE.md` "Commands" |
| Specific Realm models / data classes that exist in this app | `CLAUDE.md` "Schema ownership" |
| Bundle ID, team ID, version | `CLAUDE.md` (top metadata or "Tech stack") |
| This project's phase state (stabilization, alpha, etc.) | `CLAUDE.md` "Phase" |
| Trust modes specific to this project (e.g. "every change requires per-change approval") | `CLAUDE.md` "Phase" or a dedicated section |
| Project-specific gated files beyond the kit defaults | `CLAUDE.md` "Gated files" |

| Generic platform content | Goes in |
|---|---|
| iOS verification gate command shape (`xcodebuild …`) | `kit/ios-task-rules.md` (already there) |
| iOS protected files (`*.xcodeproj/`, etc.) | `kit/ios-task-rules.md` (already there) |
| Apple build-number monotonic constraint | `kit/ios-task-rules.md` (already there) |
| Universal build/test/release patterns | `kit/task-rules.md` (already there) |

If during reconciliation you find your project had a generic
improvement that the kit lacks (e.g. a workflow pattern that would
help every project), open a PR against `claude-kit` to push it
upstream. That's how the kit gets better.

### What to do if you're unsure

Use `/sync` after init. The skill reads `.claude/foundation.json`
and shows a diff of every kit-managed file vs the local version.
You can accept changes file-by-file or mark a file as a "local
override" so future syncs respect it.

### Rollback

`bin/init` is non-destructive of bootstrap files (CLAUDE.md, etc.),
but it does overwrite `task-rules.md` and `task-template.md`. If
something went wrong, the integration branch can be deleted and the
project reverts to its pre-init state (you didn't merge the
branch yet — you were on `chore/integrate-claude-kit`, right?).

---

## Iterating

### "I improved a skill in project A — get it into the kit"

1. In project A, edit the skill in `.claude/skills/<name>/SKILL.md`.
2. When ready, copy that change into the claude-kit repo's
   `kit/skills/<name>/SKILL.md`.
3. Commit + push to claude-kit.
4. In project B (and every other project), run `/sync` and accept the
   skill update.

The `/sync` skill is the one-way valve. It reads from the kit, never
writes back. Pushing improvements back to the kit is a manual git
operation — that's intentional, so changes are reviewed.

### "I want to override a kit file in one project only"

Just edit the file locally. `/sync` will detect the divergence as a
"local override" and **not** overwrite it without your approval. The
override is recorded in `.claude/foundation.json` so future syncs
respect it.

### "The kit shipped a bad change — I want to roll back"

```sh
# In claude-kit:
git revert <bad-commit>
git push
# Then in each project:
/sync   # picks up the revert
```

Or pin to an older commit by editing `.claude/foundation.json`'s
`pinned_sha` field manually.

---

## Design principles

- **Generic where possible, specific where it matters.** Skills detect
  toolchains; rules reference `CLAUDE.md` for project-specific commands;
  templates use `{{PLACEHOLDER}}` markers.
- **Honest reporting both ways.** Same ethos as [Anthropic's CLAUDE.md
  conventions]. Skills report failures plainly; sync surfaces conflicts
  rather than silently merging.
- **Never auto-commit.** Every skill that modifies files leaves changes
  staged or unstaged for the human to review.
- **Solo-dev-friendly first.** No team-mode features (codeowners,
  required reviewers, multi-author workflows) until they're actually
  needed.

---

## License

MIT. Copy, fork, hack on it. If you make it better, send a PR.
