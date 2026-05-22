---
name: <kebab-case-runtime-name>
kind: mobile-app
language: <swift | kotlin | dart | objective-c | java>
framework: <swiftui | uikit | jetpack-compose | flutter | react-native | other>
platform: <ios | android | flutter>

commands:
  install: "<resolve dependencies — e.g. xcodebuild -resolvePackageDependencies, ./gradlew dependencies>"
  build: "<build command — e.g. xcodebuild -scheme MyApp build>"
  run: "<launch on simulator/emulator — e.g. xcrun simctl boot 'iPhone 15' && xcodebuild -scheme MyApp run>"
  test: "<test command — e.g. xcodebuild test -scheme MyAppTests>"
  clean: "<clean build artifacts — e.g. xcodebuild clean>"

# Mobile-specific config
simulator:
  default_device: "iPhone 15"
  os_version: "17.0"

build_artifacts:
  output_path: "build/Debug-iphonesimulator/MyApp.app"
  # for Android: "app/build/outputs/apk/debug/app-debug.apk"

env:
  template: ".env-template"           # if applicable for the platform
  file: ".env"                        # or "Config.xcconfig" for iOS, "local.properties" for Android
  environments:                       # optional — most mobile apps use build configurations instead
    local: ".env"
  required: []                        # build-time / runtime env vars (rare for mobile)
  optional: {}

depends_on: []           # external dependencies (usually backend APIs)
  # - { name: api, check: "curl -s http://localhost:8000/health" }

process:
  type: build-and-run    # not long-running like a server

tags: []
---

# <Name> — local mobile runtime

> Mobile apps build-and-run rather than run-as-a-daemon. The stamp
> captures both the build and run steps; body explains the simulator
> / device setup.

## What this is

<One paragraph: which app, which platform, who talks to what backend.>

## How to build + run

```sh
<install command>
<build command>
<run command>
```

The app launches in the simulator (or on a connected device).

## First-time setup

1. Install Xcode (or Android Studio, etc.) from the App Store / direct download
2. Open the project: `open MyApp.xcworkspace` (or .xcodeproj)
3. Resolve dependencies: `<install command>`
4. Trust the developer certificate (Settings → General → Device
   Management on iOS device, if using a physical device)
5. Run via the IDE OR via the `run` command above

## Simulator / device management

- **Default simulator:** `<default_device>` running iOS `<os_version>`
- List available: `xcrun simctl list devices`
- Boot another: `xcrun simctl boot '<device name>'`
- Reset state: `xcrun simctl erase '<device name>'`

## Connecting to local backend

If `depends_on` includes a local API:
- iOS Simulator: API at `http://localhost:8000` works directly
- Physical iOS device: use the Mac's LAN IP (`http://192.168.x.x:8000`),
  ensure Mac firewall allows the connection
- Android Emulator: API at `http://10.0.2.2:8000` (special host alias)
- Physical Android device: same as iOS — Mac LAN IP

## Gotchas

- ...

## References

- <link to platform docs>
- <link to internal architecture doc, if any>

---

*Last verified working: <YYYY-MM-DD>.*
