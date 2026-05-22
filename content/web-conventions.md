# Web conventions (platform reference)

Conventions and patterns that are useful background when working on
**any** web project. Generic — doesn't assume anything about a specific
codebase. Project-specific architecture goes in the project's own
`docs/architecture/` directory.

Read this when:

- Onboarding to a web codebase
- Working on web code from a non-web repo (e.g., an iOS / Python repo
  consuming a web-app artifact)
- Cross-referencing web patterns in cross-platform discussions
- **Starting a new web project** — the "Default stack" section below
  is the kit's opinionated default

## Default stack (the kit's opinion)

For a new browser SPA, the kit defaults to this stack unless the
project explicitly opts out and documents the reason in `CLAUDE.md`:

| Layer | Choice | Why |
|---|---|---|
| Build | **Vite 6+** (ESM) | Fast HMR, modern defaults, no config sprawl |
| Framework | **React 18 (JSX)** | Hooks-first, no state-mgmt library by default. Type discipline carried via JSDoc per `craft-rules.md`. |
| Styling | **Tailwind 3+ + PostCSS + autoprefixer** | Utility-first, project palette extension in `tailwind.config.js` |
| Icons | **lucide-react** | Tree-shakable, consistent stroke weight |
| Backend | **Firebase** (Auth + Firestore/RTDB + Storage) | Realtime listeners replace most state-mgmt needs |
| Hosting | **Firebase Hosting** | Same vendor as backend, preview channels for staging |
| E2E tests | **Playwright** (chromium-only, headless gate, headed `:watch`) | Fast inner loop, single-browser keeps the matrix small |
| Module type | **ESM** (`"type": "module"`) | Modern default, plays well with Vite |
| Package manager | **npm** + `package-lock.json` | Default; pnpm/yarn fine if documented |

**State management.** No Redux / Zustand / Jotai by default. React
hooks + Firebase realtime listeners cover the common cases. Reach for
a state library only when you've measured a real problem the existing
tools can't solve.

**Language: JSX with JSDoc type discipline.** The kit is type-strict
everywhere — see `craft-rules.md` → Type strictness — but file
extensions stay `.jsx` / `.js`. Types are declared via **JSDoc**
annotations: `@param`, `@returns`, `@typedef`, `@type`. A
`tsconfig.json` at the project root with `"checkJs": true, "strict":
true, "noEmit": true, "allowJs": true` gives full TypeScript-grade
IDE type checking on the JSDoc-typed JS without changing the file
extension or adding a compile step. TypeScript itself (`.ts` /
`.tsx`) is welcome on a per-project basis — document the choice in
`CLAUDE.md`.

**Deviations are fine, but documented.** If a project picks Next.js
for SSR, Astro for content sites, Svelte instead of React, or
Cloudflare Workers instead of Firebase Functions, that's a real
choice — document the deviation and the reason in `CLAUDE.md`. The
default exists to remove a decision; it doesn't override actual
project requirements.

## Top-level shape (typical Vite + React SPA)

```
my-app/
  index.html                       # Vite entry; <div id="root"></div>
  vite.config.js                   # build config (plugins, server port)
  tailwind.config.js               # Tailwind + project palette extension
  postcss.config.js                # PostCSS pipeline (Tailwind + autoprefixer)
  tsconfig.json                    # IDE-only: checkJs + strict for JSDoc validation
  package.json                     # ESM ("type": "module")
  firebase.json                    # hosting config (cache headers, rewrites)
  .firebaserc                      # Firebase project alias
  .env / .env.example              # VITE_* env vars (build-time inlined)
  playwright.config.js             # E2E config
  e2e/tests/                       # Playwright specs
  public/                          # static assets served as-is
  dist/                            # build output (gitignored)
  src/
    main.jsx                       # React root + global providers
    App.jsx                        # route shell
    index.css                      # Tailwind directives + global styles
    theme.js                       # design tokens (mirror tailwind palette)
    components/
      ui/                          # primitives (Button, Card, Pill, etc.) — JSDoc-typed Props
      <feature-area>/              # feature-grouped components — JSDoc-typed Props
    pages/                         # route-level components (one per route)
    hooks/                         # one hook per concern (useX.{js,jsx}); JSDoc-typed return
    firebase/                      # client-side Firebase modules
      config.js                    # init + exports
      paths.js                     # canonical collection / RTDB path strings
      auth.js                      # auth helpers
      <collection>.js              # one file per top-level collection
      writeHelpers.js              # shared write utilities
    models/                        # plain JS classes per domain entity (JSDoc-typed)
    data/                          # static / seed data
    lib/                           # generic helpers (JSDoc-typed)
```

