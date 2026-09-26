# Android instructions

Read with the root `AGENTS.md` when planning, changing, building or testing
Android (`src-mobile/android`, `docs/android`, `plans/Android`). Root privacy,
locale and validation rules apply.

## Status and sources

- Android is a native port in progress; the Gradle project is
  `src-mobile/android` (modules `:app`, `:core:domain`, `:core:designsystem`).
  The plan is `plans/Android/DoneAt_Android_Handoff_v1_1/` (package 1.2; the
  folder keeps its 1.1 name so links survive). Start at `00_START_HERE.md`.
- `docs/android/progress.md` is the only task-status record. `tasks.json`
  defines dependencies, scope and acceptance, not status.
- Behaviour is ported from the pinned iOS baseline recorded in
  `docs/android/baseline.md`, not from `main`. At each milestone run the drift
  command in `progress.md`, log the result, then decide whether to advance the
  baseline. Never follow `main` silently.
- Decisions live in the package's `decisions.json`; do not reopen approved
  ones. First release excludes T21 (server purchase verification), T22 (Drive
  sync) and T27 (Wear OS). Deferred is neither failed nor done.

## Architecture

- Kotlin, Jetpack Compose, Room, java.time. No WebView, Capacitor, Flutter,
  React Native or runtime JavaScript. `:core:domain` is pure JVM: no
  `android.*`, Room, Compose or Billing, and no hidden `Instant.now()`.
- Release uses stable Compose/Material3 only (D-12). Expressive styling comes
  from DoneAt shape/motion/colour tokens in `:core:designsystem`; no alpha or
  experimental Material3 APIs.
- Four main destinations match iOS `AppTab`: timer, focus, records, settings.
  Each has its own Navigation 3 back stack; routes are `ui/Route` keys and one
  entry registry (`AppShell`) maps them to screens. Back pops the tab, then
  returns to the timer, then leaves.
- Committed settings live only in the archive's `syncedPreferences`, written
  through `SettingsRepository`. Before first-run setup completes, edits go to
  the device draft and nothing reaches the archive; an archive that already
  holds settings (restored backup) counts as set up.
- The in-app language is `languageOverride`. Android 13+ mirrors it into the
  system per-app language both ways; earlier versions switch it inside Compose
  (`AppLanguageScope` wraps the activity, never a bare configuration context).
  AAB language splits stay disabled.
- The running countdown is `session/ShiftSession` (reads) and
  `SessionCommands` (writes), stored by `SessionStore`. Its state file is
  device-local and never joins the archive (the frozen clock-off snapshot
  carries salary). Screens read figures from the session's rules snapshot at
  the current second; never compute `end - now`. A command's archive writes
  (observations, today's override) go through `SessionStore.run`, never
  straight to `RecordStore`.
- The brand mark is drawn natively (`DoneAtBrandMark`, from the
  `assets/brand` geometry), never as an embedded image; the launcher icon's
  vectors in `res/drawable/ic_launcher_*` use the same paths.
- Money reaches the screen only through `TimerText.money`, which masks it
  while earnings are hidden. Revealing goes through `EarningsGate`.
- Records pages read one archive revision through `records/RecordsQueries`
  and draw finished models (`RecordsDayCanvasModel`, day cells, headline);
  views never intersect shifts, clip overtime or derive lunch. Without Plus a
  locked day or summary is never built, so nothing behind the lock can reach
  a view or the accessibility tree. Plus comes from `PlusAccess`; its debug
  switch lives only in the `debug` source set.
- UI takes colour, shape, motion and type from `:core:designsystem` tokens
  (`docs/android/design-tokens-adr.md`); screens do not inline hex colours,
  radii or durations. Check new tokens in the Debug-only gallery
  (`adb shell am start -n com.rainif.doneat/.gallery.DesignGalleryActivity`)
  in light, dark, 200% font and with animations removed.

## Rules parity

- Shared rules (`lib/countdown.ts`, `lib/reminders.ts`, `lib/summary.ts`)
  reach Kotlin through `npm run generate:android-rule-fixtures`, which writes
  `core/domain/src/test/resources/shared-rule-fixtures.json`: the iOS fixture
  cases verbatim plus hashes of every `lib/`/oracle input. `npm test` fails
  when it is stale, even if the iOS fixture is not. iOS-only rules (extended schedules, record resolution, focus) reach
  Kotlin through `npm run generate:android-extended-fixtures` (macOS): it
  compiles the real `src-mobile/ios/Shared` Swift with
  `scripts/android-extended-fixtures/main.swift` and records its answers in
  `extended-schedule-fixtures.json`. `npm test` fails on any platform once
  those Swift sources change; regenerate on macOS, then fix Kotlin. Decide which side is correct before
  regenerating; never regenerate to hide a failure.
- A shared or iOS-only rule change updates Kotlin in the same change
  (`core/domain/.../schedule`, `salary`); `:core:domain:test` must stay green.
  `docs/android/rule-parity.md` lists which fixture sections Kotlin covers.
- Rule inputs take an explicit `ZoneId`; rules never read a default zone or
  the current time. The holiday calendar is loaded by the caller and passed
  into `ExtendedSchedulePlan`; it is the same `HolidayTemplates.json` as iOS.
- Focus session IDs use the source SHA-256 truncation, not Java
  `nameUUIDFromBytes` or random UUIDs.

## Localization

- Android copy is generated, never hand-edited: `npm run generate:android-strings`
  converts `Localizable.xcstrings` plus `app/i18n/android-strings.json` into
  `res/values*/strings_catalog.xml`, `res/xml/locales_config.xml`,
  `app/i18n/key-map.json` and the typed `l10n/Strings.kt` accessors. `npm test`
  and Android CI fail when any of them is stale.
- `{{name}}` becomes positional `%N$s` in English order; call strings with
  arguments through `Strings` so names, not positions, are passed. Message
  pools (`key.1…`) become string-arrays that keep `{{name}}` for the shared
  rules to substitute. Keywords get a trailing underscore (`R.string.continue_`).
- Android-only copy needs all 19 locales in `android-strings.json`, may not
  reuse a catalog key, and follows the catalog's wording per locale (zh-HK is
  colloquial Cantonese). Indonesian uses Android's legacy `in`; Hong Kong and
  Taiwan stay separate; `pt` is not `pt-BR`.

