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
  iOS includes its main store in iCloud device backup). Exclude purchase
  caches, pending-acknowledge markers, Keystore material, tokens and debug
  settings. After a restore, re-query Play and system permissions; never trust
  restored entitlements or grants.
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
