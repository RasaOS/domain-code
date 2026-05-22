# Craft Rules

Build it right the first time. These rules apply to **every** task,
every project, every language. They're the discipline layer that sits
between `task-rules.md` (process) and the platform extensions (stack).
**Read this file before you write code.**

> **Why this file exists.** Cutting corners early compounds. A
> "we'll fix it later" shipped on Tuesday is still in `main` six
> months later, blocking the next refactor. The shortest path is to
> build it right the first time — not to build a minimum and patch it
> indefinitely. Speed comes from clarity, not from skipping steps.

## Build it right the first time

- **No "we'll fix it later" code.** Later is a lie. If a hack ships,
  it stays. The cost of doing it right now is small; the cost of
  shipping a half-fix and revisiting it is large.
- **MVP / POC / throwaway are not licenses to ship sloppy code.**
  Ship less, not worse. A small, clean feature is more valuable than
  a sprawling, fragile one — and easier to delete if it doesn't pan
  out.
- **Workarounds are allowed; sloppy workarounds aren't.** If a
  constraint forces a workaround, write the workaround correctly and
  document the constraint in a comment with a one-line *why*. Future-
  you needs to know whether the workaround is still load-bearing.
- **No half-finished implementations.** If a feature can't be
  completed in scope, don't ship a partial path that "works for the
  happy case." Either finish it or back it out and file a follow-up.

## Follow the pattern (don't recreate the wheel)

If the codebase already does something one way, do it that way
everywhere. Consistency beats cleverness. The reader learns the
pattern once and it pays off across every file they touch after.

- **Look for the pattern first.** Before adding a feature, scan how
  similar features are done elsewhere — same shape, same layering,
  same naming, same error-surfacing. If a precedent exists, you
  follow it.
- **Follow it even if you'd have done it differently.** Disagreeing
  with a pattern is fine; *silently forking* it is not. If a pattern
  is genuinely wrong, surface it and migrate everywhere — don't add
  one variant and let divergence rot. One way, every time, every
  place.
- **No pattern? Set the precedent deliberately.** Whoever writes the
  first instance defines the shape — the next person will copy it.
  Pick the shape thoughtfully, and document the decision in
  `CLAUDE.md` when you know you're setting precedent.
- **Cascade of fallbacks.** Match the file you're in → match the
  codebase → fall back to the kit conventions (`web-conventions.md`,
  `ios-conventions.md`) when no project-local pattern exists. The
  kit defaults are the floor, not the ceiling.

The cost of consistency is small. The cost of N inconsistent
implementations of the same idea — each with its own bugs, edge
cases, and context-switching tax — accumulates silently.

## Modular by default

- **One file = one concern.** If a file holds two unrelated things,
  split before you extend.
- **One function = one job.** If you're describing it as "X *and* Y,"
  split it. If it takes a boolean flag that switches between two
  paths, those are usually two functions.
- **Clear directory shape.** Components, hooks, helpers, models,
  services — each lives in its own directory under a stable structure
  (see the platform conventions file for the exact layout per stack).
- **The smallest unit that's still self-contained.** Premature
  splitting is bad; under-splitting is worse — the seams become
  invisible and the file grows past comprehension.

## Reusable, dynamic, composable

- **No copy-paste.** If two callers need the same logic, lift it. If
  three callers need the same logic, you waited too long. Duplicated
  business logic drifts in three different directions on three
  different schedules.
- **No magic numbers, magic strings, or hardcoded paths in business
  logic.** Constants live at the top of their module or in a shared
  `constants.{js,ts,swift,py}` next door. The point isn't ceremony —
  it's that the same value appears once and changes in one place.
- **Configuration over conditionals.** If `if (env === 'prod')` shows
  up twice, refactor to a config object the call sites read. Branching
  on environment-or-flag inline is a smell that compounds.
- **Composition over inheritance, props over globals.** Components and
  helpers take what they need as arguments; they don't reach across
  the codebase for state. The signature is the contract.
- **Schema strings go through one source of truth.** Database paths,
  collection names, RTDB keys, query string keys — all behind a
  single `paths.js` / `keys.ts` / equivalent. Inline string literals
  for these are a refactoring tripwire.

## Architecture from day one

The architectural shape of the project gets decided before the second
feature ships, not as a refactor later. Cleanup-as-you-grow doesn't
work — by the time the seams hurt, they're load-bearing, and every
new feature stacks more weight on the wrong foundation.

- **Separate business logic from UI views.** Views render. Logic
  lives elsewhere. A view file should read end-to-end as "what's on
  screen and what triggers what" — not "what's on screen, plus the
  seven branches of business rules that decide what's on screen."
- **The layer you change for a logic bug is not the layer you change
  for a UI tweak.** If those are the same file, the architecture is
  wrong.
- **Web (kit default):** hooks own data + logic; components render;
  pages compose hooks + components. See `web-conventions.md` →
  Architecture for the layer model.
- **iOS (kit default):** ViewModels (`ObservableObject` /
  `@Observable`) own logic; SwiftUI views render and dispatch
  intents. See `ios-conventions.md` → Architecture for the pattern.
