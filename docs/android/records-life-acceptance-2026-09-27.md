# Records/Life acceptance — 2026-09-27

## Scope and result

Large-archive cancellation, navigation and Life accessibility were exercised with synthetic data. QA-056 and QA-131 have partial evidence; neither is a complete release acceptance pass. Status remains in `progress.md`.

## Fixes

- Build the All records index and year/month groups on `Dispatchers.Default`; render cached groups and an explicit loading state. Use locale-independent civil month keys.
- Check the owning coroutine during index, daily schedule/resolution and Life week loops. Cancelled work cannot publish an outdated page. Reset page data when the query context changes.
- Give each allocation legend a minimum 48 dp target and a complete duration/percentage description with selected state. Remove duplicate color-bar accessibility and keyboard stops.

## Automated evidence

- Android: 436 tests (domain 337, data 74, design 8, app 17), no failures. Lint: 0 errors, 34 warnings, 1 hint. Debug and R8 Release APK builds passed.
- `RecordsComputationTest`: cancelling a paused Life calculation stops at its first checkpoint and publishes no result; the following Month calculation completes. Free-window filtering and Arabic default-locale month lookup pass.
- `RecordsQueriesTest`: exported/imported synthetic archive, 15,000 life days and 3,653 observations; full Life, Year and index calculation took 125.64 ms in one local JVM sample. Cancellation interrupts Life and index after 100 checks. This is diagnostic evidence, not a cross-device benchmark.
- Repository lint, 445 npm tests, version check and headless iOS simulator build passed. No iOS manual visual inspection.

## Device evidence

Pixel 10 Pro used a separate `com.rainif.doneat.qa` Debug app and synthetic archive. The existing user app was not modified. Twenty-four rapid Year/Life/Week/Month taps finish on Month without a stale result replacing it. Hidden synthetic salary is absent from the accessibility tree.

`gfxinfo`: 538 frames, 29 janky (5.39%); median 5 ms, P90 13 ms, P95 53 ms, P99 109 ms. GPU median 1 ms and P95 2 ms. These Debug transition measurements still contain slow frames; no same-device before/after baseline or Release performance claim is made.

API 36 emulator:

- All records → 2019 → September opens the ten-year archive correctly.
- Life allocation labels include category, approximate years where applicable, precise duration and percentage; masked income stays masked in the tree.
- Keyboard Tab reaches the labelled allocation entries without duplicate color-bar stops; Enter on Sleep marks its parent checked and retains the full label.
- Light/default size and dark 320 dp / 200% font with system animation scales at zero were visually inspected. Life content scrolls and labels remain readable. The global bottom navigation still splits Records/Settings across lines at this extreme font/width combination.
- TalkBack 16 was enabled and its service verified bound. Accessibility semantics were inspected, but injected input did not establish the actual spoken gesture flow. Spoken TalkBack acceptance remains open.
- Emulator Debug frame output was 146 frames / 97.95% janky / P95 250 ms, with unreliable GPU timing. It is retained as diagnostic output, not substituted for physical-device performance.

Local ignored evidence: `build/android-preconsole/records-pixel-large-frames.txt`, `records-large-frames.txt`, `records-life-a11y.xml`, `records-life-allocation-a11y.png`. Large-font screenshots are in the primary checkout's same ignored directory (`records-life-large-dark-final.png`, `records-life-large-dark-legends.png`). Build logs: `/tmp/doneat-records-gradle.log`, `/tmp/doneat-records-final-gradle.log`, `/tmp/doneat-records-ios.log`.

## Remaining acceptance

Measure an installable optimized build on Pixel, including scrolling and repeated transitions; investigate remaining slow frames. Complete spoken TalkBack navigation and QA-131's Focus alternatives. QA-124's full sensitive-surface policy is a separate unresolved decision. Website Android privacy additions remain local and unpublished; Play Console KYC has not been reverified here.

## Follow-up: confirmation button audit

`Time manually` replaced `DoneAtPrimaryButton` with `ArmableButton` on its first tap. This changed its pill shape to `MaterialTheme.shapes.medium`, padding, text style and icon. Both states now retain `DoneAtPrimaryButton`; only the existing confirmation copy changes, including timeout reset.

Source audit covered all four inline timer confirmations: manual start, early clock-in, early clock-off and cancel manual timing. The other three retain their components; early actions intentionally use warning color/icon, while the banner retains its TextButton. Dialog confirmations across Records day editing/data import/delete/timezone, schedule changes/discard, Focus stop/clear/extend, archive recovery, onboarding import and overtime use Material AlertDialog/TextButton. No additional conditional replacement of inline confirmation button components was found. This source audit is not a claim that every destructive operation was executed on a device.

API 36 screenshots (`manual-button-before.png`, `manual-button-confirm.png`) confirm the same pill shape, orange fill, typography and position before/after the first tap; a subsequent UI dump after timeout showed Time manually again. The screenshot check passed; the automated bounds assertion was inconclusive because UI dumping exceeded the five-second confirmation window. The follow-up app tests, lint and Debug/R8 Release builds passed (`/tmp/doneat-confirm-buttons-gradle.log`).

Cleanup: original emulator files were restored and compared byte-for-byte, system test settings restored, app stopped. The Pixel QA package was uninstalled; the existing user package and its stay-awake settings were retained.
