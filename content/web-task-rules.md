# Web task rules (platform extensions)

Platform-specific extensions to `task-rules.md` for web projects. Read
this when working on web code or any task that touches a web frontend.

The universal `task-rules.md` is generic and references "the project's
verification command," "the project's protected files," etc. This file
fills those in for any web project on the kit's default stack
(`web-conventions.md`). **Project-specific values (site name, scheme
flags, env-var names, etc.) still live in `CLAUDE.md`.**

## Scope of "web project" for this file

Any project where the primary deployable is a browser-served bundle:

- React / Next.js / Remix
- Vue / Nuxt
- Vite-based SPAs (the kit default — see `web-conventions.md`)
- Static sites (Astro, Eleventy, etc.)

Backend-only Node projects use a different convention (see the
"Backend pairing" section of `web-conventions.md`).

## Verification gate

Two commands form the gate. The exact script names come from
`CLAUDE.md` per project; the shape is universal:

```sh
# 1. Build (production-equivalent)
npm run build         # vite build under the hood for the kit default

# 2. Verification suite (E2E, headless)
npm run test:e2e      # playwright test, chromium-only, headless
```

Contract:

- **Build** must succeed with **zero new warnings** vs the project's
  baseline. New warnings that weren't there before this task are a
  blocker — fix them or surface them.
- **`test:e2e` is the gate**, not `test:e2e:watch`. Agents and CI run
  the headless variant. The headed variant is for humans iterating.
- **A clean `dist/` build** (no `console.error`, no unhandled promise
  rejections in the smoke-test) — even if no specific test asserts it.
- **Local run check.** `npm run dev` boots cleanly and the implemented
  flow works in a real browser. Type-checking and tests verify code
  correctness, not feature correctness.

If any gate fails and you can't fix it in scope, **stop and write a
blocker note**. Do not skip tests. Do not bypass hooks (`--no-verify`).

## Iteration vs. gate

While working a task:

- Run a single Playwright spec via `--grep` or path filter, not the
  full suite. Re-running the full E2E on every edit wastes minutes.
- Use `npm run test:e2e:watch` (headed, `PW_SLOWMO=700`) when you
  need to *see* what the test sees. Useful for diagnosing flake.

Before opening the PR, run the unfiltered headless gate once to
confirm green.

## Protected files (require explicit permission to modify)

Touching any of these = blocker, not autonomous work:

- **Dependency manifests**: `package.json` (adding/upgrading/removing
  deps), `package-lock.json` / `pnpm-lock.yaml` / `yarn.lock`
- **Build config**: `vite.config.*`, `webpack.*`, `rollup.config.*`,
  `tsconfig*.json`, `babel.config.*`
- **Styling config**: `tailwind.config.*`, `postcss.config.*`
- **Test config**: `playwright.config.*`, `vitest.config.*`,
  `cypress.config.*`, `jest.config.*`
- **Hosting / deploy config**: `firebase.json`, `.firebaserc`,
  `vercel.json`, `netlify.toml`, `wrangler.toml`
- **Security rules**: `firestore.rules`, `database.rules.json`,
  `storage.rules`
- **Environment templates**: `.env.example` (the actual `.env` is
  always gitignored and never edited by an agent)
- **Schema-source-of-truth**: `src/firebase/paths.js` (or equivalent
  per-project canonical-paths file). See `web-conventions.md`.

If a task requires touching one of these, surface it in the task
file's blocker section before editing.

## Firebase schema discipline (when project uses Firebase)

If the project uses Firebase RTDB or Firestore (the kit default):

- **`src/firebase/paths.js`** is the canonical source of all path /
  collection-name strings. **Never hardcode a path inline.** Add it
  to `paths.js` first, reference the constant from the call site.
- **Field names are a cross-platform contract.** If an iOS or
  Android client mirrors the same schema, renaming a field is a
  coordinated migration — never a refactor. Surface as a blocker.
- **Adding a new field** is allowed within scope; renaming or
  removing is not.
- **Security rules changes** (`firestore.rules`,
  `database.rules.json`) require explicit user approval — they're
  the access-control boundary.

## Hosting and deploy

- **Deploys flow through `/release` (or `/web-release` when added)**,
  per `git-flow-rules.md`. Don't run `firebase deploy` directly.
- **Cache headers in `firebase.json` are mandatory** — see
  `web-conventions.md`. Hashed bundle assets get long-cache; the
  HTML shell gets `no-cache`.
- **Preview channels** (`firebase hosting:channel:deploy`) are fine
  for sharing in-progress work. They expire and don't affect
  production hosting. Tag preview deploys in chat with the channel
  URL so the reviewer can check.

## Common web gotchas (verification-gate-relevant)

- **Hot reload vs production build divergence.** Code that works in
  `npm run dev` may break in `vite build` (tree shaking,
  minification, dynamic import resolution). The build gate catches
  most of these — running `npm run preview` after the build catches
  the rest.
- **Browser-side env vars.** Only `VITE_*` / `NEXT_PUBLIC_*`-prefixed
  vars reach the browser. If a feature needs a non-prefixed env var
  in the client, that's a misconfiguration — surface it.
- **Hydration mismatches** in Next.js / Remix — typically caused by
  rendering different content server-side vs client-side. Show up as
  console errors during dev; the gate's "no console errors on
  affected screens" rule catches them.
- **CORS** when calling APIs from the browser — different from
  server-side fetch. Route through a Firebase Function or proxy.
- **Realtime listener leaks.** Every Firebase listener must
  unsubscribe in `useEffect` cleanup. Forgotten unsubs accumulate
  per navigation and silently corrupt state.

## Test infrastructure

The kit default is **Playwright for E2E** (chromium-only, headless
gate, headed `:watch` for iteration — see `web-conventions.md` for
the full config shape).

Other layers a project may use:

- **Unit tests**: Vitest (preferred for Vite projects), Jest
- **Component tests**: Testing Library, Cypress component testing
- **E2E**: Playwright (default), Cypress

`CLAUDE.md` documents which test layer is the verification gate for
the project. Default: E2E is the gate; unit tests are an inner-loop
aid, not a release contract.
