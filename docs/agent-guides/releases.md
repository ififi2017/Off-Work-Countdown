# Packaging and release instructions

Read with `AGENTS.md` for Desktop channels, signing, packaging, versions,
release CI, store listings/media or release download counts.

## Versions and channels

- Run `npm run check:version` before any packaging. Product versions match in
  `package.json`, `package-lock.json`, `src-tauri/Cargo.toml`,
  `src-tauri/Cargo.lock`, `src-tauri/tauri.conf.json`, the MSIX manifest and
  the macOS widget project. iOS and Android (4.0 and later) are versioned and
  released from the private native repository.
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
- iOS, Watch and Android (4.0 and later) are built, versioned and released
  from the private native repository. The iOS app shares one App Store record
  and bundle ID (`com.rainif.offworkcountdown.macappstore`, Universal
  Purchase) with the Mac App Store build from this repository, so App-level
  listing fields are shared between them.

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

- A macOS `CFBundleVersion` must be higher than every earlier upload, not just
  within its version (90061). 3.2.1 shipped as build 3.2.10, so later builds
  need a higher number (3.2.3 shipped as 3.2.30). Set both host and widget:
  `OWC_WIDGET_BUILD_NUMBER=<n>` and
  `--config '{"bundle":{"macOS":{"bundleVersion":"<n>"}}}'` on `tauri build`.
  Check with `xcrun altool --validate-app -t macos` before uploading.

Verify the signed host group is Team ID-prefixed:

```bash
codesign -d --entitlements - --xml DoneAt.app \
  | plutil -extract 'com.apple.security.application-groups' xml1 -o - -
```

`embed-macos-profile.mjs` and `pack-macappstore.sh` reject iOS-style `group.*`
locally. Profile/App Group/upload history: `docs/PLAN-MSSTORE.md` 9.11–9.12.

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

- Generate desktop media via `scripts/marketing-shots/` (`shots:macos`,
  `shots:windows`, `shots:chrome-web-store`). The App Store Connect sync
  (`npm run asc:sync`, see `docs/APP-STORE-CONNECT-SYNC.md`) stays here
  because the Mac App Store listing belongs to the desktop app; the private
  native repository runs the same script for iOS listings.
- App Info (name, subtitle, privacy URLs) is shared by iOS and Mac and locked
  while either platform is in review. `asc:sync` skips it then.

## Source and license notices

Before distributing MPL-based builds, follow [SOURCE.md](../../SOURCE.md):
retain the immutable covered source, record each platform/version/build to
source-commit mapping, and verify that recipients can obtain it through the
existing About/GitHub entry. Existing MIT binaries keep their original terms.
Store-only macOS builds also need a public source commit/tag in their release
record; a moving main link alone is not the version record. iOS, Watch and
Android source up to 3.3.0 stays public at tag `ios-v3.3.0`; 4.0 and later
native builds are not built from this repository.

Web/Desktop and extension builds generate `licenses/source.txt` with the
commit and source archive URL, plus MPL, historical MIT and scope notices.
Confirm these files are in the output; never ship a notice marked as a local
dirty build. For builds from archives without Git, set `DONEAT_SOURCE_COMMIT`
to the archive's verified full commit SHA. Independent distributors must
point source notices to their own modified source, preserve upstream notices
and use appropriate branding. Store copy changes in this migration take
effect only when a corresponding release/listing is actually published.
