# iOS instructions

Read with the root `AGENTS.md` for iOS changes/builds/tests and shared
rules/locales consumed by iOS. Root validation gates and visual-testing consent
rules apply.

## Project and shared rules

- `scripts/ios-schedule-rule-oracle.mjs` exposes the TypeScript entry points.
  `npm run generate:ios-rule-fixtures` writes
  `AppTests/ScheduleRuleFixtures.generated.swift`;
  `AppTests/ScheduleRuleFixtureTests.swift` checks Swift parity. `npm test`
  rejects stale fixtures; resolve disagreements before regeneration.
- Universal Purchase shares the Mac App Store record and bundle ID:

  | Target | Scheme | Bundle ID |
  |---|---|---|
  | App | `App` | `com.rainif.offworkcountdown.macappstore` |
  | Widget | `OffWorkCountdownWidgetsExtension` | `com.rainif.offworkcountdown.macappstore.widget` |

  Both use `group.com.rainif.offworkcountdown.macappstore`, containing only the
  salary-free `WidgetSnapshot`. This unprefixed group is iOS-only; macOS signing
  uses the Team ID prefix (release guide).
- `App/Native` and `AppTests` are synchronized folders
  (`PBXFileSystemSynchronizedRootGroup`, `objectVersion = 77`). New Swift files
  compile automatically without `project.pbxproj` edits: use
  `Native/DesignSystem`, `Native/Models`, `Native/Services` or `Native/Views` as
  appropriate; do not add `PBXFileReference`/`PBXBuildFile` entries.
  Never leave scratch/backup sources there; they compile too.
- Everything outside those folders needs explicit project registration:
  `AppDelegate.swift`, localized `InfoPlist.strings`, `Assets.xcassets`,
  `Localizable.xcstrings`, `WidgetExtension/`, the two shared widget sources
  from `src-tauri/macos-widget`, and `public/locales`. The last is copied into
  the widget extension only; removing it causes raw localization keys.
- `Native/Models/LiveActivityAttributes.swift` also compiles into the widget
  via the project's single `PBXFileSystemSynchronizedBuildFileExceptionSet`.
  Add any further shared widget files to that same exception set.
- App and Watch reference `assets/brand/AppIcon.icon` (Icon Composer), never
  symlink it. `npm run check:ios` reads the working tree without a build and
  guards bundle IDs, SwiftUI entry point, iPhone/iPad orientations, App Groups,
  embedded widget, Live Activities, icon and localization bundle membership.

## Rendering and automated checks

- `ImageRenderer` views have no parent environment. Pass everything they draw
  explicitly; an `@Environment(SomeObservable.self)` lookup can crash when the
  share sheet opens. Cover the exact button render path as
  `ShareCardRenderTests` does.
- `-only-testing` must name declarations, not files, with parentheses:
  `@Suite` method `AppTests/RecordsPerformanceTests/surfaceCost()`; top-level
  `@Test` function `AppTests/newShiftDiscardsPreviousRecoveryPrompt()`.
  `AppTests/FocusStoreTests` matches nothing. A miss or a crash/restart can
  report zero tests, exit 0 and `TEST SUCCEEDED`. Verify expected tests actually
  ran and passed; neither the banner nor exit code proves success. Inspect
  individual `✔ Test … passed` / `✘ Test … failed` and `Test run with N tests`
  log entries.
- The simulator follows the Mac's time zone; `TZ=` on `xcodebuild` does not
  change it. Default store zone is `TimeZone.current`, default shift 09:00–17:00,
  and day keys use `recordsCalendar`. Build test instants from `DateComponents`
  through `store.recordsCalendar`, not raw epochs. Pin
  `store.recordsTimeZoneIdentifier` per affected test and use that calendar for
  expectations too; do not mix pinned stores with `Calendar.current` assertions.
  Never mutate process-global `NSTimeZone.default` in parallel tests. A suite
  migration must move both store and assertion calendars together; until then,
  fix affected tests individually.
- Main-actor contention makes parallel wall-clock assertions unreliable (for
  example `recordsDayCanvas`/`RecordsPerformanceTests.surfaceCost`); off-main
  computation such as `lifePrepareMs` is not that artefact. When performance
  assertions are in scope, run `-parallel-testing-enabled NO`; never raise a
  ceiling before measuring serially.

Headless simulator build (allowed without a visual-testing request):

```bash
npm run check:ios
xcodebuild -project src-mobile/ios/App/App.xcodeproj -scheme App \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

`xcrun simctl list devices available` lists installed simulators.

## Visual QA — only when explicitly requested

`npm run qa:ios-shots` covers eight surfaces on iPhone/iPad in both orientations,
including phone portrait, phone landscape and iPad sidebar shells that share
views; model tests do not cover these layouts. It uses DEBUG launch arguments,
its own DerivedData, and writes `scripts/ios-qa-shots/index.html`. Treat launch
failure, missing app or wrong orientation as a miss; a PNG alone proves nothing.

Controls: `IOS_QA_SCENES`, `IOS_QA_THEME=both`, `IOS_QA_LANGUAGE`,
`IOS_QA_IPHONE`, `IOS_QA_IPAD`, `IOS_QA_SKIP_BUILD=1`.
For manual requested QA: `xcrun simctl install <udid> <path>` and
`xcrun simctl launch <udid> com.rainif.offworkcountdown.macappstore`.

`qaOrientation` must pin the mask through `AppOrientationPolicy` before the
geometry update; otherwise `supportedInterfaceOrientations` can restore
portrait. The pin lasts for the process and must remain DEBUG-only; geometry
errors go to `ios.native.qaOrientationError`. **The fix still needs a full
sweep before trusting landscape columns.** Do not infer it was verified.

## CI

GitHub Actions has no iOS job. Xcode Cloud's
`src-mobile/ios/App/ci_scripts/ci_post_clone.sh` installs Node and checks Watch
and rule fixtures, `check:ios-strings` and `check:ios` before Xcode builds.
App Store Connect owns branch/path triggers, Release archives and TestFlight
distribution; keep `docs/XCODE-CLOUD.md` aligned. CI does not replace the local
simulator build required for changes to `lib/`, `public/locales` or `src-mobile/`.
For upload/archive/signing instructions, read [Releases](releases.md).