- **Decide the architecture before file three.** Project-specific
  layer choices (which directory holds what, who calls whom) get
  documented in `CLAUDE.md`. The decision lives in code review, not
  in tribal memory.
- **Refactoring into clean layers later is a tax, not a bonus.** It
  costs more than getting it right on day one because every existing
  feature has to be re-routed through the new layer. Pay the cost up
  front when there's nothing yet to migrate.

## Navigation discipline

Set up real navigation from the first commit. The "we'll add a router
later" path costs more than just adding it on day one — it drags
every new feature into a conditional-rendering app router that
doesn't survive a refresh, doesn't deep-link, and can't be shared.

- **One source of truth for navigation state.** The URL (web) or a
  typed path (iOS), not both, not neither.
- **The view-state anti-pattern.** Top-level navigation handled by
  `useState("landing")` / `setView("dashboard")` is the failure mode
  this rule rules out. It looks fine for two screens and breaks the
  moment the user reloads, deep-links, or hits the back button.
- **Web (kit default):** React Router from the first commit. Routes
  are first-class. `pages/` are route components. URL is canonical.
  See `web-conventions.md` → Routing.
- **iOS (kit default):** `NavigationStack` with a typed path
  (`NavigationPath` or enum-driven). One navigator per main flow.
  Don't sprinkle `NavigationLink` ad-hoc — it makes deep linking and
  state restoration impossible. See `ios-conventions.md` →
  Navigation.
- **Deep-link aware from day one.** Every top-level destination is
  reachable by a URL (web) or a path value (iOS) — not only by a
  nested click chain from the home screen. Restoring state on
  cold-start should land where the user left off, not at the root.

## Naming

Identifiers are human-readable. Name a thing what it *is*, as
concisely as possible. The reader shouldn't need to look up an
abbreviation or trace history to know what they're looking at.

### Casing (kit-wide, all languages)

