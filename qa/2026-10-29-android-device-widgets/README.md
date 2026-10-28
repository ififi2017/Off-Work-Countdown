# Physical Android widget size verification — 2026-10-29

User explicitly authorized installation and testing on their physical phone. Pixel 10 Pro, Android 17, 1280×2856, density 480, font scale 1.0. Debug-signed `com.rainif.doneat.parityqa` (DoneAt Widget QA) is isolated from the existing applications and their data. Test schedule and Focus task were created only in that package; Plus uses the existing debug-only override.

## Evidence and scope

- `pixel-launcher-ring.png`: actual Pixel Launcher 2×2 widget, measured 186×208 dp; cropped to the widget to exclude unrelated home-screen content.
- `native/`: 38 production Glance/RemoteViews captures on the physical phone, hosted in a dedicated debug AppWidgetHost. Small 186×208, medium 390×180, large 390×390 dp; Detail has no small variant. These are native widget layouts with real isolated test state, not bitmap previews and not 38 separate Launcher placements. `native-sheet.jpg` is a thumbnail index, not a scale comparison.
- `native/locked/`: nine additional locked-state captures for Focus, Summary and Life. Unlocked Focus captures show a running native Chronometer and aligned controls. Tapping the visible Stop control ended the isolated task and refreshed to the empty state (`focus-stop-result.png`). Life's native capture covers its missing-birth-year state.
- `samples-zh-CN-light/`: 38 renderer exports made on the phone using explicitly synthetic data, at 180×240, 390×180 and 390×390 dp. Populated Life, planned leave and queued Focus are samples, not user records or Launcher interaction evidence.

## Fixes verified

- Wide and large Big/Ring/Timeline now compose for their actual host dimensions instead of letterboxing a 170 dp square.
- Large suite widgets use centered content panels, larger primary values and appropriately bounded chart/block heights. Native Focus controls and countdown share the painter's geometry.
- Canvas measurement now uses the same tabular numerals and sans-serif face as the native Chronometer. This fixes a real-device trailing-seconds clipping issue found in the medium ring.
- Resizable providers permit 110 dp minimum dimensions, retaining Detail's 220 dp minimum width and existing initial grid targets.

## Validation and limits

Android four-module unit tests: 779 passing (468 domain, 96 data, 13 design system, 202 app). Full Gradle tests/lint/debug/release succeeded; app tests/lint/debug/release rerun after the final native font fix. Lint: 0 errors, 73 warnings, 4 hints. Version consistency and headless iOS Simulator build passed. No iOS manual visual testing.

Verified physical-device layout, not all manufacturers, all 19 languages, purchasing, alarms, reboot or full accessibility. The prior design evidence remains historical; this directory supersedes its widget size conclusions. No production release or merge performed. The temporary QA binding grant is revoked after inspection; the installed test app and its pinned Ring remain available for owner review.
