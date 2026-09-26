# Android pre-Console QA evidence — 2026-09-26

This matrix tracks all **126 first-release cases** in [`07_TEST_CATALOG.md`](../../plans/Android/DoneAt_Android_Handoff_v1_1/07_TEST_CATALOG.md). QA-110–122 and QA-137 are deferred and excluded from the count. Status follows the catalog vocabulary: **PASS**, **FAIL**, **BLOCKED**, **NOT_RUN**. **Partial** in the coverage column means some automated evidence exists, but the complete acceptance has not passed. All method names cited below were matched against passing testcases in the fresh JUnit XML. A method pass only satisfies a case when its assertions cover the whole catalog acceptance.

The first combined Gradle run (`/tmp/doneat-preconsole-full-gradle.log`) completed the Android build, lint and release bundle successfully. The final acceptance run (`/tmp/doneat-preconsole-salary-final-gradle.log`) has completed **330 domain, 68 data, 8 design-system, and 11 app unit tests** with no failures or skips per current JUnit XML under `src-mobile/android/core/*/build/test-results/` and `src-mobile/android/app/build/test-results/`. Final lint, Debug, R8 Release and AAB builds passed, including the salary field's adaptive layout. Lint reports 0 errors, 33 warnings and 1 hint. The new exact pre-start, overtime, full-day, night, cycle, clipping, free-window, wall-clock reversal and future-archive assertions passed. The iOS `ScheduleRuleFixtureTests` run passed all 12 tests (`/tmp/doneat-preconsole-ios-fixture-tests.log`), including its shared snapshot suite; the final headless build passed again (`doneat-preconsole-ios-final-build.log`).

The later QA-051 run (`/tmp/doneat-life-history-final-gradle.log`) passes **333 domain + 68 data + 8 design-system + 11 app = 420 tests**, lint (0 errors / 33 warnings / 1 hint), Debug/R8 Release/AAB. Seven Swift employment-history tests pass, including three invalid-end cases in one parameterized test (`/tmp/doneat-life-history-swift-tests.log`). The same run builds the iOS simulator target headlessly. API 36 screenshots `life-gap-edit-final.png` and `life-overlap-edit-final.png` show the preserved end and visible validation; actual Save preserves the 2022–2024 gap. No manual iOS visual inspection was performed. PR #239 commits `ae0ec1f0` and `e2d874c` passed all remote checks; later commits require their own CI result.

The QA-041 follow-up (completed 2026-09-27) passes **336 domain + 68 data + 8 design-system + 11 app = 423 tests**, lint (0 errors / 33 warnings / 1 hint), Debug/R8 Release/AAB (`doneat-number-input-save-final-gradle.log`). All **17 Swift tests** (5 numeric-input + 12 shared-rule methods; parameterized inputs included) pass on the final iOS sources (`doneat-number-input-final-ios.log`). npm has 445 passing tests; lint, Web/Desktop builds and output checks pass. iOS app, Widget, Watch app and Watch Widget build as 3.2.1; Android remains 3.2.0 (1). API 36 exercises negative, repeated-separator, overlength, NaN/Infinity and exponent drafts without changing the saved salary; comma decimal, zero and empty edits persist on leaving. Invalid bonus and recovered raw text remain unchanged. A Done commit followed by another edit and leaving the same page persists the latest value. All 14 original emulator files were restored byte-for-byte; the app was stopped and the Pixel was untouched. Normal and 320 dp / 200% font screenshots show the validation. The initial cold-boot run hit an input-dispatch ANR under system/input-method load; after reopening, the complete exercise passed. The first exercise also exposed cancellation of valid salary saves on page disposal; the final app-scoped commit fixes it. No iOS visual inspection was performed.

The independent iOS → Kotlin → iOS v6 round trip passed (`/tmp/doneat-preconsole-roundtrip-final.log`). Swift imported both original and Kotlin output, compared the whole `RecordState`, and verified all 12 entity families. This is QA-070 evidence. The 15,000-day/2,609-workday Life JVM test printed **4.848166 ms** in its JUnit XML for one model build on this Mac. It is calculation evidence only and does not establish QA-056 device scroll, frame, or cancellation behavior. No Play Console evidence is available.