| Kind | Casing | Examples |
|---|---|---|
| Classes / types / structs / enums / protocols | **PascalCase** | `UserAccount`, `InspectionStore`, `VehicleListViewModel`, `AuthProvider` |
| React / SwiftUI components | **PascalCase** (they're type-shaped) | `<UserCard />`, `struct VehicleList: View` |
| Variables / properties / fields | **camelCase** | `userAccount`, `currentUser`, `isLoading` |
| Functions / methods | **camelCase** | `getUserById`, `loadInspections`, `renderHeader` |
| React hooks | **camelCase**, prefixed `use…` | `useAuth`, `useInspections` |
| Constants (when distinct from runtime values) | **UPPER_SNAKE_CASE** | `MAX_RETRIES`, `DEFAULT_TIMEOUT_MS` |

**This is kit-wide and overrides language idioms where they conflict.**
Python in this kit uses **camelCase** for functions and variables, not
PEP 8 `snake_case`. The reason is consistency across the codebase, the
team, and the kit — the cost of context-switching between languages
outweighs the cost of deviating from a per-language style guide.

### Style rules

- **Describe the thing, not the implementation detail.** `getUserById`
  not `runUserQuery`. `disabled` not `notEnabled`.
- **No abbreviations beyond domain-standard ones.** `userManager` not
  `usrMgr`. `getDocument` not `getDoc` — unless "doc" *is* the domain
  term (e.g. Firestore).
- **Booleans read as predicates.** `isLoading`, `hasAccess`, `canEdit`.
  Not `loading`, `access`, `edit`.
- **Concise but unambiguous.** `inspection` is better than `i` even in
  a tight loop. `currentUser` is better than `current` if there's any
  chance of ambiguity in scope.
- **Functions read as verbs, things read as nouns.** `loadInspections()`
  / `inspections`. `getCurrentUser()` / `currentUser`. The asymmetry is
  intentional — at a call site, `inspections.length` and
  `loadInspections()` should be unambiguous about which one is the
  data and which one is the action.

## Type strictness

The kit declares types everywhere, regardless of whether the language
requires them. If the language carries types natively, use them. If
it doesn't, declare them in comments. The signature is the contract
— if the contract isn't written down, it's not a contract.

### Per-language conventions

| Language | Mechanism |
|---|---|
| **JavaScript / JSX** | The kit's web default. Declare types via **JSDoc** — `@param`, `@returns`, `@typedef`, `@type`. A `tsconfig.json` with `"checkJs": true, "strict": true, "noEmit": true, "allowJs": true` validates them in the IDE without changing the file extension or adding a build step. |
| **TypeScript** | When a project specifically chooses TS over JSX. `tsconfig.json` `strict: true`. No `any` / `unknown` escape hatches in source code. |
| **Python** | The language doesn't enforce types; the kit does. Type hints on every function (parameters and return) and on module-level variables and class fields. `mypy --strict` (or equivalent) is the gate when a project has one. |
| **Swift** | Explicit annotations on function returns and stored properties even where inference works. Inline `let x = …` is fine for obvious literals; ambiguous expressions get an annotation. |
| **Go / Rust / Java / Kotlin / C#** | The language already enforces this; the rule is a no-op. |

### Rules that apply regardless of mechanism

- **Always declare function parameter and return types.** The
  signature is the part the reader sees first; missing types turn
  the API into guesswork.
- **Declare component / view prop types.** React props, SwiftUI view
  inputs — typed via JSDoc / TS / Swift, never implicit.
- **No `any` / `unknown` / `Object` / dynamic-type escape hatches.**
  If a value is genuinely dynamic (parsed JSON, plugin payloads),
  declare it precisely — a discriminated union, a documented
  `Record<string, unknown>` — and validate at the boundary so the
  internal code sees a precise type.
- **Variables get types when the inferred type isn't obvious.**
  `const count = 0` is fine. `const result = await fetchSomething()`
  — declare the resolved shape if it isn't screaming obvious.

### JSDoc patterns (web kit default)

For component props:

```jsx
/**
 * @typedef {Object} LandingPageProps
 * @property {() => void} onLogin
 */

/**
 * @param {LandingPageProps} props
 * @returns {JSX.Element}
 */
export default function LandingPage({ onLogin }) {
  return <button onClick={onLogin}>Sign in</button>;
}
```

For hooks:

```jsx
/**
 * @typedef {Object} AuthState
 * @property {import("firebase/auth").User|null} user
 * @property {boolean} loading
 */

/**
 * @returns {AuthState}
 */
export function useAuth() {
  // …
}
```

For type-only utility:

```js
/** @type {readonly string[]} */
const STATES = ["pending", "active", "complete"];
```

A `tsconfig.json` at the project root with `"checkJs": true, "strict":
true, "noEmit": true, "allowJs": true` gives full IDE type-checking on
JSDoc-typed JS / JSX without changing the file extension or adding a
compile step.

### Python type-hint patterns

```python
from typing import Optional

def getUserById(userId: str) -> Optional[User]:
    """Look up a user by their canonical ID."""
    ...

USERS_PATH: str = "users"
```

Type hints carry the contract. Even when Python doesn't enforce them
at runtime, they're part of how the codebase communicates with itself
(and with `mypy`).

## Comments

Comments exist to help the next person (and future-you) understand
the code, the contract, or the intent. Write them where they add
value. The kit is not anti-comment — it's anti-noise.

### Three reasons to comment

1. **Types** — when the language doesn't carry types natively,
   declare them in comments. JSDoc on JS / JSX, docstring type
   hints on Python. These are part of the function signature, not
   commentary. Required by the Type strictness rule above. JSDoc
   blocks are *not* what the rest of this section means by
   "comment noise" — they're contract.
2. **Why** — hidden constraints, non-obvious invariants,
   workarounds for specific bugs, behavior that would surprise a
   reader.
3. **Future-dev orientation** — when a non-trivial section would
   be confusing without context, leave a sentence orienting the
   next person. Not "here's what this does" if the code already
   says it — but "here's why this section exists and what to be
   careful of."

### What still doesn't go in comments

- **What well-named code already says.** `// increment counter`
  above `count++` is noise.
- **The current task, fix, or callers.** `// added for TASK-042`
  or `// used by the dashboard` rots the moment something moves —
  that context belongs in the PR description.
- **Decorative banners and section headers.** ASCII separators,
  `// === HOOKS ===` blocks, sectioning art — visual noise, not
  information.
- **Filler.** A comment on every line is harder to read than a
  function with none. Aim for comments where the next person will
  actually thank you.

### When in doubt

Ask: *would this help the next person?* If yes, write it. If it
fills space or comes from a habit of "I should comment more," skip
it.

## Error handling

- **Validate at boundaries.** User input, external APIs, file I/O,
  cross-process messages — these need defensive checks. Internal code
  that you control should *trust* its callers and the type system.
- **No swallowed errors.** A `catch` block either handles the error
  meaningfully or re-throws. `catch (e) {}` is a bug, full stop.
- **Don't add error handling for impossible cases.** If a function
  always returns a value, don't `if (response === undefined) {}` at
  every call site. Imagined defensiveness adds noise without adding
  safety.
- **Errors surface; they don't get hidden.** A failed network call,
  a write that didn't land, a validation that didn't pass — the user
  or the log sees it. Silent recovery hides bugs that compound.

## Dead code

- **No commented-out code.** Git remembers; the file shouldn't.
- **No unused imports, vars, or exports.** The linter catches these —
  don't suppress.
- **Removing a feature = removing the code.** Not commenting it out,
  not leaving "in case we need it later" stubs. If the feature comes
  back, git knows where it was.

## Premature abstraction

- **Three similar lines is fine.** Two callers is not a pattern.
  Wait for the third before extracting — by then you'll know the
  shape.
- **Don't design for hypothetical future requirements.** A file with
  seven extension points and one caller is worse than a file with
  one inline path you can read top to bottom.
- **Half-finished abstractions are the worst case.** If you can't
  finish the abstraction in scope, leave the duplication and file a
  follow-up task. A partial extraction with a leaky API is a trap
  for the next person.

## When in doubt

- **Ask before guessing.** One round trip beats an hour of building
  the wrong thing.
