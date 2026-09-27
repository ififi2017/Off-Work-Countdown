# Pixel Records/Life performance capture — 2026-09-27

## Setup

Pixel 10 Pro, API 37, wireless ADB. Synthetic archive: 15,000 life days and 3,653 observations, salary hidden. Tested `com.rainif.doneat.qa`, separate from the user's package. The analysis APK uses the release compiler, R8 and resource shrinking, is non-debuggable and shell-profileable, and is signed locally for installation. Only this temporary package reads the test Plus preference. Production Plus code and manifest remain unchanged.

Each run performs 24 Year/Life/Week/Month taps, verifies Month is selected, then selects Life and performs three up/down scroll pairs. ADB injection and a live user device are not a controlled benchmark laboratory. No production data is seeded, modified or uploaded.

## Release startup defect found and fixed

The first optimized package exited during AndroidX Startup initialization:

`NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init> []`

The resolved Room 2.6.1 consumer rule retains RoomDatabase subclasses but omits explicit constructors. The R8 usage output listed `WorkDatabase_Impl`'s no-arg constructor as removed. Added an explicit constructor keep rule in `app/proguard-rules.pro`; R8 remains enabled. The corrected optimized package starts on Pixel and API 36 emulator and completes the journeys below.

This is why successful APK compilation alone was insufficient release validation. The first capture had no application process and is excluded from performance results.

## Frame results

Numbers below are the primary `gfxinfo` counters, not its legacy jank counters.

| Build / run | Journey | Frames | Janky | P95 | P99 |
|---|---|---:|---:|---:|---:|
| Prior Debug run | 24 scale switches | 538 | 29 / 5.39% | 53 ms | 109 ms |
| Optimized, first valid capture | 24 scale switches | 853 | 15 / 1.76% | 13 ms | 31 ms |
| Optimized, first valid capture | Life scrolling | 401 | 2 / 0.50% | 7 ms | 12 ms |
| Optimized, warmed repeat | 24 scale switches | 886 | 11 / 1.24% | 13 ms | 30 ms |
| Optimized, warmed repeat | Life scrolling | 434 | 0 / 0.00% | 7 ms | 8 ms |

These are different builds/runs, not a measured percentage improvement from a single code change. Optimized tracing still has overhead. Thermal status read after the warmed run was 0. No manual AOT compilation was forced.

## Trace findings

- Records computation markers run on Default dispatcher workers, not the main thread. The first valid capture contains 13 such spans, mean 14.79 ms, maximum 54.96 ms. Cached Life results do not imply a new full Life calculation on every tap.
- Slow UI frames contain Compose recomposition, applying changes, and measure/layout. One 38.23 ms frame includes 18.14 ms recomposition and 11.67 ms measure/layout; these are nested spans and must not all be summed as independent work.
- The warmed trace also contains scheduling/pipeline waits: the two largest main-thread frame spans are 52.56 / 44.29 ms wall time but 22.79 / 23.08 ms scheduled CPU time. Other 25–33 ms frames spend nearly their entire span on CPU. Thus this is a mixture of page reconstruction cost and waiting, not simply a slow GPU or a Life calculation blocking the UI.
- GPU P95 in both first-run phases is 2 ms. FrameTimeline also reports SurfaceFlinger scheduling and dropped/resynchronized frames. Its categories and counts have a different scope from `gfxinfo`; do not add them into the table's percentages.
- The first valid trace used a shared ring buffer and lost initial process metadata. Its application PID was identified from the Records worker spans. The warmed repeat uses separate metadata/frame buffers and a larger scheduler buffer; process identity is intact.

## Other fix and verification

Bottom navigation labels now remain one line with ellipsis at extreme font sizes instead of splitting words. API 36 emulator, dark mode, 320 dp width and 200% font: visual inspection passed, and the accessibility tree retains full Timer/Focus/Records/Settings names. Screenshot: `navigation-large-font-fixed.png`.

Android 436 tests passed, with lint and Debug/R8 Release builds. Version check and headless iOS simulator build passed. No iOS manual visual testing. Full spoken TalkBack acceptance remains separate.

## Local evidence and references

Ignored local `build/android-preconsole/` contains `records-optimized.perfetto-trace`, `records-warm.perfetto-trace`, matching `*-switch-frames.txt` / `*-scroll-frames.txt`, and the navigation screenshot. Traces stay local because system traces can include other process metadata. SQL summaries are in `/tmp/doneat-perf-summary.txt`, `/tmp/doneat-warm-summary.txt`, `/tmp/doneat-frame-cpu.txt`. Build logs: `/tmp/doneat-release-fix-final.log`, `/tmp/doneat-profile-final-checks.log`, `/tmp/doneat-profile-ios.log`.

Method references: [Android composition tracing](https://developer.android.com/develop/ui/compose/tooling/tracing), [R8 full mode](https://developer.android.com/topic/performance/app-optimization/full-mode), [Perfetto command-line analysis](https://perfetto.dev/docs/getting-started/command-line-analysis).

## Component-level follow-up

A separate diagnostic APK temporarily includes the official Perfetto tracing binary and enables the tracing receiver. These dependencies are absent from the production build. The trace shows 25 calls to `AppShell` (85.81 ms inclusive total, 6.98 ms maximum), with corresponding MainActivity theme/language wrappers, during 24 scale changes. MainActivity subscribed to the entire device settings object for `dynamicColor`; AppShell did the same for `selectedTab`. Persisting `recordsScale` therefore invalidated both unrelated ancestors.

Changed those two subscriptions to `map` the required field and `distinctUntilChanged`. Existing immediate scale selection and persistence remain in place. The narrower subscriptions still observe dynamic-color and selected-tab changes. This is a targeted reduction of unrelated work; rebuilding the selected chart still has a cost.

The matching component-level replay after the subscription change contains **zero AppShell or MainActivity wrapper compositions**, versus 25 before. RecordsScreen still composes for its own changing content (55 recorded entries). This confirms the unnecessary ancestor work was removed.

Do not claim a frame-rate win from this single A/B sample: with component tracing enabled, before was 803 switch frames / 7 janky (0.87%) / P95 14 ms / P99 30 ms; after was 802 / 10 (1.25%) / P95 16 ms / P99 30 ms. After-change Life scrolling was 385 / 0 janky / P95 7 ms. Remaining chart/layout work and run-to-run scheduling variation remain. `records-composition.perfetto-trace` and `records-narrowed.perfetto-trace` plus their frame files hold this comparison; `/tmp/doneat-component-summary.txt` and `/tmp/doneat-root-after.txt` hold filtered component results.

Final functional regression on Pixel: dynamic wallpaper color toggles the whole theme and restores the original palette; Settings → Records restores Life; three force-stop/cold-launch cycles reach Records with the optimized package. The final ordinary build's initial subscription values are captured once inside `remember` to satisfy Compose lint; the ongoing flow filtering is unchanged from the measured build. Final app tests/lint/build log: `/tmp/doneat-narrowed-final.log`.

Cleanup: both isolated QA packages removed; emulator display size/font/night mode restored. Pixel's original app/data and stay-awake settings retained. Production manifest, release Plus override and dependencies contain no profiling hooks. Website and Play Console were not changed.
