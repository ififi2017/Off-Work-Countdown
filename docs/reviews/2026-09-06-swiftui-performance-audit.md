# iOS performance audit — 2026-09-06

## PR integration on current main

The measurements below were captured before integrating main at `56bf539`; they are historical diagnostic evidence, not fresh measurements of main's newer Life income projection or iPad sidebar. The integration preserves those features and relocates the sidebar signpost to its current timeline. `lifeBuildModel` now also contains the existing lifetime-income calculation; the narrower `lifeBuildWeeks` marker still covers only week construction.

## Scope and measurement environment

Life cold loading, repeated computation in the records navigation lists, and idle countdown CPU/update frequency. App Intents and SwiftData migration remain deferred.

Physical device: iPad mini (6th generation), iPadOS 27.0 Beta (24A5424a), wired. The user initially described it as mini 5; CoreDevice reports mini 6. Host: Xcode 26.6 (17F113). Measurements use a **Debug build with Swift optimization `-O`**, not an App Store Release build. Instruments overhead and the beta OS limit generalization; these are single-device diagnostic samples, not battery-life estimates.

`-owcPerformanceFixture` creates an in-memory archive and a separate preferences suite. Existing personal records are not imported into the fixture. Sample records come from the existing QA seed (23 recorded workdays within 32 calendar days); Life uses the existing sample profile. No migration or deletion of the installed archive was performed.

## Life: the main wait is the shared-rule prefetch

Time Profiler + Points of Interest, cold process launch, 8-second capture:

| Stage | Wall time |
| --- | ---: |
| Background rule prefetch (`lifePrefetch`) | 2,125.0 ms |
| Main-actor model assembly (`lifeBuildModel`) | 83.9 ms |
| ↳ Resolve career days (`lifeResolveDays`) | 69.7 ms |
| ↳ Project overtime (`lifeProjectOvertime`) | 5.9 ms |
| ↳ Build weeks (`lifeBuildWeeks`) | 7.4 ms |

The last three rows are contained in model assembly, not additive to it. Prefetch includes the actor call, JavaScriptCore rule expansion and conversion back to Swift; this capture does not separate those components. It is elapsed time, not evidence that the main thread blocked for 2.1 seconds. The independent SwiftUI cold-launch trace detected no hangs above its 250 ms threshold.

The next useful experiment is to split the rule invocation from decoding and investigate the career-length expansion in the shared TypeScript implementation. Retain differential tests and the existing rules boundary. Moving the remaining 84 ms off the main actor could reduce a smaller frame interruption, but does not address the dominant wait. Replacing JSON persistence with SwiftData cannot directly remove this in-memory sample's prefetch cost.

No speculative Life algorithm rewrite was made. Existing warm caches remain intact. Stage signposts were retained for repeatable follow-up measurements; the signposter now uses the standard PointsOfInterest category so the stock instrument captures it.

## Records lists: remove repeated work within one render

`RecordsAllRecordsView.presentation` constructed `store.recordDayIndex()` and a presenter on every property access. Empty checks, `ForEach`, row counts and last-row checks repeatedly evaluated that property. Year and month lists had the equivalent repeated `months` / `days` calculations.

The change binds one local presentation per body evaluation and passes the current months/days to the content helper. It introduces no persistent cache and keeps access gating reactive.

Matched device launch samples:

| Measurement | Before | After |
| --- | ---: | ---: |
| Presenter constructions | 8 | 1 |
| Total presenter initializer time | 0.293 ms | 0.046 ms |

Each eliminated presenter access also eliminates a full `recordDayIndex()` call. The initializer signpost **does not include index construction**, because the entries argument is evaluated first. Do not describe the table as total screen latency or claim a measured large-data speedup. It confirms the repeated work was removed; this small fixture was already fast. Year/month helper changes are the same code-level correction, not separately timed device results.

## Countdown

A Time Profiler launch capture excludes startup by analyzing 5–19 seconds. It contains 6,261 ms of sampled CPU weight in 14 seconds, approximately **44.7% of one CPU core** across the app's threads. This is an estimate from sampling, not a battery or device-wide utilization figure.