## Data, purchases and privacy

- User backups are `RecordJSON` schemaVersion 6, accepting 1–6. Records live
  as iOS keeps them (D-13): an in-memory `RecordState` saved by
  `:core:data`'s `RecordStore` as one atomically replaced `RecordLocalFile`
  (the v6 document plus tombstones). Every write is encoded, read back and
  only then published; a damaged file blocks writes and is quarantined, never
  overwritten. No Room tables.
- `npm run generate:android-record-fixtures` (macOS) compiles the real iOS
  `RecordJSON` and records its answers for 88 documents; `npm test` fails when
  that Swift or the case list changes.
- Android Auto Backup and device transfer include the business database (as
  iOS includes its main store in iCloud device backup). The rules
  (`res/xml/data_extraction_rules.xml`, and `backup_rules.xml` for Android 11
  and earlier) are an include list: `records/` and `device/settings.json`.
  Anything else, including new files, stays out until named there. The
  session, focus queue, reminder registry, purchase caches, pending-acknowledge
  markers, Keystore material, tokens and debug settings are never backed up.
  After a restore, re-query Play and system permissions; never trust
  restored entitlements or grants.
- The home-screen widget reads only `WidgetSnapshot` (`:core:domain` `widget/`, the
  shared widget contract): intervals the app precomputed from the schedule rules,
  picked by time. Never compute a shift in the widget or put money in the
  snapshot. Glance recomposes a live session without calling `provideGlance`,
  so anything it shows is read inside `provideContent`, keyed on
  `WidgetSignals.tick`; a Glance container holds at most ten children.
- Shares carry hours only: `ShareContent` words the card, and the link is the
  web app with `s=HHMM-HHMM` (as iOS). The card is lent through the `.share`
  FileProvider (cache `share/` only).
- First release uses client-only Play Billing (D-08), mirroring iOS StoreKit:
  entitlements come only from `queryPurchasesAsync` plus Play public-key
  signature checks, never from backups, imports or local booleans. Acknowledge
  on the client and retry within the three-day window.
- Reminders are absolute alarms registered up front (`Reminders`, `ReminderSync`),
  never a foreground service or a polling worker. Exact timing needs the
  user-granted `SCHEDULE_EXACT_ALARM`; never declare `USE_EXACT_ALARM`. The
  alarm registry lives in `noBackupFilesDir`; receivers stay unexported and
  post only what the registry still holds.
- First release requests no Google sign-in or OAuth. Salary never appears in
  widgets, notifications, share cards/links, logs or analytics.

## Environment

- SDK: `~/Library/Android/sdk` (no `cmdline-tools`; install from Android
  Studio's SDK Manager if needed). Point `sdk.dir` in untracked
  `src-mobile/android/local.properties` at it.
- JDK: the system Temurin 21 is x86_64 and fails on this Mac. Use Android
  Studio's JBR: `export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`.
- Do not commit `local.properties`, `build/`, `.gradle/`, keystores or
  signing passwords.

## Validation

Versions and verified commands live in `docs/android/environment-lock.md`.
From `src-mobile/android`, with `JAVA_HOME` set as above:

```bash
./gradlew :core:domain:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:assembleRelease
```

`.github/workflows/android.yml` runs the same set on Android path changes and
rejects pre-release Compose/Material3 in the release classpath (D-12).

Cover every module's tests before calling a suite complete; device-only
behaviour (alarms, widgets, backup restore, purchases) needs device evidence.
