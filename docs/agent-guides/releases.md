# Packaging and release instructions

Read with `AGENTS.md` for Desktop channels, signing, packaging, versions,
release CI, store listings/media or release download counts.

## Versions and channels

- Run `npm run check:version` before any packaging. Product versions match in
  `package.json`, `package-lock.json`, `src-tauri/Cargo.toml`,
  `src-tauri/Cargo.lock`, `src-tauri/tauri.conf.json`, the macOS widget project
  and `src-mobile/ios/App/App.xcodeproj` (`MARKETING_VERSION`, all four build
  configurations of both targets).
- iOS `CURRENT_PROJECT_VERSION` is independent of product version; increment
  it for every TestFlight/App Store upload. Reuse under the same
  `MARKETING_VERSION` is rejected.
- Web deploys on pushes to `main` through CI/connected deployment. Prefer PRs.
  `npm run deploy:web` is the owner's convenience for validating and pushing
  already-committed local `main`.
- Desktop channels are selected at build time; bundles are not interchangeable:

  | Channel | Frontend | Bundle/package |
  |---|---|---|
  | `github` (default) | `npm run build:desktop` | `npm run tauri:build` |
  | Microsoft Store | `npm run build:desktop:msstore` | `npm run pack:msix` |
  | Mac App Store | `npm run build:desktop:macappstore` | `npm run tauri:build:macappstore`, then `npm run pack:macappstore` |

  Store channels compile out updater/restart plugins. GitHub compiles out the
  desktop widget by product decision (`docs/PLAN-MSSTORE.md` 9.9).
- `npm run release:desktop -- [version]` requires clean `main` exactly equal to
  `origin/main`; it validates and pushes `desktop-v<version>`.
  `.github/workflows/release-desktop.yml` builds macOS Apple Silicon/Intel and
  Windows x64/ARM64 into a Draft Release. Inspect all assets, `latest.json` and
  `latest-cn.json` before publishing.
- `mirror-manifest` produces `latest-cn.json`: same signatures, asset URLs
  rewritten through a reverse proxy, used only after direct download fails.
  Missing manifest or unrewritten URLs silently disable fallback. The job
  downloads every asset to compute SHA-256: subtract one download per asset
  (two for `latest.json`) before interpreting demand.
- GitHub macOS builds intentionally use ad-hoc signing; the project does not
  buy Developer ID certificates. Installation docs must accurately explain
  Gatekeeper and Windows SmartScreen. Mac App Store signing differs below.
- iOS ships only through App Store Connect, without a GitHub channel/tag
  workflow. Universal Purchase shares one record and bundle ID
  (`com.rainif.offworkcountdown.macappstore`) with the Mac App Store app;
  iOS submission releases that shared product, not an independent one.

## Mac App Store signing

The Mac store app is Tauri + nested WidgetKit `.appex`, not an iOS build.
`npm run tauri:build:macappstore` includes `--no-default-features`; retain it or
the binary uses the GitHub channel even with store config.

- iOS's `group.com.rainif.offworkcountdown.macappstore` is rejected by macOS
  validation (409). With `OWC_APPLE_TEAM_ID`, `src-tauri/build.rs` and
  `scripts/build-macos-widget.sh` prefix it, yielding
  `3GSK5B9S3T.group.com.rainif.offworkcountdown.macappstore`. Never copy iOS
  entitlements onto the Mac host. Ad-hoc local packages strip App Groups
  (`src-tauri/macappstore/README.md`).
- Widget `distribution` signing requires an explicit Mac `.provisionprofile`,
  never an iOS `.mobileprovision`. Host profile is optional:
  `embed-macos-profile.mjs` searches
  `~/Library/Developer/Xcode/UserData/Provisioning Profiles` if omitted.
  Owner copies: `~/Downloads/Off_Work_Countdown_macOS_App_Store.provisionprofile`
  and `~/Downloads/Off_Work_Countdown_Widget_App_Store.provisionprofile`.
- Sign `.app` with **Apple Distribution** (find identity with
  `security find-identity -v -p codesigning`); sign `.pkg` separately with
  **Mac Installer Distribution** (`3rd Party Mac Developer Installer`).
  `pack:macappstore` must not re-sign `.app`.

```bash
OWC_WIDGET_SIGNING_MODE=distribution \
OWC_APPLE_TEAM_ID=3GSK5B9S3T \
OWC_WIDGET_PROVISION_PROFILE="$HOME/Downloads/Off_Work_Countdown_Widget_App_Store.provisionprofile" \
OWC_MACOS_PROVISION_PROFILE="$HOME/Downloads/Off_Work_Countdown_macOS_App_Store.provisionprofile" \
APPLE_SIGNING_IDENTITY="Apple Distribution: … (3GSK5B9S3T)" \
npm run tauri:build:macappstore

npm run pack:macappstore
```

Verify the signed host group is Team ID-prefixed:

```bash
codesign -d --entitlements - --xml DoneAt.app \
  | plutil -extract 'com.apple.security.application-groups' xml1 -o - -
```

`embed-macos-profile.mjs` and `pack-macappstore.sh` reject iOS-style `group.*`
locally. Profile/App Group/upload history: `docs/PLAN-MSSTORE.md` 9.11–9.12.

## iOS upload

Use an archive, not `build`, after bumping the build number:

```bash
npm run check:version
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath build/OffWorkCountdown.xcarchive archive
```

Distribute through Xcode Organizer. The repository has no `ExportOptions.plist`
or fastlane; export is deliberately manual. Agree on signing setup before
introducing an automated export path. Keep `docs/XCODE-CLOUD.md` aligned with
App Store Connect's workflow triggers, Release archive and distribution.

## Store media and metadata

- Generate via `scripts/marketing-shots/`, sync with `npm run asc:sync`;
  see `docs/APP-STORE-CONNECT-SYNC.md`. The approved 2026-09-08 screenshot
  decision requires all 17 App Store locales, six iPhone + six iPad each
  (204 PNGs); see `docs/reviews/2026-09-08-ios-marketing-shots.md`.
  App Previews remain `en-US`, `zh-Hans`, `zh-Hant`; other locales inherit
  English video. The 19 UI locales differ: `zh-HK`/`zh-TW` share one Traditional
  Chinese store listing; `mr-IN` has no store locale.
- 1320×2868 iPhone screenshots use `APP_IPHONE_67`, never nonexistent
  `APP_IPHONE_69`. After replacement, delete leftover sets on unused display
  types such as `APP_IPHONE_65`; Connect may prefer those stale sets.
- App Info (name, subtitle, privacy URLs) is shared with Mac and locked while
  either platform is in review. `asc:sync` skips it then; version-level media
  still applies to an editable iOS version.
- Compose official Apple frames like site DeviceHero: frame PNG defines the
  box, capture sits in the hole, frame overlays it. Never punch bezels or
  redraw Dynamic Island. App Previews use `IPHONE_67`, 886×1920 portrait,
  with an audio track (silent stereo is acceptable).