The largest leaf was image convolution (`vSepConvolveARGB8bgf_vec`, 2,282 ms / 36.45% of sampled CPU), followed by image sampling, drawing and AttributeGraph updates. This points to rendering/animation work rather than persistence. The separate SwiftUI capture contains recurring animation and geometry work; many view identities are unknown because the process was attached after creation and the device runs a newer beta OS. Its hundreds of thousands of internal events must not be reported as app body executions.

The iPad active countdown uses `TabletTimerView`, while the phone/fallback uses `TimerDesignView`; the sidebar has its own timeline. Phone-only markers are insufficient to measure the iPad. Markers now cover all three entry points. An isolated diagnostic numeric-transition override (`-owcPerformanceDisableNumericTransition`) is gated behind both DEBUG and the fixture flag. It disables only countdown digit transitions and does not change the user's system setting.

### Controlled numeric-transition comparison

Both samples use the `working` QA scenario, the same in-memory fixture and a 5–14 second analysis window. Production countdown arithmetic, tick schedules and other animations were unchanged.

| Measurement (9-second window) | Normal digit transition | Digit transition disabled |
| --- | ---: | ---: |
| Sampled app CPU time | 4,045 ms | 408 ms |
| Approximate single-core utilization | 44.9% | 4.5% |
| Main iPad countdown content updates | 9 | 9 |
| Sidebar timeline content updates | 9 | 9 |

Update counts come from the final normal/disabled marker captures. CPU baseline uses the earlier normal capture (`owc-ipad-timer-poi.trace`), reanalyzed over the identical 9-second window; the final normal capture's `time-profile` export crashed xctrace twice. Its signposts exported successfully. The earlier normal capture differs only in diagnostic marker coverage and the unrelated records-list fix, not the timer's behavior.

This supports digit-transition rendering as the dominant idle cost in this environment, rather than excessive app-level tick frequency. The normal capture's convolution leaf accounts for 37% of CPU samples. Treat the approximately tenfold difference as a diagnostic result, not a promised production improvement or battery-life multiplier.

A follow-up should concentrate on the large iPad digit transition (and the sidebar when showing digits): compare a cheaper transition or direct updates, then inspect the result and repeat on a supported stable OS/Release build. The shipping animation was deliberately left unchanged; disabling it here is an experiment, not a completed timer optimization. Life likewise has a measured next target, not an unverified algorithm change.

Final comparison artifacts:

- `/tmp/owc-ipad-timer-normal-matched-cpu.json`
- `/tmp/owc-ipad-timer-final-normal.trace`, `/tmp/owc-ipad-timer-final-normal-events.json`
- `/tmp/owc-ipad-timer-final-no-numeric.trace`, `/tmp/owc-ipad-timer-final-no-numeric-cpu.json`, `/tmp/owc-ipad-timer-final-no-numeric-events.json`

The device was relaunched without diagnostic arguments after measurement, restoring its normal data path. The installed binary remains the local optimized Debug build.

## Validation and artifacts

- Generated the shared iOS rules bundle; `npm run check:ios` passed.
- Final diagnostic code compiled for both physical device and simulator. `/tmp/owc-perf-final-device-build3.log`, `/tmp/owc-perf-final-sim-build2.log`.
- Full simulator test suite: **383 tests in 7 suites passed**, 11.645 seconds. `/tmp/owc-perf-verified.xcresult` and `/tmp/owc-perf-verified.log`.
- Checked rendered iPhone dark / iPad light All Records screens. `/tmp/owc-records-iphone-after.png`, `/tmp/owc-records-ipad-after.png`. No layout/style change is part of the list fix.
- Device traces and JSON analysis are local diagnostic artifacts in `/tmp`, not committed assets:
  - `/tmp/owc-ipad-life-poi.trace`, `/tmp/owc-ipad-life-poi.json`
  - `/tmp/owc-ipad-life-cold.trace`, `/tmp/owc-ipad-life-cold.json`
  - `/tmp/owc-ipad-records-poi-before.trace`, `/tmp/owc-ipad-records-poi-before.json`
  - `/tmp/owc-ipad-records-poi-after.trace`, `/tmp/owc-ipad-records-poi-after.json`
  - `/tmp/owc-ipad-timer-before.trace`, `/tmp/owc-ipad-timer-before.json`
  - `/tmp/owc-ipad-timer-poi.trace`, `/tmp/owc-ipad-timer-poi-cpu.json`

No release, commit, App Intents integration or SwiftData migration was performed. Existing unrelated working-tree changes were preserved.