## App entry point

`src/main.jsx` mounts the React tree and wraps it in any global
providers (auth context, realtime-pref provider, theme provider, etc.):

```jsx
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App.jsx";
import "./index.css";

const rootElement = document.getElementById("root");
if (!rootElement) throw new Error("Root element #root not found");

ReactDOM.createRoot(rootElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
```

`StrictMode` stays on in development — it surfaces side-effect bugs
in mount/unmount. The explicit null-check on `getElementById` is the
type-strict pattern: we throw on a real failure rather than ignoring
the `HTMLElement | null` return — and `tsconfig.json` with `checkJs`
flags this in the IDE if it's missing.

## Architecture — separation of concerns

The kit default lays out a strict layer model. Each `src/` directory
owns one layer; cross-layer calls only go in the documented direction.
Views render. Hooks compute. `firebase/` and `models/` and `lib/` are
leaves.

| Layer | Directory | What lives here | Calls |
|---|---|---|---|
| Data access | `src/firebase/` | Firebase SDK calls, path constants, query helpers | (leaf) |
| Domain types | `src/models/` | Plain JS classes per entity; JSDoc-declared property types | (leaf) |
| Generic utils | `src/lib/` | Pure utilities with JSDoc types (no Firebase, no React) | (leaf) |
| Business logic | `src/hooks/` | One hook per concern; subscribes, transforms, exposes derived state. JSDoc `@typedef`/`@returns` declares the shape. | `firebase/`, `models/`, `lib/` |
| Render primitives | `src/components/ui/` | Stateless UI primitives (Button, Card, Pill); JSDoc-typed Props for each | (leaf — props only) |
| Feature views | `src/components/<area>/` | Feature-grouped UI; render + dispatch intents | `hooks/` (read-only), `components/ui/` |
| Pages | `src/pages/` | Route components; compose hooks + feature views | `hooks/`, `components/` |

Rules that fall out:

- **Components don't call Firebase directly.** They call hooks; hooks
  call `firebase/` modules.
- **Hooks don't render.** They return state + actions.
- **Pages compose, they don't compute.** A page file reads like a
  layout — which hooks supply what, which components render what.
  Multi-step business logic in a page body is a smell; push it down
  into a hook.
- **`models/`, `firebase/`, `lib/` are leaves.** They don't import
  from each other or from React. This keeps them testable in
  isolation and prevents cyclic dependency creep.
- **The layer you change for a logic bug is not the layer you change
  for a UI tweak.** If a single edit spans multiple layers regularly,
  the boundary is in the wrong place — fix the boundary, not the
  feature.

If a feature needs a new layer (a non-Firebase backend integration, a
heavy compute pipeline, a worker), document the new layer in
`CLAUDE.md` with the same shape as the table above.

## Routing

The kit default is **React Router v6+** from the first commit. Even
a single-page MVP gets a router — the conditional-rendering view-state
pattern (`const [view, setView] = useState("landing")`) does not
survive growing past two screens. Set up routing on day one.

Mount the router at `main.jsx`:

```jsx
// src/main.jsx
import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import App from "./App.jsx";
import "./index.css";

const rootElement = document.getElementById("root");
if (!rootElement) throw new Error("Root element #root not found");

ReactDOM.createRoot(rootElement).render(
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>
);
```

Define routes in `App.jsx` (or `src/routes.jsx` once the tree grows):

```jsx
// src/App.jsx
import { Routes, Route, Navigate } from "react-router-dom";
import LandingPage from "./pages/LandingPage.jsx";
import LoginPage from "./pages/LoginPage.jsx";
import DashboardPage from "./pages/DashboardPage.jsx";
import FullPageSpinner from "./components/ui/FullPageSpinner.jsx";
import { useAuth } from "./hooks/useAuth";

/**
 * @returns {JSX.Element}
 */
export default function App() {
  const { user, loading } = useAuth();
  if (loading) return <FullPageSpinner />;
  return (
    <Routes>
      <Route path="/" element={<LandingPage />} />
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/dashboard/*"
        element={user ? <DashboardPage /> : <Navigate to="/login" replace />}
      />
    </Routes>
  );
}
```

