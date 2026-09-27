# Records/Life acceptance — 2026-09-27

## Scope and result

QA-056 and QA-131 now pass their catalog scope with optimized Pixel measurements, actual TalkBack gestures/utterances and keyboard alternatives. The earlier sections retain the initial measurements; the final-candidate follow-up records the completed acceptance. This is not a full Android release pass. Status remains in `progress.md`.

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

The final follow-up below completes optimized Pixel performance and TalkBack/keyboard acceptance. Some measured rendering/scheduling spikes remain; no zero-jank claim is made. QA-124's full sensitive-surface policy is a separate unresolved decision. Website Android privacy additions remain local and unpublished; Play Console KYC has not been reverified here.

## Follow-up: confirmation button audit

`Time manually` replaced `DoneAtPrimaryButton` with `ArmableButton` on its first tap. This changed its pill shape to `MaterialTheme.shapes.medium`, padding, text style and icon. Both states now retain `DoneAtPrimaryButton`; only the existing confirmation copy changes, including timeout reset.

Source audit covered all four inline timer confirmations: manual start, early clock-in, early clock-off and cancel manual timing. The other three retain their components; early actions intentionally use warning color/icon, while the banner retains its TextButton. Dialog confirmations across Records day editing/data import/delete/timezone, schedule changes/discard, Focus stop/clear/extend, archive recovery, onboarding import and overtime use Material AlertDialog/TextButton. No additional conditional replacement of inline confirmation button components was found. This source audit is not a claim that every destructive operation was executed on a device.

API 36 screenshots (`manual-button-before.png`, `manual-button-confirm.png`) confirm the same pill shape, orange fill, typography and position before/after the first tap; a subsequent UI dump after timeout showed Time manually again. The screenshot check passed; the automated bounds assertion was inconclusive because UI dumping exceeded the five-second confirmation window. The follow-up app tests, lint and Debug/R8 Release builds passed (`/tmp/doneat-confirm-buttons-gradle.log`).

Cleanup: original emulator files were restored and compared byte-for-byte, system test settings restored, app stopped. The Pixel QA package was uninstalled; the existing user package and its stay-awake settings were retained.

## Final-candidate follow-up

Actual TalkBack 16 gestures were injected through the emulator's hardware-touch gRPC interface on API 36. Verification used TalkBack's **Display speech output** overlay and rendered screens, not only the app accessibility tree. Audio pronunciation/voice quality was not evaluated. Verbose logging stayed disabled.

- Month: select dates, display the floating explanation, open day details. Year: January announces its month/year, selected state and button role; its custom “See this month” action opens January.
- Minute-boundary regression: open the Year/January custom-action dialog at 11:24:50, keep it open through 11:25, then invoke it at 11:25:19. The final candidate enters January 2026; the old candidate lost this action when refresh removed the chart.
- Life: Childhood announces its date range, selected state and button role; double-tap selects it and moves the floating explanation. Two-finger scrolling reaches allocation/income. Regular work announces about 5.61 years, 2,049 d 16 h and 13.7%. Hidden Month earned income and Life total remain masked in TalkBack's actual output.
- Focus: create Alpha/Beta in an isolated template, use TalkBack custom Move down/Move up, verify the reordered rows and boundary actions (first has only down, last only up), save and reopen the template successfully. No drag is needed.

Local speech/screenshot evidence: `/tmp/doneat-talkback-live/final-life-*`, `/tmp/doneat-boundary-actions.png`, `/tmp/doneat-boundary-result.png`, `/tmp/doneat-focus-moved.png`, `/tmp/doneat-focus-last-actions.png`, `/tmp/doneat-focus-reopened.png`. Failed gesture attempts and screenshots captured before transitions settled are excluded.

Pixel original package: final ordinary Debug candidate installed over existing data; business archive hashes match before/after. Chinese Week/Month/Year/Life navigation passes, including returns from Year/Life to Month; Settings → Hours & schedule → left-edge back passes without changing schedule. The independent QA app covers first-run time/lunch controls, notification denial, salary-lock demonstration, actual system fingerprint/PIN prompt (cancelled), skip and completion.

Pixel widgets: inspect actual 2×2, 4×2 and 4×4 previews; add 4×4, resize down to a horizontal layout and tap it to open the original Timer. Labels/countdown remain visible and widgets contain no salary. Remove the added test widget afterward. Optimized performance measurements and their limits are in `pixel-performance-2026-09-27.md`.

Final keyboard follow-up: after Esc dismisses the input-method toolbar, Tab reaches a Focus task and its More button, Enter opens the menu (Move down is initially focused), and Enter moves Alpha below Beta. The order is checked from the actual UI. A mistaken extra Down selected Delete in the synthetic draft; that draft was discarded and the successful run repeated. Calendar Tab reaches Tue, Sep 1; Enter selects it and a second Enter opens that date's details. Earlier Life Tab/Enter and disabled-animation evidence remains applicable. Timer focus announces hours/minutes once, with no per-second repeated output in the subsequent capture.

Final cleanup: both `.qa` packages uninstalled; original apps retained. TalkBack's speech-output overlay restored off, detailed log level remains ERROR, enabled accessibility services restored to null and accessibility_enabled to 0. Pixel screen timeout remains 2147483647 and stay_on_while_plugged_in remains 15 as requested. Final ordinary candidate matches source commit `fe8d9db`.
