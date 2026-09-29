---
name: ios-release
description: iOS-specific release orchestrator — archive, export to .ipa, validate, and upload to App Store Connect / TestFlight. Triggered when the user wants to ship an iOS build — e.g. "/ios-release", "ship to TestFlight", "upload v5.0.10-110". Operates only on a tagged commit on main; refuses if working tree is dirty or tag doesn't match source MARKETING_VERSION + CURRENT_PROJECT_VERSION.
---

# /ios-release — Ship an iOS build to App Store Connect

End-to-end orchestrator for `xcodebuild archive` → `xcodebuild
-exportArchive` → `xcrun altool --validate-app` → `xcrun altool
--upload-app`. Hands off the binary to Apple; TestFlight processing
happens on Apple's side (5–15 min typical).

**Production deploys are user-confirmed every time.** This skill
prepares, asks, and executes only on explicit go.

Pairs with the iOS platform extensions in
[`ios-task-rules.md`](../../ios-task-rules.md) and the universal
[`/release`](../release/SKILL.md) skill — `/release` discovers what
kind of project this is and delegates here for iOS.

## Behavior contract

### Discover, don't assume

Read in this order to understand the project's release setup:

1. `CLAUDE.md` — "Deploy" / "Release" section, scheme name, team ID,
   bundle ID
2. `scripts/release-testflight.sh` if it exists — the project's own
   wrapper. Prefer running this over re-implementing.
3. `scripts/.release.env` — operator config with `ASC_KEY_ID` +
   `ASC_ISSUER_ID`. Required.
4. `scripts/ExportOptions.plist` — App Store distribution config.
5. `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` — the API
   key. Must exist; surface clearly if missing.

If the project doesn't have these files yet, the skill scaffolds
them as a one-time setup (with user confirmation), referencing the
`ios-task-rules.md` and the Element's pattern for `release-testflight.sh`.
The `scripts/` files it writes are code class: propose them with
`bash .claude/skills/land/land.sh pr --skill ios-release --title "<what>" -- <file>...`,
naming only those files (never `scripts/.release.env`, which is
gitignored). That PR is never merged by this skill; the setup report
says `PR: #N open, never merged by this skill`, and the release runs
once the PR has merged and the shipped commit is tagged.

### Pre-flight gates (refuse if any fail)

- Working tree clean
- HEAD on a `vMAJOR.MINOR.PATCH-BUILD` tag (annotated)
- Tag matches source `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`
- `scripts/.release.env` exists with non-placeholder Key ID + Issuer ID
- `AuthKey_<KEY_ID>.p8` at the canonical path
- API key auth verified (read-only `xcrun altool --list-providers`)

If any fail, surface the specific gap and stop. Don't half-run.

### Confirm before running

Even with all gates green, ask one final go:

> Ready to ship `<tag>` to App Store Connect?
> - Scheme: `<from CLAUDE.md>`
> - Marketing version: `<X.Y.Z>`
> - Build: `<N>`
> - Will run: archive → export → validate → upload
> - Estimated time: 8–15 minutes
> Confirm: [yes / no]

Wait for explicit yes. Don't proceed on "ok" or "looks good" — those
are review-language, not release-language.

### Execution

```sh
# 1. Archive (signed, real distribution cert via -allowProvisioningUpdates)
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "generic/platform=iOS" \
    -configuration Release \
    -archivePath "$ART_DIR/$SCHEME.xcarchive" \
    -allowProvisioningUpdates

# 2. Export to .ipa
xcodebuild -exportArchive \
    -archivePath "$ART_DIR/$SCHEME.xcarchive" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$ART_DIR/export" \
    -allowProvisioningUpdates

# 3. Validate (catches issues without uploading)
xcrun altool --validate-app \
    -f "$IPA_PATH" \
    --type ios \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"

# 4. Upload (the production-side action)
xcrun altool --upload-app \
    -f "$IPA_PATH" \
    --type ios \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"
```

All output to `release-artifacts/<tag>/logs/`. Failures stop the
chain — never partial-applies.

### Confirm completion + log

When upload succeeds, post a closing report:

```markdown
## /ios-release — Shipped <tag>

| | |
|---|---|
| **Tag** | `vX.Y.Z-N` |
| **Marketing** | `X.Y.Z` |
| **Build** | `N` |
| **Status** | ✅ Uploaded — Apple processing |

**Artifacts**: `release-artifacts/<tag>/`
**Logs**: `release-artifacts/<tag>/logs/{archive,export,validate,upload}.log`

Apple is processing the build. Watch progress at:
https://appstoreconnect.apple.com/apps

Processing typically takes 5–15 minutes. Apple emails when ready.
```

Then append to `tasks/AUDIT.md`:

```markdown
- 🚀 Released `vX.Y.Z-N` to TestFlight (uploaded YYYY-MM-DD HH:MM)
```

and land that line. `tasks/AUDIT.md` is docs class: it merges itself
after CI, built on the latest trunk (see `land/SKILL.md`):

```bash
bash .claude/skills/land/land.sh docs --skill ios-release --title "record <version>" -- tasks/AUDIT.md
```

- Exit 0 → from the output (`land/SKILL.md` has the table): `merged=#N`
  → add `Landed: PR #N merged`; `merge=held` → `PR #N open, held for a
  person`; `landed=nothing`/`landed=already` → `Already on the trunk`.
- Exit 4 → no `gh`: finish with the session's GitHub tooling per
  `land/SKILL.md` "Without gh".
- Any other exit → add `Not landed: exit N — <message>`; never retry
  blindly (on 6 the PR stays open).

When this skill runs as a step of `/mission`, `/self-heal` or
`/self-improve`, skip the landing: the orchestrator's branch and PR
carry `tasks/AUDIT.md`.

## What this skill does NOT do

- **Bump version / build numbers.** That's a deliberate human step;
  protected-file edit; explicit approval each time.
- **Tag commits.** You tag the commit you want to ship before
  invoking this.
- **Submit to App Store review.** Only TestFlight upload. App Store
  review submission has its own metadata workflow (release notes per
  locale, screenshots, age rating, export compliance, privacy
  nutrition labels) — separate skill if needed.
- **Manage TestFlight test groups.** Internal vs external, tester
  invitations — App Store Connect web UI.
- **Auto-deploy on tag push.** Each release is an explicit human
  invocation of this skill.

## Failure recovery

| Failure | What to do |
|---|---|
| Archive fails (signing) | Open Xcode, sign in, archive once manually so cert + profile cache, retry |
| Validation fails | Read `validate.log` — Apple lists every issue. Fix in source, retag (or amend tag if not yet pushed), re-run |
| Upload fails (network) | Retry — validation passes quickly second time |
| Apple-side processing rejection | Comes via email + visible in App Store Connect 5–15 min after upload. Fix, bump build, re-ship |
| "Build number must be greater than the most recent build number" | Apple won't let you reuse a build number. Bump `CURRENT_PROJECT_VERSION`, retag, re-run |

## Project-specific values

These live in `CLAUDE.md`:

- Scheme name (e.g., `CM Transportation`)
- Team ID
- Bundle ID
- ExportOptions.plist path (defaults to `scripts/ExportOptions.plist`)
- Whether the project has its own `release-testflight.sh` wrapper
- Apple ID associated with the team (for signing identity reference)

Operator-local values live in `scripts/.release.env` (gitignored):

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
