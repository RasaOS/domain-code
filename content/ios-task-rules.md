# iOS task rules (platform extensions)

Platform-specific extensions to `task-rules.md` for iOS projects. Read
this when working on iOS code or any task that touches the iOS app.

The universal `task-rules.md` is generic and references "the project's
verification command," "the project's protected files," etc. This file
fills those in for any iOS project. **Project-specific values (scheme
name, bundle ID, baseline warning count, etc.) still live in `CLAUDE.md`.**

## Verification gate

Headless build (the contract — agents must use this, not Xcode UI):

```sh
xcodebuild \
    -scheme "$SCHEME" \
    -project "$PROJECT" \
    -destination "generic/platform=iOS Simulator" \
    -configuration Debug \
    build CODE_SIGNING_ALLOWED=NO
```

- `$SCHEME` and `$PROJECT` come from `CLAUDE.md`.
- `CODE_SIGNING_ALLOWED=NO` skips signing for build-only verification —
  archives for release use real signing (see `ios-release` skill).
- A clean build = exit code 0, `** BUILD SUCCEEDED **` in output, and
  warning count **at or below** the project's baseline (recorded in
  `CLAUDE.md` or a sibling verification doc).

If your change introduces new warnings vs the baseline, that's a
blocker. Either fix the warning or surface it as a blocker note —
never bump the baseline silently.

## Protected files (require explicit permission to modify)

Touching any of these = blocker, not autonomous work:

- **Project files**: `*.xcodeproj/`, `*.xcworkspace/` and everything inside
- **Dependency manifests**: `Package.swift`, `Package.resolved`, `Podfile`,
  `Podfile.lock`, `Cartfile`, `Cartfile.resolved`
- **Build settings**: `*.xcconfig` files
- **Capabilities / signing**: `*.entitlements`, signing identities
- **Info dictionaries**: `Info.plist` (project's main one)
- **Cloud config**: `GoogleService-Info.plist`, any other vendor config plist
- **Assets**: `Assets.xcassets/Contents.json` at the catalog level (per-asset
  contents files are usually safe to edit; the catalog manifest is gated)

If a task requires touching one of these, surface it in the task file's
blocker section before editing.

## Realm schema migrations (when project uses Realm)

If the project uses Realm Swift (`DB/Models/` or wherever the canonical
schema lives — see `CLAUDE.md`):

- **Realm classes are the schema.** Treat property names as a
  cross-platform contract. Renaming a `@Persisted` property is a
  coordinated migration across iOS, web, future Android — never a
  refactor.
- **Adding a Realm property** requires a Realm schema version bump
  and migration block in the configuration. Doing this autonomously
  is **out of scope** — surface as a blocker.
- **`deleteRealmIfMigrationNeeded: true`** (a common iOS-side
  shortcut) wipes the local DB on schema mismatch. If the project
  uses this, schema changes are tolerable because data re-syncs from
  the cloud — but documented in `CLAUDE.md` either way.
- **Typos in Realm property names** that exist in production data
  are load-bearing. Don't "correct" them.

## Apple build-number constraint (release time)

`CFBundleVersion` (build number, `CURRENT_PROJECT_VERSION`) must be
**strictly increasing per `CFBundleShortVersionString` (marketing
version, `MARKETING_VERSION`)**. Apple enforces this at upload time.

- Two TestFlight uploads under the same marketing version cannot share
  a build number.
- You cannot upload build 109 after build 110 under the same marketing
  version.
- Abandoned TestFlight uploads still consume their build number — those
  numbers are gone, not reusable.

Bumping `CURRENT_PROJECT_VERSION` is a protected-file edit (it's in
`project.pbxproj`) and requires explicit approval each time.

## Code signing — automatic vs manual

If `project.pbxproj` has `CODE_SIGN_STYLE = Automatic` (Xcode-managed):

- Headless `xcodebuild archive` and `xcodebuild -exportArchive` need
  `-allowProvisioningUpdates` to fetch the distribution cert + App
  Store profile on demand.
- Apple ID must be logged into Xcode (Xcode → Settings → Accounts).
- The signing identity must exist in the keychain (Xcode generates it
  the first time you archive a Release build through the UI).

If `CODE_SIGN_STYLE = Manual`:

- Distribution certificate must be in the keychain explicitly.
- Provisioning profile must match the bundle ID and live in
  `~/Library/MobileDevice/Provisioning Profiles/`.
- `-allowProvisioningUpdates` is a no-op; manual signing requires the
  exact assets to exist.

`CLAUDE.md` records which mode the project uses.

## Release flow (handover to the iOS release skill)

The `ios-release` skill orchestrates archive → export → validate →
upload to App Store Connect. It expects:

- A tagged commit on `main` (`vMAJOR.MINOR.PATCH-BUILD` format)
- An App Store Connect API key at
  `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`
- An operator-local config (e.g., `scripts/.release.env`) with
  `ASC_KEY_ID` and `ASC_ISSUER_ID`
- The project's `ExportOptions.plist` configured for App Store
  distribution

Per release: **explicit user confirmation required** before invoking
the release skill. Pushing to TestFlight is the most production-
impacting action available.

## Common iOS gotchas

- **`.DS_Store` files** are macOS finder noise and should be `.gitignore`d
  globally — never tracked.
- **`*.xcuserstate` files** in `xcuserdata/` directories are per-user
  Xcode UI state — never tracked.
- **`xcuserdata/`** at the project level holds breakpoints, scheme
  user settings, etc. — gitignore the whole directory.
- **Realm migrations + `deleteRealmIfMigrationNeeded`** as a pair is
  brittle for tightly-coupled clients but works fine for projects where
  the cloud is authoritative and local Realm is just a cache.
- **`@StateObject` vs `@ObservedObject` vs `@EnvironmentObject`**
  ownership confusion is one of the top sources of state-bleed bugs
  in SwiftUI iOS apps. Establish a project convention in `CLAUDE.md`
  and stick to it.
