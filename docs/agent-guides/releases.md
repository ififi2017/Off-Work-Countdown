# Packaging and release instructions

Read with `AGENTS.md` for Desktop channels, signing, packaging, versions,
release CI, store listings/media or release download counts.

## Versions and channels

- Run `npm run check:version` before any packaging. Product versions match in
  `package.json`, `package-lock.json`, `src-tauri/Cargo.toml`,
  `src-tauri/Cargo.lock`, `src-tauri/tauri.conf.json`, the macOS widget project
  `src-mobile/ios/App/App.xcodeproj` (`MARKETING_VERSION`, all shipping targets),
  and Android `app/build.gradle.kts` (`versionName`). Android `versionCode`
  increases for Play uploads independently of the product version.
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
- Android ships through Google Play like iOS through Xcode Cloud: every PR
  runs the `Android tests` check (`.github/workflows/android.yml`, skipped
  as passing when nothing Android-related changed), and a merge to `main`
  that touches `src-mobile/android/` (outside tests/docs) or the shared
  resources runs `.github/workflows/release-android.yml`, which tests again,
  uploads to `alpha` and commits it for review (`status: completed`).
  Manual `workflow_dispatch` runs remain for dry runs and re-sends: it builds a signed AAB with the upload key
  from Secrets (`ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_UPLOAD_STORE_PASSWORD`,
  `ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD`) and the Play billing
  IDs from repository Variables (`DONEAT_PLUS_*`, `DONEAT_PLAY_BILLING_PUBLIC_KEY`).
  By default it only stores the AAB and R8 mapping as an artifact; with
  `upload` it sends them to the chosen track (default `alpha`, closed testing)
  as a draft through the `PLAY_SERVICE_ACCOUNT_JSON` service account.
  `versionCode` defaults to 100 + run number. The upload keystore itself stays
  outside the repository. Play "What's new" (en-US) comes from
  `scripts/android-release-notes.mjs`: user-facing (`feat`/`fix`/`perf`) PRs
  scoped `android`, or touching `src-mobile/android/` without another platform
  scope, merged since the last `android-v<version>-<code>` tag, which each
  successful upload pushes. `notes_since` overrides the start.
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

## Chrome extension

- `npm run package:extension` writes the upload ZIP; its version is the product
  version, and the store rejects a package that is not higher than the
  published or in-review one.
- `npm run cws:upload` uploads without submitting; `npm run cws:publish` is the
  separate step that submits for review. Credentials live outside the
  repository (`~/.config/doneat/chrome-web-store.env`).
- The API cannot edit the listing: listing text and privacy answers are in
  `docs/CHROME-WEB-STORE-LISTING.md`, images from `npm run shots:chrome-web-store`.

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

## Source and license notices

Before distributing MPL-based builds, follow [SOURCE.md](../../SOURCE.md):
retain the immutable covered source, record each platform/version/build to
source-commit mapping, and verify that recipients can obtain it through the
existing About/GitHub entry. Existing MIT binaries keep their original terms.
Store-only iOS/macOS builds also need a public source commit/tag in their
release record; a moving main link alone is not the version record.

Web/Desktop and extension builds generate `licenses/source.txt` with the
commit and source archive URL, plus MPL, historical MIT and scope notices.
Confirm these files are in the output; never ship a notice marked as a local
dirty build. For builds from archives without Git, set `DONEAT_SOURCE_COMMIT`
to the archive's verified full commit SHA. Independent distributors must
point source notices to their own modified source, preserve upstream notices
and use appropriate branding. Store copy changes in this migration take
effect only when a corresponding release/listing is actually published.