Conventions:

- **`pages/` is the route-component layer.** One file per top-level
  route. Pages can compose nested routes for sub-sections (e.g., a
  dashboard with `/dashboard/vehicles` and `/dashboard/inspections`).
- **Route definitions live in one place** — `App.jsx` for smaller
  projects, `src/routes.jsx` once the route tree grows past ~15
  routes.
- **`useNavigate()` for programmatic navigation, `<Link>` for
  declarative links.** Don't `window.location.href = …` (it's a full
  reload and breaks the SPA contract).
- **Auth-gated routes use `<Navigate>` redirects, not conditional
  view-state.** Combine with `?redirectTo=…` for post-login return.
- **Deep-link aware.** Every screen the user can reach is bound to a
  URL. Cold-start to that URL lands on that screen, not on the home
  screen.

For SSR / file-based routing (Next.js, Remix), the routing rules
above are baked into the framework — follow its idioms.

## Config files and what's in them

| File | Purpose | Tracked? |
|---|---|---|
| `package.json` | Dependencies, scripts, ESM marker | ✅ |
| `package-lock.json` | Exact dependency tree (lockfile) | ✅ |
| `vite.config.js` | Vite build + dev server config | ✅ |
| `tailwind.config.js` | Tailwind palette + content globs | ✅ |
| `postcss.config.js` | PostCSS plugin pipeline | ✅ |
| `playwright.config.js` | E2E config (browsers, base URL, env loader) | ✅ |
| `firebase.json` | Hosting + cache headers + rewrites | ✅ |
| `.firebaserc` | Firebase project alias | ✅ |
| `.env.example` | Documented env-var template | ✅ |
| `.env` | Real env values (per-developer) | ❌ gitignore |
| `dist/` | Build output | ❌ gitignore |
| `node_modules/` | Installed deps | ❌ gitignore |
| `test-results/` | Playwright artifacts | ❌ gitignore |
| `.firebase/` | Firebase CLI cache | ❌ gitignore |
| `.DS_Store` | macOS finder noise | ❌ gitignore |

## Versioning

For a private SPA (no npm publish), the `package.json` `version` field
is informational. The deploy tag on `main` is the authoritative
version record (per `release-rules.md`):

- Semver `vX.Y.Z` annotated tags
- `package.json` `version` may be bumped alongside the tag for human
  readability, but the tag is the source of truth

## Scripts (typical `package.json`)

```json
{
  "scripts": {
    "predev": "kill -9 $(lsof -ti:5173 2>/dev/null) 2>/dev/null; exit 0",
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "deploy": "npm run build && firebase deploy --only hosting:<site>",
    "deploy:preview": "npm run build && firebase hosting:channel:deploy preview --only <site> --expires 7d",
    "test:e2e": "playwright test",
    "test:e2e:watch": "PW_SLOWMO=700 playwright test --headed"
  }
}
```

The `predev` port-kill is a kit-default nicety: re-running `npm run
dev` while the previous one still holds 5173 hangs the new boot
otherwise.

## State / data ownership

- **`useState`** — view-local mutable state, ephemeral.
- **`useReducer`** — view-local state with multiple correlated fields.
- **Custom hooks (`useX`)** — per-concern data layer; encapsulate
  Firebase listeners, fetch logic, derived state.
- **React Context** — implicit injection from an ancestor (e.g., a
  `RealtimePrefProvider` for a global setting). Use sparingly.
- **No state-management library by default.** If three or more
  unrelated views share the same mutable state and prop drilling /
  context starts to hurt, *then* consider a library — but document
  the decision.

The Firebase realtime listener pattern replaces most of what a state
library would otherwise hold. A `useInspections()` hook subscribes,
returns the live list, and any view that calls it gets reactive
updates for free.

## Firebase patterns (when used)

- **`src/firebase/config.js`** initializes the app once and exports
  `auth`, `db`, `rtdb`, `storage` for reuse.
- **`src/firebase/paths.js`** holds canonical path strings (RTDB or
  Firestore). **Never hardcode a path inline in a hook or component**
  — go through `paths.js`. This is the schema-discipline rule from
  `task-rules.md` applied at the file level.
- **One module per collection** under `src/firebase/` (e.g.
  `inspections.js`, `vehicles.js`). Each module exports CRUD + query
  helpers for that collection.