| Case | Tier | Status | Coverage | Automated evidence | Remaining acceptance |
|---|---|---|---|---|---|
| QA-001 | CI | NOT_RUN | None | — | Run the specified CI/build/static gate and capture output. |
| QA-002 | CI | PASS | Complete | Final Gradle log; release dependency tree (stable, no dynamic versions); environment-lock.md | — |
| QA-003 | UI | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-004 | CI | PASS | Complete | Android app uses AGP built-in Kotlin + Compose/serialization; core:domain uses kotlin.jvm with no Android imports; module builds passed | — |
| QA-005 | CI | PASS | Complete | SharedRuleFixturesTest + generate-android-rule-fixtures.test.mjs stale-case rejection; nonzero 417 Android and 442 npm tests | — |
| QA-006 | SEC | PASS | Complete | Final R8 APK DEX string scan, release manifest and ELF/ZIP 16 KiB alignment; no debug_plus/gallery/bypass text or private-key headers | — |
| QA-007 | CI | PASS | Complete | npm lint/test442; Web/Desktop build+output guards; iOS headless build+12 Swift fixture tests; Android417 tests/lint/builds | — |
| QA-008 | JVM | PASS | Complete | `ShiftExamplesTest.workStartAndBreakEndAreExactBoundaries` | — |
| QA-009 | JVM | PASS | Complete | `ShiftExamplesTest.workStartAndBreakEndAreExactBoundaries` | — |
| QA-010 | JVM | PASS | Complete | `ShiftExamplesTest.beforeAndAtLunchUseEffectiveWorkTime` | — |
| QA-011 | JVM | PASS | Complete | `ShiftExamplesTest.beforeAndAtLunchUseEffectiveWorkTime`; `lunchFreezesWorkAndPay` | — |
| QA-012 | JVM | PASS | Complete | `ShiftExamplesTest.workStartAndBreakEndAreExactBoundaries` | — |
| QA-013 | JVM | PASS | Complete | `ShiftExamplesTest.clockOffAndFiveMinutesLaterDoNotCreateOvertime`; `ShiftSessionTest.natural end and five minutes later are completed without overtime` | — |
| QA-014 | JVM | PASS | Complete | `ShiftExamplesTest.overtimeExtendsTheOriginalRate` | — |
| QA-015 | JVM | PASS | Complete | `ShiftExamplesTest.severalGapsDoNotCountAsWorkOrAccumulateTogether` | — |
| QA-016 | JVM | PASS | Complete | `RecordsQueriesTest.aNightShiftPutsItsMorningOnTheNextDay` | — |
| QA-017 | JVM | PASS | Complete | `ShiftExamplesTest.degenerateClocksAndCyclesTerminate` | — |
| QA-018 | JVM | PASS | Complete | `ShiftExamplesTest.malformedSegmentsAreRejectedWithoutNegativeOrNanFigures`; `RecordStoreTest.anEditThatWouldNotReadBackNeverReachesDisk`; `aPersistedMalformedRowBlocksWritesAndKeepsItsBytes` covers illegal date and empty/zero/reversed/overlapping segments on disk | — |
| QA-019 | JVM | NOT_RUN | None | `ShiftExamplesTest.eachSegmentBoundaryUsesHalfOpenTime` | Half-open segment boundaries passed; displayed rounding against the source oracle remains unverified. |
| QA-020 | JVM | PASS | Complete | `ExtendedScheduleFixtureTest.dayResolution`; `expansionUsesUniqueCivilDaysAcrossNewYearLeapDayAndDst` | — |
| QA-021 | ORACLE | PASS | Complete | `ScheduleRuleFixtureTest.losAngelesGapAndRepeatedHourMatchTheSharedOracle`; iOS `ScheduleRuleFixtureTests` | — |
| QA-022 | JVM | PASS | Complete | `RecordStoreTest.changingDeviceZoneAndReopeningKeepsHistoricalCivilDays`; explicit migration test and API 36 UTC migration UI | — |
| QA-023 | JVM | NOT_RUN | None | — | Pause foreground ticker for 90 seconds, resume and assert a fresh absolute-time evaluation without backfilled ticks. |
| QA-024 | DEVICE | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-025 | ORACLE | PASS | Complete | `ShiftExamplesTest.noWorkdaysMeansNoNextShift`; `manualModeHasNoRestDayAndNoPlannedShift`; `unresolvedFutureTypeNeverBecomesAnInventedTomorrow`; manual SessionCommands start test | — |
| QA-026 | JVM | PASS | Complete | `ExtendedScheduleFixtureTest.validation`; Swift oracle includes blank, whitespace, 40/41 characters and Unicode grapheme boundaries | — |
| QA-027 | JVM | PASS | Complete | `ExtendedScheduleFixtureTest.validation`; `cycleLengthAndUnknownPresetBoundaries` | — |
| QA-028 | JVM | PASS | Complete | `ExtendedScheduleFixtureTest.threeDayCycleWrapsToItsLastDayBeforeTheAnchor` | — |
| QA-029 | JVM | PASS | Complete | `DayRecordResolverTest.clearedOverrideFallsThrough`; `RecordEditsTest.restMakeupAndClearWriteBothLayersAndClearLeftoverHours` | — |
| QA-030 | JVM | PASS | Complete | `ExtendedScheduleFixtureTest.rosterDayRecoversWhenItsReferencedTypeArrivesLater` | — |
| QA-031 | JVM | PASS | Complete | `RecordEditsTest.editedTypeChangesFutureSnapshotWhileFrozenHistorySurvivesDisablingExtendedSchedule`; `ScheduleSaveTest.a hand-set day is stamped, and following the pattern leaves a tombstone` | — |
| QA-032 | JVM | PASS | Complete | `RecordEditsTest.editedTypeChangesFutureSnapshotWhileFrozenHistorySurvivesDisablingExtendedSchedule` | — |
| QA-033 | ORACLE | PASS | Complete | `ExtendedScheduleFixtureTest.dayResolution` (Swift carry-over cases cover 31→30→28/29 and authored-month gaps); `ScheduleSaveTest.a hand-set day is stamped, and following the pattern leaves a tombstone` | — |
| QA-034 | ORACLE | PASS | Complete | `RecordEditsTest.hoursStoreTheTypesAndRuleButNeverTheRoster`; `ExtendedScheduleFixtureTest.clearBoundaryStopsHolidayAutofillButKeepsExplicitRosterDays`; Swift day-resolution oracle | — |
| QA-035 | JVM | PASS | Complete | `ScheduleSaveTest.an archived type leaves new choices but keeps its saved roster day`; both ScheduleScreen selectors use `ScheduleEditing.activeTypes` | — |
| QA-036 | JVM | PASS | Complete | `ScheduleSaveTest.a running shift follows the chosen schedule boundary`; `RecordEditsTest.aSecondScheduleSaveOnTheSameDayEditsTheWinningSnapshot` | — |
| QA-037 | JVM | PASS | Complete | `DayRecordResolverTest.eachClearedLayerExposesTheNextDayRule`; `RecordHistory.resolveDay` excludes observations from the planning chain | — |
| QA-038 | JVM | PASS | Complete | `DayRecordResolverTest.sameSlotSnapshotPicksEditStamp` with reversed order and ID tie | — |
| QA-039 | JVM | PASS | Complete | `RecordEditsTest.theFirstHoursEditSeedsAndOverridesInOneChangeAndKeepsLunch`; `DayRecordResolverTest.customOverrideBeatsExceptionAndSchedule` | — |
| QA-040 | DB | PASS | Complete | `RecordsEditingTest.aFailedDayEditKeepsBothLayersAndTheDraftAfterReopen`; reviewed RecordsDayEditScreen save branch closes/confirms only when saved is true and the same draft is still displayed | — |
| QA-041 | JVM | PASS | Complete | `NumberInputTest`; `LifeProfileDraftTest.invalidSalaryDraftCannotEraseTheStoredSalary`; `RecordsTransferTest.invalidSalaryTextInARecoveredArchiveDoesNotBecomeAnAmount`; matching Swift input and TS/Swift/Kotlin overflow fixtures; API 36 edit/leave persistence checks and 200% font validation | Recovered malformed raw text remains lossless but cannot be committed by the editor or used as an amount. The archive schema is unchanged. |
| QA-042 | ORACLE | PASS | Complete | `SummaryFixtureTest.fixedMonthlyPayKeepsTheFullMonthAndBonusShareDespiteSparseRecords`; `recordsIncomeAndMonthlyEquivalent` | — |
| QA-043 | ORACLE | PASS | Complete | `SummaryFixtureTest.monthlyWeekCrossingMonthsUsesEachMonthsNaturalDays`; `actualAndForecast` | — |
| QA-044 | ORACLE | PASS | Complete | `SummaryFixtureTest.dailyPayFollowsWorkdaysWhileMonthlyPayIncludesRestDays`; `actualAndForecast` | — |
| QA-045 | JVM | PASS | Complete | `SummaryFixtureTest.partlyObservedDayReconcilesElapsedAndFutureWithoutOverlap`; `actualAndForecast` | — |
| QA-046 | JVM | PASS | Complete | `RecordsQueriesTest.withoutPlusOnlyTheLastSevenDaysAreRevealedAndNoSummaryIsBuilt` | — |
| QA-047 | JVM | PASS | Complete | `SessionStoreTest.qa047ObservationPolicyFollowsFreePaidAndExpiredAccess`; `EntitlementEngineTest` historical-purchase policy | — |
| QA-048 | SEC | NOT_RUN | Partial | `RecordsDayCanvasModelTest.aLockedDayCarriesNothingReal` | Release artifact inspection and targeted security/device exercise. |
| QA-049 | UI | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-050 | JVM | PASS | Complete | `LifeRulesTest.endedPeriodsLeaveARealGap`; `SummaryFixtureTest.lifetimeIncomeLeavesEmploymentGapsEmptyAndRejectsOverlap` | — |
| QA-051 | JVM | PASS | Complete | `LifeProfileDraftTest.invalidImportedEndsCannotBeSilentlyRelinkedOnSave`; `editingSalaryPreservesHistoricalGapsAndEndDates`; `editingAnAdjacentStartStillUpdatesItsLinkedEnd`; matching 7 Swift tests; invalid import preserves old profile; API 36 Save keeps the gap and overlap disables Save with visible validation | — |
| QA-052 | ORACLE | PASS | Complete | `SummaryFixtureTest.futureAgeThresholdAppliesOneFixedRatioUntilRetirement`; `lifetimeIncome` | — |
| QA-053 | ORACLE | PASS | Complete | `LifeRulesTest.aPassedAdjustmentAgeAppliesTheRatioAndLeavesHistory` | — |
| QA-054 | JVM | PASS | Complete | `SummaryFixtureTest.partialLeapMonthUsesItsOwnDayCountAndAnExclusiveEnd`; `lifetimeIncome` | — |
| QA-055 | UI | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-056 | PERF | NOT_RUN | Partial | `LifeRulesTest.fifteenThousandDayLifeWithTenYearsOfRecordsBuildsOnTheJvm` | 15,000-day/2,609-workday JVM model built in 4.848166 ms; rapid-switch cancellation and device main-thread/frame evidence remain. |
| QA-057 | JVM | PASS | Complete | `FocusPlannerTest.focusTimerSettingsClampToSupportedRanges` | — |
| QA-058 | JVM | PASS | Complete | `FocusEngineTest.changingDurationLeavesTheRunningEndAndAppliesToTheNextSession` | — |
| QA-059 | JVM | PASS | Complete | `FocusPlannerTest.identityVectorsMatchTheSpecification` | — |
| QA-060 | DB | PASS | Complete | `FocusStoreTest.concurrentStartsAndRepeatedCallbacksRecordOneLogicalBlock`; `FocusEngineTest.twoDevicesFinishingTheSameBlockStartOneSharedBreak` | — |
| QA-061 | DEVICE | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-062 | JVM | NOT_RUN | Partial | `FocusEngineTest.aFocusEndingAtABoundaryLeavesNoUnusableBreakAction` | Focus boundary prevents unusable break action; notification rebuild across lunch/clock-off remains. |
| QA-063 | JVM | PASS | Complete | `FocusPlanningTest.twoThreeOneTemplateKeepsItsSavedSixRoundsAcrossShortAndLongShifts`; `shortShiftsTakeAWholeTaskPrefix` | — |
| QA-064 | JVM | PASS | Complete | `FocusPlanningTest.twoThreeOneTemplateKeepsItsSavedSixRoundsAcrossShortAndLongShifts` | — |
| QA-065 | UI | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-066 | UI | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-067 | SYNC | NOT_RUN | Partial | `FocusEngineTest.twoDevicesFinishingTheSameBlockStartOneSharedBreak` | Same-ID engine convergence test; add export/import integration and superseded history assertion. |
| QA-068 | JVM | PASS | Complete | `FocusEngineTest.aBoundaryCutAndAUserStopDoNotCount` | — |
| QA-069 | DB | PASS | Complete | `RecordsTransferTest.everyKnownVersionPreviewsAndImports` | — |
| QA-070 | DB | PASS | Complete | `RecordsTransferTest.exportAllEntitiesForSwiftRoundTrip`; Swift whole-state round trip, 12 families | — |
| QA-071 | DB | PASS | Complete | `RecordsTransferTest.invalidRowsAreCountedSeparatelyFromUnreadableDocuments`; `aNewerOrBrokenFileIsRefusedWithItsReason`; Swift invalid-date/zone import oracle | — |
| QA-072 | SEC | PASS | Complete | `RecordsTransferTest.hostileBackupDepthAndNumbersFailBeforeChangingRecords`; `largeDistinctAndRepeatedIdentitiesMergeWithinTheFileCeiling`; reviewed byte/depth/container/entry guards before decode and indexed identity merge | — |
| QA-073 | DB | PASS | Complete | `RecordsTransferTest.cancellingAConflictedImportLeavesTheLocalFileUntouched`; API 36 SAF conflict preview/cancel with byte-identical archive; both conflict choices exercised | — |
| QA-074 | DB | PASS | Complete | `RecordStoreTest.tombstonesPersistAndStillBlockImports` | — |
| QA-075 | DB | PASS | Complete | `RestoreErasedRemapTest.restoredIdentitiesCarryTheirReferences` | — |
| QA-076 | DB | PASS | Complete | `RecordJsonFixtureTest.everyCaseMatchesSwift`; `editStampTieBreakerWinsWhenWallClockRunsBackward` | — |
| QA-077 | DB | NOT_RUN | Partial | `RecordStoreTest.aFailedWriteCommitsNothing`; `atomicWriterRemovesPendingFileWhenReplacementFails` | Low-space writer and replacement failure preserve old bytes; process termination around a large import commit remains. |
| QA-078 | SEC | PASS | Complete | `RecordsTransferTest.exportsOnlySchemaSixRecordsEvenAfterImportingUnknownPrivateFields` checks both export modes and private-field exclusion; actual free SAF export; release has no broad storage permission and uses CreateDocument | — |
| QA-079 | DEVICE | NOT_RUN | None | — | SAF cloud URI, readonly URI and cancellation require device. |
| QA-080 | DB | PASS | Complete | `RecordStoreTest.everyOlderLocalEnvelopeWritesBackAsSchemaSix`; synthetic v1–v6 restart, tombstone, failed-write, damaged and future archive tests | — |
| QA-081 | DEVICE | PASS | Complete | `SettingsRepositoryTest.theDraftSurvivesTheProcessDyingMidSetup`; API 36 force-stop/relaunch restored alternating-week setup; no archive before Finale confirmation; `doneat-preconsole-onboarding.log` | — |
| QA-082 | DEVICE | PASS | Complete | API 36 free user exported via SAF, deleted records, reimported 92 items and recovered 10 tasks/Life profile; Life editing still opened Plus; `doneat-preconsole-free-data-controls.log` | — |
| QA-083 | DEVICE | PASS | Complete | API 36 denied notification permission, completed setup and opened Timer; revisiting reminders did not repeat the prompt or re-enable ongoing notifications; Settings displayed Denied; `doneat-preconsole-onboarding.log` | — |
| QA-084 | DEVICE | PASS | Complete | API 36 denied exact-alarm capability; delayed-reminder explanation and actual inexact registry/system alarms; no USE_EXACT_ALARM; `doneat-preconsole-exact-alarm.log` | — |
| QA-085 | DEVICE | PASS | Complete | API 36 grant→exact registry, revoke→return→nonempty inexact registry with unique IDs and no crash; `doneat-preconsole-exact-alarm.log` | — |
| QA-086 | DEVICE | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-087 | ORACLE | PASS | Complete | `ReminderPlannerTest.withProgressOffTheCycleSummaryStillRingsOnceAtClockOff` | — |
| QA-088 | ORACLE | PASS | Complete | `ReminderPlannerTest.anUnresolvedFollowingDayIsNeverReadAsRest` | — |
| QA-089 | DEVICE | NOT_RUN | Partial | `FocusEngineTest.twoDevicesFinishingTheSameBlockStartOneSharedBreak` | Device/UI exercise with stated setup and expected result. |
| QA-090 | DEVICE | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-091 | DEVICE | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-092 | DEVICE | NOT_RUN | Partial | `WidgetSnapshotTest.nothing in the snapshot mentions money` | Widget contract is salary-free; layouts/theme/language require device. |
| QA-093 | DEVICE | NOT_RUN | Partial | `WidgetSnapshotTest.later shifts start on their own without reopening the app` | Projection test covers time selection; Doze and system refresh require device. |
| QA-094 | SEC | NOT_RUN | None | — | Inspect merged release manifest and exercise external Intent attempts on device. |
| QA-095 | PLAY | NOT_RUN | None | — | Play Console configuration and license-test evidence. |
| QA-096 | PLAY | NOT_RUN | None | — | Play Console configuration and license-test evidence. |
| QA-097 | PLAY | NOT_RUN | Partial | `EntitlementEngineTest.purchaseLifecycle` | Engine pending state test does not prove 24-hour Play behavior. |
| QA-098 | PLAY | NOT_RUN | Partial | `EntitlementEngineTest.acknowledgementOnlyDuringPurchasedWindow` | Engine acknowledgement test; Play purchase callback/idempotent pending action needs license test. |
| QA-099 | SEC | NOT_RUN | None | — | Release artifact inspection and targeted security/device exercise. |
| QA-100 | PLAY | NOT_RUN | None | — | Play Console configuration and license-test evidence. |
| QA-101 | PLAY | NOT_RUN | None | — | Play Console configuration and license-test evidence. |
| QA-102 | PLAY | NOT_RUN | Partial | `EntitlementEngineTest.offlineSubscriptionExpiresButLifetimeSurvives` | Play Console configuration and license-test evidence. |
| QA-103 | PLAY | NOT_RUN | None | — | Play Console configuration and license-test evidence. |
| QA-104 | PLAY | NOT_RUN | Partial | `EntitlementEngineTest.offlineSubscriptionExpiresButLifetimeSurvives` | Play Console configuration and license-test evidence. |
| QA-105 | PLAY | NOT_RUN | Partial | `EntitlementEngineTest.acknowledgementOnlyDuringPurchasedWindow` | Engine window test; pending-ack marker persistence and killed-process retry need device/Play. |
| QA-106 | PLAY | NOT_RUN | None | — | Play Console configuration and license-test evidence. |
| QA-107 | PLAY | NOT_RUN | None | — | Play Console configuration and license-test evidence. |
| QA-108 | DEVICE | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-109 | SYNC | NOT_RUN | None | — | Inspect final manifest/dependencies and capture fresh-install device network behavior to prove no Google OAuth or implicit salary/preferences upload. |
| QA-123 | SEC | NOT_RUN | None | — | Release artifact inspection and targeted security/device exercise. |
| QA-124 | SEC | NOT_RUN | None | — | Recent-task and TalkBack privacy inspection needs device. |
| QA-125 | SEC | NOT_RUN | Partial | `ShiftSessionTest.share links stay on the web app and carry only the hours` | Share URL unit test; card pixels, metadata and logs need inspection. |
| QA-126 | DEVICE | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-127 | SEC | NOT_RUN | Partial | API 36 local Auto Backup and official D2D reinstall tests; named device-local/no_backup probes excluded | Real Google cloud transport/account restore remains; local transport is not a claim about cloud completion. |
| QA-128 | UI | PASS | Complete | 19-locale generation/placeholder checks and `PreferencesRulesTest.systemLanguagesMapLikeIos`; English/Chinese phone and tablet, German Settings and Arabic RTL visual inspection; HK/TW resources remain separate | — |
| QA-129 | UI | PASS | Complete | API 36 at 320 dp and 200% font: Settings/Plus inspected, shift-type name saved with keyboard, salary keypad Done persisted amount, Focus Add persisted task; `doneat-preconsole-large-font-editors.log` and final screenshots | — |
| QA-130 | UI | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-131 | UI | NOT_RUN | None | — | Device/UI exercise with stated setup and expected result. |
| QA-132 | DEVICE | NOT_RUN | Partial | `ReviewPolicyTest.completionArmsNextLaunchAndIsConsumedOnce` | Policy unit tests; actual Play review flow needs device. |
| QA-133 | PLAY | NOT_RUN | None | — | Play Console configuration and license-test evidence. |
| QA-134 | PLAY | NOT_RUN | None | — | Play Console configuration and license-test evidence. |
| QA-135 | PLAY | NOT_RUN | None | — | Play Console configuration and license-test evidence. |
| QA-136 | PLAY | NOT_RUN | None | — | Play Console configuration and license-test evidence. |
| QA-138 | DEVICE | NOT_RUN | Partial | API 36 system Auto Backup and D2D reinstall restore records/settings byte-for-byte; first launch reads restored setup | Two physical devices with the same Google account, device locks and rebuilt reminders/widgets remain. |
| QA-139 | SEC | NOT_RUN | Partial | D2D test excludes no_backup/device-local probes and debug_plus preference; Auto Backup excludes runtime session/SharedPreferences | Real signed purchase/acknowledgement cache, new-device permissions and Play re-query remain. |
| QA-140 | DB | NOT_RUN | Partial | `RecordStoreTest.aNewerLocalArchiveIsPreservedAndBlocksWrites`; `aDamagedArchiveBlocksWritesUntilQuarantined` | Future-version and damaged local archives preserve their bytes and block writes; backup during replacement and restored-archive UI remain. |

