# iOS conventions (platform reference)

Conventions and patterns that are useful background when working on
**any** iOS project. Generic — doesn't assume anything about a specific
codebase. Project-specific architecture goes in the project's own
`docs/architecture/` directory.

Read this when:

- Onboarding to an iOS codebase
- Working on iOS code from a non-iOS repo (e.g., a web/Python project
  consuming an iOS-app-related artifact)
- Cross-referencing iOS patterns in cross-platform discussions
- **Starting a new iOS project** — the "Default stack" section below
  is the kit's opinionated default

## Default stack (the kit's opinion)

For a new iOS app, the kit defaults to this stack unless the project
explicitly opts out and documents the reason in `CLAUDE.md`:

| Layer | Choice |
|---|---|
| UI | **SwiftUI** (UIKit interop via `@UIApplicationDelegateAdaptor` only when needed) |
| Language | **Swift 5.9+** |
| Project | Single `*.xcodeproj` (workspace only when SPM with a local package is involved) |
| Dependency manager | **Swift Package Manager (SPM)** — `Package.swift` + `Package.resolved` |
| Local DB | **Realm Swift** (when offline cache is needed; cloud is authoritative) |
| Cloud | **Firebase** (Auth + Realtime DB or Firestore) |
| Tests | **XCTest** (unit) + **XCUITest** (UI flows). `Maestro` allowed when XCUITest cost is high. |
| Release | **TestFlight via App Store Connect**, automated by `/ios-release` |

If a project deviates (UIKit-first app, no Firebase, Combine-heavy
architecture, third-party DB instead of Realm), document the deviation
and the reason in `CLAUDE.md`. The default exists to remove a
decision; it doesn't override real project requirements.

## Top-level shape (typical SwiftUI app)

```
MyApp/
  MyApp.xcodeproj/                     # the project
  MyApp.xcworkspace/                   # only if using SPM/CocoaPods
  MyApp/                               # source
    MyAppApp.swift                     # @main entry (SwiftUI lifecycle)
    AppDelegate.swift                  # for UIKit interop / Firebase init
    ContentView.swift                  # initial root view (often replaced)
    Assets.xcassets/                   # images, colors, app icon
    Info.plist                         # app-level config
    GoogleService-Info.plist           # if using Firebase
    Models/                            # data layer (Realm classes etc.)
    Views/                             # SwiftUI views
    Utils/                             # helpers, extensions
  MyAppTests/                          # unit tests
  MyAppUITests/                        # XCUITest UI tests
```

## App entry point

SwiftUI apps use `@main` on a struct conforming to `App`:

```swift
@main
struct MyAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

For Firebase / push notifications / other UIKit-era SDK setup, an
`@UIApplicationDelegateAdaptor` is the standard bridge:

```swift
@main
struct MyAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { … }
}
```

## Navigation

The kit default is **`NavigationStack` with a typed path** (iOS 16+).
`NavigationView` is deprecated; new code uses `NavigationStack`. Set
up real navigation on day one — sheet-presenting from a root view as
the only navigation pattern collapses fast.

```swift
@main
struct MyAppApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) {
            HomeView()
                .navigationDestination(for: Vehicle.self) { v in
                    VehicleDetailView(vehicle: v)
                }
                .navigationDestination(for: Inspection.self) { i in
                    InspectionDetailView(inspection: i)
                }
        }
    }
}
```

Conventions:

- **One typed `NavigationPath` per main flow.** Push values onto the
  path; views bind via `.navigationDestination(for:)`. Don't sprinkle
  `NavigationLink(destination:)` ad-hoc — it makes deep linking,
  state restoration, and programmatic back-stack manipulation
  impossible.
- **Enum-driven path** is an alternative when destinations are
  closed-set: `enum Route { case vehicle(Vehicle), inspection(Inspection) }`,
  then `path: [Route]`. Useful when the same value type can lead to
  different screens depending on context.
- **One navigator per tab / per main flow.** A `TabView` with three
  tabs has three independent `NavigationStack` instances, each with
  its own `path`. Don't share a path across tabs.
- **Sheet vs. push.** Sheets are modal (settings, transient flows,
  forms). Pushes are linear (drill-down). If the user expects "go
  back," it's a push; if they expect "dismiss," it's a sheet.
- **Deep-link aware.** Every screen reachable from a typed value or
  enum case. Persist `path` in `@SceneStorage` for state restoration
  so cold-start lands where the user left off.

## Architecture — ViewModels (separation of concerns)

The kit default separates business logic from SwiftUI views. Views
render and dispatch intents; ViewModels own state, Firebase calls,
Realm queries, and derived computation.

iOS 17+ with `@Observable`:

```swift
@Observable
final class VehicleListViewModel {
    var vehicles: [Vehicle] = []
    var isLoading = false
    var error: Error?

    private let store: VehicleStore

    init(store: VehicleStore = .shared) { self.store = store }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do { vehicles = try await store.fetchAll() }
        catch { self.error = error }
    }
}

struct VehicleListView: View {
    @State private var vm = VehicleListViewModel()
    var body: some View {
        List(vm.vehicles) { VehicleRow(vehicle: $0) }
            .task { await vm.load() }
    }
}
```

Pre-iOS-17 (`ObservableObject` + `@Published`, view holds a
`@StateObject`):

```swift
final class VehicleListViewModel: ObservableObject {
    @Published var vehicles: [Vehicle] = []
    // ...
}