- **`src/firebase/writeHelpers.js`** holds shared write utilities
  (timestamp stamping, soft-delete helpers, etc.) so writes are
  consistent across collections.
- **Cross-platform schema.** If an iOS app or another client mirrors
  the same Firebase schema, treat field names as a *contract*. The
  rule from `task-rules.md` ("never invent or rename a field")
  applies. `paths.js` is among the most-protected files in the repo.

## Styling — Tailwind + design tokens

- **`tailwind.config.js`** owns the project palette under
  `theme.extend.colors.<project>` (e.g. `colors.vsi.navy`).
- **`src/theme.js`** mirrors the same color values for inline-styled
  use cases (gradients, dynamic borders, status-pill backgrounds)
  where utility classes don't compose cleanly. Keep it in sync with
  `tailwind.config.js` — drift here means the inline gradient
  silently disagrees with the bordering utility-class tile.
- **Status / tone palettes.** Cross-cutting status colors (pass /
  fail / warn / pending) belong in `theme.js` as a single source of
  truth, not scattered across components.

## Hosting and cache discipline

`firebase.json` should set cache-control headers explicitly:

- **Hashed bundle assets** (`.js`, `.css`, `.woff2`, images, fonts) →
  `public, max-age=31536000, immutable`. Vite emits hashed filenames,
  so long cache is safe.
- **`/index.html`** → `no-cache, no-store, must-revalidate`. The
  HTML must not be cached or users will load a stale shell that
  references gone bundles after a deploy.

Without these, default Firebase headers will cache `index.html` for
hours and break deploys for users with warm caches.

## Testing — Playwright defaults

- **`e2e/tests/`** holds specs. One spec file per feature or task.
- **`fullyParallel: false`, `workers: 1`** by default — single-threaded
  is slower but eliminates a class of flake from shared state. Bump
  parallelism only when the suite outgrows it.
- **`reuseExistingServer: true`** so a dev server already on 5173 is
  reused instead of fighting for the port.
- **Two scripts: `test:e2e` (headless gate) and `test:e2e:watch`
  (headed, slow-motion via `PW_SLOWMO`).** Headless is the contract
  for CI and agents; headed is for humans iterating.
- **Inline `.env` parser.** A small inline `.env` parser at the top
  of `playwright.config.js` keeps the dotenv dep out of the runtime
  (test config doesn't need to ship). Pattern: read `.env`, split on
  `=`, populate `process.env` if not already set.

## Common web gotchas

- **`predev` port-kill is mandatory.** Vite hangs silently if the port
  is held by an orphaned dev server.
- **Browser-side env vars.** Only `VITE_*`-prefixed vars are inlined
  into the build. Anything else is server-only and won't reach the
  browser.
- **Hot reload vs production build divergence.** Code that works in
  dev may fail in `vite build` — tree shaking, dead-code elimination,
  dynamic import resolution differ. Run `npm run build && npm run
  preview` before assuming a feature is done.
- **Firebase Auth state on hard reload.** `onAuthStateChanged` fires
  asynchronously after mount; don't gate the entire UI on `auth`
  being non-null synchronously, or you'll flash a logged-out shell
  on every reload.
- **CORS.** Direct browser → third-party API calls hit CORS; route
  through Firebase Functions or a proxy when the third party doesn't
  CORS-allow your origin.
- **Hosted index.html caching.** Always set `no-cache` headers for
  `/index.html` in `firebase.json` — see above.
- **Realtime listeners cleanup.** Every `onSnapshot` / `on('value')`
  needs an unsubscribe in the hook's `useEffect` cleanup, or you
  leak listeners across navigations.

## Backend pairing — Node service (when applicable)

When a web project pairs with a Node backend service (or has an
internal Node tool / script), the kit's secondary default stack:

| Layer | Choice |
|---|---|
| Runtime | **Node ≥20**, ESM |
| Language | **TypeScript strict** — `target: ES2022`, `module: NodeNext`, `noUncheckedIndexedAccess` |
| Dev | **`tsx watch server/index.ts`** |
| Build | **`tsc`** (no bundler) |
| Server | **Express 4** |
| Local DB | **better-sqlite3** (synchronous, fast, no ORM) |
| Env | **dotenv** |

This is the `claude-messages` / Galt shape. Use it when you need a
local service, a CLI tool with state, or a thin AI-integration layer
behind a UI. For larger backends (multi-service, queue-driven,
cross-region), document the chosen stack in `CLAUDE.md`.