## Counts and limits

- PASS: 73
- FAIL: 0
- BLOCKED: 0
- NOT_RUN: 53

The matrix has 126 first-release rows. These counts track exact catalog acceptance, not test-method count. Partial evidence stays NOT_RUN until the remaining conditions listed on that row are checked. The 423 passing JUnit tests, cross-platform builds and local backup simulations do not replace real Play purchases, cloud-account restore or the specified device matrix.

## Device evidence collected in this pass

- API 36 emulator used synthetic data. Screenshots and copied logs are under `build/android-preconsole/`; all 14 original app files were restored byte-for-byte before launch. Display overrides, font, timezone, app language, backup transport and test flags were restored (`doneat-preconsole-emulator-restored.log`). The app was left stopped.
- Both free and Debug Plus states passed the actual Records picker regression script, including returning to the initially selected Life scale and repeated Month entries. This is navigation evidence, not Play entitlement evidence.
- Year expansion, Life expansion, and the selected day's Pomodoro history were inspected. Month controls use localized abbreviations and adapt their columns to available width and system font scale. Actual two-pointer input passed Year→Month→Week→Month→Year→Life; a spread gesture in Life kept Life selected (`doneat-preconsole-pinch.log`).
- SAF import preview showed one conflict. Cancel left the full local archive byte-identical. The comparison page showed both task titles; keeping the import and keeping this device were each exercised using synthetic tasks.
- Explicit timezone migration from Asia/Shanghai to UTC completed in one archive update. Periods, exceptions, overrides and observations changed their zone while civil date labels stayed unchanged; replaced observation identities retained tombstones.
- Local Auto Backup restore returned records and settings byte-for-byte. Before first launch, session/focus/reminder runtime files, SharedPreferences and no_backup contents were absent. The official D2D reinstall path also restored records/settings exactly; device-local and no_backup marker files and the Debug Plus preference were excluded. Widgets/application startup may regenerate fresh runtime caches afterward.
- At 320 dp and 200% font, Settings values and salary inputs now move beneath their labels and Plus legal actions wrap as whole controls. Shift-type name Save, salary keypad Done and Focus Add were exercised with the keyboard open; the salary and task values were verified in the archive afterward.
- First-run interruption retained the chosen alternating-week pattern and setup page. Before final confirmation there was no business archive. Denying notifications kept the ongoing switch off, allowed completion and Timer use, and showed the actual denied state in Settings. Re-entering the reminders step did not repeat the system prompt.
- Free data controls were exercised through the actual system file picker: full export, delete, preview/import and paid-feature lock after restoration. Exact-alarm denial, grant and revocation rebuilt the expected registry and showed the delayed-reminder explanation.
- English/Chinese phone and tablet captures, long German Settings and Arabic RTL Settings were inspected. The final Plus legal-action layout is `plus-320dp-200font-final.png`; older screenshots without the `final` suffix include intermediate states and are not final acceptance evidence.
- Pixel received the updated APK without clearing its data. The final build's interactive regression still needs an unlocked device; earlier Pixel navigation/callout/predictive-back results are preserved in progress.md.

## Limits

Real Play product/purchase/review behavior, Google-account cloud restore, physical device transfer, OEM background behavior, long Doze runs and the complete accessibility/device matrix remain unverified. No Console upload, release signing, live website publication or iOS visual inspection was performed.

QA-051 was fixed together in iOS/Kotlin: stored employment gaps and ends survive editing; overlapping periods fail validation. QA-041 is also fixed across iOS/Kotlin: invalid drafts are preserved for correction and cannot replace saved salary; shared calculation overflow returns no amount. Recovered raw salary text is retained without silently normalizing it.