struct VehicleListView: View {
    @StateObject private var vm = VehicleListViewModel()
    // ...
}
```

Rules that fall out:

- **Views don't call Realm, Firebase, or networking directly.** They
  call ViewModel methods. Data access lives in the ViewModel — or in
  a `Store` / `Repository` the ViewModel composes.
- **Views don't transform data.** Filtering, sorting, grouping live
  on the ViewModel as derived state (`var filtered: [Vehicle] { … }`),
  not inline in the view body.
- **One ViewModel per screen by default.** Shared services
  (`AuthStore`, `VehicleStore`) are injected into multiple ViewModels
  — they're the data-access layer.
- **Ownership.** `@StateObject` (or `@State` for `@Observable`) when
  the view *owns* the ViewModel. `@ObservedObject` (or `@Bindable`)
  when the ViewModel is owned by an ancestor.
- **The layer you change for a logic bug is not the layer you change
  for a UI tweak.** If a Realm query lives next to a `Color`
  modifier in the same view file, the architecture is wrong.

For larger flows (multi-screen wizards, tab sections), a coordinator
ViewModel can manage navigation state and shared values across
sub-screens — but keep the boundary clear.

## Config files and what's in them

| File | Purpose | Tracked? |
|---|---|---|
| `*.xcodeproj/project.pbxproj` | Project structure, build settings, file references | ✅ |
| `*.xcworkspace/contents.xcworkspacedata` | Workspace structure (multi-project) | ✅ |
| `xcuserdata/` (anywhere) | Per-user Xcode UI state, breakpoints, schemes | ❌ gitignore |
| `*.xcuserstate` | Per-user file open state | ❌ gitignore |
| `Info.plist` | App-level config (bundle ID, version, capabilities) | ✅ |
| `*.entitlements` | App capabilities (push, app groups, etc.) | ✅ |
| `*.xcconfig` | Build setting overlay files | ✅ |
| `Package.swift` | SPM manifest | ✅ |
| `Package.resolved` | SPM lockfile | ✅ |
| `Podfile` / `Podfile.lock` | CocoaPods manifest + lockfile | ✅ |
| `GoogleService-Info.plist` | Firebase project config | ✅ (not secret) |
| `Assets.xcassets/Contents.json` | Asset catalog manifest | ✅ |
| `.DS_Store` | macOS finder noise | ❌ gitignore |

## Versioning

- **`MARKETING_VERSION`** (`CFBundleShortVersionString`) — public
  version like `5.0.10`. Increases on a meaningful release.
- **`CURRENT_PROJECT_VERSION`** (`CFBundleVersion`) — build number,
  monotonically increasing. Bump every TestFlight upload.
- Both live in `project.pbxproj` build settings, accessible via
  `xcodebuild -showBuildSettings`.

Tag format on `main` for releases: `vMAJOR.MINOR.PATCH-BUILD` (e.g.
`v5.0.10-110`). See `git-flow.md` (universal) for the convention.

## Common dependency managers (in order of modernness)

1. **Swift Package Manager (SPM)** — current default. Manifest is
   `Package.swift`. Lockfile is `Package.resolved` inside the
   workspace. No separate install step (Xcode resolves).
2. **CocoaPods** — pre-SPM. `Podfile` + `Podfile.lock`. `pod install`.
3. **Carthage** — rare now, mostly legacy.

## SwiftUI state ownership conventions

- **`@State`** — view-local mutable state, ephemeral.
- **`@StateObject`** — view *owns* this `ObservableObject`'s lifecycle.
  Use when the view creates the object.
- **`@ObservedObject`** — view *consumes* an object owned elsewhere.
  Don't construct in the view's body — that recreates on every render.
- **`@EnvironmentObject`** — implicit injection from an ancestor's
  `.environmentObject(...)`. Globals like a session.
- **`@Binding`** — a write-through reference to state owned by an
  ancestor.

Mixing patterns sloppily is a top source of state-bleed bugs. Pick a
convention per project (documented in `CLAUDE.md`) and stick to it.

## Realm (when used)

Realm Swift is a common local-DB choice. If the project uses Realm:

- Models inherit from `Object` with `@Persisted` properties
- Schema is the **cross-platform contract** if a web/Android client
  mirrors it (typical for Firebase RTDB + Realm-as-cache patterns)
- Migrations are versioned; bumping the schema version requires a
  migration block on the `Realm.Configuration`
- A common iOS shortcut: `deleteRealmIfMigrationNeeded: true` wipes
  the local DB on schema mismatch. Workable when the cloud is
  authoritative; brittle otherwise.

## Firebase (when used)

- Initialize early: `FirebaseApp.configure()` in `AppDelegate.didFinishLaunchingWithOptions`
- `GoogleService-Info.plist` per environment — handle Stage vs Prod
  via separate plists or a runtime config swap
- Realtime Database vs Firestore — different SDKs, different idioms,
  pick one per project

## Background queues / threading

- The Realm thread-confinement rule: a `Realm` instance can't cross
  thread boundaries; pass IDs and re-fetch on the target thread.
- `DispatchQueue.global(qos: .background)` for heavy work; back to
  `DispatchQueue.main.async` for UI updates.
- Combine and async/await both work in SwiftUI; `.task { }` modifier
  is the SwiftUI-native async entry point.

## Testing

- **XCUITest** ships with Xcode. Tests live in a separate target.
- **XCTest** for unit tests.
- Headless test run: `xcodebuild test -scheme … -destination …`.
- `Maestro` (third-party, mobile.dev) is an alternative for UI flows
  that's simpler than XCUITest but adds an external dependency.

## Apple-specific gotchas

- **TestFlight build numbers** consume forever — never reuse.
- **Apple Connect API keys** are downloadable exactly once.
- **App Store review** is a separate workflow from TestFlight upload —
  more involved (release notes per locale, screenshots, age rating,
  export compliance, privacy nutrition labels).
- **Code signing identities** in Keychain need to match the team /
  bundle ID in the project file.
