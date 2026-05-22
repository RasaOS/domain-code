# Claude Code · Terminal Output Design Catalogue

A reference of visual patterns Claude Code can use to make end-of-task output, status reports, audits, and roadmaps feel *designed* rather than dumped. Each entry includes the raw template (copy-pasteable), what it's for, and the design rationale.

All designs assume a monospace font and ANSI color support. Color cues below use semantic names (success / warning / danger / accent / dim) rather than specific hex values so you can map them to whatever palette you settle on.

---

## Patterns by use case

**Finishing a task** — [1 Hero card](#1--hero-completion-card) · [10 Banner](#10--section-banner) · [26 Empty state](#26--empty-state)

**Reporting progress** — [2 Live dashboard](#2--live-status-dashboard) · [23 Activity timeline](#23--activity-timeline) · [30 Multi-step wizard](#30--multi-step-wizard)

**Planning & roadmaps** — [3 Roadmap](#3--roadmap-timeline) · [4 Sprint board](#4--sprint-task-board) · [13 Kanban](#13--kanban-board) · [14 Decision tree](#14--decision-tree)

**Deployment & ops** — [5 Deployment](#5--deployment-report) · [27 Service topology](#27--service-topology) · [25 Alert variants](#25--alert-variants)

**Quality & review** — [6 Audit](#6--severity-audit) · [7 Tests](#7--test-results) · [8 Benchmark](#8--performance-benchmark) · [9 PR review](#9--pr--code-review-summary) · [19 Histogram](#19--distribution-histogram)

**Code & version control** — [12 Side-by-side diff](#12--side-by-side-diff) · [15 Stack trace](#15--stack-trace-with-code-context) · [16 Git log](#16--git-log-graph) · [17 Branch overview](#17--git-branch-overview) · [22 Diff stats](#22--diff-stats-with-bars) · [29 Search results](#29--search-results-with-code-context)

**Graphs & visualisations** — [11 Dependency graph](#11--dependency-graph) · [18 Heatmap](#18--contribution-heatmap) · [20 Bar chart](#20--horizontal-bar-chart) · [21 Funnel](#21--funnel-flow) · [28 Stats grid](#28--stats-card-grid)

**Data display** — [24 Comparison matrix](#24--comparison-matrix) · [31 JSON tree](#31--json-tree-viewer) · [32 Leaderboard](#32--leaderboard)

**User interaction** — [33 Command reference](#33--command-reference) · [34 Selection prompt](#34--selection-prompt)

---

## 1 · Hero completion card

**Use when:** a long task finishes successfully. Reserve this template for genuine end-of-run moments — using it after every small operation dilutes the impact.

```
╭─────────────────────────────────────────────────────────╮
│                                                         │
│   ✦  TASK COMPLETE                                      │
│                                                         │
│      Authentication system migration                    │
│      duration · 18m 42s                                 │
│                                                         │
│   ─────────────────────────────────────────────────     │
│                                                         │
│      12  files changed                                  │
│     347  lines added       ·   84  removed              │
│       8  tests passing     ·    0  failing              │
│                                                         │
│   ─────────────────────────────────────────────────     │
│                                                         │
│   →  next: review diff and run integration tests        │
│                                                         │
╰─────────────────────────────────────────────────────────╯
```

**Color cues**
- Outer rounded box · accent color (mauve / purple)
- `✦` glyph · warm accent (yellow / amber)
- Headline `TASK COMPLETE` · bright white
- Counts `347` · success green; `84` · danger red
- Inner separator and labels · dim gray
- `→` arrow · cyan / teal

**Why it works**
- Single accent color on the box keeps it celebratory without being loud.
- Generous internal padding (blank lines top and bottom inside the box) signals "important, take a moment."
- The colored corner glyph is the only ornament — every other element is data.

---

## 2 · Live status dashboard

**Use when:** a long-running pipeline or multi-step operation is in progress. Designed to be re-rendered in place as state changes.

```
┌─ Build pipeline ──────────────────────────── 14:32:08 ─┐
│                                                        │
│  ● lint        ████████████████████  100%   passed     │
│  ● typecheck   ████████████████████  100%   passed     │
│  ◐ test        ████████████░░░░░░░░   62%   running    │
│  ○ build       ░░░░░░░░░░░░░░░░░░░░    0%   queued     │
│  ○ deploy      ░░░░░░░░░░░░░░░░░░░░    0%   queued     │
│                                                        │
│  eta · ~3 min                                          │
└────────────────────────────────────────────────────────┘
```

**Color cues**
- Box border, timestamp, "eta" label · dim gray
- `●` and filled bar segments for done steps · success green
- `◐` and filled bar for active step · warning yellow
- `○` and `░` for queued steps · dim gray

**Why it works**
- Three-state glyphs (`●` `◐` `○`) plus filled-vs-empty bar characters give two redundant encodings of progress — readable even with color stripped.
- Each row aligns into a clean grid: glyph, label, bar, percentage, status word. Eye scans top-to-bottom for state at a glance.

---

## 3 · Roadmap timeline

**Use when:** showing multi-phase project state — quarterly plans, large migrations, anything with phases that have a clear sequence.

```
  ROADMAP ▏ Q4 2026


  ●━━━━━━━━━━●━━━━━━━━━━●─ ─ ─ ─ ─ ─ ○
  phase 1     phase 2     phase 3      phase 4
  done        done        active       planned


  Phase 3  ·  integration layer

  ├─  ✓  api client refactor
  ├─  ✓  type definitions
  ├─  ◐  endpoint mappings        ← in progress
  ├─  ○  error handling
  └─  ○  retry logic
```

**Color cues**
- Solid track `━━━` and done phase nodes · success green
- Active node and `◐` glyph · warning yellow
- Dashed track `─ ─ ─` and pending nodes · dim gray
- `←` pointer · dim gray (or accent for emphasis)

**Why it works**
- Top half is the macro view (which phase are we in); bottom half is the micro view (what's happening inside the active phase).
- The `←` pointer is a stronger "you are here" indicator than any amount of bold text.
- Track style — solid for done, dashed for future — encodes time without dates.

---

## 4 · Sprint task board

**Use when:** showing a hierarchical to-do list with multiple groups. Good for sprint summaries, refactor plans, anything with collapsible sections.

```
┏━ SPRINT 14 · 7 of 12 done ━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                                                       ┃
┃  ▾ Refactor auth module            ●●●○               ┃
┃     [✓]  extract token validation                     ┃
┃     [✓]  move session logic to middleware             ┃
┃     [◐]  update tests           ← in progress         ┃
┃     [ ]  add error boundaries                         ┃
┃                                                       ┃
┃  ▾ Documentation                   ○○○                ┃
┃     [ ]  update api reference                         ┃
┃     [ ]  add migration guide                          ┃
┃     [ ]  record demo video                            ┃
┃                                                       ┃
┃  ▸ Performance                     ●●○○○              ┃
┃     5 items collapsed                                 ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

**Color cues**
- Heavy box border · accent (mauve / purple)
- `▾` `▸` group toggles, group titles · bright white
- `●` filled mini-progress dots · success green
- `[✓]` complete · success green
- `[◐]` active · warning yellow
- `[ ]` pending and `○` empty dots · dim gray

**Why it works**
- Heavy box drawing (`┏━┓ ┃ ┗━┛`) reads as more emphasized than light box drawing — appropriate for a top-level summary.
- Per-group inline progress (`●●●○`) acts as a TL;DR — you can read just the group lines and know the state.
- Collapsed sections show their item count instead of their guts, keeping the view scannable.

---

## 5 · Deployment report

**Use when:** announcing a release. Captures what was deployed, where, by whom, and how to verify it.

```
  ▲  DEPLOYMENT   ·   prod-us-east-1   ·   v2.4.1


  ┌─ services ─────────────────────────────────────────┐
  │                                                    │
  │   ●  api-gateway       healthy    ▲ 0.1.4 → 0.1.5  │
  │   ●  auth-service      healthy    ▲ 1.2.0 → 1.3.0  │
  │   ●  database          healthy    ═ 3.4.2          │
  │   ●  worker-pool       healthy    ▲ 0.8.1 → 0.9.0  │
  │   ●  cache             healthy    ═ 2.1.0          │
  │                                                    │
  └────────────────────────────────────────────────────┘


  deployed by    chazz@example.com
  started        2026-04-29  09:14 UTC
  completed      2026-04-29  09:18 UTC   ·   4m 12s


  →  https://app.example.com
  →  https://api.example.com/health
```

**Color cues**
- `▲` deploy banner glyph · accent (orange / coral)
- Title row, environment, version · bright white / accent
- `●` healthy indicators and `healthy` text · success green
- `▲` version-bumped arrows · cyan / teal
- `═` unchanged marker, key labels, separators · dim gray
- URLs · blue (link color)

**Why it works**
- Glyph shorthand carries the version state: `▲` means "bumped", `═` means "unchanged" — no need for a "changed?" column.
- Two-column key/value rows below the box beat a table when values are short. The visual rhythm of label-then-value is easy to scan.
- Health-check URLs at the bottom give the reader an obvious next step.

---

## 6 · Severity audit

**Use when:** displaying findings from a security scan, dependency audit, lint pass, or anything with multi-level severity. Critical issues should grab attention; lows should not.

```
  SECURITY AUDIT   ·   41 findings across 12 files


  ●  CRITICAL    ━━━━                                   2
  ●  HIGH        ━━━━━━━━━━                             5
  ●  MEDIUM      ━━━━━━━━━━━━━━━━━━━━━━                11
  ●  LOW         ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   23


  ▌ CRITICAL  ·  src/auth/login.ts:42
    Hardcoded credentials detected
    └─ replace with environment variable

  ▌ CRITICAL  ·  src/api/routes.ts:18
    Missing input validation on /user endpoint
    └─ add zod schema validation

  ▌ HIGH      ·  src/db/query.ts:103
    Potential SQL injection via string interpolation
    └─ use parameterized query

  ⋮  showing 3 of 41   ·   → claude-code show all
```

**Color cues**
- Each severity tier has its own color for both the `●` dot, the bar, and the `▌` left-edge accent:
  - CRITICAL · danger red
  - HIGH · warning orange
  - MEDIUM · warning yellow
  - LOW · info blue
- File paths and label text · neutral subtext gray
- Action hints after `└─` · default body text

**Why it works**
- Bar lengths are inversely proportional to severity — criticals are short, urgent stubs; lows sprawl. The eye lands on dangerous things first.
- The `▌` left-edge accent pulls focus into each finding without the cost of a full surrounding box.
- The `⋮` ellipsis with explicit "showing 3 of 41" handles long lists honestly.

---

## 7 · Test results

**Use when:** reporting test outcomes. Failures should show enough information to fix them without opening the file.

```
  ▌▌▌  TEST RESULTS  ▌▌▌


   142  ✓ passing
     2  ✗ failing
     5  ⊘ skipped


  ────────────────────────────────────────────────────────


  ✗  AuthService › login › rejects expired tokens
     expected   TokenExpiredError
     received   ValidationError
     at  src/auth/__tests__/login.test.ts:84


  ✗  PaymentFlow › retry logic › backs off exponentially
     expected   [100, 200, 400, 800]
     received   [100, 100, 100, 100]
     at  src/payments/__tests__/retry.test.ts:23


  ────────────────────────────────────────────────────────

  coverage   ████████████████░░░░   82.4%
```

**Color cues**
- `▌▌▌` banner bars · success green
- `✓ passing` count · success green
- `✗ failing` count and glyphs · danger red
- `⊘ skipped` count · dim gray
- `expected` value · success green
- `received` value · danger red
- `at` location · dim gray
- Coverage bar filled portion · success green; empty portion · dim gray

**Why it works**
- The triple-bar (`▌▌▌`) gives a heavy banner without the visual weight of a full box.
- Failures show *both* values in their semantic colors — green is what was true, red is what was wrong. The brain pattern-matches the diff instantly.
- The breadcrumb path (`AuthService › login › rejects expired tokens`) reads like a sentence, friendlier than `auth_service__login__rejects_expired_tokens`.

---

## 8 · Performance benchmark

**Use when:** showing latency or throughput results across multiple endpoints or operations. Block-character sparklines compress distribution shape into a few characters.

```
  BENCHMARK  ·  api endpoints              p50  /  p95  /  p99


  GET   /users/:id          ▁▁▁▁▂          12 /  28 /  45 ms
  GET   /posts              ▁▁▂▃▅          38 /  92 / 184 ms
  POST  /comments           ▁▁▁▂▃          21 /  54 /  98 ms
  GET   /search             ▂▃▅▆█         147 / 312 / 478 ms
  POST  /uploads            ▃▅▆▇█         234 / 587 / 921 ms


  ✓  all endpoints meet sla   ·   p95 < 1000ms
```

**Color cues**
- Sparklines for fast endpoints · success green
- Sparklines for slower-but-acceptable endpoints · warning yellow
- Sparklines for slowest endpoints · accent orange
- p95 column (the "important" one) is colored to match its sparkline; other percentiles are default
- SLA confirmation row · `✓` success green; supporting text · dim gray

**Why it works**
- Sparkline blocks (`▁▂▃▄▅▆▇█`) carry distribution shape — you see at a glance that `/search` is right-skewed (long tail) while `/users/:id` is tight.
- Highlighting only the p95 column draws the eye to the metric most teams care about, while still keeping p50/p99 visible for context.

---

## 9 · PR / code review summary

**Use when:** giving a per-file quality summary at PR-review time. The light-mode terminal palette here is intentional — review feedback is collaborative, not alarming.

```
  CODE REVIEW   ·   PR #427   ·   feat/payment-flow


  ★★★★☆   4.2 / 5      ready to merge with minor changes


  ┌────────────────────────────────────────────────────┐
  │  src/payments/processor.ts          ★★★★★  ✓       │
  │  src/payments/validator.ts          ★★★★☆  ✓       │
  │  src/payments/__tests__/proc.ts     ★★★★★  ✓       │
  │  src/api/checkout.ts                ★★★☆☆  !       │
  │  src/utils/currency.ts              ★★★★★  ✓       │
  └────────────────────────────────────────────────────┘


  !  src/api/checkout.ts
     suggestion   extract retry logic into shared utility
     why          lines 45-78 duplicate src/api/orders.ts
```

**Color cues** *(light terminal background)*
- Filled stars `★` · warning yellow
- Empty stars `☆` and box border · dim gray
- `✓` files clean · success green
- `!` files with suggestions · accent orange
- "ready to merge" · success green
- File paths and section labels · dim gray
- Suggestion text · default body color

**Why it works**
- Stars and `✓ / !` provide twin encodings of quality — color-blind safe and skimmable.
- A light background reads as friendlier than a dark one for what is essentially feedback. Save the dark "alarm" palette for security and failure contexts.
- Each file's score sits in a fixed column, so the eye finds the lowest-rated file instantly.

---

## 10 · Section banner

**Use when:** a long output needs major section breaks. Half-block characters give a banner that feels printed rather than typed.

```
  ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
  █                                                 █
  █     M I G R A T I O N    R E P O R T            █
  █     postgres 14 → 16   ·   3,421 rows           █
  █                                                 █
  ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀


  ▸ Phase 1   schema migration           complete
  ▸ Phase 2   data backfill               complete
  ▸ Phase 3   index rebuild               running
  ▸ Phase 4   cutover                     pending
```

**Color cues**
- Banner blocks `▄ █ ▀` · accent (mauve / purple)
- Title `M I G R A T I O N    R E P O R T` · bright white
- Subtitle line · subtext gray
- `▸` phase markers and labels · subtext gray
- "complete" · success green; "running" · warning yellow; "pending" · dim gray

**Why it works**
- Half-block characters (`▄ ▀ █`) at the top and bottom give the banner solid weight without needing to fill in the interior.
- Letter-spaced title (`M I G R A T I O N`) reads as deliberate signage rather than a bold heading. Reserve this trick — overuse breaks the effect.

---

## 11 · Dependency graph

**Use when:** visualising module relationships, package dependencies, or any DAG. The horizontal-tree style stays readable even with many nodes.

```
  DEPENDENCY GRAPH  ·  src/


  app
   ├──▶  auth ──────────┬──▶  jwt
   │                    └──▶  crypto
   │
   ├──▶  api  ──────────┬──▶  routes ──┬──▶  auth ⟲
   │                    │              └──▶  users
   │                    └──▶  middleware ──▶  logger
   │
   └──▶  db  ───────────┬──▶  postgres
                        ├──▶  redis
                        └──▶  logger


  ⟲  circular reference   ·   2 cycles detected
```

**Color cues**
- Tree branch characters (`├──▶  └──▶`) · dim gray
- Module names at depth 1 · bright white
- Module names at depth 2+ · default body text
- `⟲` cycle marker and any node involved in a cycle · danger red
- Footer legend · subtext gray

**Why it works**
- Horizontal layout means the tree grows rightward, not down — you can fit ~3 levels deep on standard terminal width.
- Repeated nodes (the `auth` and `logger` that show up twice) are flagged with `⟲` so the reader sees fan-in without rendering every edge.
- Aligning the arrows in vertical columns at each depth turns the structure into a near-visual bar chart of branching factor.

---

## 12 · Side-by-side diff

**Use when:** showing before/after on the same code. More cognitively cheap than unified diffs for showing structural rewrites.

```
  src/auth/login.ts


  ┌─ before ────────────────────────────┬─ after ─────────────────────────────┐
  │                                     │                                     │
  │ 41  function login(u, p) {          │ 41  function login(creds) {         │
  │ 42    if (!u) return null;          │ 42    const { user, pass } = creds; │
  │ 43    if (!p) return null;          │ 43    if (!user || !pass) {         │
  │ 44    return auth(u, p);            │ 44      throw new ValidationError();│
  │ 45  }                               │ 45    }                             │
  │                                     │ 46    return auth(creds);           │
  │                                     │ 47  }                               │
  │                                     │                                     │
  └─────────────────────────────────────┴─────────────────────────────────────┘

  -2 lines     +3 lines     5 lines changed
```

**Color cues**
- Box borders and column headers · dim gray
- Line numbers · subtext gray
- Removed lines (left side, when shown with `-` prefix) · danger red dim
- Added lines (right side, when shown with `+` prefix) · success green dim
- Footer counts: `-2` · danger red, `+3` · success green, `5 changed` · default

**Why it works**
- Two equal columns force the eye to compare like for like at the same vertical position.
- Headers `before` / `after` are tiny and quiet — the code is the content, the labels are scaffolding.
- The footer summary gives the macro impact without re-counting; readers can skip it if they read the columns.

---

## 13 · Kanban board

**Use when:** showing parallel work-in-progress across stages. The column layout maps directly onto how teams actually think about flow.

```
  KANBAN  ·  payments-team


  ┌─ TODO ────────────┬─ DOING ───────────┬─ DONE ────────────┐
  │                   │                   │                   │
  │  ▣ Stripe webhook │  ▣ Auth migration │  ▣ Refactor api   │
  │    @chazz         │    @sam · ◐ 60%   │    @chazz         │
  │                   │                   │                   │
  │  ▣ Email retry    │  ▣ Retry tests    │  ▣ Update docs    │
  │    unassigned     │    @chazz · ◐ 30% │    @sam           │
  │                   │                   │                   │
  │  ▣ Refund flow    │                   │  ▣ Fix typo       │
  │    @sam           │                   │    @ana           │
  │                   │                   │                   │
  │   3 items         │   2 items         │   3 items         │
  └───────────────────┴───────────────────┴───────────────────┘
```

**Color cues**
- Column headers `TODO` / `DOING` / `DONE` · subtext gray; `DONE` may go green for satisfaction
- `▣` card markers · column-themed (gray for todo, yellow for doing, green for done)
- Card titles · default body text
- `@handle` tags · cyan / accent
- `◐ 60%` progress markers on doing cards · warning yellow
- Item counts at the bottom · dim gray

**Why it works**
- Three equal columns echo the physical metaphor of a board on a wall.
- Each card is just two lines (title + meta) — anything more would crowd the column.
- Per-card progress only appears on `DOING` cards, where it's actually meaningful. Variable density per column tells you something.

---

## 14 · Decision tree

**Use when:** capturing a decision or recommendation that depends on branching criteria. Useful for technology choices, architectural trade-offs, troubleshooting flows.

```
  DECISION  ·  database choice for new service


  Need transactional consistency?
  │
  ├── yes ──▶  Need horizontal scale?
  │           │
  │           ├── yes ──▶  CockroachDB
  │           └── no  ──▶  PostgreSQL  ★
  │
  └── no  ──▶  Document model?
              │
              ├── yes ──▶  MongoDB
              │
              └── no  ──▶  Need persistence?
                          │
                          ├── yes ──▶  SQLite
                          └── no  ──▶  Redis


  ★  recommended for your use case
```

**Color cues**
- Tree branches and `yes / no` labels · dim gray
- Question text at branch points · default body text
- Leaf node names (the actual answers) · bright white
- `★` recommendation marker and the recommended leaf · accent (yellow)

**Why it works**
- Each question is a single line — no ambiguity about what "yes" or "no" means.
- The recommended leaf gets a star *and* keeps its plain styling — the decoration calls attention without changing the semantics.
- Indentation depth equals decision depth, so the tree's shape immediately tells you how many factors weighed in.

---

## 15 · Stack trace with code context

**Use when:** showing an error. Inline code context turns a stack trace from "where" into "why" without forcing the reader to open the file.

```
  ⚠  TypeError: Cannot read properties of undefined (reading 'id')


  ▌ at  AuthMiddleware.validateUser
        src/auth/middleware.ts:42:18

        40 │  const user = await db.find(token);
        41 │
     ▶  42 │  return { id: user.id, role: user.role };
                                ^^
        43 │
        44 │  // user can be undefined when token is stale


  ▌ at  Router.handle
        src/api/router.ts:108:14


  ▌ at  Server.<anonymous>
        node:internal/server.js:312:6


  caused by  ▼

  ⚠  TokenExpiredError: jwt expired at 2026-04-29T08:45:21
        src/auth/jwt.ts:67
```

**Color cues**
- `⚠` error glyph and error class name · danger red
- Error message body · bright white (it's the headline)
- `▌` left-edge frame markers · danger red on top frame, dim on chained frames
- Function name at each frame · accent (cyan)
- File path and line number · subtext gray
- Code context line numbers and `│` separator · dim gray
- The `▶` highlighted line · default body text
- Caret pointer `^^` underneath the failing expression · danger red
- `caused by ▼` divider · subtext gray

**Why it works**
- The `▶` arrow plus a caret-underline pinpoints the *exact* expression that failed — not just the line.
- Showing 2 lines of context above and below converts hieroglyphics into something a reader can actually understand.
- Chained errors get a `caused by ▼` divider so cause-and-effect reads top-down, the way the reader thinks about it.

---

## 16 · Git log graph

**Use when:** showing recent commit history with branches. The traditional `git log --graph` style, cleaned up.

```
  GIT LOG  ·  feat/payments  →  main


  *  4f8c3d2  (HEAD → feat/payments)  add stripe webhook
  │           chazz · 14 minutes ago
  │
  *  9a2e1b7  refactor: extract retry helper
  │           chazz · 2 hours ago
  │
  │ *  8b7d4f1  (origin/main, main)  fix: typo in readme
  │ │           sam · 1 day ago
  │ │
  *─┘  c4a9e83  feat: stripe integration scaffolding
  │             chazz · 1 day ago
  │
  *  e2f6a90  chore: bump deps
              dependabot · 3 days ago
```

**Color cues**
- `*` commit nodes · default; merge commits (`*─┘`) · accent
- `│` and `─` graph lines · dim gray
- Commit hash · accent (yellow / amber)
- Refs in parens like `(HEAD → feat/payments)` · cyan; `origin/main` · accent green
- Commit subject · bright white
- Author and timestamp · subtext gray

**Why it works**
- The graph column on the left captures branch topology at a glance — you can see the branch diverged at `c4a9e83` without reading anything.
- Author and timestamp on a second line keeps each commit visually contained as a "card" without needing actual borders.
- Refs in parens distinguish current branch (cyan) from remote (green) so you know what's published vs. local.

---

## 17 · Git branch overview

**Use when:** giving a high-level snapshot of all active branches. Useful for stand-ups or weekly summaries.

```
  BRANCHES


   main                                                  ●
   │
   ├──── feat/payments       chazz   2 commits ahead    ●━━●
   │
   ├──── feat/auth-rewrite   sam     5 commits ahead    ●━●━●━●━●
   │     └─ ◇ pull request  #427    needs review
   │
   ├──── fix/cache-leak      ana     1 commit ahead     ●
   │     └─ ◇ pull request  #428    ✓ approved
   │
   └──── chore/deps          bot     3 commits ahead    ●━●━●  (stale 12d)
```

**Color cues**
- `main` and main's node · bright white
- Branch tree characters (`├── └──`) · dim gray
- Active feature branches · accent (cyan)
- Author handle · subtext gray
- "X commits ahead" · default
- Commit dots `●━━●` · success green for healthy branches; warning yellow for stale; danger red for very stale or broken
- `◇` PR markers · accent
- `✓ approved` · success green; `needs review` · warning yellow
- `(stale 12d)` annotation · danger red

**Why it works**
- The dots-and-bars pattern (`●━●━●`) gives a literal sense of how many commits ahead each branch is.
- Sub-rows for PRs (`└─ ◇ pull request`) hang off their parent branch, so the relationship is structural, not described.
- Stale branches turn red on the right edge — you read past them, then the red catches you.

---

## 18 · Contribution heatmap

**Use when:** showing activity density across time. Github-style commit graph, but works equally well for any "thing per day" measurement.

```
  CONTRIBUTIONS  ·  last 12 weeks         total · 247 commits


       w1  w2  w3  w4  w5  w6  w7  w8  w9 w10 w11 w12
  mon  ░   ▒   ▓   █   ▒   ░   ▓   █   █   ▓   ▒   ░
  tue  ▒   ▓   █   ▓   ▒   ▒   █   █   ▓   ░   ▒   ▒
  wed  ▓   █   █   ▓   ▒   ▓   █   ▓   ▒   ▒   ▓   ░
  thu  ▒   ▓   ▒   ░   ▓   █   ▓   ▒   ░   ▒   ▓   ▒
  fri  ░   ▒   ░   ░   ▓   ▒   ░   ░   ▒   ▓   ░   ░
  sat  ·   ·   ·   ░   ·   ·   ·   ░   ·   ·   ·   ·
  sun  ·   ·   ·   ·   ·   ·   ░   ·   ·   ·   ·   ·


  less  ·   ░   ▒   ▓   █   more
```

**Color cues**
- Day-of-week labels and column headers · dim gray
- `·` (no activity) · dim gray
- `░` (low) · success green at low opacity
- `▒` (medium-low) · success green slightly stronger
- `▓` (medium-high) · success green stronger
- `█` (high) · success green at full intensity
- Legend row at the bottom · subtext gray

**Why it works**
- Four density blocks (`░ ▒ ▓ █`) plus the empty `·` give five distinct levels in pure ASCII.
- Days of week as rows (rather than columns) means weekend rows can stay sparse without throwing off the rhythm.
- The legend bar at the bottom is itself a tiny version of the encoding — readers learn the scale by example.

---

## 19 · Distribution histogram

**Use when:** showing the *shape* of a metric, not just summary statistics. Reveals bimodal distributions, long tails, and outliers that p50/p95/p99 hide.

```
  RESPONSE TIMES  ·  /api/search   ·   10,000 samples


       0-50ms     ████████████████████  4,231
      50-100ms    ████████████████      3,012
     100-200ms    █████████             1,847
     200-500ms    ████                    721
     500-1000ms   ▌                       139
     1000ms+      ▎                        50


  p50    42 ms   ◀━━━━━━━━━━┓
  p95   187 ms              ━━━━━━━━━━━━━┓
  p99   622 ms                          ━━━━━━━━━━━┓
  max 4,210 ms                                     ━━━━┓
```

**Color cues**
- Bucket labels and counts · subtext gray
- Bars for low-latency buckets · success green
- Bars for medium buckets · warning yellow
- Bars for high-latency buckets · accent orange or danger red
- Percentile rows below: labels and values · default; the indicator line `◀━━━┓` · matches the colour of the bucket the percentile falls into

**Why it works**
- The vertical alignment of the percentile indicators below the histogram visually shows you which bucket each percentile lives in.
- Sub-block characters `▌ ▎` for the smallest counts mean tiny buckets still get a visible bar — they don't disappear into "0".
- Counts on the right keep precise data accessible; bars give you the shape; percentiles below give you the headline numbers. Three levels of detail in one chart.

---

## 20 · Horizontal bar chart

**Use when:** comparing parts of a whole, or ranking items. Cleaner than pie charts, and labels stay readable.

```
  LANGUAGE BREAKDOWN  ·  this repo


   TypeScript    ████████████████████████████████  62.4%   84,231 lines
   Python        ███████████                       21.8%   29,447
   CSS           ██████                            10.2%   13,772
   Shell         █                                  3.1%    4,189
   Dockerfile    ▌                                  1.4%    1,891
   Other         ▎                                  1.1%    1,488
                                                   ─────   ───────
                                                   100%   135,018
```

**Color cues**
- Category labels · default body text
- Each bar gets its own color from a categorical palette (cyan, green, yellow, accent, pink, gray) — same color across the whole row would also work
- Percentages · subtext gray
- Line counts · subtext gray
- Total row separator (`─────`) and totals · dim gray

**Why it works**
- Single longest bar establishes the chart's scale; everything else is read relative to it.
- Sub-block characters for tiny percentages keep the chart readable down to ~1%.
- The summed total at the bottom is a sanity check — readers trust the chart more when they see the math close.

---

## 21 · Funnel flow

**Use when:** showing conversion or drop-off through stages. Each stage shows what arrived and what was lost.

```
  USER FLOW  ·  signup funnel


  visitors          ████████████████████  10,000
                          │
                          ├──▶ bounced     ████████          4,212  (42%)
                          │
                          ▼
  signup page       ████████████          5,788
                          │
                          ├──▶ abandoned   ████              2,103  (36%)
                          │
                          ▼
  verified          ████████              3,685
                          │
                          ├──▶ inactive    ███               1,247  (34%)
                          │
                          ▼
  activated         █████                 2,438  (24% of visitors)
```

**Color cues**
- Stage labels · bright white
- Main funnel bars · accent (cyan)
- Drop-off bars on the side · subtext gray (or warning yellow if the drop is unusually high)
- Drop-off percentages in parens · subtext gray
- Final stage percentage `(24% of visitors)` · accent (cyan), highlighting the headline number

**Why it works**
- Bar widths shrink down the page in proportion to volume — the funnel shape literally is the data.
- Each drop-off branches to the right, so the reader's eye follows the main flow downward and only steps aside when investigating a leak.
- The final number gets re-stated as a percentage of the original to give a single conversion-rate KPI.

---

## 22 · Diff stats with bars

**Use when:** summarising changed files in a PR. Adds a visual weight to each file beyond the raw line counts.

```
  CHANGED FILES  ·  PR #427


   M   src/payments/processor.ts        +47   -12   ████████████░░░
   A   src/payments/__tests__/proc.ts   +89    -0   ████████████████████
   M   src/api/checkout.ts              +23   -34   ███████░░░░░░░░░░░░
   M   src/utils/currency.ts            +12    -3   ████░░░░░░░░░░░░░░░
   D   src/payments/legacy.ts            +0  -156   ░░░░░░░░░░░░░░░░░░░░  deleted
                                        ───   ────
                                        +171  -205   net -34


   A  added     M  modified    D  deleted
```

**Color cues**
- `A` add marker · success green
- `M` modify marker · warning yellow
- `D` delete marker · danger red
- File paths · default body text
- `+47` adds · success green; `-12` removes · danger red
- Bar: `█` filled portion (additions) · success green; `░` empty portion (deletions or "deleted" state) · danger red dim
- Total row separators · dim gray
- "net -34" · color depends on direction (red if removing, green if adding)

**Why it works**
- The bar shows additions/deletions at a glance — a mostly-`█` bar is a "growing" file, mostly-`░` is shrinking.
- Files with `D` show only `░` — deletion is total, the bar reflects that.
- Three encodings of the same data (file marker, numeric counts, bar) make it accessible to many reading styles.

---

## 23 · Activity timeline

**Use when:** showing a chronological sequence of events. Good for incident postmortems, audit logs, deployment histories.

```
  ACTIVITY


  09:42  ◆  deploy started        v2.4.1 → prod-us-east-1
         │  by chazz · commit 4f8c3d2
         │
  09:43  ●  health check failed   api-gateway   2 of 5 instances
         │
  09:44  ●  health check failed   api-gateway   4 of 5 instances
         │
  09:45  ▲  rollback initiated    auto-trigger after 3 failures
         │
  09:46  ◇  rollback complete     v2.4.0 restored
         │  duration · 4m 12s
         │
  09:48  ◇  postmortem requested  by sam
```

**Color cues**
- Timestamps · subtext gray
- Connecting `│` line · dim gray
- Event glyph color carries the event type:
  - `◆` neutral / informational · accent
  - `●` failure or alert · danger red
  - `▲` automated action · warning yellow
  - `◇` resolution · success green
- Primary event description · bright white
- Secondary metadata (next line) · subtext gray

**Why it works**
- A single vertical line connects all events into one narrative — disconnected log lines don't read this way.
- Glyphs do most of the type-marking work; reading down the glyph column tells you the story before you read any text.
- Sub-lines for metadata reduce horizontal noise and keep the timeline column-aligned.

---

## 24 · Comparison matrix

**Use when:** comparing 3+ options across several criteria. The matrix layout is more honest than prose because it forces every cell to be filled.

```
  DATABASE COMPARISON


                       │ postgres │ mongodb │  redis  │ sqlite │
   ────────────────────┼──────────┼─────────┼─────────┼────────┤
    ACID               │    ✓     │    ◐    │    ✗    │   ✓    │
    horizontal scale   │    ◐     │    ✓    │    ✓    │   ✗    │
    full-text search   │    ✓     │    ✓    │    ◐    │   ◐    │
    embedded mode      │    ✗     │    ✗    │    ✗    │   ✓    │
    json native        │    ✓     │    ✓    │    ◐    │   ◐    │
    setup complexity   │  medium  │  medium │   low   │  none  │


   ✓  supported     ◐  partial     ✗  not supported
```

**Color cues**
- Header row (column names) · bright white
- Row labels (criteria) · default body text
- Cell separators (`│ ─ ┼`) · dim gray
- `✓` · success green
- `◐` · warning yellow
- `✗` · danger red
- Text values like "medium / low / none" · subtext gray
- Legend at bottom · subtext gray

**Why it works**
- Every cell is colour-coded, so the matrix becomes a heatmap — green columns are strong fits, red columns are not.
- Reading down a column tells you about an option; reading across a row tells you about a criterion. The same chart works for both questions.
- Three-state symbols (`✓ ◐ ✗`) capture nuance that binary yes/no can't.

---

## 25 · Alert variants

**Use when:** drawing attention to a single piece of information. Four variants handle the common cases.

```
  ┌─ ⓘ  INFO ─────────────────────────────────────────────────┐
  │  schema changes detected                                  │
  │  run `claude-code migrate` to apply 3 pending migrations  │
  └───────────────────────────────────────────────────────────┘


  ┌─ ⚠  WARNING ─────────────────────────────────────────────┐
  │  api key found in committed file                         │
  │  src/config.ts:14 — rotate immediately                   │
  └──────────────────────────────────────────────────────────┘


  ┌─ ✗  ERROR ───────────────────────────────────────────────┐
  │  build failed                                            │
  │  3 errors in 2 files — see report above                  │
  └──────────────────────────────────────────────────────────┘


  ┌─ ✓  SUCCESS ─────────────────────────────────────────────┐
  │  all tests passing                                       │
  │  142 tests · 8.4s · coverage 82.4%                       │
  └──────────────────────────────────────────────────────────┘
```

**Color cues**
- INFO box border, glyph, label, title text · info blue
- WARNING border, glyph, label, title · warning yellow
- ERROR border, glyph, label, title · danger red
- SUCCESS border, glyph, label, title · success green
- Body text in all variants · default

**Why it works**
- Four variants cover ~95% of single-point alerts; teams don't need a fifth.
- The glyph doubles as a fallback for when terminal color is stripped — you can tell the type from `ⓘ`, `⚠`, `✗`, `✓` alone.
- Headline on first line, supporting detail on second line — the reader gets the gist even if they bail after one line.

---

## 26 · Empty state

**Use when:** there's nothing to show. A friendly empty state beats a blank screen and prevents the "is it broken?" question.

```


                    ┌───────┐
                    │   ·   │
                    │       │
                    └───────┘


               No issues found

          your code is clean today


        →  claude-code review --recheck
```

**Color cues**
- Sketch frame `┌─┐ │ └─┘` · dim gray
- `·` inside frame · subtext gray
- Headline "No issues found" · bright white
- Subtitle · subtext gray
- `→ claude-code review --recheck` action hint · accent (cyan)

**Why it works**
- The little ASCII illustration signals "this is intentional" — the screen isn't broken, it's just quiet.
- Centered layout (vs the left-aligned norm) reinforces the "moment of stillness" feeling.
- A suggested next action keeps the user moving — empty states are choice points, not dead ends.

---

## 27 · Service topology

**Use when:** showing a system architecture or service mesh — what connects to what, what's healthy, what's not.

```
  SERVICE MESH


               ┌─ load balancer ─┐
               │                 │
               ▼                 ▼
         ┌─ api-gw ─┐      ┌─ api-gw ─┐
         │  3.4.1   │      │  3.4.1   │
         └────┬─────┘      └─────┬────┘
              │                  │
              └────────┬─────────┘
                       ▼
               ┌─ auth-svc ─┐
               │   1.3.0    │
               └────┬───────┘
                    │
         ┌──────────┼──────────┐
         ▼          ▼          ▼
     ┌─ db ─┐  ┌─ cache ─┐  ┌─ queue ─┐
     │ pg14 │  │ redis 7 │  │ rabbit  │
     └──────┘  └─────────┘  └─────────┘


   ●  healthy     ⊘  degraded     ✗  down       all healthy
```

**Color cues**
- Box borders for each service · dim gray
- Service names · bright white
- Version labels (`3.4.1`, `pg14`, `redis 7`) · subtext gray
- Connecting lines and arrowheads · dim gray
- Status legend glyphs · success green / warning yellow / danger red
- "all healthy" overall summary · success green

**Why it works**
- Top-to-bottom flow puts ingress at the top and data layers at the bottom — the way the request actually travels.
- Each service is a small box with two lines (name + version), constraining width so the topology fits horizontally.
- A status summary on a single line saves repeating "healthy" five times — the absence of any non-green dots is the message.

---

## 28 · Stats card grid

**Use when:** dashboard-style summary of several headline numbers. Four cards is the sweet spot — eight is too many to scan.

```
  ┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐
  │                 │                 │                 │                 │
  │     14,231      │    142 / 142    │      82.4%      │     0 / 12      │
  │   total tests   │     passing     │    coverage     │      flaky      │
  │                 │                 │                 │                 │
  │  ▲ +127 today   │   ✓ all green   │     ▲ +1.2%     │    ✓ stable     │
  │                 │                 │                 │                 │
  └─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

**Color cues**
- Card borders · dim gray
- Headline numbers · bright white, large visual weight from spacing
- Card labels · subtext gray
- Trend indicators:
  - `▲ +127 today` movement · success green
  - `✓ all green` · success green
  - `▲ +1.2%` (depends on direction — up is good for coverage) · success green
  - `✓ stable` · success green
- A bad-news card would use `▼` and danger red

**Why it works**
- The big number is the headline; the label below identifies it; the trend below contextualises it. Three lines of decreasing visual weight.
- Equal card widths force you to keep labels short — if "passing" had to be "tests currently passing" you'd notice the layout breaking.
- A row of all-green trend indicators feels reassuring; one yellow or red one stands out instantly.

---

## 29 · Search results with code context

**Use when:** showing matches for a search query across files. Inline context lines beat raw match counts.

```
  RESULTS  ·  "validateToken"   ·   3 files, 7 matches


  src/auth/middleware.ts
        38 │  import { validateToken } from './jwt';
     ▶  42 │  const user = await validateToken(req.headers.auth);
        43 │  if (!user) throw new UnauthorizedError();


  src/auth/jwt.ts
        12 │  // Public API
     ▶  14 │  export async function validateToken(token: string) {
        15 │    return jwt.verify(token, SECRET);


  src/auth/__tests__/jwt.test.ts
         8 │  import { validateToken } from '../jwt';
     ▶  21 │    await expect(validateToken('expired'))
        22 │      .rejects.toThrow(TokenExpiredError);
```

**Color cues**
- File path headers · accent (cyan)
- Line numbers · subtext gray
- `│` separator · dim gray
- `▶` arrow on matched line · accent (yellow)
- The matched substring `validateToken` itself · highlighted (warning yellow background, or bold yellow)
- Context lines around the match · default body text

**Why it works**
- One line of context above and below converts a match from a coordinate ("line 42") into a human-readable claim ("here's where it's used").
- The `▶` arrow plus the highlighted substring give two ways to spot the match.
- File paths as headers separate match groups visually without needing dividers.

---

## 30 · Multi-step wizard

**Use when:** guiding a user through a multi-step process, or reporting progress on one. Combines a static stepper with the active step's detail.

```
   ●━━━━━━●━━━━━━●━━━━━━○━━━━━━○
   plan   apply  verify deploy notify

   ✓      ✓      ◐      ·      ·
   done   done   active  next    


   STEP 3 OF 5  ·  verify

   running 142 integration tests against staging
   ████████████░░░░░░░░  62%   ETA 1m 24s
```

**Color cues**
- Done step nodes (`●`) and connecting bars (`━━━`) · success green
- Active step node and bar leading to it · warning yellow
- Pending step nodes (`○`) and bars · dim gray
- `✓` checkmarks under done steps · success green
- `◐` under active step · warning yellow
- `·` placeholders under pending steps · dim gray
- Active step detail block headline · bright white
- Progress bar · warning yellow filled, dim gray empty
- "ETA" · subtext gray

**Why it works**
- The stepper visualisation has *two* rows — the connector graph above, the status row below — so you can read either to understand state.
- "STEP 3 OF 5" is redundant with the visual stepper, but explicit numbers help screen readers and quick scans.
- Showing only the *active* step's details keeps the wizard focused; the others are just dots until you get to them.

---

## 31 · JSON tree viewer

**Use when:** showing structured data like API responses. The collapsible-tree style scales to large objects without flooding the screen.

```
  RESPONSE  ·  GET /api/users/42


  {
    ▾ user
        id  ······  42                    number
        name  ····  "Maya Rodriguez"      string
      ▾ roles
          [0]  ··  "admin"                string
          [1]  ··  "editor"               string
      ▾ profile
          email  ·  "maya@example.com"    string
          avatar ·  null                  null
      ▸ permissions  (12 items)
    ▸ metadata  (4 keys)
    ▾ links
        self  ····  "/api/users/42"        string
        posts  ···  "/api/users/42/posts"  string
  }
```

**Color cues**
- Braces `{ }` · default body text
- Keys (`user`, `id`, `name`) · accent (cyan)
- `▾` expanded toggle · subtext gray
- `▸` collapsed toggle · subtext gray
- Dot leaders `····` · dim gray
- String values (in quotes) · success green
- Number values · accent (yellow)
- `null` value · danger red
- Type annotations on the right (`number`, `string`, `null`) · subtext gray
- Collapsed-section counts `(12 items)` · subtext gray

**Why it works**
- Triangle toggles `▾ ▸` show what's expanded vs collapsed — same metaphor as every file explorer ever.
- Dot leaders align values into a visual column without drawing one — a much lighter touch than a vertical bar.
- Type annotations on the right turn the viewer into a schema — you can read structure from a glance even before you read values.

---

## 32 · Leaderboard

**Use when:** ranking contributors, services, or anything else by a metric. Friendlier than a sorted table because the scale is implicit in the bar lengths.

```
  ★  TOP CONTRIBUTORS  ·  this sprint


   1   chazz       ████████████████████   42 commits   +3,891 −1,247
   2   sam         █████████████          27 commits   +2,103 −  892
   3   ana         ███████                15 commits   +1,247 −  431
   4   kim         ████                    8 commits   +  587 −  201
   5   bot         ██                      4 commits   +  124 −   18
```

**Color cues**
- `★` and "TOP CONTRIBUTORS" header · accent (yellow)
- Rank numbers (`1` through `5`) · subtext gray; first place may be highlighted
- Names · bright white
- Bars: top three · success green; below · subtext gray (or all the same colour for less drama)
- Commit counts · default body text
- `+` additions · success green
- `−` deletions · danger red

**Why it works**
- The longest bar establishes the scale; everything else reads as a fraction of the leader.
- Multiple metrics per row (commits + add/delete) without requiring a header row, because the format is visually obvious.
- Ranking by visual length means even readers who don't read the numbers see the order.

---

## 33 · Command reference

**Use when:** showing help text, command listings, or option reference. Most CLI help output is bad — this layout fixes the common problems.

```
  CLAUDE CODE   ·   command reference


  USAGE
    claude-code <command> [options]


  COMMANDS

    plan          ·  generate a task plan
                     --depth <n>      detail level (1-3)
                     --output <file>  save to file

    exec          ·  execute a plan
                     --dry-run        preview only
                     --watch          re-run on file changes

    review        ·  request code review
                     --files <glob>   limit scope
                     --severity <s>   minimum severity

    audit         ·  security and quality audit
                     --fix            auto-fix where safe


  EXAMPLES

    claude-code plan "migrate auth to oauth"
    claude-code exec plan.md --dry-run
    claude-code review --files "src/api/**"


  FLAGS
    -v, --verbose     extra output
    -q, --quiet       suppress non-essential output
    -h, --help        show this help
```

**Color cues**
- Section headers (`USAGE`, `COMMANDS`, `EXAMPLES`, `FLAGS`) · subtext gray, slightly emphasised
- Command names (`plan`, `exec`, etc.) · bright white
- Command summaries · default body text
- Option flags (`--depth`, `--dry-run`) · accent (cyan)
- Option descriptions · subtext gray
- Examples · default body text in monospace

**Why it works**
- Command name and summary live on the same line; options indent below — the eye finds the command first, then drills into options.
- Examples come immediately after commands, not at the bottom of a man page — a developer just wants to see one working command.
- Aligned columns within each command keep the help readable at any width.

---

## 34 · Selection prompt

**Use when:** mocking up an interactive prompt where the user picks from a list. Useful for documenting CLI flows even if your real prompt uses a TUI library.

```
  SELECT FILES TO INCLUDE


    ▸  [✓]  src/auth/login.ts
       [✓]  src/auth/session.ts
       [ ]  src/auth/legacy.ts
       [✓]  src/auth/middleware.ts
       [ ]  src/auth/deprecated.ts


    3 of 5 selected


    space  toggle      ↵  confirm      esc  cancel
```

**Color cues**
- Prompt headline · bright white
- `▸` cursor on the focused row · accent (cyan)
- `[✓]` selected boxes · success green
- `[ ]` unselected boxes · dim gray
- File names on selected rows · default; on unselected rows · subtext gray
- "3 of 5 selected" status · subtext gray
- Key hints at the bottom (`space`, `↵`, `esc`) · accent; their labels · subtext gray

**Why it works**
- The cursor `▸` is a separate column from the checkbox, so you can be focused on a row that isn't selected (or vice versa) without ambiguity.
- Unselected rows fade slightly so selected rows visually pop — your eye finds the chosen set immediately.
- Key hints at the bottom in a single line act as a permanent micro-legend; readers don't have to remember.

---

## Design principles

A few rules that apply across every template above.

**Color encodes meaning, not novelty.** Pick a scheme and stick to it across all your output:
- Success green · done, healthy, passing, expected
- Warning yellow · active, in progress, medium severity
- Danger red · failed, critical, blocked, received-but-wrong
- Accent orange · high severity, version bumps, suggestions
- Info blue · links, low severity, neutral information
- Dim gray · pending, queued, separators, supporting text
- Bright white · titles and headlines

**Two encodings beat one.** Anywhere status matters, encode it twice — color and glyph, glyph and position, color and bar length. This means the design still reads when color is stripped (logs, screenshots, color-blind users).

**Whitespace and alignment are the design.** Generous blank lines above and below banners; column alignment that creates a visual grid without drawing one; consistent indent depth signaling hierarchy. Terminal output looks "designed" mostly by being generously spaced.

**Severity and bar length should match the message.** In the audit example, criticals are *short* (urgent stubs) and lows *sprawl* (long, ignorable bars) — the inverse of what a default chart library would draw. The eye lands on the dangerous stuff first.

**Reserve heavy ornaments for moments that earn them.** The hero card, the migration banner, the heavy `┏━┓` box around a sprint summary — these all draw attention by being rare. If every output gets a celebration card, no output gets one.

**Light vs dark terminal mode is a tone choice.** Dark feels "alarm" or "operations." Light feels "collaborative" or "review." Match the palette to the emotional register of the output.

**Diagrams beat tables for relationships, tables beat diagrams for lookups.** Use a topology diagram when "what depends on what" is the question; use a comparison matrix when "which one is best at X" is the question. Picking the right form is half the design.

**Code context is worth ten error messages.** A stack trace alone is hieroglyphics. Add three lines of source code with the failing expression highlighted, and now anyone can debug it. The same principle applies to search results, diff views, and review comments.

**Empty states are also a design opportunity.** A blank screen reads as broken. A tiny ASCII frame with a "no issues found" message and a follow-up action turns nothing-to-show into a positive moment.

**Columns are easier than nested objects.** When you have parallel categories — todo/doing/done, before/after, four service-health cards — split the screen into columns. The brain processes columns faster than indented hierarchies.

**Glyphs are vocabulary, not decoration.** Pick a small set (5-10 glyphs total) and use them consistently across all your output. `●` always means "done"; `◐` always means "active"; `▶` always means "you are here". Inconsistency is what makes terminal output feel cluttered.

---

## Glyph vocabulary

A reference of the Unicode characters used across these templates.

**Box drawing — light**
```
─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼
```

**Box drawing — heavy**
```
━ ┃ ┏ ┓ ┗ ┛ ┣ ┫ ┳ ┻ ╋
```

**Box drawing — double**
```
═ ║ ╔ ╗ ╚ ╝ ╠ ╣ ╦ ╩ ╬
```

**Box drawing — rounded**
```
╭ ╮ ╰ ╯
```

**Half blocks and shading**
```
█ ▀ ▄ ▌ ▐    ░ ▒ ▓
```

**Sparkline blocks** *(low to high)*
```
▁ ▂ ▃ ▄ ▅ ▆ ▇ █
```

**Status — done / active / pending**
```
●  ◐  ○         filled / half / empty disc
✓  ✗  ⊘         check / cross / no-entry
[✓] [◐] [ ]     bracketed checkboxes
◆  ◇  ▣         filled diamond / hollow diamond / boxed item
```

**Severity and alerts**
```
ⓘ  ⚠  ✗  ✓     info / warning / error / success
▌              left-edge accent (severity bar)
★  ☆           filled / hollow star (rating)
```

**Direction and movement**
```
▲ ▼ ◀ ▶         solid triangles
▴ ▾ ◂ ▸         small triangles (collapse / expand toggles)
↑ ↓ ← →         arrows
↗ ↘ ↙ ↖         diagonal arrows
⟲ ⟳ ↻           cycle / rotation (great for circular dependencies)
═               unchanged / no-op
```

**Markers and accents**
```
▌  ▍  ▎         left-edge bars (severity / focus)
═  ━  ─         rule weights (heavy → light)
·  •            dot separators
⋮  …  ⋯         ellipses (vertical / horizontal)
✦  ✧            sparkles (celebration / decoration)
```

**Tree structure**
```
├─  ─
│
└─  ─
├──▶  └──▶      tree branches with arrowhead
│ *  *─┘        git-graph style commit + merge
```

Each of these can be combined and recombined. The goal is consistent vocabulary across all your output — same glyph means the same thing every time.
